## Procedural low-poly jet fighters that ship with the GitHub release (no
## original data needed). Builds an ArrayMesh from primitives: forward is -Z.
## Surfaces: 0 body, 1 glass, 2 dark, 3 accent (tail paint, team-coloured).
extends RefCounted

const BODY := 0
const GLASS := 1
const DARK := 2
const ACCENT := 3

static var _cache := {}
static var _accent_cache := {}


static func build(model_name: String) -> ArrayMesh:
	var key: String = _profile_of(model_name)
	if not _cache.has(key):
		_cache[key] = _build_profile(key, model_name)
	return _cache[key]


## Cyan for player-side fighters, amber-red for MiGs (matches HUD colours).
static func accent_material(model_name: String) -> StandardMaterial3D:
	var n := model_name.to_upper()
	var ally: bool = n.begins_with("F-16") or n.begins_with("F16")
	var key := "ally" if ally else "enemy"
	if not _accent_cache.has(key):
		var m := StandardMaterial3D.new()
		m.albedo_color = Color(0.30, 0.72, 0.90) if ally else Color(0.82, 0.42, 0.12)
		m.metallic = 0.5
		m.roughness = 0.4
		m.emission_enabled = true
		m.emission = m.albedo_color * 0.12
		_accent_cache[key] = m
	return _accent_cache[key]


static func _profile_of(model_name: String) -> String:
	var n := model_name.to_upper()
	if n.contains("MIG29"):
		return "mig29"
	if n.contains("MIG21"):
		return "mig21"
	return "f16"


static func _build_profile(profile: String, model_name: String) -> ArrayMesh:
	var body := StandardMaterial3D.new()
	var glass := StandardMaterial3D.new()
	var dark := StandardMaterial3D.new()
	match profile:
		"mig29":
			body.albedo_color = Color("#77806e")
		"mig21":
			body.albedo_color = Color("#8d9296")
		_:
			body.albedo_color = Color("#9aa4ad")
	body.metallic = 0.55
	body.roughness = 0.45
	glass.albedo_color = Color("#141d29")
	glass.metallic = 0.9
	glass.roughness = 0.12
	dark.albedo_color = Color("#26292d")
	dark.metallic = 0.4
	dark.roughness = 0.6

	var groups: Array = [[], [], [], []]
	var twin: bool = profile == "mig29"
	var slim: bool = profile == "mig21"
	var sweep: float = deg_to_rad(40.0) if slim else deg_to_rad(28.0)
	var fin_x: float = 0.95 if twin else 0.0
	var wing_len: float = 5.6 if slim else 4.6
	var nose_r: float = 0.10 if slim else 0.18
	var waist: float = 0.72 if slim else (1.05 if twin else 1.0)
	var z_axis := Vector3(-PI / 2, 0, 0)

	# Fuselage: tapered cylinder along Z (rotate_x(-PI/2) maps +Y -> -Z = nose).
	_add(groups[BODY], CylinderMesh.new(), _xform(z_axis, Vector3(0, 0, 0.5), Vector3.ONE),
		{"top_radius": nose_r, "bottom_radius": waist, "height": 13.0})
	# Canopy.
	_add(groups[GLASS], SphereMesh.new(), _xform(Vector3.ZERO, Vector3(0, 0.78, -2.1), Vector3(0.85, 0.72, 2.3)),
		{"radius": 0.55, "height": 1.1})
	# Radome.
	_add(groups[DARK], CylinderMesh.new(), _xform(z_axis, Vector3(0, -0.15, -6.6), Vector3.ONE),
		{"top_radius": 0.04, "bottom_radius": 0.42, "height": 1.8})
	# Wings, intakes and stabilators.
	for side in [-1.0, 1.0]:
		_add(groups[BODY], BoxMesh.new(),
			_xform(Vector3(0, side * sweep, 0), Vector3(side * wing_len * 0.42, -0.1, 1.3), Vector3(wing_len, 0.14, 2.0)),
			{"size": Vector3.ONE})
		_add(groups[DARK], BoxMesh.new(),
			_xform(Vector3.ZERO, Vector3(side * 1.15, -0.42, 0.6), Vector3(1.0, 0.95, 3.2)),
			{"size": Vector3.ONE})
		_add(groups[BODY], BoxMesh.new(),
			_xform(Vector3(0, side * sweep * 0.6, 0), Vector3(side * 1.15, 0.0, 6.1), Vector3(2.1, 0.1, 1.2)),
			{"size": Vector3.ONE})
	# Vertical tails (accent painted).
	if twin:
		for side in [-1.0, 1.0]:
			_add(groups[ACCENT], BoxMesh.new(),
				_xform(Vector3(0.38, 0, 0), Vector3(side * fin_x, 1.15, 5.6), Vector3(0.12, 2.3, 1.7)),
				{"size": Vector3.ONE})
	else:
		_add(groups[ACCENT], BoxMesh.new(),
			_xform(Vector3(0.38, 0, 0), Vector3(0, 1.25, 5.7), Vector3(0.14, 2.5, 1.9)),
			{"size": Vector3.ONE})
	# Engine nozzle(s).
	if twin:
		for side in [-1.0, 1.0]:
			_add(groups[DARK], CylinderMesh.new(), _xform(z_axis, Vector3(side * 0.55, 0, 6.9), Vector3.ONE),
				{"top_radius": 0.5, "bottom_radius": 0.42, "height": 1.4})
	else:
		_add(groups[DARK], CylinderMesh.new(), _xform(z_axis, Vector3(0, 0, 7.0), Vector3.ONE),
			{"top_radius": 0.52, "bottom_radius": 0.44, "height": 1.4})

	var out := ArrayMesh.new()
	var mats: Array = [body, glass, dark, accent_material(model_name)]
	for i in 4:
		if groups[i].is_empty():
			continue
		var st := SurfaceTool.new()
		st.begin(Mesh.PRIMITIVE_TRIANGLES)
		for part in groups[i]:
			st.append_from(part[0], 0, part[1])
		st.commit(out)
		out.surface_set_material(out.get_surface_count() - 1, mats[i])
	return out


static func _add(group: Array, mesh: Mesh, xf: Transform3D, props: Dictionary) -> void:
	for k in props:
		mesh.set(k, props[k])
	group.append([mesh, xf])


static func _xform(rot: Vector3, pos: Vector3, scl: Vector3) -> Transform3D:
	return Transform3D(Basis.from_euler(rot).scaled(scl), pos)
