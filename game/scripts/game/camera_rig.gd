## Chase, cockpit and free-orbit cameras with smoothing.
extends Node3D

enum Mode { CHASE, COCKPIT, CLEAN, ORBIT }
const NAMES := ["Chase", "Cockpit", "No cockpit", "Free orbit"]

var target: Node3D
var mode := Mode.CHASE
var fov := 70.0
var camera: Camera3D
var _orbit := Vector2(0.4, 0.25)
var _orbit_dist := 40.0
var _smoothed := Transform3D.IDENTITY
var _first := true
var cockpit_model: MeshInstance3D = null
var cockpit_instruments: Node3D = null   # live gauges inside the pit
# Procedural pilot silhouette below the pit (flight_scene builds the legs).
var pilot_node: Node3D = null
var vr_active := false           # OpenXR interface is initialized
# Flyby cutaway: a short scripted pass across the aircraft (waypoint reached).
var _flyby_prev := Mode.CHASE
var _flyby_t := -1.0
var _flyby_len := 3.0
# Waypoint jump animation: the original cut to a short cinematic when the
# aircraft "jumped" to the next area. Two beats: a fast pass from ahead of the
# nose down along the wing, then a pull-up into the trailing view.
var _jump_prev := Mode.CHASE
var _jump_t := -1.0
var _jump_len := 3.0
# Landing cinematic: first track the player, then settle at a fixed viewpoint
# beside the runway for the touchdown and roll-out.
var _land_t := -1.0
var _land_thr := Vector3.ZERO
var _land_dir := Vector3.FORWARD
var _land_ground_y := 0.0
const LAND_FOLLOW_S := 3.0
# Cockpit mouse look: drag the mouse to swing the view, left click returns
# to the default seat direction. Degrees, clamped.
var _pit_aim := Vector2(0.0, 0.0)
var _pit_aim_sm := Vector2(0.0, 0.0)
var _pit_dragged := false
var _pit_mouse_move := Vector2.ZERO   # accumulated mouse movement per frame
const PIT_AIM_MAX := 30.0     # degrees from the default view
const PIT_AIM_SPEED := 0.06   # degrees of smoothing per frame
const PIT_COCKPIT_OFFSET := Vector3(0.0, 0.9, -3.2)  # closer to the seat
const PIT_COCKPIT_PITCH_DEG := -1.0   # default near-level view (canopy + HUD, panel low)


var xr_origin: XROrigin3D = null
var xr_camera: XRCamera3D = null


func _ready() -> void:
	camera = Camera3D.new()
	camera.near = 0.3
	camera.far = 400000.0
	camera.doppler_tracking = Camera3D.DOPPLER_TRACKING_PHYSICS_STEP
	add_child(camera)
	if vr_active:
		# Proper Godot 4 XR setup: the headset's tracking drives XRCamera3D
		# relative to XROrigin3D. The origin follows the desktop camera's
		# transform, so every view mode (cockpit/chase) works in VR too.
		xr_origin = XROrigin3D.new()
		xr_origin.current = true
		add_child(xr_origin)
		xr_camera = XRCamera3D.new()
		xr_camera.near = 0.3
		xr_camera.far = 400000.0
		xr_origin.add_child(xr_camera)
		camera.current = false
		xr_camera.current = true


## Position the view. In VR the XROrigin3D carries the aircraft/camera pose
## and the headset's tracking is added on top by XRCamera3D.
func _set_cam(t: Transform3D) -> void:
	camera.global_transform = t
	if xr_origin != null:
		xr_origin.global_transform = t


func cycle() -> void:
	mode = (mode + 1) % Mode.size()
	_flyby_t = -1.0
	_jump_t = -1.0
	_land_t = -1.0
	_cine_t = -1.0
	camera.fov = fov
	_first = true
	_pit_aim = Vector2(0.0, 0.0)
	_pit_aim_sm = Vector2(0.0, 0.0)
	_pit_dragged = false


## A cinematic flyby pass (about 3 s): the camera sweeps past the aircraft
## and returns to the previous view. Triggered when a waypoint is reached,
## cancelled by any camera cycle (as in the original's camera cuts).
func start_flyby(duration := 3.0) -> void:
	_flyby_prev = mode
	_flyby_len = duration
	_flyby_t = 0.0
	_first = true


func flyby_active() -> bool:
	return _flyby_t >= 0.0


func _flyby(dt: float) -> void:
	# Real time: fast travel runs at time_scale 8, which made a 5 s pass last
	# 0.6 s on screen.
	_flyby_t += dt / maxf(Engine.time_scale, 0.001)
	var k: float = clampf(_flyby_t / _flyby_len, 0.0, 1.0)
	var tx := target.global_transform
	var b := tx.basis.orthonormalized()
	# A dramatic sweep: start ahead-left of the nose, cross over the aircraft
	# and settle behind the tail (the original's pass at the waypoint).
	var side: float = lerpf(-1.0, 1.0, k)
	var pos: Vector3 = tx.origin + b * Vector3(side * 70.0, lerpf(6.0, 22.0, k), lerpf(40.0, -18.0, k))
	var look: Vector3 = tx.origin + b * Vector3(0.0, 0.0, 6.0)
	_set_cam(Transform3D(Basis.looking_at(look - pos, Vector3.UP), pos))
	if _flyby_t >= _flyby_len:
		mode = _flyby_prev
		_flyby_t = -1.0
		_first = true


## Starts the waypoint-jump animation. Real time, like the flyby: a test run at
## time_scale 10 still shows the full pass. Any camera cycle cancels it.
func start_jump(duration := 3.0) -> void:
	_jump_prev = mode
	_jump_len = duration
	_jump_t = 0.0
	_flyby_t = -1.0
	_first = true


func _jump(dt: float) -> void:
	_jump_t += dt / maxf(Engine.time_scale, 0.001)
	var k: float = clampf(_jump_t / _jump_len, 0.0, 1.0)
	var tx := target.global_transform
	var b := tx.basis.orthonormalized()
	var pos: Vector3
	var look: Vector3
	if k < 0.6:
		# Ahead-left of the nose, dropping toward the wing as the aircraft
		# sweeps past the camera.
		var s := smoothstep(0.0, 1.0, k / 0.6)
		pos = tx.origin + b * Vector3(lerpf(-95.0, -16.0, s), lerpf(15.0, 3.0, s), lerpf(95.0, -8.0, s))
		look = tx.origin + b * Vector3(lerpf(0.0, -26.0, s), 1.0, lerpf(0.0, -20.0, s))
	else:
		# Pull up behind the tail into the normal trailing view.
		var s := smoothstep(0.0, 1.0, (k - 0.6) / 0.4)
		pos = tx.origin + b * Vector3(lerpf(-16.0, 0.0, s), lerpf(3.0, 7.0, s), lerpf(-8.0, 26.0, s))
		look = tx.origin - b.z * lerpf(20.0, 60.0, s)
	var up := (b * Vector3.UP).lerp(Vector3.UP, smoothstep(0.0, 1.0, k)).normalized()
	_set_cam(Transform3D(Basis.looking_at(look - pos, up), pos))
	camera.fov = lerpf(fov, fov * 0.82, sin(k * PI))
	if _jump_t >= _jump_len:
		camera.fov = fov
		mode = _jump_prev
		_jump_t = -1.0
		_first = true


## Starts the autoland shot. The camera follows the aircraft for a few seconds,
## then drifts to a fixed spot beside the runway and watches it land.
func start_landing_anim(threshold: Vector3, direction: Vector3, ground_y: float) -> void:
	_land_thr = threshold
	_land_dir = direction.normalized()
	_land_ground_y = ground_y
	_land_t = 0.0
	_jump_t = -1.0
	_flyby_t = -1.0
	_first = true


func stop_landing_anim() -> void:
	_land_t = -1.0
	_first = true


func landing_anim_active() -> bool:
	return _land_t >= 0.0


func _landing_anim(dt: float) -> void:
	_land_t += dt / maxf(Engine.time_scale, 0.001)
	var tx := target.global_transform
	if _land_t < LAND_FOLLOW_S:
		# Low, close chase on the aircraft while it turns onto finals.
		var s := clampf(_land_t / LAND_FOLLOW_S, 0.0, 1.0)
		var b := tx.basis.orthonormalized()
		var pos: Vector3 = tx.origin + b * Vector3(lerpf(34.0, 58.0, s), lerpf(6.0, 12.0, s), lerpf(8.0, 34.0, s))
		var look: Vector3 = tx.origin + b * Vector3(0.0, 1.0, -8.0)
		_set_cam(Transform3D(Basis.looking_at(look - pos, Vector3.UP), pos))
		return
	# The camera leaves the aircraft and settles beside the threshold.
	var s := smoothstep(0.0, 1.0, clampf((_land_t - LAND_FOLLOW_S) / 2.5, 0.0, 1.0))
	var side: Vector3 = _land_dir.cross(Vector3.UP).normalized()
	var fixed_pos: Vector3 = _land_thr - _land_dir * 220.0 + side * 170.0
	fixed_pos.y = _land_ground_y + 22.0
	var fixed_look: Vector3 = _land_thr + _land_dir * 320.0
	fixed_look.y = _land_ground_y + 6.0
	var b2 := tx.basis.orthonormalized()
	var follow_pos: Vector3 = tx.origin + b2 * Vector3(58.0, 12.0, 34.0)
	var follow_look: Vector3 = tx.origin + b2 * Vector3(0.0, 1.0, -8.0)
	var pos2: Vector3 = follow_pos.lerp(fixed_pos, s)
	var look2: Vector3 = follow_look.lerp(fixed_look, s)
	_set_cam(Transform3D(Basis.looking_at(look2 - pos2, Vector3.UP), pos2))


## Cinematic shot around another aircraft (the join-up with the MISN-1A
## C-130): the camera starts ahead and low on the left of `focus`, sweeps
## along its side and ends high behind it, looking at the formation slots.
## Real time, like the flyby. Any camera cycle ends it.
var _cine_focus: Node3D
var _cine_t := -1.0
var _cine_len := 7.0

func start_cinematic(focus: Node3D, duration := 7.0) -> void:
	_cine_focus = focus
	_cine_len = duration
	_cine_t = 0.0
	_flyby_t = -1.0


func cinematic_active() -> bool:
	return _cine_t >= 0.0


func _cinematic(dt: float) -> void:
	if _cine_focus == null or not is_instance_valid(_cine_focus) or not _cine_focus.alive:
		_cine_t = -1.0
		_first = true
		return
	_cine_t += dt / maxf(Engine.time_scale, 0.001)
	var k: float = smoothstep(0.0, 1.0, clampf(_cine_t / _cine_len, 0.0, 1.0))
	var tx := _cine_focus.global_transform
	var b := tx.basis.orthonormalized()
	# Model space: -Z forward, +X right, +Y up.
	# Behind-left of the transport, drifting up and in: the fighters coming
	# from behind fly past the camera into their slots. Heading-only frame and
	# world up, so the shot stays level while the transport banks.
	var fwd := Vector3(-b.z.x, 0.0, -b.z.z).normalized()
	var right := fwd.cross(Vector3.UP).normalized()
	var pos: Vector3 = tx.origin + right * lerpf(-110.0, -55.0, k) + Vector3.UP * lerpf(20.0, 38.0, k) - fwd * lerpf(230.0, 130.0, k)
	var look: Vector3 = tx.origin + right * 25.0 - fwd * 45.0
	_set_cam(Transform3D(Basis.looking_at(look - pos, Vector3.UP), pos))
	if _cine_t >= _cine_len:
		_cine_t = -1.0
		_first = true


func mode_name() -> String:
	return NAMES[mode]


## Cockpit mouse look: dragging swings the view, a plain left click returns to
## the default seat direction (after a short press so accidental presses while
## moving elsewhere do not reset).
func _cockpit_mouse_look(dt: float) -> void:
	var pressed: bool = Input.is_mouse_button_pressed(MOUSE_BUTTON_LEFT)
	var d: Vector2 = _pit_mouse_move
	_pit_mouse_move = Vector2.ZERO
	if pressed:
		if d.length() > 0.02:
			var speed: float = float(Settings.get_value("controls", "mouse_sensitivity"))
			_pit_aim.x -= d.x * 0.20 * speed
			_pit_aim.y += d.y * 0.20 * speed
			_pit_dragged = true
	else:
		# Left click (no real drag) returns the view to the default seat.
		if not _pit_dragged:
			_pit_aim = Vector2(0.0, 0.0)
		_pit_dragged = false
	_pit_aim.x = clampf(_pit_aim.x, -PIT_AIM_MAX, PIT_AIM_MAX)
	_pit_aim.y = clampf(_pit_aim.y, -PIT_AIM_MAX, PIT_AIM_MAX)
	_pit_aim_sm.x = move_toward(_pit_aim_sm.x, _pit_aim.x, PIT_AIM_SPEED)
	_pit_aim_sm.y = move_toward(_pit_aim_sm.y, _pit_aim.y, PIT_AIM_SPEED)


func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventMouseMotion:
		_pit_mouse_move += event.relative
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
	# During a flyby the camera is outside even if the chosen view is the
	# cockpit: show the aircraft (it was hidden -> the pass showed empty sky).
	var in_seat: bool = mode == Mode.COCKPIT or mode == Mode.CLEAN
	var cutaway: bool = _flyby_t >= 0.0 or _jump_t >= 0.0 or _cine_t >= 0.0 or _land_t >= 0.0
	var outside: bool = not in_seat or cutaway
	if model:
		model.visible = outside and target.alive
	if cockpit_model != null:
		# "No cockpit" keeps the seat camera but drops the pit mesh and legs.
		cockpit_model.visible = in_seat and mode == Mode.COCKPIT and not cutaway and target.alive
	if pilot_node != null:
		pilot_node.visible = in_seat and mode == Mode.COCKPIT and not cutaway and target.alive
	if cockpit_instruments != null:
		# The gauges are the HUD in VR; keep them in both seat views, even
		# when the pit mesh itself is hidden ("No cockpit").
		cockpit_instruments.visible = in_seat and not cutaway and target.alive
		# Above the seat's tail: the legs hang down and read in front of the
		# flat pit silhouette.
		var mi: Node3D = target.get("model_instance")
		if mi != null and mi.mesh != null:
			var bb: AABB = mi.mesh.get_aabb()
			var seat := Vector3(bb.position.x + bb.size.x * 0.5,
				bb.position.y + bb.size.y * 0.42,
				bb.position.z + bb.size.z * 0.62)
			var t := mi.global_transform
			t.origin = seat + Vector3(0.0, 0.3, 0.9)
			pilot_node.global_transform = t
	if in_seat and not vr_active:
		_cockpit_mouse_look(dt)
	if _cine_t >= 0.0:
		_cinematic(dt)
		return
	if _land_t >= 0.0:
		_landing_anim(dt)
		return
	if _jump_t >= 0.0:
		_jump(dt)
		return
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
			_set_cam(_smoothed)
		Mode.COCKPIT, Mode.CLEAN:
			var pos := tx.origin + tx.basis * PIT_COCKPIT_OFFSET
			# Sit IN the seat: derive the cockpit spot from the model's AABB
			# (the RealSpace meshes point their nose at +z in mesh space, the
			# canopy sits ~38 % back from the nose). The AABB is in MESH
			# space, so it must be transformed by the model_instance node -
			# not by the aircraft basis (the mesh may be yawed 180 degrees
			# relative to the airframe).
			var mi: Node3D = target.get("model_instance")
			if mi != null and mi.mesh != null:
				var bb: AABB = mi.mesh.get_aabb()
				# Move well forward in the pit, to the control-stick / legs
				# position the original view was framed from: low in the mesh
				# and toward the front, not the rear seat corner.
				# Original libRealSpace: pilot eye ~3 units above the plane
				# origin, instruments at 5.8-6.2 units in front. Inside the pit
				# mesh that means forward (+Z in mesh space) and high in Y.
				var seat := Vector3(bb.position.x + bb.size.x * 0.5,
					bb.position.y + bb.size.y * 0.54,
					bb.position.z + bb.size.z * 0.48)
				pos = mi.global_transform * seat
			var cam_basis := tx.basis.orthonormalized()
			if not vr_active:
				cam_basis = cam_basis.rotated(Vector3.UP, deg_to_rad(_pit_aim_sm.x))
				cam_basis = cam_basis.rotated(cam_basis.x, deg_to_rad(_pit_aim_sm.y + PIT_COCKPIT_PITCH_DEG))
			_set_cam(Transform3D(cam_basis, pos))
		Mode.ORBIT:
			var dir := Vector3(sin(_orbit.x) * cos(_orbit.y), sin(_orbit.y), cos(_orbit.x) * cos(_orbit.y))
			var pos := tx.origin + dir * _orbit_dist
			_set_cam(Transform3D(Basis.looking_at(tx.origin - pos, Vector3.UP), pos))
	_first = false
