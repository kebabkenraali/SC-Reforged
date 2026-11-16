with open('C:/AI_Projektit/strike commander/game/scripts/game/flight_scene.gd', 'r', encoding='utf-8') as f:
    content = f.read()

# Find the function
idx = content.find('func _enemy_ai')
next_idx = content.find('\n## AA guns', idx)
old_func = content[idx:next_idx]

new_func = '''func _enemy_ai() -> void:
	for e in enemies:
		if not e.alive:
			continue
		e.evading = not e.incoming.is_empty()
		if e.evading and e.cm_cooldown <= 0.0 and e.countermeasures > 0 and randf() < 0.05:
			_drop_countermeasure(e)

		# Build list of valid hostile targets (respect IFF - don't shoot friendlies)
		var potential_targets: Array = []
		if player.alive and not player.on_ground and player.hostile:
			potential_targets.append(player)
		for a in allies:
			if a.alive and not a.on_ground and a.hostile:
				potential_targets.append(a)

		var tgt = null
		if e.scripted and not e.attack_ids.is_empty():
			# Scripted target: only attack if it's hostile
			for id in e.attack_ids:
				var ti: int = mission.part_index(id) if mission != null else -1
				if ti >= 0 and _part_nodes.has(ti) and is_instance_valid(_part_nodes[ti]) and _part_nodes[ti].alive \\
						and _part_nodes[ti].get("velocity") != null:
					var candidate = _part_nodes[ti]
					if candidate.hostile:
						tgt = candidate
						break
		else:
			# Free hunt: pick nearest hostile target
			var best_dist := 1e9
			for pt in potential_targets:
				var d := pt.global_position.distance_to(e.global_position)
				if d < best_dist:
					best_dist = d
					tgt = pt

		if tgt == null or not tgt.alive or tgt.on_ground:
			e.attack_point = null
			continue
		var to: Vector3 = tgt.global_position - e.global_position
		var dist := to.length()
		if dist > DETECT_RANGE:
			e.attack_point = null
			continue
		e.attack_point = tgt.global_position + tgt.velocity * clampf(dist / 900.0, 0.0, 2.5)
		var fwd: Vector3 = -e.global_transform.basis.z
		var ang := fwd.angle_to(to / maxf(dist, 1.0))
		if dist < 1100.0 and ang < 0.08 and e.can_fire():
			if e.get_meta("burst_cd", 0.0) <= Time.get_ticks_msec() / 1000.0:
				e.set_meta("burst_cd", Time.get_ticks_msec() / 1000.0 + 0.8)
				Sfx.play_at("gun", e.global_position, -2.0)
				e.consume_round(0.09)
				_fire(e, 0.006)
		if e.missile_cooldown <= 0.0 and ang < 0.45 and dist > 900.0:
			for name in e.missiles:
				if Weapons.mode_of(name) == "air" and e.missiles[name] > 0 and dist < Weapons.missile(name).range:
					_launch_missile(e, name, tgt)
					e.missiles[name] -= 1
					e.missile_cooldown = randf_range(12.0, 20.0)
					break


'''

new_content = content[:idx] + new_func + content[next_idx:]
with open('C:/AI_Projektit/strike commander/game/scripts/game/flight_scene.gd', 'w', encoding='utf-8') as f:
    f.write(new_content)
print('Done')