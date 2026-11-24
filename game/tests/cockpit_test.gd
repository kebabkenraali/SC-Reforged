## Virtual cockpit against the original data: every flyable aircraft must load
## without errors, and the three aircraft that ship an original 3D cockpit must
## get that model attached to the camera rig in cockpit view.
extends SceneTree


var failures := 0


func _initialize() -> void:
	await process_frame
	var sc = root.get_node("SCData")
	if not sc.is_mounted():
		sc.auto_mount()
	var FlightScene = load("res://scripts/game/flight_scene.gd")
	var Menu = load("res://scripts/ui/main_menu.gd")
	var aircraft: Array = Menu.aircraft_models()
	var with_data := 0
	print("cockpit test: ", aircraft.size(), " flyable aircraft")
	for model_path in aircraft:
		var f = FlightScene.new()
		f.plane_model = model_path
		f.camera_mode = 1   # CameraRig.Mode.COCKPIT
		root.add_child(f)
		await process_frame
		await physics_frame
		var name: String = f.player.display_name.to_upper() if f.player != null else "?"
		var ok: bool = f.player != null
		if not ok:
			print("FAIL ", model_path, " no player")
			failures += 1
			f.free()
			continue
		var expected: String = _cockpit_for(name)
		var has_original: bool = expected != "" and sc.has(expected)
		if has_original:
			with_data += 1
			if f.cockpit_model == null:
				print("FAIL ", name, " original cockpit not attached (", expected, ")")
				failures += 1
			elif f.rig.cockpit_model != f.cockpit_model:
				print("FAIL ", name, " cockpit not handed to camera rig")
				failures += 1
			elif f.cockpit_model.mesh == null or f.cockpit_model.mesh.get_surface_count() == 0:
				print("FAIL ", name, " cockpit mesh has no surfaces")
				failures += 1
		# Pilot silhouette: two procedural legs hang below the pit for every
		# aircraft (also those without an original 3D pit).
		if f.rig.pilot_node == null:
			print("FAIL ", name, " pilot silhouette missing")
			failures += 1
		elif f.rig.pilot_node.get_child_count() != 2:
			print("FAIL ", name, " pilot silhouette should have 2 legs (got ",
				f.rig.pilot_node.get_child_count(), ")")
			failures += 1
		elif not f.rig.pilot_node.visible:
			print("FAIL ", name, " pilot silhouette not visible in cockpit view")
			failures += 1
		elif not has_original:
			# Aircraft without a shipped cockpit get the procedural legs only.
			if f.cockpit_model != null:
				print("FAIL ", name, " invented a cockpit without original data")
				failures += 1
		var cam: Transform3D = f.rig.camera.global_transform
		if not is_finite(cam.origin.x) or not is_finite(cam.origin.y) or not is_finite(cam.origin.z):
			print("FAIL ", name, " cockpit camera has non-finite position")
			failures += 1
		print("%-12s cockpit=%-6s original=%s" % [name,
			"yes" if f.cockpit_model != null else "none", expected])
		f.free()
		await process_frame
	_check("four aircraft have original cockpit data", with_data == 4, str(with_data))
	print("cockpit_test failures=", failures)
	quit(failures)


func _cockpit_for(name: String) -> String:
	# Mirror of flight_scene.COCKPIT_MODELS for data that exists in SC.dat.
	var table: Dictionary = {
		"F-16DES": "OBJECTS/F16-CKPT.IFF",
		"F-16GRAY": "OBJECTS/F16-CKPT.IFF",
		"F-16": "OBJECTS/F16-CKPT.IFF",
		"F16": "OBJECTS/F16-CKPT.IFF",
		"F-22": "OBJECTS/F22-CKPT.IFF",
		"F22": "OBJECTS/F22-CKPT.IFF",
		"F-22B": "OBJECTS/F22BCKPT.IFF",
		"F22B": "OBJECTS/F22BCKPT.IFF",
	}
	if table.has(name):
		return table[name]
	var norm := name.replace("-", "").replace("_", "")
	for suffix in ["DES", "GRAY", "GRA", "DEF", "EARLY"]:
		if norm.ends_with(suffix):
			norm = norm.substr(0, norm.length() - suffix.length())
	var sc = root.get_node("SCData")
	for candidate in ["OBJECTS/%s-CKPT.IFF" % norm, "OBJECTS/%sCKPT.IFF" % norm]:
		if sc.has(candidate):
			return candidate
	return ""


func _check(label: String, ok: bool, info: String) -> void:
	if not ok:
		failures += 1
	print("%s %s %s" % ["PASS" if ok else "FAIL", label, info])


