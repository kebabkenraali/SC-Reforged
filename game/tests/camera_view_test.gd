## C key camera cycle must include the cockpit-less seat view. The HUD is a
## separate 2D overlay and must stay present in every camera mode.
extends SceneTree


func _initialize() -> void:
	await process_frame
	var sc = root.get_node("SCData")
	if not sc.is_mounted():
		sc.auto_mount()
	var FlightScene = load("res://scripts/game/flight_scene.gd")
	var f = FlightScene.new()
	f.plane_model = "OBJECTS/F-16DES.IFF"
	f.camera_mode = 1
	root.add_child(f)
	await process_frame
	await physics_frame
	var failures := 0

	var seen: Array[String] = []
	for i in range(4):
		seen.append(f.rig.mode_name())
		f.rig.cycle()
		await process_frame
	var expected := ["Cockpit", "No cockpit", "Free orbit", "Chase"]
	if seen != expected:
		print("FAIL camera cycle: ", seen, " != ", expected)
		failures += 1

	# "No cockpit" = seat camera, but neither the pit mesh nor the pilot legs.
	f.rig.mode = 2
	await process_frame
	await physics_frame
	if f.rig.mode_name() != "No cockpit":
		print("FAIL mode 2 name")
		failures += 1
	if f.rig.cockpit_model != null and f.rig.cockpit_model.visible:
		print("FAIL cockpit mesh visible in no-cockpit view")
		failures += 1
	if f.rig.pilot_node != null and f.rig.pilot_node.visible:
		print("FAIL pilot legs visible in no-cockpit view")
		failures += 1
	if f.hud == null or not is_instance_valid(f.hud):
		print("FAIL HUD missing")
		failures += 1

	f.free()
	print("camera_view_test failures=", failures)
	quit(failures)
