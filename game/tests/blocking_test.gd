extends SceneTree
func _init():
	var frame = 0
	print("=== BLOCKING TEST - Headless: ", DisplayServer.get_name(), " ===")
	while frame < 60:
		frame += 1
		if frame % 10 == 0:
			print("Frame ", frame)
		OS.delay_msec(17)
	print("DONE: ", frame, " frames")
	quit(0)
