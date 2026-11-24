## Cockpit HUD must be attached to the aircraft, not locked to the screen:
## turning the head moves the camera but not the gauge mesh or its labels.
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
	var inst = f.cockpit_instruments
	if inst == null or inst.quads.is_empty():
		print("FAIL no 3D instruments")
		quit(1)
		return
	# HUD is now a framebuffer texture on the cockpit glass (libRealSpace way),
	# so its text must NOT be a screen-space overlay in cockpit view.
	var hud_parent = f.hud.get_parent()
	var in_framebuffer: bool = hud_parent != null and hud_parent.name == "HUDFramebuffer"
	if not in_framebuffer and not f.hud.hide_text:
		print("FAIL screen-space HUD text still drawn in cockpit view")
		failures += 1

	var before_cam: Transform3D = f.rig.camera.global_transform
	var inv: Transform3D = f.player.global_transform.affine_inverse()
	var before_pos: Vector3 = inv * inst.quads[0].global_position
	var before_label: Vector3 = inv * inst.alti_label.global_position
	f.rig._pit_aim.x = 25.0
	f.rig._pit_aim_sm.x = 25.0   # smoothed value actually used by the camera
	await process_frame
	await process_frame
	var after_cam: Transform3D = f.rig.camera.global_transform
	inv = f.player.global_transform.affine_inverse()
	var after_pos: Vector3 = inv * inst.quads[0].global_position
	var after_label: Vector3 = inv * inst.alti_label.global_position
	if before_cam.basis.x.distance_to(after_cam.basis.x) < 0.01:
		print("FAIL camera did not turn")
		failures += 1
	if before_pos.distance_to(after_pos) > 0.01:
		print("FAIL gauge moved with the head")
		failures += 1
	if before_label.distance_to(after_label) > 0.01:
		print("FAIL HUD label moved with the head")
		failures += 1

	f.free()
	print("hud_attachment_test failures=", failures)
	quit(failures)
