## Campaign state and the interpreter for GAMEFLOW effects.
##
## Effects (pairs op/arg, decoded from GAMEFLOW.IFF and the sprite labels):
##   00 n conversation n        01 n go to base screen n     06 n / 07 n set / clear flag
##   02 n story cut-scene MIDn  08 n establishing shot n (OPTIONS.IFF ESTB)
##   0c n select mission n      16 n fly the selected mission
##   0d n next stage = n        0f    go to the next stage
##   conditions 09 n / 0a n flag n clear / set, 14 / 15 last answer yes / no, 16 fly,
##   20 n mission n succeeded; 21 n: next n conditions all hold; 1e else, 1f endif
##   10 save  11 load  12 n transport (map animation n)  13 kill board  17 catalog  19 ledger
## Sprite requirements (REQU) are pairs (value, flag): flag must equal value.
## The `host` (the base screen) plays conversations, cut-scenes and flights.
extends RefCounted

const Demo = preload("res://scripts/core/demo.gd")

const Art = preload("res://scripts/core/art.gd")
static var save_path := "user://demo_campaign.json" if Demo.enabled() else "user://campaign.json"   # tests use their own file

signal screen_changed(screen_id: int)
signal message(text: String)

var stage := 0                  # index into gameflow.stages
var screen := -1                # current base screen id
var flags := {}                 # flag id -> bool
var next_stage := -1
var _pending_fly := false
var mission := -1               # mission number selected by 0c
var wingman := ""
var results := {}               # mission number -> 1 succeeded / 2 failed (read by 20 n)
var answer := true              # last yes / no answer in a conversation (read by 14 / 15)

# --- squadron economy (decoded from OPTTEST.EXE, see docs/GAMEFLOW_VM.md) ----
# Money in thousands of dollars, as in the original.
const WEAPONS := ["SWINDERJ", "SWINDERM", "AGM-65D", "DURANDAL", "MK20", "MK82", "GBU-15G", "POD", "AMRAAM"]
const PLANE_COST := 500         # replacement of one lost F-16 (k$)
const MAX_PLANES_LOST := 16     # more lost planes than this ends the game (effect 1d)
var cash := 0                   # +0x27b
var overhead := 0               # +0x27f, charged on every flight
var purchases := 0              # +0x283, catalog orders, charged on the next flight
var plane_costs := 0            # +0x287, replacement cost of the last flight's losses
var planes_lost := 0            # +0x3d4, whole campaign
var planes_lost_last := 0       # +0xea, last flight (effect 24)
var score := 0                  # +0x3dc
var weapons := [0, 0, 0, 0, 0, 0, 0, 0, 0]   # stock of WEAPONS (+0x261)
var pilots := []                # 8 x [air kills, ground kills, status]; 0 = the player
var stat := [0, 0, 0, 0]        # mission registers 2..5 of the last flight (conditions 25, 27-29)
var player_scored := false      # +0xed: the player got kills (effect 1a)
var game_over := 0              # 0xfe too many planes lost, 0xff out of money
var names := {"N": "Jack", "S": "Reed", "C": "Blade"}
var host                        # base screen: play_conversation / play_cutscene / fly_mission
var busy := false
## Loadout chosen on the weapon-loading screen for the upcoming flight
## (set by base_screen.fly_mission, consumed by flight_scene).
var _pending_loadout = null


func gameflow():
	return Art.gameflow()


## Campaign mission files in campaign order (MISN-1A, 1B, 1C, 2A, ...); the
## X / AA / BB variants are alternates and not part of the main sequence.
static func mission_files() -> Array:
	var out := []
	for f in SCData.list("MISSIONS/MISN-", ".IFF"):
		var tag: String = f.get_file().get_basename().substr(5)
		if tag.ends_with("X") or tag.ends_with("AA") or tag.ends_with("BB"):
			continue
		out.append(f)
	out.sort_custom(func(a, b): return _key(a) < _key(b))
	return out


static func _key(f: String) -> String:
	var tag: String = f.get_file().get_basename().substr(5)
	var digits := ""
	for ch in tag:
		if ch >= "0" and ch <= "9":
			digits += ch
	return "%03d%s" % [int(digits), tag.substr(digits.length())]


func current_stage() -> Dictionary:
	var st: Array = gameflow().stages
	return st[clampi(stage, 0, st.size() - 1)]


func flag(n: int) -> bool:
	return flags.get(n, false)


## True when a sprite's requirements hold.
func available(sprite: Dictionary) -> bool:
	for r in sprite.requires:
		if flag(r[1]) != (r[0] != 0):
			return false
	return true


## Sprites of the current screen as defined by the current stage.
func screen_sprites() -> Array:
	return current_stage().scenes.get(screen, [])


func substitute(text: String) -> String:
	return text.replace("$N", names.N).replace("$S", names.S).replace("$C", names.C) \
		.replace("$W", wingman if wingman != "" else "your wingman")


# --- stages ----------------------------------------------------------------

func start_new() -> void:
	print("CAMPAIGN: start_new()")
	stage = 0
	flags.clear()
	screen = -1
	_reset_economy()
	print("CAMPAIGN: playing MID1")
	await host.play_story(1)          # MID1: the opening cut-scene
	print("CAMPAIGN: MID1 done, entering stage 0")
	await enter_stage(0)


func _reset_economy() -> void:
	cash = 0
	overhead = 0
	purchases = 0
	plane_costs = 0
	planes_lost = 0
	planes_lost_last = 0
	score = 0
	weapons = [0, 0, 0, 0, 0, 0, 0, 0, 0]
	_reset_pilots()
	stat = [0, 0, 0, 0]
	player_scored = false
	game_over = 0


func _reset_pilots() -> void:
	pilots = []
	for i in 8:
		pilots.append([0, 0, 1])


## Effect 22 n: ledger transaction n of GAMEFLOW.IFF (FORM STAT / CHNG):
## CASH / OVER change the money, WEAP the weapon stock, PILT the pilots.
func apply_change(n: int) -> void:
	var c = gameflow().changes.get(n)
	if c == null:
		return
	if pilots.size() < 8:
		_reset_pilots()
	if c.has("cash"):
		cash = _apply(cash, c.cash[0], c.cash[1])
	if c.has("over"):
		overhead = _apply(overhead, c.over[0], c.over[1])
	for w in c.weap:
		if w[1] < weapons.size():
			weapons[w[1]] = maxi(0, _apply(weapons[w[1]], w[0], w[2]))
	for p in c.pilt:
		if p[1] < pilots.size() and p[2] < 3:
			pilots[p[1]][p[2]] = _apply(pilots[p[1]][p[2]], p[0], p[3])


static func _apply(v: int, op: int, amount: int) -> int:
	match op:
		0:
			return v + amount
		1:
			return v - amount
		2:
			return amount
	return v


## Charged when a flight starts (the original's hand-over to STRIKE.EXE).
func charge_flight() -> void:
	cash -= overhead + purchases
	purchases = 0


## misn2op: the flight's results. Returns 1 succeeded / 2 failed, or 0 when
## the flight was aborted (the original's exit code 5: nothing changes).
func apply_report(r) -> int:
	if not r is Dictionary:
		r = {"ok": bool(r), "regs": {0: 1 if r else 0}}
	if r.get("aborted", false):
		return 0
	var regs: Dictionary = r.get("regs", {})
	planes_lost_last = int(r.get("jets_lost", 0))
	planes_lost += planes_lost_last
	plane_costs = planes_lost_last * PLANE_COST
	stat = [int(regs.get(2, 0)), int(regs.get(3, 0)), int(regs.get(4, 0)), int(regs.get(5, 0))]
	cash += int(regs.get(1, 0)) & 0xffff
	if pilots.size() < 8:
		_reset_pilots()
	var ka: int = int(r.get("kills_air", 0))
	var kg: int = int(r.get("kills_ground", 0))
	pilots[0][0] += ka
	pilots[0][1] += kg
	player_scored = ka > 0 or kg > 0
	# Success is the mission script's register 0 (MISN-1A: flag 12,
	# "Mission accomplished"); without registers the flight's own verdict.
	var ok: bool = int(regs.get(0, 0)) != 0 if regs.has(0) else bool(r.get("ok", false))
	cash -= plane_costs
	return 1 if ok else 2


func ledger_text() -> String:
	return "Ledger: cash $%dK, overhead $%dK per mission, plane losses $%dK, orders $%dK." % [
		cash, overhead, plane_costs, purchases]


func enter_stage(index: int) -> void:
	stage = index
	next_stage = -1
	save()
	var st = current_stage()
	print("CAMPAIGN: enter_stage %d, effects count: %d" % [index, st.effects.size()])
	for i in st.effects:
		print("CAMPAIGN:   effect %s" % str(i))
	await run(st.effects)


## Condition effects: when one fails, the following effects are skipped up to
## the matching 1e (else) or 1f (endif). Decoded from the original interpreter
## (OPTTEST.EXE 0xb916, see docs/GAMEFLOW_VM.md): the condition ops are
## 09 0a 14 15 16 1c 20 23 25 (and 27-2a, unused). 16 is the weapon-loading
## screen: true when the player clicks the cockpit to fly.
const CONDITIONS := [0x09, 0x0a, 0x14, 0x15, 0x16, 0x1c, 0x20, 0x23, 0x25, 0x27, 0x28, 0x29, 0x2a]


## Runs an effect list; awaits conversations, cut-scenes and flights.
func run(effects: Array) -> void:
	busy = true
	var skip := false        # inside a branch whose condition failed
	var depth := 0           # conditions nested inside the skipped branch
	var all_of := 0          # 21 n: the next n effects are conditions that must all hold
	# Pending "fly" command (the original's +0xe8 = 1, set by 16 / 03 / 0e):
	# the flight starts only after the whole effect list has run, so effects
	# after 16 (stage 2's "06 40") happen before the flight, whatever its result.
	_pending_fly = false
	var i := 0
	while i < effects.size():
		var op: int = effects[i][0]
		var arg: int = effects[i][1]
		i += 1
		var chained := all_of > 0
		if chained:
			all_of -= 1
		if op == 0x1e:                # else
			if depth == 0:
				skip = not skip
			continue
		if op == 0x1f:                # endif
			if depth == 0:
				skip = false
			else:
				depth -= 1
			continue
		if op == 0x21:
			all_of = arg
			continue
		if skip and not chained:
			if op in CONDITIONS:
				depth += 1
			continue
		if op in CONDITIONS:
			if not await _condition(op, arg):
				skip = true
			continue
		match op:
			0x00:
				var r = await host.play_conversation(arg)
				if r is Dictionary:
					answer = r.get("accepted", true)
			0x01:
				screen = arg
				screen_changed.emit(arg)
			0x06:
				flags[arg] = true
			0x07:
				flags[arg] = false
			0x02:
				await host.play_story(arg)
			0x08:
				await host.play_cutscene(arg)
			0x0c:
				mission = arg
			0x0d:
				next_stage = arg
			0x0f:
				var target: int = gameflow().stage_index(next_stage) if next_stage >= 0 else stage + 1
				if target >= 0 and target < gameflow().stages.size():
					busy = false
					await enter_stage(target)
					return
			0x10, 0x11:
				save()
				message.emit("Progress is saved automatically.")
			0x03:
				mission = arg
				_pending_fly = true
			0x0e:
				_pending_fly = true
			0x18:
				if host.has_method("play_music"):
					host.play_music(arg)
			0x12:
				await host.play_transport(arg)
			0x13:
				message.emit("Kill board: you have %d air / %d ground kills." % [pilots[0][0], pilots[0][1]])
			0x17:
				message.emit("Weapons catalog is not available yet.")
			0x19:
				message.emit(ledger_text())
			0x1a:
				# After a flight in which the player scored: the kill board update.
				if player_scored:
					message.emit("Kill board updated: %d air / %d ground kills." % [pilots[0][0], pilots[0][1]])
			0x1b:
				if arg < pilots.size():
					pilots[arg][2] = 0
			0x1d:
				# Game over: too many planes lost or out of money.
				if planes_lost > MAX_PLANES_LOST:
					game_over = 0xfe
				elif cash < 0:
					game_over = 0xff
				if game_over != 0:
					message.emit("The Wildcats are finished: %s." % ("too many planes lost" if game_over == 0xfe else "out of money"))
					if host.has_method("end_campaign"):
						host.end_campaign(game_over)
					busy = false
					return
			0x22:
				apply_change(arg)
			0x24:
				# A plane was lost on the last flight: music 8 and the loss talk.
				if planes_lost_last != 0:
					if host.has_method("play_music"):
						host.play_music(8)
					var r2 = await host.play_conversation(0xfc)
					if r2 is Dictionary:
						answer = r2.get("accepted", true)
	busy = false
	if _pending_fly and mission >= 0:
		_pending_fly = false
		# The original writes op2misn.iff, hands over to STRIKE.EXE and comes
		# back with misn2op.iff: then the stage named by 0d starts, whatever
		# the result (stage 1 reads it with "20 0" -> flag 72).
		charge_flight()
		var r = await host.fly_mission(mission)
		if r == null:
			cash += overhead
			return
		var res := apply_report(r)
		if res == 0:
			cash += overhead     # aborted: as if the mission had not been flown
			return
		results[mission] = res
		if res == 1 and Demo.enabled() and mission >= Demo.LAST_MISSION:
			host.end_demo()
			return
		var target: int = gameflow().stage_index(next_stage) if next_stage >= 0 else stage + 1
		if target >= 0 and target < gameflow().stages.size():
			await enter_stage(target)
			save()   # progress after every flight (the original saved in the barracks)


func _condition(op: int, arg: int) -> bool:
	match op:
		0x16:
			# Weapon-loading screen (argument: loadout set, not decoded).
			if mission < 0:
				return false
			var go: bool = await host.choose_loadout(mission) if host.has_method("choose_loadout") else true
			if go:
				_pending_fly = true
			return go
		0x09:
			return not flags.get(arg, false)
		0x0a:
			return flags.get(arg, false)
		0x14:
			return answer
		0x15:
			return not answer
		0x20:
			return int(results.get(arg, 0)) == 1
		0x25, 0x27, 0x28, 0x29:
			# Mission registers 2..5 of the last flight (STAT words 2..5).
			return stat[[0x25, 0x27, 0x28, 0x29].find(op)] != 0
		0x1c:
			return true
	return false                      # 23: always false in the original; 2a: field not decoded


func activate(sprite: Dictionary) -> void:
	if busy or not available(sprite):
		return
	await run(sprite.effects)


# --- persistence --------------------------------------------------------------

func save() -> void:
	var f := FileAccess.open(save_path, FileAccess.WRITE)
	if f == null:
		return
	var fl := {}
	for k in flags:
		fl[str(k)] = flags[k]
	var res := {}
	for k in results:
		res[str(k)] = results[k]
	f.store_string(JSON.stringify({"stage": stage, "screen": screen, "flags": fl,
		"mission": mission, "wingman": wingman, "names": names, "results": res,
		"economy": {"cash": cash, "overhead": overhead, "purchases": purchases,
			"plane_costs": plane_costs, "planes_lost": planes_lost, "planes_lost_last": planes_lost_last,
			"score": score, "weapons": weapons, "pilots": pilots, "stat": stat}}))


static func has_save() -> bool:
	return FileAccess.file_exists(save_path)


func load_saved() -> bool:
	var f := FileAccess.open(save_path, FileAccess.READ)
	if f == null:
		return false
	var d = JSON.parse_string(f.get_as_text())
	if not d is Dictionary:
		return false
	stage = int(d.get("stage", 0))
	screen = int(d.get("screen", -1))
	mission = int(d.get("mission", -1))
	wingman = d.get("wingman", "")
	names.merge(d.get("names", {}), true)
	flags.clear()
	for k in d.get("flags", {}):
		flags[int(k)] = d.flags[k]
	results.clear()
	for k in d.get("results", {}):
		results[int(k)] = int(d.results[k])
	_reset_economy()
	var e: Dictionary = d.get("economy", {})
	for key in ["cash", "overhead", "purchases", "plane_costs", "planes_lost", "planes_lost_last", "score"]:
		set(key, int(e.get(key, get(key))))
	if e.has("weapons"):
		weapons = e.weapons.map(func(v): return int(v))
	if e.has("pilots"):
		pilots = e.pilots.map(func(p): return p.map(func(v): return int(v)))
	if e.has("stat"):
		stat = e.stat.map(func(v): return int(v))
	return true
