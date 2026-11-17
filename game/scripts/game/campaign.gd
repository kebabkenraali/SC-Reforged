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
var mission := -1               # mission number selected by 0c
var wingman := ""
var results := {}               # mission number -> 1 succeeded / 2 failed (read by 20 n)
var answer := true              # last yes / no answer in a conversation (read by 14 / 15)
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
	print("CAMPAIGN: playing MID1")
	await host.play_story(1)          # MID1: the opening cut-scene
	print("CAMPAIGN: MID1 done, entering stage 0")
	await enter_stage(0)


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
## the matching 1e (else) or 1f (endif), as in OPTTEST.EXE's interpreter.
## (16 "fly" is NOT a condition: the original continues the campaign after a
## failed flight too - the next stage reads the result with 20 n.)
const CONDITIONS := [0x09, 0x0a, 0x14, 0x15, 0x1c, 0x20, 0x23, 0x25]


## Runs an effect list; awaits conversations, cut-scenes and flights.
func run(effects: Array) -> void:
	busy = true
	var skip := false        # inside a branch whose condition failed
	var depth := 0           # conditions nested inside the skipped branch
	var all_of := 0          # 21 n: the next n effects are conditions that must all hold
	var flown := false       # a 16 flight ran in this list -> go to the next stage at the end
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
			0x16:
				# Fly the selected mission. Decoded from GAMEFLOW: every stage
				# names its successor on entry (0d n) and the flight leads there
				# whatever the result - stage 1 starts with "20 0" (did mission 0
				# succeed?) and sets flag 72 for the later conversations; stage 2
				# names itself and re-enters with flag 40 set by the "06 40" that
				# follows its flight. The argument of 16 is not understood yet.
				if mission < 0:
					continue
				var r = await host.fly_mission(mission)
				if r == null:
					busy = false      # not flown (backed out of the loadout screen)
					return
				results[mission] = 1 if r else 2
				flown = true
				if r and Demo.enabled() and mission >= Demo.LAST_MISSION:
					host.end_demo()
					busy = false
					return
			0x12:
				await host.play_transport(arg)
			0x13:
				message.emit("Kill board is not available yet.")
			0x17:
				message.emit("Weapons catalog is not available yet.")
			0x19:
				message.emit("Ledger is not available yet.")
	busy = false
	if flown:
		var target: int = gameflow().stage_index(next_stage) if next_stage >= 0 else stage + 1
		if target >= 0 and target < gameflow().stages.size():
			await enter_stage(target)
			save()   # progress after every flight (the original saved in the barracks)


func _condition(op: int, arg: int) -> bool:
	match op:
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
		0x1c:
			return true
	return false                      # 23 / 25: state the port does not track yet


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
		"mission": mission, "wingman": wingman, "names": names, "results": res}))


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
	return true
