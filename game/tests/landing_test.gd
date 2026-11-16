## Test laskeutumista lentokentalle
## Kaytto: godot.exe --headless --path game --script res://tests/landing_test.gd --quit
extends SceneTree

var _tree: MainLoop


func _init() -> void:
	print("=== LANDING TEST ===")
	var t0 = Time.get_ticks_msec()
	
	# Tarkistetaan SCData
	print("SCData class exists: ", ClassDB.class_exists("SCData"))
	
	# Ladataan pelidata SCData:n kautta
	var err = SCData.mount("C:/Gog games/Strike Commander")
	print("SCData.mount result: ", err)
	if not SCData.is_mounted():
		print("FAIL: Pelidata ei lataudu SCData:n kautta!")
		quit(1)
	print("OK: Pelidata ladattu SCData:n kautta")
	
	# Luodaan paa-node
	var main = Node.new()
	root.add_child(main)
	
	# Ladataan maasto
	var terrain = SCData.terrain("CANYON")
	if terrain == null:
		print("FAIL: CANYON-alue ei lataudu")
		quit(1)
	print("OK: CANYON-maasto ladattu (", terrain.grid_size, "x", terrain.grid_size, " grid)")
	
	# Haetaan FlightScene
	var FlightScene = load("res://scripts/game/flight_scene.gd")
	
	var flight = FlightScene.new()
	flight.area = "CANYON"
	flight.approach = true
	flight.autopilot = false
	main.add_child(flight)
	
	# Odotetaan valmiiksi
	await flight.ready
	
	# Tarkistetaan asetukset
	var home_runway_found = flight.home_runway != null
	
	print("\n--- TILANNE ---")
	print("Home runway: ", "LOUTY" if home_runway_found else "PUUTE!")
	print("Waypoints: ", flight.waypoints.size())
	print("Nav index: ", flight.nav_index)
	if flight.player:
		print("Player alive: ", flight.player.alive)
		print("Player on_ground: ", flight.player.on_ground)
		print("Player speed: ", "%.1f" % flight.player.speed())
		var agl = flight.player.global_position.y - terrain.height_at(flight.player.global_position.x, flight.player.global_position.z)
		print("Player height (AGL): ", "%.1f" % agl)
		print("Player position: ", flight.player.global_position)
	else:
		print("Player: null!")
	
	if not home_runway_found:
		print("\nWARNING: Home runway ei kaytettavissa, yritetaan pakottaa!")
		for o in flight.ground_objects:
			if o.blast_only:
				flight.home_runway = o
				print("  Pakotettu home runway: ", o.global_position)
				break
	
	# Aja fysikaalista simulaatiota
	var frames = 0
	var max_frames = 6000
	var landed = false
	var crashed = false
	
	print("\n--- LASKU ALKAA ---")
	while frames < max_frames:
		var dt = 1.0 / 60.0
		flight._physics_process(dt)
		frames += 1
		
		if flight.player and frames % 600 == 0:
			var agl = flight.player.global_position.y - terrain.height_at(flight.player.global_position.x, flight.player.global_position.z)
			var spd = flight.player.speed()
			var on_gnd = flight.player.on_ground
			print("Frame %d: AGL=%.0f m, Speed=%.0f m/s, OnGround=%s" % [frames, agl, spd, on_gnd])
			
			if on_gnd and agl < 5.0:
				landed = true
				print("\n!!! LASKI! (frame ", frames, ") !!!")
				break
			
			if agl < -50.0:
				crashed = true
				print("\n!!! KRAHASI! (frame ", frames, ") !!!")
				break
	
	# Tulosta lopputulos
	print("\n=== TULOKSET ===")
	print("Frames: ", frames, "/", max_frames)
	print("Laskettu: ", "Kylla" if landed else "Ei")
	print("Krahasi: ", "Kylla" if crashed else "Ei")
	
	var exit_code = 0
	if landed:
		print("OK: Laskeutuminen onnistui!")
	else:
		print("FAIL: Laskeutuminen ei onnistunut!")
		print("Lopullinen tila:")
		if flight.player:
			var agl = flight.player.global_position.y - terrain.height_at(flight.player.global_position.x, flight.player.global_position.z)
			print("  AGL: ", "%.1f" % agl)
			print("  Speed: ", "%.1f" % flight.player.speed())
			print("  OnGround: ", flight.player.on_ground)
			print("  Alive: ", flight.player.alive)
			print("  Position: ", flight.player.global_position)
		if flight.home_runway:
			print("  Home runway pos: ", flight.home_runway.global_position)
		print("  Nav index: ", flight.nav_index)
		print("  Waypoints: ", flight.waypoints.size())
		exit_code = 1
	
	print("\nTesti kesti ", (Time.get_ticks_msec() - t0) / 1000.0, " sekuntia")
	quit(exit_code)
