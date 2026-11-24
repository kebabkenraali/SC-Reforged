## Headless check of mission and ground object parsing against the original data.
extends SceneTree


func _initialize() -> void:
	await process_frame
	var sc = root.get_node("SCData")
	if not sc.is_mounted():
		sc.auto_mount()
	var failures := 0
	var ms: Array = sc.missions()
	print("missions: ", ms.size())
	for m in ms.slice(0, 6):
		print("  ", m.file, " | ", m.name, " | ", m.area)
	if ms.size() < 10:
		failures += 1

	var first_mission = sc.mission("MISSIONS/MISN-1A.IFF")
	var original_route: Array = first_mission.nav_plan().map(func(wp): return wp.label)
	var flight_route: Array = first_mission.flight_nav_plan().map(func(wp): return wp.label)
	var expected_original_route := [
		"Rendezvous With Cargo",
		"Land Cargo",
		"Scenic Nouakchott",
		"Head Home",
	]
	# The gameplay route must follow the original data: a previous remake-only
	# override swapped Land Cargo and Nouakchott and sent the autopilot the
	# wrong way while the escorted C-130 flew to the cargo field.
	var expected_flight_route := [
		"Rendezvous With Cargo",
		"Land Cargo",
		"Scenic Nouakchott",
		"Head Home",
	]
	if original_route != expected_original_route:
		print("MISN-1A original route data mismatch: ", original_route)
		failures += 1
	if flight_route != expected_flight_route:
		print("MISN-1A flight route mismatch: ", flight_route)
		failures += 1

	var flight_script = load("res://scripts/game/flight_scene.gd")
	var flight = flight_script.new()
	flight.mission = first_mission
	flight.terrain = sc.terrain(first_mission.area)
	var spawn_pos = flight._activation_spawn_position(first_mission.part_index(8))
	if not spawn_pos is Vector3:
		print("MISN-1A C-130 activation position was not resolved")
		failures += 1
	else:
		var rendezvous: Vector3 = first_mission.spots[3]
		var spawn_distance: float = Vector2(
			spawn_pos.x - rendezvous.x,
			spawn_pos.z - rendezvous.z
		).length()
		var cargo_ground: float = flight.terrain.height_at(spawn_pos.x, spawn_pos.z)
		print("MISN-1A C-130 activation distance=%.0f m AGL=%.0f m" % [
			spawn_distance, spawn_pos.y - cargo_ground
		])
		if spawn_distance > 8000.0 or spawn_pos.y - cargo_ground < 200.0:
			print("MISN-1A C-130 activation position is not at Rendezvous")
			failures += 1

	var m = sc.mission("MISSIONS/MISN-10A.IFF")
	var original_10a_route: Array = m.nav_plan().map(func(wp): return wp.label)
	var flight_10a_route: Array = m.flight_nav_plan().map(func(wp): return wp.label)
	if flight_10a_route != original_10a_route:
		print("MISN-10A route was unexpectedly changed: ", flight_10a_route)
		failures += 1

	var p = m.player_part()
	var t = sc.terrain(m.area)
	var ground: float = t.height_at(p.pos.x, p.pos.z)
	print("MISN-10A area=%s player=%s pos=%s ground=%.1f heading=%d" % [m.area, p.model, p.pos, ground, p.heading])
	print("  areas: ", m.areas.map(func(a): return a.name))
	print("  msgs: ", m.messages)
	if absf(p.pos.y - ground) > 15.0:
		failures += 1

	var bad := 0
	for o in t.objects:
		if absf(o.pos.y - t.height_at(o.pos.x, o.pos.z)) > 30.0:
			bad += 1
	print("terrain objects=%d off-ground=%d first=%s" % [t.objects.size(), bad, t.objects[0] if t.objects.size() else null])
	if t.objects.is_empty() or bad > t.objects.size() / 5:
		failures += 1
	var missing := {}
	for o in t.objects:
		if not sc.has("OBJECTS/%s.IFF" % o.model):
			missing[o.model] = true
	print("missing models: ", missing.keys())
	print("mission_test failures=%d" % failures)
	quit(failures)
