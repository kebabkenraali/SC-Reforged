## Procedural modern effects (no assets needed): explosions, tracers.
extends RefCounted


static func explosion(size: float) -> Node3D:
	var root := Node3D.new()
	var fire := CPUParticles3D.new()
	fire.one_shot = true
	fire.amount = 64
	fire.lifetime = 1.6
	fire.explosiveness = 0.95
	fire.direction = Vector3.UP
	fire.spread = 180.0
	fire.initial_velocity_min = size * 2.0
	fire.initial_velocity_max = size * 6.0
	fire.gravity = Vector3(0, 2, 0)
	fire.damping_min = 4.0
	fire.damping_max = 8.0
	fire.scale_amount_min = size * 0.6
	fire.scale_amount_max = size * 1.4
	var grad := Gradient.new()
	grad.set_color(0, Color(1.0, 0.9, 0.5, 1.0))
	grad.add_point(0.25, Color(1.0, 0.45, 0.1, 0.9))
	grad.set_color(grad.get_point_count() - 1, Color(0.15, 0.13, 0.12, 0.0))
	fire.color_ramp = grad
	var quad := QuadMesh.new()
	var mat := StandardMaterial3D.new()
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	mat.vertex_color_use_as_albedo = true
	mat.billboard_mode = BaseMaterial3D.BILLBOARD_PARTICLES
	mat.albedo_texture = _soft_dot()
	quad.material = mat
	fire.mesh = quad
	fire.emitting = true
	root.add_child(fire)

	var light := OmniLight3D.new()
	light.light_color = Color(1.0, 0.6, 0.25)
	light.light_energy = 12.0
	light.omni_range = size * 25.0
	root.add_child(light)
	root.ready.connect(func():
		var t := root.create_tween()
		t.tween_property(light, "light_energy", 0.0, 0.8)
		t.tween_interval(1.5)
		t.tween_callback(root.queue_free))
	return root


static var _dot: Texture2D


static func _soft_dot() -> Texture2D:
	if _dot == null:
		var g := GradientTexture2D.new()
		g.fill = GradientTexture2D.FILL_RADIAL
		g.fill_from = Vector2(0.5, 0.5)
		g.fill_to = Vector2(1.0, 0.5)
		var grad := Gradient.new()
		grad.set_color(0, Color(1, 1, 1, 1))
		grad.set_color(1, Color(1, 1, 1, 0))
		g.gradient = grad
		_dot = g
	return _dot


static func tracer_mesh() -> Mesh:
	var m := BoxMesh.new()
	m.size = Vector3(0.25, 0.25, 14.0)
	var mat := StandardMaterial3D.new()
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.albedo_color = Color(1.0, 0.85, 0.4)
	mat.emission_enabled = true
	mat.emission = Color(1.0, 0.7, 0.3)
	mat.emission_energy_multiplier = 6.0
	m.material = mat
	return m
