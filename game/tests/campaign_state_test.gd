## Plan items 3, 4, 5, 8: real campaign state (not FakeHost), weapon economy,
## debrief report fields, and save/load round trip.
extends SceneTree


var failures := 0


func _initialize() -> void:
	await process_frame
	var sc = root.get_node("SCData")
	if not sc.is_mounted():
		sc.auto_mount()
	var Campaign = load("res://scripts/game/campaign.gd")
	var BaseScreen = load("res://scripts/ui/base_screen.gd")
	Campaign.save_path = "user://campaign_state_test.json"
	var c = Campaign.new()
	var base = BaseScreen.new()
	base.campaign = c
	root.add_child(base)
	await process_frame

	# 3. real campaign state: the base-game list is GAMEFLOW.IFF's full MLST
	# (47 entries, alternates included). TOBIGTRE.TRE adds another set only
	# when the tactical data set is active.
	_check("47 base MLST entries, add-on excluded", c.mission_files().size() == 47, str(c.mission_files().size()))
	_check("first mission is MISN-1A", String(c.mission_files()[0]).ends_with("MISN-1A.IFF"), str(c.mission_files()[0]))

	# 4. economy: buying adds stock, flying consumes it
	c.cash = 20000
	var o: Dictionary = c.catalog_open()
	var before_weapons: int = int(c.weapons[0])
	_check("catalog buy succeeds", c.catalog_buy(o, 0), str(o))
	_check("catalog buy adds stock", int(c.weapons[0]) > before_weapons, "%d -> %d" % [before_weapons, c.weapons[0]])
	var stock: int = int(c.weapons[0])
	base._consume_loadout({c.WEAPONS[0]: 4})
	_check("flying consumes loadout", int(c.weapons[0]) == maxi(0, stock - 4), "%d -> %d" % [stock, c.weapons[0]])
	base._consume_loadout({c.WEAPONS[0]: 9999})
	_check("stock never goes negative", int(c.weapons[0]) >= 0, str(c.weapons[0]))

	# 5. debrief report fields from a real flight scene
	var FlightScene = load("res://scripts/game/flight_scene.gd")
	var f = FlightScene.new()
	f.mission_file = "MISSIONS/MISN-1A.IFF"
	root.add_child(f)
	await process_frame
	await physics_frame
	var r: Dictionary = f.campaign_report(true)
	for key in ["ok", "aborted", "regs", "jets_lost", "kills_air", "kills_ground"]:
		_check("debrief has " + key, r.has(key), str(r.keys()))
	f.queue_free()

	# 8. save / load round trip with changed state
	c.cash = 12345
	c.score = 678
	c.weapons[0] = 42
	c.wingman = "SAVED"
	c.save()
	var c2 = Campaign.new()
	_check("save file exists", Campaign.has_save(), "")
	_check("load succeeds", c2.load_saved(), "")
	_check("cash survives", c2.cash == 12345, str(c2.cash))
	_check("score survives", c2.score == 678, str(c2.score))
	_check("weapons survive", int(c2.weapons[0]) == 42, str(c2.weapons[0]))

	base.queue_free()
	print("campaign_state_test failures=", failures)
	quit(failures)


func _check(label: String, ok: bool, info: String) -> void:
	if not ok:
		failures += 1
	print("%s %s %s" % ["PASS" if ok else "FAIL", label, info])
