## Runtime loader for externally supplied aircraft models.
##
## Free (CC0 / CC-BY) 3D-drop-ins are supported: put a .glb in game/models/
## named after the aircraft, e.g. F-16, MIG29, and it is used instead of the
## original RealSpace mesh (settings: video -> modern_models can bypass this).
## See game/models/README.md for where the current drop-ins came from and
## their license terms.
extends RefCounted

const BASER := "res://models/"

## Per-model orientation override: yaw about +Y in DEGREES, keyed by an
## upper-case substring of the model name. Use this to fine-tune a drop-in the
## automatic heuristic gets wrong (wingspan longer than the fuselage, or the
## nose pointing backwards). The engine's forward axis is -Z.
##   0   = fuselage already along -Z (nose forward)
##   90  = model's nose points +X  -> rotate to -Z
##   -90 = model's nose points -X
##   180 = nose points +Z (backwards) -> flip
## Add an entry here (e.g. "C130": 0.0) when a specific model needs it.
const ORIENT_YAW_DEG := {
	# Transports have a wingspan longer than the fuselage, so the automatic
	# "wide = rotate" heuristic would turn them sideways: keep them as-is.
	"C130": 0.0,
}


## Maps original model names to the prefix of an external glb file.
## e.g. F-16DES.IFF / F-16GRAY.IFF -> "F-16DES.glb", "F16DES.glb" or "F16*.glb".
static func _patterns(name: String) -> Array:
	var base: String = name.get_file().get_basename().to_upper()
	var out := []
	# All spelling variants of a base name: as-is, dashes->underscores, and with
	# dashes/underscores removed entirely (the shipped glb files use e.g. F16DES).
	var variants := func(b: String) -> Array:
		var arr := [b]
		if "-" in b:
			arr.append(b.replace("-", "_"))
		var joined := b.replace("-", "").replace("_", "")
		if joined != b:
			arr.append(joined)
		return arr
	for v in variants.call(base):
		out.append(v)
	# Family names (strip descriptors like DES/GRAY/DEF), same spelling variants.
	for suffix in ["DES", "GRAY", "DEF", "AVE", "AT", "GRA", "EW", "EARLY", "AD"]:
		if base.ends_with(suffix) and base.length() > suffix.length() + 1:
			var stripped := base.substr(0, base.length() - suffix.length())
			for v in variants.call(stripped):
				out.append(v)
	return out


## Returns a merged ArrayMesh from a matching .glb under res://models/,
## or null when no drop-in exists.
static func override_mesh(model_name: String) -> Mesh:
	var files := _scan()
	if files.is_empty():
		return null
	for pat in _patterns(model_name):
		for f in files:
			var fname: String = f.get_file().to_upper()
			if fname.begins_with(pat) and fname.ends_with(".GLB"):
				return _load_glb_mesh(f, model_name)
	return null


## Target real-world size (metres, largest dimension) per aircraft class. Used
## only to fix drop-in models exported in the wrong units (e.g. the detailed
## F16DES.glb is ~114 m across, ~10x a real F-16).
static func _target_size(model_name: String) -> float:
	var n := model_name.to_upper()
	if "130" in n:
		return 30.0                                  # C-130 Hercules
	if "BISON" in n or "TU14" in n or "TU-14" in n:
		return 48.0
	if "747" in n or "L1011" in n or "L-1011" in n or "E3" in n or "AWACS" in n:
		return 48.0
	if "LEAR" in n:
		return 16.0
	return 16.0                                       # fighters: ~15-16 m


static func _scan() -> Array:
	var out := []
	var dir := DirAccess.open(BASER)
	if dir == null:
		return out
	for f in dir.get_files():
		if f.to_upper().ends_with(".GLB"):
			out.append(BASER + f)
	return out


## Loads a glTF binary file at runtime and merges all its meshes into one
## ArrayMesh (vertices baked into the root node's local space). The result is
## recentred on the origin and, when the source is in the wrong units (much
## larger/smaller than a real aircraft), rescaled to a sane size.
static func _load_glb_mesh(path: String, model_name := "") -> Mesh:
	var doc := GLTFDocument.new()
	var state := GLTFState.new()
	if doc.append_from_file(path, state) != OK:
		push_warning("External model failed to load: " + path)
		return null
	var root := doc.generate_scene(state)
	if root == null:
		return null
	# First pass: measure the raw bounds (bakes node transforms).
	var raw := ArrayMesh.new()
	_collect(root, Transform3D.IDENTITY, raw)
	var aabb := raw.get_aabb()
	var size := aabb.size
	var maxd := maxf(size.x, maxf(size.y, size.z))
	var factor := 1.0
	# Only correct clear outliers; leave already-sane drop-ins untouched.
	if maxd > 0.001 and (maxd > 40.0 or maxd < 4.0):
		factor = _target_size(model_name) / maxd
	# Second pass: scale (if needed), orient (nose to -Z) and recentre on origin.
	var yaw := _orientation_yaw(model_name, size)
	var rot := Basis(Vector3.UP, yaw).scaled(Vector3(factor, factor, factor))
	var center := aabb.get_center()
	var xf := Transform3D(rot, -(rot * center))
	var out := ArrayMesh.new()
	_collect(root, xf, out)
	root.free()
	return out


## Yaw (radians) that brings the model's nose to the engine's forward (-Z).
## An explicit ORIENT_YAW_DEG entry wins; otherwise the longest horizontal axis
## is aligned to Z (a wide model, x > z, is turned 90 degrees). The nose
## direction (+X vs -X) cannot be detected from geometry, so the default
## assumes +X -> -Z; add an override if a specific model is backwards.
static func _orientation_yaw(model_name: String, size: Vector3) -> float:
	var n := model_name.to_upper()
	for key in ORIENT_YAW_DEG:
		if n.contains(key.to_upper()):
			return deg_to_rad(ORIENT_YAW_DEG[key])
	if size.x > size.z * 1.15:
		return PI * 0.5
	return 0.0


static func _collect(node: Node, xf: Transform3D, out: ArrayMesh) -> void:
	if node is MeshInstance3D and node.mesh != null:
		var full: Transform3D = xf * node.transform
		for s in node.mesh.get_surface_count():
			# SurfaceTool handles arbitrary glTF surface formats (custom/UV2/etc.)
			# and bakes the transform into vertices and normals without the
			# "Invalid array format" errors of add_surface_from_arrays.
			var st := SurfaceTool.new()
			st.begin(node.mesh.surface_get_primitive_type(s))
			st.append_from(node.mesh, s, full)
			st.commit(out)
			var mat = node.mesh.surface_get_material(s)
			if mat != null:
				out.surface_set_material(out.get_surface_count() - 1, mat)
	for c in node.get_children():
		_collect(c, xf * node.transform, out)
