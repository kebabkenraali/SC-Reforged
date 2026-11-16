## Aircraft using an original RealSpace model with a modern flight model:
## fly-by-wire g-command pitch, aerodynamic lift/drag, thrust lapse with
## altitude, stall, ground handling. Player and AI share the same physics.
extends Node3D

const G := 9.81

signal destroyed(aircraft)
signal crashed(aircraft)

@export var mass := 12000.0
@export var wing_area := 27.9
@export var thrust_mil := 76000.0
@export var thrust_ab := 127000.0
@export var cd0 := 0.022
@export var induced_k := 0.11
@export var cl_alpha := 4.6
@export var aoa_max := 0.42
@export var max_roll_rate := 4.2
@export var max_g := 9.0

var terrain                     # sc_terrain.gd instance
var velocity := Vector3.ZERO
var throttle := 0.85
var afterburner := false
var brakes := false
var controls := Vector3.ZERO    # pitch (+ = nose up), roll (+ = right), yaw (+ = right)
var firing := false
var is_player := false
var alive := true
var health := 100.0
var max_health := 100.0   # the original Kill Number of the aircraft type
var on_ground := false
var aoa := 0.0
var g_force := 1.0
var radius := 8.0
var display_name := ""
var model_name := ""
var last_hit_by = null           # last damage cause (shooter node) for kill attribution
@export var team: int = 0  # 0 = neutral, 1 = player/ally, 2 = enemy

var hostile := false

func is_hostile_to(other) -> bool:
	if team == 0 or other.team == 0:
		return false  # neutral
	return team != other.team

func is_friendly_to(other) -> bool:
	if team == 0 or other.team == 0:
		return true  # neutral is friendly to all
	return team == other.team
var missiles := {}              # weapon name -> rounds left (from the original WPNS)
var countermeasures := 30
var incoming: Array = []        # missiles currently tracking this aircraft

# Combat AI (set by the flight scene each frame while engaging)
var attack_point = null         # Vector3 to steer at, or null to patrol
var evading := false
var missile_cooldown := 0.0
var cm_cooldown := 0.0
var home := Vector3.ZERO        # patrol centre (mission area)
var patrol_radius := 0.0

# Mission script data (PART leader / offset, AI and route blocks)
var formation_leader: Node3D    # fly in formation on this aircraft
var formation_offset := Vector3(0, 0, 60)   # leader-local, metres
var route: Array = []           # Vector3 waypoints from the route block
var route_index := 0
var attack_ids: Array = []      # PART ids the AI block says to attack (a7)
var scripted := false           # behaviour comes from a mission AI program
var takeoff := false            # script action a1: take off from the ground
var takeoff_after: Node3D       # wait for this aircraft (the flight lead) to get airborne

var model_instance: MeshInstance3D
var _ai_target := Vector3.ZERO
var _ai_timer := 0.0
var _gun_cooldown := 0.0
## Pitch-rate override from the level autopilot (flight_scene.gd). NaN = use
## the normal fly-by-wire pitch loop; reset every physics step, so it only
## applies to the frame the caller sets it.
var pitch_rate_override := NAN
## Standby: an enemy in briefing position does nothing until the player is
## near (the original showed the raiders arriving with the scenario scene).
var standby := false
signal hud_contact(name: String)   # fired when a standby ship becomes active
## Filled by the game scene; the AI uses it to see the player's position.
var scene_ref = null


func setup(model, palette: PackedColorArray, smooth: bool, modern_mesh: Mesh = null, fallback_name := "") -> void:
	model_instance = MeshInstance3D.new()
	var box: AABB
	if modern_mesh != null:
		# Free procedural model (ships with the release, no original data needed).
		model_instance.mesh = modern_mesh
		box = modern_mesh.get_aabb()
	else:
		model_instance.mesh = model.build_mesh(palette, 0, smooth)
		box = model.aabb()
	model_instance.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_ON
	add_child(model_instance)
	radius = maxf(4.0, box.size.length() * 0.5)
	var n: String = model.name if model != null else fallback_name
	display_name = n.get_file().get_basename()
	model_name = n
	var Weapons = preload("res://scripts/game/weapons.gd")
	# Original "Kill Number" damage resistance (Playtester's Guide pp. 86-96).
	health = float(Weapons.kill_number(display_name, 0))
	max_health = health
	missiles = Weapons.loadout(model) if model != null else {"AMRAAM": 4, "SWINDERM": 2}


func air_density() -> float:
	return 1.225 * exp(-global_position.y / 8500.0)


func speed() -> float:
	return velocity.length()


func _physics_process(dt: float) -> void:
	if not alive:
		return
	if not is_player:
		_ai(dt)
	_flight(dt)
	pitch_rate_override = NAN   # applies one frame; re-set by the caller each step
	_gun_cooldown -= dt
	missile_cooldown -= dt
	cm_cooldown -= dt
	incoming = incoming.filter(func(m): return is_instance_valid(m) and m.alive)


func _flight(dt: float) -> void:
	var b := global_transform.basis.orthonormalized()
	var fwd := -b.z
	var right := b.x
	var up := b.y
	var spd := velocity.length()
	var rho := air_density()
	var q := 0.5 * rho * spd * spd
	var vl := b.transposed() * velocity
	aoa = atan2(-vl.y, -vl.z) if spd > 5.0 else 0.0
	var beta := atan2(vl.x, -vl.z) if spd > 5.0 else 0.0

	# Lift with a post-stall drop-off.
	var cl := cl_alpha * aoa
	var stall := aoa_max * 1.15
	if absf(aoa) > stall:
		cl = signf(aoa) * cl_alpha * stall * maxf(0.2, 1.0 - (absf(aoa) - stall) * 2.5)
	var lift_mag := q * wing_area * cl
	var vdir := velocity / spd if spd > 1.0 else fwd
	var lift_dir := right.cross(vdir).normalized()
	var drag := q * wing_area * (cd0 + induced_k * cl * cl + (0.09 if brakes else 0.0))
	var thrust := (thrust_ab if afterburner else thrust_mil * throttle) * clampf(rho / 1.225, 0.25, 1.0)

	var force := fwd * thrust + lift_dir * lift_mag - vdir * drag - right * q * wing_area * 0.6 * beta
	force += Vector3.DOWN * mass * G
	var accel := force / mass
	g_force = (accel + Vector3.UP * G).dot(up) / G

	# Fly-by-wire: stick commands load factor; the controller picks the AoA.
	# Neutral stick holds the flight path (compensating for climb angle and bank).
	var stick := controls.x
	var gamma := asin(clampf(vdir.y, -1.0, 1.0))
	var cb := cos(b.get_euler().z)
	var neutral := cos(gamma) * (1.0 / maxf(cb, 0.5) if cb > 0.0 else cb)
	var n_cmd := neutral + (stick * (max_g - neutral) if stick >= 0.0 else stick * (neutral + 3.0))
	var target_aoa := clampf(n_cmd * mass * G / maxf(q * wing_area * cl_alpha, 1.0), -0.2, aoa_max)
	# Feed-forward: rotate the nose at the rate the flight path is turning.
	var turn_ff := (lift_mag - mass * G * cos(gamma) * cb) / (mass * maxf(spd, 40.0))
	var pitch_rate := clampf(turn_ff + (target_aoa - aoa) * 4.5, -1.6, 1.6)
	if not is_nan(pitch_rate_override):
		pitch_rate = pitch_rate_override
	var authority := clampf(q / 15000.0, 0.15, 1.0)
	var roll_rate := controls.y * max_roll_rate * authority
	var yaw_rate := controls.z * 0.45 * authority + beta * 3.0

	if on_ground:
		pitch_rate = minf(pitch_rate, 0.6) if spd > 70.0 else 0.0
		roll_rate = 0.0
		yaw_rate = controls.z * 0.6

	b = b * Basis(Vector3.RIGHT, pitch_rate * dt)
	b = b * Basis(Vector3.BACK, -roll_rate * dt)
	b = b * Basis(Vector3.UP, -yaw_rate * dt)
	global_transform.basis = b.orthonormalized()

	velocity += accel * dt
	global_position += velocity * dt
	_ground(dt)


func _ground(dt: float) -> void:
	if terrain == null:
		return
	var h: float = terrain.height_at(global_position.x, global_position.z) + 2.2
	var b := global_transform.basis
	var e := b.get_euler()
	# Once on the wheels, stay there: the airframe still has lift surplus
	# above its weight at touchdown speed, and releasing on the first upward
	# pixel made the landing bounce off forever. PIN the plane to the ground
	# while the roll-out runs; a pilot asking for pitch-up (take-off
	# rotation) lifts off the normal way.
	if on_ground and global_position.y <= h + 0.6 and controls.x <= 0.05:
		global_position.y = h
		velocity.y = 0.0
		var friction := (6.0 if brakes else 0.4) * dt
		var flat_fwd := Vector3(-b.z.x, 0.0, -b.z.z).normalized()
		var flat_v := Vector3(velocity.x, 0.0, velocity.z)
		flat_v = flat_v.move_toward(Vector3.ZERO, friction)
		velocity = flat_fwd * flat_v.length()
		global_transform.basis = Basis.from_euler(Vector3(clampf(e.x, 0.0, 0.55), e.y, 0.0))
		return
	if global_position.y > h:
		on_ground = false
		return
	# First contact: accept up to ~165 m/s with a sink gentler than -7 m/s,
	# wings level (the original allowed a nose-up flare; the FBW trim
	# equilibrium keeps the sink gentle at approach speeds anyway).
	var level: bool = absf(e.z) < 0.45 and e.x > -0.15 and e.x < 0.55
	if velocity.y > -7.0 and level and velocity.length() < 165.0 and absf(e.z) < 0.45:
		on_ground = true
		global_position.y = h
		velocity.y = 0.0
		var friction := (6.0 if brakes else 0.4) * dt
		var flat_fwd := Vector3(-b.z.x, 0.0, -b.z.z).normalized()
		var flat_v := Vector3(velocity.x, 0.0, velocity.z)
		flat_v = flat_v.move_toward(Vector3.ZERO, friction)
		velocity = flat_fwd * flat_v.length()
		global_transform.basis = Basis.from_euler(Vector3(clampf(e.x, 0.0, 0.55), e.y, 0.0))
	else:
		global_position.y = h
		explode()
		crashed.emit(self)


func can_fire() -> bool:
	return alive and _gun_cooldown <= 0.0


func consume_round(rate := 0.05) -> void:
	_gun_cooldown = rate


func damage(amount: float, cause = null) -> void:
	if not alive:
		return
	last_hit_by = cause
	health -= amount
	if health <= 0.0:
		explode()
		destroyed.emit(self)


func explode() -> void:
	if not alive:
		return
	alive = false
	Sfx.play_at("explosion_big", global_position, 6.0)
	for c in get_children():
		if c is AudioStreamPlayer3D:
			c.stop()
	if model_instance:
		model_instance.visible = false
	var fx := preload("res://scripts/game/effects.gd").explosion(radius)
	get_parent().add_child(fx)
	fx.global_position = global_position


func respawn(pos: Vector3, heading: float, spd := 220.0) -> void:
	standby = false   # a respawn into position implies active duty
	global_position = pos
	global_transform.basis = Basis(Vector3.UP, heading)
	velocity = -global_transform.basis.z * spd
	alive = true
	health = max_health   # the aircraft's original Kill Number (damage resistance)
	countermeasures = 30
	for c in get_children():
		if c is AudioStreamPlayer3D and not c.playing:
			c.play()
	on_ground = false
	throttle = 0.85
	afterburner = false
	if model_instance:
		model_instance.visible = true


# --- simple AI: wander between waypoints, keep altitude above terrain -------

func _ai(dt: float) -> void:
	# Standby: enemies wait at their briefing position until the fight is
	# near (the original brought the raiders in at the scenario scene, so
	# they do not cruise the whole map from the first frame).
	if standby and scene_ref != null:
		var px: Vector3 = scene_ref.player.global_position
		if global_position.distance_to(px) < 18000.0:
			standby = false
			hud_contact.emit(display_name)
		if on_ground and not takeoff:
			controls = Vector3.ZERO
			throttle = 0.0
			brakes = true
			return
		# hold position: a slow wide circleover the spawn point
		var fwd2: Vector3 = -global_transform.basis.z
		var orbit: Vector3 = home + fwd2.cross(Vector3.UP).normalized() * 4000.0
		orbit.y = maxf(home.y, (terrain.height_at(orbit.x, orbit.z) + 900.0) if terrain != null else home.y)
		steer_towards(orbit, 0.4, 200.0)
		throttle = 0.55
		return
	if on_ground:
		if takeoff and (takeoff_after == null or not is_instance_valid(takeoff_after) or not takeoff_after.on_ground):
			# Full power down the runway, rotate at 75 m/s.
			brakes = false
			throttle = 1.0
			afterburner = true
			controls = Vector3(1.0 if speed() > 75.0 else 0.0, 0.0, 0.0)
			return
		if scripted:
			controls = Vector3.ZERO
			throttle = 0.0
			brakes = true
			return
	if evading and not incoming.is_empty():
		# Break turn across the missile's path at full power.
		var m: Node3D = incoming[0]
		var away := (global_position - m.global_position).normalized()
		var side := away.cross(Vector3.UP).normalized() * 3000.0
		steer_towards(global_position + side + Vector3.UP * 200.0, 1.0, 200.0)
		throttle = 1.0
		afterburner = true
		return
	afterburner = false
	if attack_point == null and _fly_formation():
		return
	if attack_point != null:
		# Energy management: ease the pull near stall speed, burner when slow or far.
		var spd := speed()
		var pull := lerpf(0.05, 1.0, clampf((spd - 120.0) / 110.0, 0.0, 1.0))
		var aim: Vector3 = attack_point
		if spd < 160.0:
			aim.y = minf(aim.y, global_position.y - 600.0)   # dive to regain speed
		steer_towards(aim, pull, 250.0)
		throttle = 1.0
		afterburner = spd < 230.0 or global_position.distance_to(attack_point) > 4000.0
		return
	if not route.is_empty():
		var wp: Vector3 = route[route_index % route.size()]
		if Vector2(wp.x - global_position.x, wp.z - global_position.z).length() < 1500.0:
			route_index += 1
		steer_towards(wp)
		throttle = 0.8
		return
	_ai_timer -= dt
	if _ai_timer <= 0.0 or global_position.distance_to(_ai_target) < 1500.0:
		_ai_timer = randf_range(20.0, 40.0)
		var r: float = patrol_radius if patrol_radius > 0.0 else (terrain.world_size() * 0.3 if terrain else 20000.0)
		_ai_target = home + Vector3(randf_range(-r, r), 0.0, randf_range(-r, r))
		_ai_target.y = (terrain.height_at(_ai_target.x, _ai_target.z) if terrain else 0.0) + randf_range(800.0, 2500.0)
	steer_towards(_ai_target)
	throttle = 0.8


## Station keeping on the formation leader. Returns false when there is no
## usable leader. A wingman waits on the ground until the leader is airborne
## and then joins up directly in position.
func _fly_formation() -> bool:
	if formation_leader == null or not is_instance_valid(formation_leader) or not formation_leader.alive:
		return false
	var lead: Node3D = formation_leader
	if lead.on_ground and not on_ground:
		# Leader still on the runway: hold overhead.
		var orbit := lead.global_position + Vector3(cos(Time.get_ticks_msec() / 9000.0), 0, sin(Time.get_ticks_msec() / 9000.0)) * 3000.0
		steer_towards(orbit + Vector3.UP * 700.0)
		throttle = 0.75
		return true
	if on_ground:
		controls = Vector3.ZERO
		throttle = 0.0
		brakes = true
		var lg: float = terrain.height_at(lead.global_position.x, lead.global_position.z) if terrain else 0.0
		if not scripted and not lead.on_ground and lead.global_position.y - lg > 150.0:
			brakes = false
			respawn(lead.global_transform * formation_offset, 0.0, lead.speed())
			global_transform.basis = lead.global_transform.basis
		return true
	var slot: Vector3 = lead.global_transform * formation_offset
	var to := slot - global_position
	if to.length() > 4000.0:
		steer_towards(lead.global_position, 0.8)
		throttle = 1.0
		afterburner = true
		return true
	var lead_fwd: Vector3 = -lead.global_transform.basis.z
	steer_towards(slot + lead_fwd * 600.0 + lead.velocity * 0.5, 0.6, 150.0)
	var closing := to.dot(lead_fwd)
	throttle = clampf(lead.throttle + closing * 0.004, 0.1, 1.0)
	afterburner = closing > 400.0
	brakes = closing < -150.0
	return true


## Bank-to-turn steering used by AI and the autopilot. `max_pull` limits the
## stick, `floor_agl` is the height above ground the AI refuses to go below.
func steer_towards(target: Vector3, max_pull := 0.7, floor_agl := 600.0) -> void:
	var b := global_transform.basis
	var to := (target - global_position)
	var ground_h: float = terrain.height_at(global_position.x, global_position.z) if terrain else 0.0
	var agl := global_position.y - ground_h
	if agl < floor_agl:
		to.y = maxf(to.y, to.length() * clampf((floor_agl - agl) / floor_agl, 0.2, 0.8))
	var local := b.transposed() * to.normalized()
	var desired_bank := clampf(atan2(local.x, -local.z) * 3.5, -1.35, 1.35)
	if local.z > 0.0:
		desired_bank = signf(local.x if absf(local.x) > 0.01 else 1.0) * 1.35  # target behind: hard turn
	var bank := -b.get_euler().z
	controls.y = clampf((desired_bank - bank) * 2.0, -1.0, 1.0)
	var behind_pull := 0.6 * max_pull if local.z > 0.0 and max_pull > 0.5 else 0.0
	controls.x = clampf(local.y * 3.0 + absf(local.x) * 0.8 + behind_pull, -0.3, max_pull)
	controls.z = 0.0


## Line-up steering: banks toward a horizontal bearing; pitch is left at 0,
## the caller (the landing autopilot) commands pitch separately with a
## vertical-speed controller. Prevents the generic point-steering's
## climb/dive phugoid during slow approaches. `max_bank` keeps the wing
## loading sane on approach - at 78 deg bank the lift losses sink the plane.
func steer_heading(aim: Vector3, max_bank := 0.5) -> void:
	var b := global_transform.basis
	var to := Vector3(aim.x - global_position.x, 0.0, aim.z - global_position.z)
	if to.length() < 1.0:
		to = -b.z
	var local := b.transposed() * to.normalized()
	var desired_bank := clampf(atan2(local.x, -local.z) * 2.0, -max_bank, max_bank)
	var bank := -b.get_euler().z
	controls.y = clampf((desired_bank - bank) * 2.0, -1.0, 1.0)
	controls.x = 0.0
	controls.z = 0.0
