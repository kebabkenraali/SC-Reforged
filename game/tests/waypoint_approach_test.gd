## F7 waypoint approach (replaces the old fast travel): the player and the
## friendly aircraft with them are placed 10 km short of the active waypoint,
## pointing at it. The waypoint and its scene triggers stay ahead, and the
## route is advanced only by actually flying the last leg.
## Run against the original MISN-1A data.
extends SceneTree


func _initialize() -> void:
	await process_frame
	var sc = root.get_node("SCData")
	if not sc.is_mounted():
		sc.auto_mount()
	var FlightScene = load("res://scripts/game/flight_scene.gd")
	var f = FlightScene.new()
	f.mission_file = "MISSIONS/MISN-1A.IFF"
	root.add_child(f)
	await process_frame
	await physics_frame
	var failures := 0
	if f.mission == null or f.player == null:
		print("FAIL mission/player did not load")
		quit(1)
		return
	var wps: Array = f.waypoints
	print("waypoints=", wps.size(), " allies=", f.allies.size())
	if wps.size() != 4:
		failures += 1
	# The cargo field must come before Nouakchott, like the escorted C-130.
	var labels := []
	for wp in wps:
		labels.append(str(wp.get("name", "")))
	if labels.size() >= 3 and (labels[1].to_lower() != "land cargo" or labels[2].to_lower() != "scenic nouakchott"):
		print("FAIL route order: ", labels)
		failures += 1
	else:
		print("route order OK: ", labels)
	# Put the player airborne well above the runway (F7 is airborne-only).
	f.player.global_position += Vector3.UP * 1500.0
	f.player.on_ground = false
	f.player.velocity = Vector3.FORWARD * 220.0
	for k in wps.size():
		var before: int = f.nav_index
		f.enemies.clear()
		f._trigger_waypoint_approach()
		var target: Vector3 = wps[k].pos
		var got: Vector3 = f.player.global_position
		var d: float = Vector2(target.x - got.x, target.z - got.z).length()
		if f.nav_index != before:
			print("FAIL approach %d advanced nav_index (%d -> %d) before the leg was flown" \
				% [k + 1, before, f.nav_index])
			failures += 1
		var expected: float = 10000.0
		if k == wps.size() - 1:
			expected = 8000.0
			if f.home_runway != null:
				var home_d: float = f.home_runway.global_position.distance_to(got)
				if home_d > 12000.0:
					print("FAIL final approach is %.0f m from home runway" % home_d)
					failures += 1
		if absf(d - expected) > 2000.0:
			print("FAIL approach %d player is %.0f m from waypoint (expected %.0f)" \
				% [k + 1, d, expected])
			failures += 1
		if not f.approach_jump:
			print("FAIL approach %d did not start the flyby" % (k + 1))
			failures += 1
		# Only friendlies that are already in the world move with the player;
		# aircraft still waiting for their scene (the C-130, the MiGs) must stay
		# dormant so their triggers fire when the leg is actually flown.
		var near := 0
		for a in f.allies:
			if a != f.player and a.alive and not a.on_ground \
					and a.global_position.distance_to(got) < 3000.0:
				near += 1
		if near < 1:
			print("FAIL approach %d left the active wingman behind (near=%d)" % [k + 1, near])
			failures += 1
		# Nose must point at the waypoint (except the final, which lines up with
		# the runway).
		if k < wps.size() - 1:
			var fwd: Vector3 = -f.player.global_transform.basis.z
			var to_wp: Vector3 = target - got
			to_wp.y = 0.0
			if to_wp.length() > 1.0 and fwd.dot(to_wp.normalized()) < 0.9:
				print("FAIL approach %d heading %.2f does not point at waypoint" % [k + 1, fwd.dot(to_wp.normalized())])
				failures += 1
		print("approach %d -> %s  nav=%d/%d  dist=%.0f  allies_near=%d" \
			% [k + 1, wps[k].name, f.nav_index, wps.size(), d, near])
		# Finish the flyby, then move to the next waypoint as a normal arrival.
		f._ft_flyby_left = 0.0
		f._update_approach_jump(0.016)
		if f.approach_jump:
			print("FAIL flyby did not end")
			failures += 1
		f.nav_index = k + 1
	print("waypoint_approach_test failures=", failures)
	quit(failures)
