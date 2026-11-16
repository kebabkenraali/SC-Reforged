## Headless sanity checks for the flight model.
## Run: Godot --headless --path game --script res://tests/flight_test.gd
extends SceneTree


var failures := 0


func _initialize() -> void:
	await process_frame
	# Loaded at runtime: the script uses autoloads that a preload would compile too early.
	var a = load("res://scripts/game/aircraft.gd").new()
	root.add_child.call_deferred(a)
	await process_frame
	a.set_physics_process(false)
	a.respawn(Vector3(0, 3000, 0), 0.0, 220.0)
	a.is_player = true

	# Hands off: the FBW should hold roughly 1 g, so altitude stays near trim.
	_run(a, Vector3.ZERO, 20.0)
	_check("hands-off altitude drift < 300 m", absf(a.global_position.y - 3000.0) < 300.0,
		"alt %.0f m, speed %.0f m/s" % [a.global_position.y, a.speed()])

	# Full aft stick: high g and a climb.
	a.respawn(Vector3(0, 3000, 0), 0.0, 230.0)
	var max_g := 0.0
	for i in 120:
		a.controls = Vector3(1, 0, 0)
		a._flight(1.0 / 60.0)
		max_g = maxf(max_g, a.g_force)
	_check("full pull reaches 6-10 g", max_g > 6.0 and max_g < 10.5, "max g %.1f" % max_g)

	# Full right roll for 1 s: bank should be strongly right.
	a.respawn(Vector3(0, 3000, 0), 0.0, 230.0)
	_run(a, Vector3(0, 1, 0), 0.5)
	var bank: float = -a.global_transform.basis.get_euler().z
	_check("right stick rolls right", bank > 0.8, "bank %.0f deg" % rad_to_deg(bank))

	# Throttle idle with no afterburner: aircraft slows down.
	a.respawn(Vector3(0, 3000, 0), 0.0, 230.0)
	a.throttle = 0.0
	_run(a, Vector3.ZERO, 10.0)
	_check("idle throttle decelerates", a.speed() < 220.0, "speed %.0f m/s" % a.speed())

	# Take-off from a runway: full afterburner, rotate at 75 m/s, must climb away.
	var flat := FlatGround.new()
	a.terrain = flat
	a.respawn(Vector3(0, 2.2, 0), 0.0, 0.0)
	a.on_ground = true
	a.afterburner = true
	var lifted := false
	for i in 60 * 40:
		a.controls = Vector3(1.0 if a.speed() > 75.0 else 0.0, 0, 0)
		a._flight(1.0 / 60.0)
		if a.global_position.y > 150.0:
			lifted = true
			break
	_check("take-off from runway", lifted and a.alive, "alt %.0f m, speed %.0f m/s, alive %s" % [a.global_position.y, a.speed(), a.alive])
	a.terrain = null

	print("flight_test failures=%d" % failures)
	quit(failures)


func _run(a, controls: Vector3, seconds: float) -> void:
	for i in int(seconds * 60.0):
		a.controls = controls
		a._flight(1.0 / 60.0)


func _check(name: String, ok: bool, detail: String) -> void:
	print("%s %s (%s)" % ["PASS" if ok else "FAIL", name, detail])
	if not ok:
		failures += 1


class FlatGround:
	func height_at(_x: float, _z: float) -> float:
		return 0.0

	func world_size() -> float:
		return 100000.0
