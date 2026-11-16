## Loads every playable mission headless and checks the player and targets.
extends SceneTree

func _initialize() -> void:
	await process_frame
	var sc = root.get_node("SCData")
	if not sc.is_mounted():
		sc.auto_mount()
	# Loaded at runtime: the scene script refers to autoloads that a preload
	# in a --script test would compile before they exist.
	var FlightScene = load("res://scripts/game/flight_scene.gd")
	var failures := 0
	for m in sc.missions():
		var f = FlightScene.new()
		f.mission_file = m.file
		root.add_child(f)
		await process_frame
		await physics_frame
		var ok: bool = f.player != null and f.player.alive and f.mission != null
		print("%s %-24s %-9s targets=%2d enemies=%d objects=%3d" % ["OK  " if ok else "FAIL",
			m.file.get_file(), m.area, f.targets.size(), f.enemies.size(), f.ground_objects.size()])
		if not ok:
			failures += 1
		# The mission's aircraft are the original PART data: every spawned
		# enemy must be an aircraft whose original model and side come from
		# the mission (FOE marking), allies likewise (FRIEND marking).
		for e in f.enemies:
			var k: String = e.model_name.get_file().get_basename()
			var orig: String = e.get_meta("part_model", "")
			var side: int = e.get_meta("part_side", -1)
			var ok_m: bool = e.has_meta("part_model") and orig != "" \
					and side != f.mission.player_part().side and k == orig
			if not ok_m:
				print("FAIL %s: enemy '%s' side=%s original_part='%s'" % [m.file.get_file(), k, side, orig])
				failures += 1
		for a in f.allies:
			if a == f.player:
				continue
			if a.has_meta("part_model") and a.get_meta("part_side", -1) != f.mission.player_part().side:
				print("FAIL %s: ally '%s' with enemy-side data" % [m.file.get_file(), a.model_name])
				failures += 1
		f.queue_free()
		await process_frame
	print("all_missions_test failures=%d" % failures)
	quit(failures)
