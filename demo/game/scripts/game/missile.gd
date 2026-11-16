## Guided missile with lead pursuit, a turn-rate limit, a smoke trail and a chance to
## be decoyed by flares (IR) or chaff (radar).
extends Node3D

const Weapons = preload("res://scripts/game/weapons.gd")

signal detonated(missile, hit_target)

var spec: Dictionary
var weapon_name := ""
var target: Node3D            # aircraft or ground object being tracked
var decoy_pos = null          # Vector3 when chasing a countermeasure
var shooter: Node3D
var velocity := Vector3.ZERO
var life := 0.0
var alive := true
var _trail: CPUParticles3D


func setup(name: String, mesh: Mesh, from: Vector3, dir: Vector3, launch_velocity: Vector3, data := {}) -> void:
	weapon_name = name
	spec = data if not data.is_empty() else Weapons.missile(name)
	life = spec.life
	velocity = launch_velocity + dir * 60.0
	if mesh != null:
		var mi := MeshInstance3D.new()
		mi.mesh = mesh
		add_child(mi)
	else:
		var mi := MeshInstance3D.new()
		var cyl := CylinderMesh.new()
		cyl.top_radius = 0.12
		cyl.bottom_radius = 0.12
		cyl.height = 3.0
		mi.mesh = cyl
		mi.rotation.x = PI * 0.5
		add_child(mi)
	_trail = CPUParticles3D.new()
	_trail.amount = 160
	_trail.lifetime = 2.5
	_trail.local_coords = false
	_trail.direction = Vector3(0, 0, 1)
	_trail.spread = 6.0
	_trail.initial_velocity_min = 2.0
	_trail.initial_velocity_max = 5.0
	_trail.gravity = Vector3(0, 1.5, 0)
	_trail.scale_amount_min = 2.0
	_trail.scale_amount_max = 4.5
	var grad := Gradient.new()
	grad.set_color(0, Color(1.0, 0.8, 0.5, 0.9))
	grad.add_point(0.08, Color(0.9, 0.9, 0.9, 0.55))
	grad.set_color(grad.get_point_count() - 1, Color(0.8, 0.8, 0.8, 0.0))
	_trail.color_ramp = grad
	var quad := QuadMesh.new()
	var mat := StandardMaterial3D.new()
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	mat.vertex_color_use_as_albedo = true
	mat.billboard_mode = BaseMaterial3D.BILLBOARD_PARTICLES
	mat.albedo_texture = preload("res://scripts/game/effects.gd")._soft_dot()
	quad.material = mat
	_trail.mesh = quad
	add_child(_trail)
	ready.connect(func():
		global_position = from
		_face(velocity))


## Returns true while the missile is flying.
func step(dt: float, terrain) -> bool:
	if not alive:
		return false
	life -= dt
	var aim = decoy_pos
	if aim == null and target != null and target.alive:
		aim = target.center() if target.has_method("center") else target.global_position
	var spd := minf(velocity.length() + 400.0 * dt, spec.speed)
	if aim != null:
		# Lead pursuit: aim where the target will be when the missile arrives.
		var los: Vector3 = (aim - global_position)
		var aim_pos: Vector3 = aim
		if decoy_pos == null and target != null and target.get("velocity") != null:
			aim_pos += target.velocity * (los.length() / maxf(spd, 1.0)) * 0.9
		var desired := (aim_pos - global_position).normalized()
		var cur := velocity.normalized()
		var ang := cur.angle_to(desired)
		# Close to the target the missile needs extra authority to follow
		# steering maneuvers (the last seconds decide the hit).
		var authority: float = spec.turn
		if decoy_pos == null and target != null and target.get("velocity") != null:
			var d2: float = (target.global_position - global_position).length()
			if d2 < 800.0:
				authority *= 3.5
			elif d2 < 1500.0:
				authority *= 2.2
		var max_ang: float = authority * dt
		if ang > max_ang and ang > 0.0001:
			desired = cur.slerp(desired, max_ang / ang)
		velocity = desired * spd
		var fuze: float = 14.0 if target == null or target.get("velocity") != null else maxf(8.0, target.radius * 0.7)
		if target != null and decoy_pos == null and los.length() < fuze:
			_detonate(true)
			return false
		if decoy_pos != null and los.length() < 20.0:
			_detonate(false)
			return false
	else:
		velocity = velocity.normalized() * spd + Vector3.DOWN * 9.81 * dt
	global_position += velocity * dt
	_face(velocity)
	if life <= 0.0 or (terrain != null and global_position.y < terrain.height_at(global_position.x, global_position.z)):
		_detonate(false)
		return false
	return true


## A countermeasure was released by `who`; maybe chase it instead. A flare
## or chaff burst can only blind a seeker that is close enough to see it
## (the original game's decoys fool the launcher on the last stretch of
## flight, not from 16 km out).
func offer_decoy(who: Node3D, pos: Vector3) -> void:
	if who != target or decoy_pos != null:
		return
	if global_position.distance_to(pos) > 2600.0:
		return
	if randf() < Weapons.DECOY_CHANCE.get(spec.seeker, 0.5):
		decoy_pos = pos


func _face(v: Vector3) -> void:
	if v.length_squared() > 1.0:
		var up := Vector3.UP if absf(v.normalized().y) < 0.98 else Vector3.RIGHT
		global_transform.basis = Basis.looking_at(v.normalized(), up)


func _detonate(hit: bool) -> void:
	alive = false
	if hit and target != null:
		target.damage(spec.damage, shooter)
	var fx := preload("res://scripts/game/effects.gd").explosion(6.0)
	get_parent().add_child(fx)
	fx.global_position = global_position
	detonated.emit(self, hit)
	# Let the smoke trail fade out before removing the node.
	_trail.emitting = false
	for c in get_children():
		if c is MeshInstance3D:
			c.visible = false
	get_tree().create_timer(_trail.lifetime).timeout.connect(queue_free)
