## Campaign flow against the original GAMEFLOW data with a fake host.
## Run: Godot --headless --path game --script res://tests/campaign_test.gd
extends SceneTree

var failures := 0


class FakeHost:
	var conversations := []
	var cutscenes := []
	var flights := []
	var succeed := true
	var report = null      # flight report (Dictionary) instead of a plain result
	var go := true
	var music := []

	func choose_loadout(_n: int) -> bool:
		return go

	func play_music(n: int) -> void:
		music.append(n)

	func play_conversation(n: int) -> void:
		conversations.append(n)

	func play_cutscene(n: int) -> void:
		cutscenes.append(n)

	func play_story(n: int) -> void:
		cutscenes.append(1000 + n)

	func play_transport(_n: int) -> void:
		pass

	func fly_mission(n: int):
		flights.append(n)
		return report if report != null else succeed


func _initialize() -> void:
	await process_frame
	var sc = root.get_node("SCData")
	if not sc.is_mounted():
		sc.auto_mount()
	var Campaign = load("res://scripts/game/campaign.gd")
	Campaign.save_path = "user://campaign_test.json"

	var files: Array = Campaign.mission_files()
	_check("40 campaign missions in order", files.size() == 40 and files[0].ends_with("MISN-1A.IFF")
		and files[3].ends_with("MISN-2A.IFF") and files[4].ends_with("MISN-3A.IFF"), "%d %s" % [files.size(), files.slice(0, 5)])

	var c = Campaign.new()
	var host := FakeHost.new()
	c.host = host
	await c.start_new()
	_check("stage 0 opens the hangar (screen 11)", c.screen == 11, str(c.screen))
	_check("stage 0 plays cut-scene 5", host.cutscenes.has(5), str(host.cutscenes))
	_check("stage 0 starts music 0 (18 0)", host.music.has(0), str(host.music))
	# Economy from GAMEFLOW.IFF FORM STAT: stage 0 runs 22 1 (CASH = 4850)
	# and 22 21 (OVER = 1500), in thousands of dollars.
	_check("starting cash $4850K, overhead $1500K", c.cash == 4850 and c.overhead == 1500,
		"cash %d overhead %d" % [c.cash, c.overhead])
	_check("starting weapon stock (22 10)", c.weapons[0] > 0, str(c.weapons))

	var sprites: Array = c.screen_sprites()
	var fly = null
	for s in sprites:
		for e in s.effects:
			if e[0] == 0x0c:
				fly = s
	if fly == null:
		# The Fly Mission hotspot lives on another screen of stage 0.
		for sid in c.current_stage().scenes:
			for s in c.current_stage().scenes[sid]:
				for e in s.effects:
					if e[0] == 0x0c:
						fly = s
	_check("stage 0 has a Fly Mission hotspot", fly != null)
	if fly != null:
		await c.activate(fly)
		_check("briefing conversation 11 before flying", host.conversations.has(11), str(host.conversations))
		_check("flies mission 0 (MISN-1A)", host.flights == [0], str(host.flights))
		# After the flight the campaign enters the stage named by 0d (stage 1),
		# which records the result in flag 72 (20 0 -> set, else clear).
		_check("successful flight -> stage 1, flag 72 set", c.stage == 1 and c.flags.get(72, false),
			"stage %d flags %s" % [c.stage, c.flags.keys()])
		# Paid flight: overhead charged, payment = mission register 1 (MISN-1A:
		# 2500 when flag 12 is set), one lost plane costs 500.
		var c4 = Campaign.new()
		var host4 := FakeHost.new()
		host4.report = {"ok": true, "regs": {0: 1, 1: 2500}, "jets_lost": 1, "kills_air": 3}
		c4.host = host4
		await c4.start_new()
		await c4.activate(fly)
		_check("payment and losses: 4850 - 1500 + 2500 - 500 = 5350", c4.cash == 5350 and c4.planes_lost == 1
			and c4.results.get(0) == 1 and c4.pilots[0][0] == 3, "cash %d lost %d results %s" % [c4.cash, c4.planes_lost, c4.results])
		var c5 = Campaign.new()
		var host5 := FakeHost.new()
		host5.report = {"ok": false, "aborted": true}
		c5.host = host5
		await c5.start_new()
		await c5.activate(fly)
		_check("aborted flight: no cost, same stage", c5.cash == 4850 and c5.stage == 0 and not c5.results.has(0),
			"cash %d stage %d" % [c5.cash, c5.stage])
		# Backing out of the loadout screen (16 false): no flight, same stage.
		var c3 = Campaign.new()
		var host3 := FakeHost.new()
		host3.go = false
		c3.host = host3
		await c3.start_new()
		await c3.activate(fly)
		_check("loadout refused -> no flight, stage 0", host3.flights.is_empty() and c3.stage == 0,
			"flights %s stage %d" % [host3.flights, c3.stage])
		# A failed flight continues the campaign too (as in the original data).
		var c2 = Campaign.new()
		var host2 := FakeHost.new()
		host2.succeed = false
		c2.host = host2
		await c2.start_new()
		await c2.activate(fly)
		_check("failed flight -> stage 1 too, flag 72 clear", c2.stage == 1 and not c2.flags.get(72, false),
			"stage %d flags %s results %s" % [c2.stage, c2.flags.keys(), c2.results])

	# Requirements: a sprite needing flag (value 1) is hidden until the flag is set.
	var req := {"requires": [[1, 0x28]], "effects": []}
	_check("requirement hides sprite while flag clear", not c.available(req))
	c.flags[0x28] = true
	_check("requirement shows sprite once flag set", c.available(req))

	# Branches as in OPTTEST.EXE: 20 n = mission n succeeded, 1e else, 1f endif.
	var branch := [[0x20, 0], [0x06, 72], [0x1e, 0], [0x07, 72], [0x1f, 0], [0x06, 73]]
	c.results = {0: 1}
	await c.run(branch)
	_check("20 n true branch", c.flags.get(72, false) and c.flags.get(73, false))
	c.results = {0: 2}
	await c.run(branch)
	_check("20 n else branch", not c.flags.get(72, true) and c.flags.get(73, false))
	c.answer = false
	c.flags.erase(74)
	await c.run([[0x14, 0], [0x09, 9], [0x06, 74], [0x1f, 0], [0x1e, 0], [0x06, 75], [0x1f, 0]])
	_check("nested condition skipped, else taken", not c.flags.has(74) and c.flags.get(75, false))
	c.flags[80] = true
	await c.run([[0x21, 2], [0x0a, 80], [0x0a, 81], [0x06, 82], [0x1f, 0]])
	_check("21 n: all conditions must hold", not c.flags.has(82))

	_check("text substitution", c.substitute("Hey, $N.") == "Hey, %s." % c.names.N)
	c.save()
	var d = Campaign.new()
	_check("save / load round trip", d.load_saved() and d.stage == c.stage and d.flags.get(0x28, false))

	print("campaign_test failures=%d" % failures)
	quit(failures)


func _check(name: String, ok: bool, detail := "") -> void:
	print("%s %s %s" % ["PASS" if ok else "FAIL", name, detail])
	if not ok:
		failures += 1
