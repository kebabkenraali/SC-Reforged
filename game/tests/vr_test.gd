## VR support: OpenXR interface is detected and --vr is harmless without a
## runtime. In a headless machine initialize() returns false; the game must
## stay playable and the cockpit camera must still work.
extends SceneTree


func _initialize() -> void:
	await process_frame
	var failures := 0
	var xr_iface = XRServer.find_interface("OpenXR")
	if xr_iface == null:
		print("FAIL OpenXR interface not registered")
		failures += 1
	else:
		# Do not call initialize() in a headless test: without a runtime it
		# leaks OpenXR interaction/profile RIDs at exit.
		print("OpenXR interface registered (headset runtime needed to activate)")
	var FlightScene = load("res://scripts/game/flight_scene.gd")
	var sc = root.get_node("SCData")
	if not sc.is_mounted():
		sc.auto_mount()
	var f = FlightScene.new()
	f.plane_model = "OBJECTS/F-16DES.IFF"
	f.camera_mode = 1
	f.vr_active = false
	root.add_child(f)
	await process_frame
	await physics_frame
	if f.cockpit_model == null or f.rig == null:
		print("FAIL cockpit not usable without VR runtime")
		failures += 1
	else:
		var cam: Transform3D = f.rig.camera.global_transform
		if not is_finite(cam.origin.x) or not is_finite(cam.origin.y) or not is_finite(cam.origin.z):
			print("FAIL camera transform non-finite")
			failures += 1
	f.free()

	# With vr_active the rig must build an XROrigin3D + XRCamera3D pair and
	# keep the origin in sync with the view transform.
	var v = FlightScene.new()
	v.plane_model = "OBJECTS/F-16DES.IFF"
	v.camera_mode = 1
	v.vr_active = true
	root.add_child(v)
	await process_frame
	await physics_frame
	if v.rig == null or v.rig.xr_origin == null or v.rig.xr_camera == null:
		print("FAIL XR origin/camera nodes not created")
		failures += 1
	elif not v.rig.xr_camera.current:
		print("FAIL XRCamera3D not current")
		failures += 1
	else:
		var cam_t: Transform3D = v.rig.camera.global_transform
		var org_t: Transform3D = v.rig.xr_origin.global_transform
		if cam_t.origin.distance_to(org_t.origin) > 0.01:
			print("FAIL XR origin not synced to camera")
			failures += 1
	v.free()
	print("vr_test failures=", failures)
	quit(failures)
