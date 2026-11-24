## Plan item 6: every model referenced by any mission PART or terrain object
## must load as real original art (or a documented generated mesh), never a
## silent fallback. Run against the player's install.
extends SceneTree


func _initialize() -> void:
	await process_frame
	var sc = root.get_node("SCData")
	if not sc.is_mounted():
		sc.auto_mount()
	var AircraftMeshes = load("res://scripts/game/aircraft_meshes.gd")
	var ExternalModels = load("res://scripts/game/external_models.gd")
	var failures := 0
	var parts_checked := 0
	var objects_checked := 0
	var missing := {}
	for entry in sc.missions():
		var m = sc.mission(entry.file)
		if m == null:
			continue
		for p in m.parts:
			var n: String = String(p.model)
			if n.is_empty():
				continue
			parts_checked += 1
			var path := "OBJECTS/%s.IFF" % n
			var model = sc.model(path)
			var mesh = null
			if model == null and ExternalModels.override_mesh(path) == null \
					and AircraftMeshes.build(path) == null:
				missing[path] = true
		var terrain = sc.terrain(m.area)
		if terrain == null:
			missing["TERRAIN:" + m.area] = true
			continue
		for o in terrain.objects:
			var n: String = String(o.model)
			if n.is_empty():
				continue
			objects_checked += 1
			var path := "OBJECTS/%s.IFF" % n
			if sc.model(path) == null and ExternalModels.override_mesh(path) == null \
					and AircraftMeshes.build(path) == null:
				missing[path] = true
	for k in missing.keys():
		print("FAIL missing model/terrain: ", k)
		failures += 1
	print("parts=%d terrain objects=%d unique missing=%d" % [parts_checked, objects_checked, missing.size()])
	print("models_test failures=", failures)
	quit(failures)
