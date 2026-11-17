## Mission script interpreter tests. The semantics follow the original
## interpreter in STRIKE.EXE (docs/PROG_VM.md): accumulator, condition flags,
## one variable array for flags and variables, forward-only labels, "09 x"
## extra arguments, 02 n block calls, E = action status.
## Run: Godot --headless --path game --script res://tests/vm_test.gd
extends SceneTree

var failures := 0


class Host:
	var vars := {}
	var states := {}
	var blocks := {}
	var regs := {}
	var globals := {}
	var alive := {}
	var actions := {}
	var done := {}
	var measures := {}
	var messages := []
	var activated := []
	var owner_ok := true
	var ended = null

	func vm_state(key):
		if not states.has(key): states[key] = {"acc": 0, "e": 0, "cond": 0}
		return states[key]
	func vm_block(n): return blocks.get(n, [])
	func vm_var(n): return vars.get(n, 0)
	func vm_set_var(n, v): vars[n] = v
	func vm_set_register(n, v): regs[n] = v
	func vm_global(op, arg): globals[op] = arg
	func vm_part_state(op, id):
		if op == 0x92: return alive.get(id, true)
		return false
	func vm_owner_ready(_key): return owner_ok
	func vm_measure(_key, op, arg): return measures.get("%d:%d" % [op, arg], 0)
	func vm_wait(_key, _secs): return true
	func vm_activate(id): activated.append(id)
	func vm_remove(_id): pass
	func vm_message(key, n): messages.append([key, n])
	func vm_end(ok): ended = ok
	func vm_action(key, op, arg, extra := -1): actions[key] = [op, arg, extra]
	func vm_action_done(key): return done.get(key, false)


func _p(pairs: Array) -> Array:
	var out := []
	for i in range(0, pairs.size(), 2):
		out.append([pairs[i], pairs[i + 1]])
	return out


func _initialize() -> void:
	await process_frame
	var sc = root.get_node("SCData")
	if not sc.is_mounted():
		sc.auto_mount()
	var VM = load("res://scripts/game/mission_vm.gd")

	# --- instruction semantics (hand-made programs) ---------------------------
	var h := Host.new()
	h.vars[4] = 3
	VM.run(_p([0x10, 5, 0x20, 3, 0x50, 1,  0x10, 7, 0x2e, 3, 0x50, 2,
		0x10, 7, 0x24, 2, 0x50, 3,  0x10, 2, 0x2f, 4, 0x50, 5,
		0x11, 4, 0x21, 4, 0x50, 6,  0x10, 0x20, 0x30, 3, 0x50, 7,
		0x10, 4, 0x23, 4,  0x10, 1, 0x27, 6,  0x01, 0]), 0, h)
	_check("ALU: 10/20/2e/24/2f/21/30 into vars via 50",
		h.vars.get(1) == 8 and h.vars.get(2) == 21 and h.vars.get(3) == 5
		and h.vars.get(5) == 6 and h.vars.get(6) == 5 and h.vars.get(7) == 10, str(h.vars))
	_check("23 n: var += ACC (var4 3+4=7); 27 n: var -= ACC (var6 6-1=5)",
		h.vars.get(4) == 7 and h.vars.get(6) == 5, str(h.vars))

	h = Host.new()
	h.vars[9] = 1
	VM.run(_p([0x45, 9, 0x48, 1, 0x52, 20, 0x08, 1,      # flag 9 == 1 -> skip
		0x10, 5, 0x40, 5, 0x4b, 2, 0x52, 21, 0x08, 2,      # 5 > 5? no -> set 21
		0x10, 6, 0x40, 5, 0x4d, 3, 0x52, 22, 0x08, 3,      # 6 >= 5 -> skip 22
		0x10, 4, 0x40, 5, 0x4a, 4, 0x52, 23, 0x08, 4,      # 4 < 5 -> skip 23
		0x01, 0]), 0, h)
	_check("compare + 48/4b/4d/4a jumps", not h.vars.has(20) and h.vars.get(21) == 1
		and not h.vars.has(22) and not h.vars.has(23), str(h.vars))

	h = Host.new()
	VM.run(_p([0x08, 2, 0x55, 9, 0x4e, 2, 0x52, 10, 0x01, 0]), 0, h)
	_check("labels are searched forward only (no loop back)", h.vars.get(9) == 1 and h.vars.get(10) == 1, str(h.vars))
	h = Host.new()
	h.vars[3] = 0x41
	VM.run(_p([0x11, 3, 0x4f, 0, 0x52, 1, 0x08, 0x41, 0x52, 2, 0x01, 0]), 0, h)
	_check("4f: jump to label ACC (state machine)", not h.vars.has(1) and h.vars.get(2) == 1, str(h.vars))
	h = Host.new()
	VM.run(_p([0x52, 5, 0x54, 5, 0x52, 6, 0x53, 6, 0x55, 7, 0x55, 7, 0x56, 7, 0x01, 0]), 0, h)
	_check("52/53/54/55/56 on the shared variable array", h.vars.get(5) == 0 and h.vars.get(6) == 0 and h.vars.get(7) == 1, str(h.vars))

	h = Host.new()
	h.blocks[3] = _p([0x52, 10, 0x01, 0])
	VM.run(_p([0x02, 3, 0x52, 11, 0x01, 0]), 0, h)
	_check("02 n calls block n and returns", h.vars.get(10) == 1 and h.vars.get(11) == 1, str(h.vars))

	h = Host.new()
	VM.run(_p([0xa5, 7, 0x09, 0x0b, 0x46, 1, 0x52, 1, 0x08, 1, 0x01, 0]), 4, h)
	_check("09 x is the extra argument of the action", h.actions.get(4) == [0xa5, 7, 0x0b], str(h.actions))
	_check("46: action in progress (E != 0) jumps", not h.vars.has(1), str(h.vars))
	h.done[4] = true
	VM.run(_p([0xa5, 7, 0x09, 0x0b, 0x46, 1, 0x52, 1, 0x08, 1, 0x01, 0]), 4, h)
	_check("46: action finished falls through", h.vars.get(1) == 1, str(h.vars))
	h = Host.new()
	h.owner_ok = false
	VM.run(_p([0xa5, 7, 0x46, 1, 0x52, 1, 0x08, 1, 0x01, 0]), -1, h)
	_check("actions without an owner do nothing (E = 0)", h.actions.is_empty() and h.vars.get(1) == 1)

	# --- original mission programs ---------------------------------------------
	var m = sc.mission("MISSIONS/MISN-10A.IFF")
	h = Host.new()
	VM.run(m.block(2), -1, h)
	_check("10A B2 idle: flag 4 not set", h.vars.get(4, 0) != 1)
	h.vars[0] = 9
	VM.run(m.block(2), -1, h)
	_check("10A B2 counter 0 >= 9 sets flag 4", h.vars.get(4, 0) == 1, str(h.vars))
	h = Host.new()
	h.vars[4] = 1
	VM.run(m.block(3), 13, h)
	_check("10A B3 announces mission accomplished", h.messages.has([13, 0x14]) and h.vars.get(5, 0) == 1)
	h.messages.clear()
	VM.run(m.block(3), 13, h)
	_check("10A B3 announces only once", not h.messages.has([13, 0x14]))
	h = Host.new()
	VM.run(m.block(4), 0, h)
	_check("10A B4 init sets state label a", h.vars.get(6, 0) == 0x61)
	VM.run(m.block(5), 0, h)
	_check("10A B5 state a: take off", h.actions.get(0, []).slice(0, 2) == [0xa1, 1], str(h.actions))
	h.done[0] = true
	VM.run(m.block(5), 0, h)
	_check("10A B5 take-off done advances to state b", h.vars.get(6, 0) == 0x62)
	VM.run(m.block(5), 0, h)
	_check("10A B5 state b: follow the player (id 9)", h.actions.get(0, []).slice(0, 2) == [0xaa, 9], str(h.actions))
	h = Host.new()
	VM.run(m.block(6), -1000, h)
	_check("10A B6 activates ids 5-8", h.activated == [5, 6, 7, 8])

	# MISN-1A C-130 (block 7): 97 07 is the distance to SPOT 7, the cargo
	# field. Flag 6 = "within 5 (x 1000 ft) of the cargo field"; with flag 6
	# and every MiG down it radios "We're safe" (#21) and sets flags 7 and 12.
	var m1 = sc.mission("MISSIONS/MISN-1A.IFF")
	h = Host.new()
	h.vars[5] = 0x31
	h.measures["%d:%d" % [0x97, 7]] = 9
	VM.run(m1.block(7), 8, h)
	_check("1A C-130 far from the cargo field: no flag 6", h.vars.get(6, 0) != 1, str(h.vars))
	h = Host.new()
	h.vars[5] = 0x31
	h.measures["%d:%d" % [0x97, 7]] = 4
	h.alive = {5: false, 6: false, 7: false}
	VM.run(m1.block(7), 8, h)
	_check("1A C-130 near the cargo field: flag 6", h.vars.get(6, 0) == 1, str(h.vars))
	VM.run(m1.block(7), 8, h)
	_check("1A MiGs down + flag 6 -> 'We're safe' and flags 7, 12",
		h.messages.has([8, 0x15]) and h.vars.get(7, 0) == 1 and h.vars.get(12, 0) == 1, "%s %s" % [h.messages, h.vars])

	var r: Dictionary = sc.radio("STRIBASE")
	_check("STRIBASE radio 0x14", r.msgs.get(0x14, "").begins_with("Mission accomplished"))

	print("vm_test failures=%d" % failures)
	quit(failures)


func _check(name: String, ok: bool, detail := "") -> void:
	print("%s %s %s" % ["PASS" if ok else "FAIL", name, detail if not ok else ""])
	if not ok:
		failures += 1
