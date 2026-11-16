with open('C:/AI_Projektit/strike commander/game/scripts/game/flight_scene.gd', 'r', encoding='utf-8') as f:
    content = f.read()

# Find insertion point
idx = content.find('func _autopilot_ground')
insert_at = content.find('\nfunc _fire', idx)

new_funcs = '''

## Waypoint autopilot: follow the mission route (waypoints from nav_plan).
func _autopilot_waypoint() -> void:
	if nav_index >= waypoints.size():
		# No more waypoints: loiter at last waypoint
		var wp: Vector3 = waypoints[-1].pos
		var cruise := maxf(wp.y, terrain.height_at(wp.x, wp.z) + 1500.0) if terrain else wp.y
		player.steer_towards(Vector3(wp.x, cruise, wp.z), 0.5, 300.0)
		player.throttle = 0.8
		player.afterburner = false
		return

	var wp: Vector3 = waypoints[nav_index].pos
	var cruise := maxf(wp.y, terrain.height_at(wp.x, wp.z) + 1500.0) if terrain else wp.y
	var target_pos := Vector3(wp.x, cruise, wp.z)
	var to: Vector3 = target_pos - player.global_position
	var dist_h: float = Vector2(to.x, to.z).length()

	# If close to waypoint horizontally, advance to next
	if dist_h < 2000.0 and player.global_position.y > target_pos.y - 200.0:
		nav_index += 1
		if nav_index < waypoints.size():
			_say("Waypoint reached - next: %s" % waypoints[nav_index].name, 4.0)
		return

	player.steer_towards(target_pos, 0.5, 300.0)
	player.throttle = 0.9
	player.afterburner = false


## Landing autopilot: approach and land at home runway.
func _autopilot_land() -> void:
	if home_runway == null:
		_say("No home runway found", 3.0)
		autopilot_land = false
		return

	var info := landing_info()
	if info.is_empty():
		_say("Landing data unavailable", 3.0)
		autopilot_land = false
		return

	var threshold: Vector3 = info.threshold
	var corners := info.corners
	var center: Vector3 = (corners[0] + corners[2]) * 0.5
	var dir: Vector3 = (center - threshold).normalized()

	# Landing phases:
	# 1. Approach: 8km out, 600m above glide slope
	# 2. Final: 3km out, on glide slope (3 deg)
	# 3. Flare: 500m out, reduce descent rate
	# 4. Touchdown: on threshold
	# 5. Rollout: slow down, exit runway

	var to_thresh: Vector3 = threshold - player.global_position
	var dist_2d: float = Vector2(to_thresh.x, to_thresh.z).length()
	var agl: float = player.global_position.y - terrain.height_at(player.global_position.x, player.global_position.z)
	var target_agl: float = tan(deg_to_rad(GLIDE_SLOPE)) * dist_2d

	# Phase 1: Far approach (> 8km)
	if dist_2d > 8000.0:
		var approach_pos := threshold - dir * 8000.0 + dir.cross(Vector3.UP) * -150.0
		approach_pos.y = threshold.y + tan(deg_to_rad(GLIDE_SLOPE)) * 8000.0 + 600.0
		player.steer_towards(approach_pos, 0.6, 400.0)
		player.throttle = 0.7
		player.afterburner = false
		return

	# Phase 2: Final approach (3km - 8km) - intercept glide slope
	if dist_2d > 3000.0:
		var intercept_agl := target_agl + 60.0  # slightly above glide slope to intercept
		var intercept_pos := threshold - dir * dist_2d + dir.cross(Vector3.UP) * -150.0
		intercept_pos.y = threshold.y + intercept_agl
		player.steer_towards(intercept_pos, 0.6, 300.0)
		player.throttle = 0.5
		player.afterburner = false
		return

	# Phase 3: Short final (500m - 3km) - on glide slope
	if dist_2d > 500.0:
		var final_pos := threshold - dir * dist_2d + dir.cross(Vector3.UP) * -150.0
		final_pos.y = threshold.y + target_agl
		player.steer_towards(final_pos, 0.5, 200.0)
		player.throttle = 0.35
		player.afterburner = false
		return

	# Phase 4: Flare and touchdown (0 - 500m)
	if dist_2d > 50.0:
		# Flare: pull up slightly to reduce sink rate
		var flare_pos := threshold - dir * dist_2d + dir.cross(Vector3.UP) * -150.0
		flare_pos.y = threshold.y + maxf(target_agl, 10.0)
		player.steer_towards(flare_pos, 0.4, 100.0)
		player.throttle = 0.2
		player.afterburner = false
		return

	# Phase 5: On ground - rollout
	if player.on_ground:
		player.throttle = 0.0
		player.brakes = true
		player.controls = Vector3(0.0, 0.0, 0.0)
		if player.speed() < 5.0:
			_say("Landed successfully", 3.0)
			autopilot_land = false
			_end_mission("landed")
		return

	# Fallback: just aim for threshold
	player.steer_towards(threshold, 0.5, 200.0)
	player.throttle = 0.3
	player.afterburner = false

'''

new_content = content[:insert_at] + new_funcs + content[insert_at:]
with open('C:/AI_Projektit/strike commander/game/scripts/game/flight_scene.gd', 'w', encoding='utf-8') as f:
    f.write(new_content)
print('Done')