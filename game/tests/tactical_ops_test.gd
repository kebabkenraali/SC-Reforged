## Plan item 1 validation: the 30 Tactical Operations missions live in
## TOBIGTRE.TRE on the original CD. Check each parses with the remake's own
## Mission parser and has a player, areas, waypoints and a terrain area.
extends SceneTree


func _initialize() -> void:
	await process_frame
	var sc = root.get_node("SCData")
	if not sc.is_mounted():
		sc.auto_mount()
	var Tre = load("res://scripts/formats/tre_archive.gd")
	var Mission = load("res://scripts/formats/sc_mission.gd")
	var src = sc.iso.file_source("TOBIGTRE.TRE")
	if src == null:
		print("FAIL TOBIGTRE.TRE not found on original CD")
		quit(1)
		return
	var entries: Dictionary = Tre.index(src)
	var failures := 0
	var checked := 0
	for k in entries:
		var name: String = String(k)
		if not name.to_upper().ends_with(".IFF") or not "MISN-" in name.to_upper():
			continue
		var e: Array = entries[k]
		var buf: PackedByteArray = e[0].read(e[1], e[2])
		if buf.is_empty():
			print("FAIL empty archive entry: ", name)
			failures += 1
			continue
		var m = Mission.load_from(buf, name)
		checked += 1
		if m == null:
			print("FAIL Mission.load_from returned null: ", name)
			failures += 1
			continue
		var problems := []
		if m.player_part() == null:
			problems.append("no player")
		if m.areas.is_empty():
			problems.append("no areas")
		if m.flight_nav_plan().is_empty():
			problems.append("no waypoints")
		if sc.terrain(m.area) == null:
			problems.append("no terrain " + m.area)
		if not problems.is_empty():
			print("FAIL %s: %s" % [name, ", ".join(problems)])
			failures += 1
	print("tactical missions parsed=%d failures=%d" % [checked, failures])
	quit(failures)
