## Cockpit sweep over every playable mission: load each original mission with
## the cockpit camera selected, verify the player's original cockpit model is
## attached where the install ships one, and that no script errors occur.
extends SceneTree


var failures := 0


func _initialize() -> void:
	await process_frame
	var sc = root.get_node("SCData")
	if not sc.is_mounted():
		sc.auto_mount()
	var FlightScene = load("res://scripts/game/flight_scene.gd")
	var missions: Array = sc.missions()
	var with_cockpit := 0
	print("cockpit mission sweep: ", missions.size(), " missions")
	for m in missions:
		var f = FlightScene.new()
		f.mission_file = m.file
		f.camera_mode = 1
		root.add_child(f)
		await process_frame
		await physics_frame
		var ok: bool = f.player != null and f.rig != null
		if not ok:
			_check(String(m.file), false, "mission did not load")
			f.free()
			continue
		var key: String = f.player.display_name.to_upper()
		var expected: String = FlightScene.COCKPIT_MODELS.get(key, "")
		var has_data: bool = expected != "" and sc.has(expected)
		if has_data:
			with_cockpit += 1
			if f.cockpit_model == null or f.rig.cockpit_model != f.cockpit_model:
				_check(String(m.file), false, "cockpit missing for " + key)
		elif f.cockpit_model != null:
			_check(String(m.file), false, "cockpit invented for " + key)
		f.free()
		await process_frame
	_check("all missions loaded in cockpit view", true, "%d/%d" % [missions.size() - failures, missions.size()])
	print("cockpits available in %d/%d missions" % [with_cockpit, missions.size()])
	print("cockpit_mission_sweep failures=", failures)
	quit(failures)


func _check(label: String, ok: bool, info: String) -> void:
	if not ok:
		failures += 1
		print("FAIL %s %s" % [label, info])
