## Tactical Operations campaign control: gameflow stages, mission order,
## art-set switching, add-on midgame fallback and save/load of the mode flag.
extends SceneTree


var failures := 0


func _initialize() -> void:
	await process_frame
	var sc = root.get_node("SCData")
	if not sc.is_mounted():
		sc.auto_mount()
	var Campaign = load("res://scripts/game/campaign.gd")
	var Art = load("res://scripts/core/art.gd")
	var Midgame = load("res://scripts/formats/sc_midgame.gd")
	Campaign.save_path = "user://tactical_flow_test.json"
	var c = Campaign.new()

	# --- base campaign is the default -----------------------------------------
	Art.set_active("base")
	_check("base default", Art.active_set == "base", Art.active_set)
	_check("base MLST parsed", c.gameflow().mission_list.size() == 47, str(c.gameflow().mission_list.size()))
	_check("base first MLST entry", c.gameflow().mission_list[0] == "MISN-1A", str(c.gameflow().mission_list[0]))
	var base_files: Array = c.mission_files()
	_check("base mission order", base_files.size() == 47 and String(base_files[0]).ends_with("MISN-1A.IFF")
		and String(base_files[1]).ends_with("MISN-1B.IFF")
		and String(base_files[12]).ends_with("MISN-5BB.IFF"), "%d %s" % [base_files.size(), str(base_files.slice(0, 2))])

	# --- tactical campaign -----------------------------------------------------
	c.tactical = true
	Art.set_active("tactical")
	_check("tactical active", Art.active_set == "tactical", Art.active_set)
	_check("tactical gameflow is GAMEFLO2", c.gameflow().stages.size() == 28, str(c.gameflow().stages.size()))
	_check("tactical MLST parsed", c.gameflow().mission_list.size() == 37, str(c.gameflow().mission_list.size()))
	_check("tactical MLST first/last", c.gameflow().mission_list[0] == "MISN-A1" \
		and c.gameflow().mission_list[36] == "MISN-H1", "%s / %s" % [c.gameflow().mission_list[0], c.gameflow().mission_list[36]])
	_check("tactical screens from OPTIONS2", c.gameflow().screens.size() == 15, str(c.gameflow().screens.size()))
	var tac_files: Array = c.mission_files()
	_check("tactical mission order", tac_files.size() == 37 and String(tac_files[0]).ends_with("MISN-A1.IFF")
		and String(tac_files[1]).ends_with("MISN-A2.IFF")
		and String(tac_files[36]).ends_with("MISN-H1.IFF"), "%d %s" % [tac_files.size(), str(tac_files.slice(0, 2))])
	_check("tactical empty slots keep their index", tac_files[2] == "" and tac_files[20] == "" and tac_files[34] == "", "")
	_check("tactical list has no base missions", not tac_files.any(func(f): return String(f).match("*MISN-1A.IFF")), "")
	_check("tactical art archive", String(Art.archives().opt[0]).ends_with("OPTSHPS2.PAK"), str(Art.archives()))
	_check("tactical conv archive", String(Art.archives().conv[0]).ends_with("CONVSHP2.PAK"), str(Art.archives()))
	_check("tactical add-on cutscene exists", Midgame.exists(5) and Midgame.exists(2) and Midgame.exists(3), "")

	# Add-on midgame fallback: real art, voice and captions from the install.
	var m = Midgame.load_number(5)
	_check("add-on midgame art loaded", m.shots.size() > 0, "shots=%d" % m.shots.size())
	_check("add-on midgame voice loaded", m.voices.size() > 0, "voices=%d" % m.voices.size())
	_check("add-on midgame text loaded", m.texts.size() > 0 or m.titles.size() > 0,
		"texts=%d titles=%d" % [m.texts.size(), m.titles.size()])

	# --- stage control is driven by the active gameflow ------------------------
	c.stage = 0
	var st: Dictionary = c.current_stage()
	_check("stage 0 is add-on opening", st.effects.any(func(e): return e[0] == 0x02 and e[1] == 5), str(st.effects))
	c.next_stage = 1
	_check("stage_index resolves add-on ids", c.gameflow().stage_index(st.id) == 0, str(st.id))

	# --- save / load the mode --------------------------------------------------
	c.screen = 11
	c.save()
	var c2 = Campaign.new()
	_check("tactical save loads", c2.load_saved(), "")
	_check("tactical flag survives", c2.tactical and Art.active_set == "tactical", "%s %s" % [c2.tactical, Art.active_set])
	_check("loaded gameflow is add-on", c2.gameflow().stages.size() == 28, str(c2.gameflow().stages.size()))
	_check("loaded mission list is add-on", String(c2.mission_files()[0]).ends_with("MISN-A1.IFF"), str(c2.mission_files()[0]))

	# --- switching back restores the base data set -----------------------------
	Art.set_active("base")
	_check("base restored", Art.active_set == "base" and c.gameflow().stages.size() > 28, str(c.gameflow().stages.size()))
	_check("base art restored", String(Art.archives().opt[0]).ends_with("OPTSHPS.PAK"), str(Art.archives()))

	print("tactical_flow_test failures=", failures)
	quit(failures)


func _check(label: String, ok: bool, info: String) -> void:
	if not ok:
		failures += 1
	print("%s %s %s" % ["PASS" if ok else "FAIL", label, info])

