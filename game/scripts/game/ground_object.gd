## Static ground object (building, AA site, parked aircraft …) placed from the
## terrain object lists or a mission. Swaps to its original "destroyed" model.
extends Node3D

signal destroyed(obj)

var display_name := ""
var radius := 10.0
var health := 40.0
var alive := true
var is_target := false
var hittable := true
var blast_only := false          # runways: hurt by bomb blasts, not by bullets
var hostile := false
var team: int = 0                # 0 = neutral, 1 = player/ally, 2 = enemy
var weapon := {}                # from FORM SWPN: name, range, ceiling, ammo, missile
var ammo := 0
var cooldown := 0.0
var incoming: Array = []        # unused for ground objects; keeps the missile API uniform
var last_hit_by = null           # last damage cause (shooter node) for kill attribution
var destroyed_mesh: Mesh
var mesh_instance: MeshInstance3D


func setup(mesh: Mesh, box: AABB, wreck: Mesh, label: String) -> void:
	display_name = label
	destroyed_mesh = wreck
	mesh_instance = MeshInstance3D.new()
	mesh_instance.mesh = mesh
	# Original models are centred on their pivot; rest them on the ground.
	mesh_instance.position.y = -box.position.y
	# Flat objects (runways, pads) sit slightly above the terrain to avoid z-fighting.
	if box.size.y < 1.5:
		mesh_instance.position.y += 0.6
		hittable = false
		blast_only = true
	add_child(mesh_instance)
	radius = maxf(6.0, box.size.length() * 0.5)
	health = clampf(box.size.length() * 2.0, 20.0, 120.0)


## World-space centre used for hit tests and HUD markers.
func center() -> Vector3:
	return global_position + Vector3.UP * radius * 0.4


func damage(amount: float, cause = null) -> void:
	if not alive:
		return
	last_hit_by = cause
	health -= amount
	if health > 0.0:
		return
	alive = false
	if destroyed_mesh:
		mesh_instance.mesh = destroyed_mesh
	elif blast_only:
		mesh_instance.transparency = 0.5     # cratered runway stays visible
	else:
		mesh_instance.visible = false
	Sfx.play_at("explosion_big" if radius > 15.0 else "explosion_small", center(), 4.0)
	var fx := preload("res://scripts/game/effects.gd").explosion(radius)
	get_parent().add_child(fx)
	fx.global_position = center()
	destroyed.emit(self)
