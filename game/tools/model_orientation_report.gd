## QA tool: print every GLB drop-in's raw bounding-box size (X/Y/Z), the scale
## factor the loader would apply, and the automatically suggested yaw correction
## (degrees). Use this to fill ExternalModels.ORIENT_YAW_DEG.
## Run: Godot --headless --path game --script res://tools/model_orientation_report.gd
extends SceneTree

const ExternalModels = preload("res://scripts/game/external_models.gd")
const BASER := "res://models/"


func _init() -> void:
	var dir := DirAccess.open(BASER)
	if dir == null:
		print("models dir NOT FOUND")
		quit()
		return
	var files := []
	for f in dir.get_files():
		if f.to_upper().ends_with(".GLB"):
			files.append(f)
	files.sort()
	print("MODEL ORIENTATION REPORT")
	print("%-26s %8s %8s %8s  %6s %6s  %s" % ["file", "X", "Y", "Z", "scale", "yaw°", "note"])
	for f in files:
		var size := _raw_size(BASER + f)
		if size == Vector3.ZERO:
			print("%-26s  (load failed)" % f)
			continue
		var maxd: float = maxf(size.x, maxf(size.y, size.z))
		var target: float = ExternalModels._target_size(f)
		var factor := 1.0
		if maxd > 0.001 and (maxd > 40.0 or maxd < 4.0):
			factor = target / maxd
		var yaw: float = rad_to_deg(ExternalModels._orientation_yaw(f, size))
		var note := ""
		if absf(yaw - 90.0) < 1.0:
			note = "rotated +90 (nose +X -> -Z)"
		elif absf(yaw + 90.0) < 1.0:
			note = "rotated -90 (nose -X -> -Z)"
		elif absf(yaw - 180.0) < 1.0:
			note = "flipped 180 (nose +Z -> -Z)"
		elif size.z >= size.x * 0.87:
			note = "fuselage along Z (ok)"
		else:
			note = "override keeps as-is (wide model)"
		if note.begins_with("fuselage") and absf(size.x - size.z) < size.z * 0.15:
			note = "span~length (ambiguous - check visually)"
		print("%-26s %8.2f %8.2f %8.2f  %6.3f %6.1f  %s" % [f, size.x, size.y, size.z, factor, yaw, note])
	quit()


func _raw_size(path: String) -> Vector3:
	var doc := GLTFDocument.new()
	var st := GLTFState.new()
	if doc.append_from_file(path, st) != OK:
		return Vector3.ZERO
	var root := doc.generate_scene(st)
	if root == null:
		return Vector3.ZERO
	var raw := ArrayMesh.new()
	_measure(root, Transform3D.IDENTITY, raw)
	var aabb := raw.get_aabb()
	root.free()
	return aabb.size


func _measure(node: Node, xf: Transform3D, out: ArrayMesh) -> void:
	if node is MeshInstance3D and node.mesh != null:
		var full: Transform3D = xf * node.transform
		for s in node.mesh.get_surface_count():
			var stt := SurfaceTool.new()
			stt.begin(node.mesh.surface_get_primitive_type(s))
			stt.append_from(node.mesh, s, full)
			stt.commit(out)
	for c in node.get_children():
		_measure(c, xf * node.transform, out)
