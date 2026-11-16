## Chase, cockpit and free-orbit cameras with smoothing.
extends Node3D

enum Mode { CHASE, COCKPIT, ORBIT }
const NAMES := ["Chase", "Cockpit", "Free orbit"]

var target: Node3D
var mode := Mode.CHASE
var fov := 70.0
var camera: Camera3D
var _orbit := Vector2(0.4, 0.25)
var _orbit_dist := 40.0
var _smoothed := Transform3D.IDENTITY
var _first := true
var cockpit_model: MeshInstance3D = null
# Flyby cutaway: a short scripted pass across the aircraft (waypoint reached).
var _flyby_prev := Mode.CHASE
var _flyby_t := -1.0
var _flyby_len := 3.0


func _ready() -> void:
	camera = Camera3D.new()
	camera.near = 0.3
	camera.far = 400000.0
	camera.current = true
	camera.doppler_tracking = Camera3D.DOPPLER_TRACKING_PHYSICS_STEP
	add_child(camera)


func cycle() -> void:
	mode = (mode + 1) % 3
	_flyby_t = -1.0
	_first = true


## A cinematic flyby pass (about 3 s): the camera sweeps past the aircraft
## and returns to the previous view. Triggered when a waypoint is reached,
## cancelled by any camera cycle (as in the original's camera cuts).
func start_flyby(duration := 3.0) -> void:
	_flyby_prev = mode
	_flyby_len = duration
	_flyby_t = 0.0
	_first = true


func _flyby(dt: float) -> void:
	_flyby_t += dt
	var k: float = clampf(_flyby_t / _flyby_len, 0.0, 1.0)
	var tx := target.global_transform
	var b := tx.basis.orthonormalized()
	# A dramatic sweep: start ahead-left of the nose, cross over the aircraft
	# and settle behind the tail (the original's pass at the waypoint).
	var side: float = lerpf(-1.0, 1.0, k)
	var pos: Vector3 = tx.origin + b * Vector3(side * 70.0, lerpf(6.0, 22.0, k), lerpf(40.0, -18.0, k))
	var look: Vector3 = tx.origin + b * Vector3(0.0, 0.0, 6.0)
	camera.global_transform = Transform3D(Basis.looking_at(look - pos, Vector3.UP), pos)
	if _flyby_t >= _flyby_len:
		mode = _flyby_prev
		_flyby_t = -1.0
		_first = true


func mode_name() -> String:
	return NAMES[mode]


func _unhandled_input(event: InputEvent) -> void:
	if mode == Mode.ORBIT:
		if event is InputEventMouseMotion and Input.is_mouse_button_pressed(MOUSE_BUTTON_RIGHT):
			_orbit += Vector2(-event.relative.x, event.relative.y) * 0.005 * float(Settings.get_value("controls", "mouse_sensitivity"))
			_orbit.y = clampf(_orbit.y, -1.4, 1.4)
		elif event is InputEventMouseButton and event.pressed:
			if event.button_index == MOUSE_BUTTON_WHEEL_UP:
				_orbit_dist = maxf(12.0, _orbit_dist * 0.9)
			elif event.button_index == MOUSE_BUTTON_WHEEL_DOWN:
				_orbit_dist = minf(400.0, _orbit_dist * 1.1)


func _process(dt: float) -> void:
	if target == null:
		return
	camera.fov = fov
	var tx := target.global_transform
	var model: Node3D = target.get("model_instance")
	if model:
		model.visible = mode != Mode.COCKPIT and target.alive
	if cockpit_model != null:
		cockpit_model.visible = mode == Mode.COCKPIT and target.alive
	if _flyby_t >= 0.0:
		_flyby(dt)
		return
	var desired: Transform3D
	match mode:
		Mode.CHASE:
			var b := tx.basis.orthonormalized()
			var pos := tx.origin + b * Vector3(0.0, 4.5, 24.0)
			var look := tx.origin - b.z * 60.0
			desired = Transform3D(Basis.looking_at(look - pos, b.y), pos)
			var k := 1.0 if _first else 1.0 - exp(-dt * 6.0)
			_smoothed = _smoothed.interpolate_with(desired, k)
			camera.global_transform = _smoothed
		Mode.COCKPIT:
			var pos := tx.origin + tx.basis * Vector3(0.0, 1.1, -4.6)
			# Sit IN the seat: derive the cockpit spot from the model's AABB
			# (the RealSpace meshes point their nose at +z in mesh space, the
			# canopy sits ~38 % back from the nose). The AABB is in MESH
			# space, so it must be transformed by the model_instance node -
			# not by the aircraft basis (the mesh may be yawed 180 degrees
			# relative to the airframe).
			var mi: Node3D = target.get("model_instance")
			if mi != null and mi.mesh != null:
				var bb: AABB = mi.mesh.get_aabb()
				var seat := Vector3(bb.position.x + bb.size.x * 0.5,
					bb.position.y + bb.size.y * 0.42,
					bb.position.z + bb.size.z * 0.62)
				pos = mi.global_transform * seat
			camera.global_transform = Transform3D(tx.basis.orthonormalized(), pos)
		Mode.ORBIT:
			var dir := Vector3(sin(_orbit.x) * cos(_orbit.y), sin(_orbit.y), cos(_orbit.x) * cos(_orbit.y))
			var pos := tx.origin + dir * _orbit_dist
			camera.global_transform = Transform3D(Basis.looking_at(tx.origin - pos, Vector3.UP), pos)
	_first = false
