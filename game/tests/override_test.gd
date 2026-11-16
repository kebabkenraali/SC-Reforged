## Regression test for the pitch-rate override channel: the control path the
## landing autopilot uses (flight_scene sets aircraft.pitch_rate_override
## every physics step; the aircraft applies it in _flight and then clears it).
## Also verifies the FBW trim and the low-speed (approach) override behaviour.
## Run: Godot --headless --path game --script res://tests/override_test.gd
extends SceneTree


var failures := 0


func _initialize() -> void:
	await process_frame
	var a = load("res://scripts/game/aircraft.gd").new()
	root.add_child.call_deferred(a)
	await process_frame
	a.set_physics_process(false)
	a.is_player = true

	# Full FBW stick rotates the nose up hard (baseline sanity).
	a.respawn(Vector3(0, 3000, 0), 0.0, 230.0)
	var start_pitch: float = a.global_transform.basis.get_euler().x
	for i in 60:
		a.controls = Vector3(1, 0, 0)
		a._flight(1.0 / 60.0)
	var dps: float = _dps(a, start_pitch)
	_check("FBW stick +1.0 climbs fast", dps > 25.0 and dps < 60.0, "pitch %.1f deg" % dps)

	# Override +0.4 rad/s at cruise speed: ~ +23 deg after 1 s.
	a.respawn(Vector3(0, 3000, 0), 0.0, 230.0)
	start_pitch = a.global_transform.basis.get_euler().x
	for i in 60:
		a.controls = Vector3.ZERO
		a.pitch_rate_override = 0.4
		a._flight(1.0 / 60.0)
	dps = _dps(a, start_pitch)
	_check("override +0.4 rad/s @230", dps > 15.0 and dps < 35.0, "pitch %.1f deg" % dps)

	# Override -0.4 rad/s: ~ -23 deg.
	a.respawn(Vector3(0, 3000, 0), 0.0, 230.0)
	start_pitch = a.global_transform.basis.get_euler().x
	for i in 60:
		a.controls = Vector3.ZERO
		a.pitch_rate_override = -0.4
		a._flight(1.0 / 60.0)
	dps = _dps(a, start_pitch)
	_check("override -0.4 rad/s @230", dps < -15.0 and dps > -35.0, "pitch %.1f deg" % dps)

	# Approach speed 150 m/s: the landing autopilot's commands must rotate
	# the plane even at the post-stall speeds (a stall keeps the flight path
	# behind, but the body angle still tracks the command).
	a.respawn(Vector3(0, 3000, 0), 0.0, 150.0)
	start_pitch = a.global_transform.basis.get_euler().x
	for i in 60:
		a.controls = Vector3.ZERO
		a.pitch_rate_override = 0.4
		a._flight(1.0 / 60.0)
	dps = _dps(a, start_pitch)
	_check("override +0.4 rad/s @150", dps > 15.0 and dps < 35.0, "pitch %.1f deg" % dps)

	# Landing speed 105 m/s, gentle rate: linear body rotation.
	a.respawn(Vector3(0, 3000, 0), 0.0, 105.0)
	start_pitch = a.global_transform.basis.get_euler().x
	for i in 60:
		a.controls = Vector3.ZERO
		a.pitch_rate_override = 0.2
		a._flight(1.0 / 60.0)
	dps = _dps(a, start_pitch)
	_check("override +0.2 rad/s @105", dps > 6.0 and dps < 18.0, "pitch %.1f deg" % dps)

	# Hands off: no spontaneous rotation once the FBW trim is established
	# (the first second at flight-path zero AoA is the normal trim transient:
	# the FBW pitches up to gain lift; measure only after that settles).
	a.respawn(Vector3(0, 3000, 0), 0.0, 150.0)
	start_pitch = a.global_transform.basis.get_euler().x
	for i in 30:
		a.controls = Vector3.ZERO
		a._flight(1.0 / 60.0)
	start_pitch = a.global_transform.basis.get_euler().x
	for i in 30:
		a.controls = Vector3.ZERO
		a._flight(1.0 / 60.0)
	dps = _dps(a, start_pitch)
	_check("hands off holds near trim", absf(dps) < 8.0, "drift %.1f deg after trim" % dps)

	print("total %d checks, failures=%d" % [6, failures])
	quit(0 if failures == 0 else 1)


func _dps(a, start_pitch: float) -> float:
	return rad_to_deg(a.global_transform.basis.get_euler().x - start_pitch)


func _check(what: String, ok: bool, detail: String) -> void:
	if ok:
		print("OK  %s (%s)" % [what, detail])
	else:
		failures += 1
		print("FAIL %s (%s)" % [what, detail])
