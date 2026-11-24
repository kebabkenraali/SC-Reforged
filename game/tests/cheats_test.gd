## Test-only cheats: god mode must keep the player alive, endless ammo must
## refill the original weapon stock.
extends SceneTree


func _initialize() -> void:
	await process_frame
	var sc = root.get_node("SCData")
	if not sc.is_mounted():
		sc.auto_mount()
	var FlightScene = load("res://scripts/game/flight_scene.gd")
	var f = FlightScene.new()
	f.mission_file = "MISSIONS/MISN-1A.IFF"
	f.god_mode = true
	f.endless_ammo = true
	f.autopilot = true
	root.add_child(f)
	await process_frame
	await physics_frame
	var failures := 0
	if f.player == null:
		print("FAIL player missing")
		quit(1)
		return
	if not f.player.god_mode:
		print("FAIL god_mode was not applied to player")
		failures += 1
	var before: float = f.player.health
	f.player.damage(before + 5000.0, null)
	if not f.player.alive or f.player.health != before:
		print("FAIL god mode did not block damage: alive=%s health=%.1f -> %.1f" \
			% [str(f.player.alive), before, f.player.health])
		failures += 1
	f.player.missiles.clear()
	await physics_frame
	await physics_frame
	if f.player.missiles.is_empty():
		print("FAIL endless ammo did not refill weapons")
		failures += 1
	print("cheats_test failures=", failures)
	quit(failures)
