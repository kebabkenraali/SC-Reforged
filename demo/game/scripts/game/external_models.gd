## Runtime loader for externally supplied aircraft models.
##
## Free (CC0 / CC-BY) 3D-drop-ins are supported: put a .glb in game/models/
## named after the aircraft, e.g. F-16, MIG29, and it is used instead of the
## original RealSpace mesh (settings: video -> modern_models can bypass this).
## See game/models/README.md for where the current drop-ins came from and
## their license terms.
extends RefCounted

const BASER := "res://models/"


## Maps original model names to the prefix of an external glb file.
## e.g. F-16DES.IFF / F-16GRAY.IFF -> "F-16*.glb".
static func _patterns(name: String) -> Array:
	var base: String = name.get_file().get_basename().to_upper()
	var out := []
	# exact first, then family names (strip descriptors like DES/GRAY/DEF)
	out.append(base)
	for suffix in ["DES", "GRAY", "DEF", "AVE", "AT", "GRA", "EW", "EARLY", "AD"]:
		if base.ends_with(suffix) and base.length() > suffix.length() + 1:
			out.append(base.substr(0, base.length() - suffix.length()))
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
				return _load_glb_mesh(f)
	return null


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
## ArrayMesh (vertices baked into the root node's local space).
static func _load_glb_mesh(path: String) -> Mesh:
	var doc := GLTFDocument.new()
	var state := GLTFState.new()
	if doc.append_from_file(path, state) != OK:
		push_warning("External model failed to load: " + path)
		return null
	var root := doc.generate_scene(state)
	if root == null:
		return null
	var out := ArrayMesh.new()
	_collect(root, Transform3D.IDENTITY, out)
	root.free()
	return out


static func _collect(node: Node, xf: Transform3D, out: ArrayMesh) -> void:
	if node is MeshInstance3D and node.mesh != null:
		var full: Transform3D = xf * node.transform
		for s in node.mesh.get_surface_count():
			var arrays: Array = node.mesh.surface_get_arrays(s)
			var verts: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
			var norms: PackedVector3Array = arrays[Mesh.ARRAY_NORMAL]
			for i in verts.size():
				verts[i] = full * verts[i]
			if norms.size() == verts.size():
				var b := full.basis.inverse().transposed()
				for i in norms.size():
					norms[i] = b * norms[i]
			arrays[Mesh.ARRAY_VERTEX] = verts
			arrays[Mesh.ARRAY_NORMAL] = norms
			out.add_surface_from_arrays(node.mesh.surface_get_primitive_type(s), arrays)
			var mat = node.mesh.surface_get_material(s)
			if mat != null:
				out.surface_set_material(out.get_surface_count() - 1, mat)
			arrays.clear()
	for c in node.get_children():
		_collect(c, xf * node.transform, out)
