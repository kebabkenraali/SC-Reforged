## Cockpit window layout test: stores on the left MFD, radar on the right,
## live tracking window only in Arcade mode, event window in both modes.
extends SceneTree

var failures := 0


func _initialize() -> void:
	await process_frame
	var aircraft := Node3D.new()
	root.add_child(aircraft)
	var inst = preload("res://scripts/game/cockpit_instruments.gd").new()
	aircraft.add_child(inst)
	inst.setup(null, Vector3.ZERO)
	var windows = preload("res://scripts/game/cockpit_windows.gd").new()
	inst.add_child(windows)
	windows.setup(null, Vector3.ZERO, aircraft, true)

	# MFD contents (user's 24.11. layout: weapons left, radar right).
	_check(inst.store_label.position.distance_to(inst._pos(inst.LAYOUT["mfd_l"]) + Vector3(0, 0, 0.3)) < 0.01,
		"stores label on left MFD")
	_check(inst.blips.size() == 8 and inst.blips[0].position.distance_to(inst._pos(inst.LAYOUT["mfd_r"])) < 0.01,
		"radar blips on right MFD")

	# Tracking window: Arcade only.
	var dummy := Node3D.new()
	aircraft.add_child(dummy)
	windows.show_missile(dummy, dummy, "AIM-9")
	await process_frame
	_check(windows.track_quad != null and windows.track_quad.visible, "Arcade tracking window visible")
	windows.set_arcade(false)
	await process_frame
	_check(not windows.track_quad.visible, "Realistic tracking window hidden")
	windows.set_arcade(true)
	windows.show_bomb(dummy, "MK-82")
	await process_frame
	_check(windows.track_quad.visible and windows.track_title.begins_with("BOMB"), "bomb tracking window")
	windows.hide_all()
	windows.show_event("Test event", 4.0)
	await process_frame
	_check(windows.event_quad.visible and windows.event_label.text == "Test event", "event window in Realistic mode")

	# Mode values from Settings (session override, no disk write).
	var settings := root.get_node("Settings")
	settings.mode_override = "arcade"
	_check(settings.is_arcade() and settings.mode_name() == "arcade", "arcade override")
	settings.mode_override = "realistic"
	_check(not settings.is_arcade(), "realistic override")
	settings.mode_override = ""

	print("cockpit_windows_test failures=%d" % failures)
	quit(failures)


func _check(ok: bool, what: String) -> void:
	if not ok:
		failures += 1
		print("FAIL: ", what)
