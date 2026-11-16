extends SceneTree

func _init() -> void:
	print("=== DIRECT FLIGHT TEST ===")
	print("Headless: ", DisplayServer.get_name())
	
	# Get SCData from autoload
	var sc_data = get_node_or_null("/root/SCData")
	if sc_data == null:
		print("ERROR: SCData not available as autoload!")
		quit(1)
	print("SCData loaded from autoload")
	
	# Load SCData
	var err = sc_data.mount("C:/Gog games/Strike Commander")
	print("SCData mount result: ", err)
	if not sc_data.is_mounted():
		print("ERROR: SCData not mounted!")
		quit(1)
	print("SCData mounted OK")
	
	# Load terrain
	var terrain = sc_data.terrain("CANYON")
	print("Terrain: ", "CANYON" if terrain else "null")
	
	# Load FlightScene class
	var FlightScene = load("res://scripts/game/flight_scene.gd")
	print("FlightScene loaded: ", FlightScene != null)
	
	# Create a main Node to parent the flight scene
	var main = Node.new()
	root.add_child(main)
	
	# Create flight scene
	var flight = FlightScene.new()
	flight.area = "CANYON"
	flight.approach = true
	flight.autopilot = false
	main.add_child(flight)
	
	print("FlightScene added, waiting for ready...")
	
	# Wait for ready using OS.delay_msec
	var wait_time = 0
	while not flight.is_node_ready() and wait_time < 1000:
		OS.delay_msec(10)
		wait_time += 10
	
	if flight.is_node_ready():
		print("FlightScene is ready!")
		print("Player alive: ", flight.player.alive if flight.player else "null")
		print("Player on_ground: ", flight.player.on_ground if flight.player else "null")
		print("Player speed: ", flight.player.speed() if flight.player else "null")
		
		# Drive simulation for 60 frames
		print("Driving 60 frames...")
		var frame = 0
		var max_frames = 60
		while frame < max_frames:
			flight._physics_process(1.0 / 60.0)
			frame += 1
			if frame % 10 == 0:
				print("  Frame ", frame, "/", max_frames)
			OS.delay_msec(17)
		
		# Print final state
		print("Final state:")
		print("  Player alive: ", flight.player.alive if flight.player else "null")
		print("  Player on_ground: ", flight.player.on_ground if flight.player else "null")
		print("  Player speed: ", flight.player.speed() if flight.player else "null")
		print("  Player pos: ", flight.player.global_position if flight.player else "null")
		if flight.home_runway:
			print("  Home runway: ", flight.home_runway.global_position)
	else:
		print("ERROR: FlightScene never became ready!")
	quit(0)