## Verifies that every mission has a usable gameplay route and that the
## arrival radii follow the original area-based rule.
extends SceneTree


func _initialize() -> void:
	await process_frame
	var sc = root.get_node("SCData")
	if not sc.is_mounted():
		sc.auto_mount()
	var failures := 0
	var entries: Array = sc.missions()
	print("missions: ", entries.size())
	var without_route := 0
	var with_route := 0
	for entry in entries:
		var m = sc.mission(entry.file)
		if m == null:
			print("FAIL mission load: ", entry.file)
			failures += 1
			continue
		var route: Array = m.flight_nav_plan()
		if route.is_empty():
			print("FAIL no waypoints: ", m.file, " areas=", m.areas.size(), " spots=", m.spots.size())
			failures += 1
			continue
		if m.nav_plan().is_empty():
			without_route += 1
		else:
			with_route += 1
			failures += _check_radii(m, route)
		if without_route <= 3:
			var wp = route[0]
			print("OK  ", m.file, " -> ", route.size(), " waypoints, first: ",
				wp.label, " pos=", wp.pos, " radius=", wp.get("radius", -1))
	print("without route block: ", without_route, ", with route: ", with_route)
	print("waypoint_test failures=", failures)
	quit(failures)


## The original counted a waypoint reached when its scenario area was entered:
## radius = largest radius of every AREA within 3 km (horizontal) of the WP,
## or 0.0 when none is close (callers then use their own default).
func _check_radii(m, route: Array) -> int:
	var bad := 0
	for wp in route:
		if not wp.has("radius"):
			print("FAIL no radius: ", m.file, " wp=", wp.get("label", ""))
			bad += 1
			continue
		var expected := 0.0
		for a in m.areas:
			if Vector2(a.pos.x - wp.pos.x, a.pos.z - wp.pos.z).length() < 3000.0:
				expected = maxf(expected, float(a.radius))
		var got := float(wp.radius)
		if absf(got - expected) > 0.01:
			print("FAIL radius: ", m.file, " wp=", wp.get("label", ""),
				" got=", got, " expected=", expected)
			bad += 1
	return bad
