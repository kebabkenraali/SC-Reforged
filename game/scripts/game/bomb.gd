## Unguided bomb: ballistic flight with simple drag. The same integration is
## used for the HUD's continuously computed impact point (CCIP).
extends Node3D

signal impacted(bomb, pos: Vector3)

const STEP := 1.0 / 60.0

var spec: Dictionary
var weapon_name := ""
var shooter: Node3D
var velocity := Vector3.ZERO
var alive := true


func setup(name: String, data: Dictionary, mesh: Mesh, from: Vector3, launch_velocity: Vector3) -> void:
	weapon_name = name
	spec = data
	velocity = launch_velocity + Vector3.DOWN * 2.0
	var mi := MeshInstance3D.new()
	if mesh != null:
		mi.mesh = mesh
	else:
		var cyl := CylinderMesh.new()
		cyl.top_radius = 0.18
		cyl.bottom_radius = 0.18
		cyl.height = 2.2
		mi.mesh = cyl
		mi.rotation.x = PI * 0.5
	add_child(mi)
	ready.connect(func():
		global_position = from
		_face())


static func integrate(vel: Vector3, drag: float, dt: float) -> Vector3:
	return vel + (Vector3.DOWN * 9.81 - vel * vel.length() * drag * 0.01) * dt


## Impact point for a bomb released now, or null if none within 60 s.
static func predict_impact(pos: Vector3, vel: Vector3, drag: float, terrain):
	var p := pos
	var v := vel
	var dt := 0.05
	for i in 1200:
		v = integrate(v, drag, dt)
		var next := p + v * dt
		var ground: float = terrain.height_at(next.x, next.z) if terrain else 0.0
		if next.y <= ground:
			return Vector3(next.x, ground, next.z)
		p = next
	return null


## Returns true while falling. `objects` are ground objects for contact fuzing.
func step(dt: float, terrain, objects: Array) -> bool:
	if not alive:
		return false
	velocity = integrate(velocity, spec.drag, dt)
	var from := global_position
	global_position += velocity * dt
	_face()
	var ground: float = terrain.height_at(global_position.x, global_position.z) if terrain else 0.0
	var hit := global_position.y <= ground
	if not hit:
		for o in objects:
			if o.alive and o.hittable and Geometry3D.segment_intersects_sphere(from, global_position, o.center(), o.radius * 0.8).size() > 0:
				hit = true
				break
	if hit:
		alive = false
		var pos := Vector3(global_position.x, maxf(global_position.y, ground), global_position.z)
		impacted.emit(self, pos)
		queue_free()
		return false
	return true


func _face() -> void:
	if velocity.length_squared() > 1.0:
		var up := Vector3.UP if absf(velocity.normalized().y) < 0.98 else Vector3.RIGHT
		global_transform.basis = Basis.looking_at(velocity.normalized(), up)
