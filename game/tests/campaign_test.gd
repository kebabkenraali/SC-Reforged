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
	var screens := []

	func show_office_screen(kind: String) -> void:
		screens.append(kind)

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

	# Office screens (effects 19 / 13 / 17): the ledger, kill board and catalog
	# as decoded from OPTTEST.EXE.
	var host_s := FakeHost.new()
	c.host = host_s
	await c.run([[0x19, 0], [0x13, 0], [0x17, 0]])
	_check("19 / 13 / 17 open ledger, kill board, catalog", host_s.screens == ["ledger", "kills", "catalog"], str(host_s.screens))
	var e = Campaign.new()
	e._reset_economy()
	e.cash = 5350
	e.overhead = 1500
	e.plane_costs = 500
	var rows: Array = e.ledger_rows()
	_check("ledger: previous 5850, current 5350, projected 3850", rows[0] == ["PREVIOUS CASH", 5850]
		and rows[4] == ["CURRENT CASH", 5350] and rows[7] == ["PROJ CASH", 3850], str(rows))
	var o: Dictionary = e.catalog_open()
	var w0: Array = e.weapons.duplicate()
	_check("package 1 = 2 GBU-15 + 24 MK-82 for 250", e.catalog_buy(o, 10) and e.weapons[6] == w0[6] + 2
		and e.weapons[5] == w0[5] + 24 and o.spent == 250, "%s spent %d" % [e.weapons, o.spent])
	_check("cancel returns the package", e.catalog_cancel(o, 10) and e.weapons == w0 and o.spent == 0)
	_check("the F-16 page cannot be ordered", not e.catalog_buy(o, 9))
	e.cash = 100
	o = e.catalog_open()
	var n_ok := 0
	while e.catalog_buy(o, 12):    # package 3, 800 each
		n_ok += 1
	_check("1 M$ credit: 100 + 1000 buys one 800 package", n_ok == 1 and o.spent == 800, "%d %d" % [n_ok, o.spent])
	e.catalog_close(o)
	_check("orders are charged with the next flight", e.purchases == 800 and e.ledger_rows()[2] == ["WEAPONS", 800])
	e.charge_flight()
	_check("flight start: cash - overhead - orders", e.cash == 100 - 1500 - 800 and e.purchases == 0, str(e.cash))
	e.pilots[0] = [3, 5, 1]
	e.pilots[7] = [12, 9, 1]
	e.pilots[4] = [9, 9, 0]
	var board: Array = e.kill_board()
	_check("kill board: most kills first, inactive pilots hidden", board.size() == 7 and board[0][0] == "HAWK"
		and board[1][0] == String(e.names.C).to_upper() and not board.any(func(r): return r[0] == "ZORRO"), str(board))
	# Hit areas and drawing of the screens.
	var Office = load("res://scripts/ui/office_screens.gd")
	var s = Office.new()
	s.campaign = e
	s.kind = "catalog"
	e.cash = 5000
	s._order = e.catalog_open()
	var hits := [s.hit(Vector2(60, 110)), s.hit(Vector2(60, 150)), s.hit(Vector2(170, 80)), s.hit(Vector2(190, 110))]
	_check("catalog page 1: AIM-9J, AIM-9M, AIM-120, LAU-3", hits.map(func(h): return h.get("rec", -1)) == [0, 1, 2, 4],
		str(hits.map(func(h): return h.get("rec", -1))))
	_check("catalog top edge returns, corner turns", s.hit(Vector2(100, 20)).what == "exit" and s.hit(s.CORNER_FORWARD).what == "forward")
	s.press(hits[0])
	_check("clicking an item orders it, its receipt cancels it", s._order.counts[0] == 1 and s.hit(Vector2(60, 196)).what == "receipt",
		str(s.hit(Vector2(60, 196))))
	var img: Image = s.compose()
	s.kind = "ledger"
	var img2: Image = s.compose()
	s.kind = "kills"
	var img3: Image = s.compose()
	_check("screens compose to 320 x 200", img.get_size() == Vector2i(320, 200) and img2.get_size() == Vector2i(320, 200)
		and img3.get_size() == Vector2i(320, 200))
	s.kind = "ledger"
	_check("ledger page turns from the page", s.hit(Vector2(150, 100)).what == "turn" and s.hit(Vector2(150, 10)).what == "exit")
	s.free()

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
