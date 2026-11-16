## Mission script interpreter tests against original mission programs.
## Run: Godot --headless --path game --script res://tests/vm_test.gd
extends SceneTree

var failures := 0


class Host:
	var vars := {}
	var flags := {}
	var alive := {}
	var actions := {}
	var done := {}
	var messages := []
	var activated := []
	var ended = null

	func vm_var(n): return vars.get(n, 0)
	func vm_set_var(n, v): vars[n] = v
	func vm_flag(n): return flags.get(n, false)
	func vm_set_flag(n, v): flags[n] = v
	func vm_alive(id): return alive.get(id, true)
	func vm_activate(id): activated.append(id)
	func vm_remove(_id): pass
	func vm_message(key, n): messages.append([key, n])
	func vm_end(ok): ended = ok
	func vm_action(key, op, arg): actions[key] = [op, arg]
	func vm_action_done(key): return done.get(key, false)
	func vm_query_param(key, op, arg):
		return qparams.get("%d:%d" % [op, arg], 0)
	func vm_query_object(key, op, arg):
		return qobjects.get("%d:%d" % [op, arg], 0)

	var qparams := {}
	var qobjects := {}


func _initialize() -> void:
	await process_frame
	var sc = root.get_node("SCData")
	if not sc.is_mounted():
		sc.auto_mount()
	var VM = load("res://scripts/game/mission_vm.gd")
	var m = sc.mission("MISSIONS/MISN-10A.IFF")

	# Mission logic B2: 9+ structures destroyed (var 0) -> objective flag 4.
	var h := Host.new()
	VM.run(m.block(2), -1, h)
	_check("B2 idle: flag 4 not set", not h.flags.get(4, false))
	h.vars[0] = 9
	VM.run(m.block(2), -1, h)
	_check("B2 counter 0 >= 9 sets flag 4", h.flags.get(4, false))
	h = Host.new()
	h.flags[7] = true
	h.flags[8] = true
	VM.run(m.block(2), -1, h)
	_check("B2 both runways (flags 7, 8) set flag 4", h.flags.get(4, false))

	# Strike Base B3: flag 4 -> radio message 0x14 once (guarded by flag 5).
	h = Host.new()
	h.flags[4] = true
	VM.run(m.block(3), 13, h)
	_check("B3 announces mission accomplished", h.messages.has([13, 0x14]) and h.flags.get(5, false))
	h.messages.clear()
	VM.run(m.block(3), 13, h)
	_check("B3 announces only once", not h.messages.has([13, 0x14]))

	# Wingman: init sets state 'a', take-off, then follow the player when done.
	h = Host.new()
	VM.run(m.block(4), 0, h)
	_check("B4 init sets state label a", h.vars.get(6, 0) == 0x61)
	VM.run(m.block(5), 0, h)
	_check("B5 state a: take off", h.actions.get(0, []) == [0xa1, 1])
	h.done[0] = true
	VM.run(m.block(5), 0, h)
	_check("B5 take-off done advances to state b", h.vars.get(6, 0) == 0x62)
	VM.run(m.block(5), 0, h)
	_check("B5 state b: follow the player (id 9)", h.actions.get(0, []) == [0xaa, 9])

	# Area 5 scene B6 activates the F-18 ambush (ids 5..8).
	h = Host.new()
	VM.run(m.block(6), -1000, h)
	_check("B6 activates ids 5-8", h.activated == [5, 6, 7, 8])

	# Radio texts come from INTEL/<actor>.IFF
	var r: Dictionary = sc.radio("STRIBASE")
	_check("STRIBASE radio 0x14", r.msgs.get(0x14, "").begins_with("Mission accomplished"))
	print("speaker=%s msg=%s" % [r.speaker, r.msgs.get(0x14, "")])

	# Parameter ops 21/24/25/2e push; 14 n consumes (var n = pop).
	# MISN-4C blk1: "10 00 14 07" -> var7 = 0, "11 02 14 00" -> var0 = var2,
	# "2e 19 50 06" -> var6 = pushed param 0x19, "2e 64 14 01" -> var1 = pushed.
	h = Host.new()
	h.qparams["46:25"] = 7    # (0x2e, 0x19)
	h.qparams["46:100"] = 3   # (0x2e, 0x64)
	h.vars[2] = 5
	VM.run(sc.mission("MISSIONS/MISN-4C.IFF").block(1), -1, h)
	_check("14 n sets var n = pop", h.vars.get(7, -1) == 0 and h.vars.get(0, -1) == 5)
	_check("2e + 50 -> var6 = param 0x19", h.vars.get(6, 0) == 7)
	_check("2e + 14 -> var1 = param 0x64", h.vars.get(1, 0) == 3)

	# Object query ops 93/98 as aircraft-state booleans (decoded from usage).
	# MISN-10D blk10 runs once (guarded by flag 3): activates F-15 backups
	# (ids 7, 8) and the 747 (id 2) when both escorts are flying and not parked.
	var m10d = sc.mission("MISSIONS/MISN-10D.IFF")
	h = Host.new()
	h.qobjects["%d:%d" % [0x93, 5]] = 1
	h.qobjects["%d:%d" % [0x98, 5]] = 0
	h.qobjects["%d:%d" % [0x93, 6]] = 1
	h.qobjects["%d:%d" % [0x98, 6]] = 0
	VM.run(m10d.block(10), -1, h)
	_check("93 true && 98 false -> activate backups", h.activated == [7, 8, 2]
		and h.flags.get(3, false))
	h = Host.new()
	h.qobjects["%d:%d" % [0x93, 5]] = 0
	VM.run(m10d.block(10), -1, h)
	_check("93 false -> no activation, no flag", h.activated.is_empty()
		and not h.flags.get(3, false))

	# Distance query 95 in whole miles: submitted runway AI waits for the
	# player to be within 1 (MISN-14A blk3, owned by RWYEXT27).
	var m14a = sc.mission("MISSIONS/MISN-14A.IFF")
	h = Host.new()
	h.qobjects["%d:%d" % [0x95, 11]] = 3
	VM.run(m14a.block(3), 20, h)
	_check("95 = distance 3 -> far (var7 = 0)", h.vars.get(7, -1) == 0)
	h = Host.new()
	h.qobjects["%d:%d" % [0x95, 11]] = 0
	VM.run(m14a.block(3), 20, h)
	_check("95 = distance 0 -> landed (var7 = 1)", h.vars.get(7, -1) == 1)

	print("vm_test failures=%d" % failures)
	quit(failures)


func _check(name: String, ok: bool) -> void:
	print("%s %s" % ["PASS" if ok else "FAIL", name])
	if not ok:
		failures += 1
