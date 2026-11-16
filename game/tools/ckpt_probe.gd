## Why does SCData.model("OBJECTS/F16-CKPT.IFF") fail? (GDScript has no try/except)
extends SceneTree

func _initialize() -> void:
	await process_frame
	var sc = root.get_node("SCData")
	if not sc.is_mounted():
		sc.auto_mount()
	print("has: ", sc.has("OBJECTS/F16-CKPT.IFF"))
	var buf: PackedByteArray = sc.read("OBJECTS/F16-CKPT.IFF")
	print("read size: ", buf.size(), " head: ", buf.slice(0, 8).get_string_from_ascii())
	var RealSpace = load("res://scripts/formats/realspace_model.gd")
	var m = RealSpace.load_from(buf, "F16-CKPT")
	print("model: ", m)
	if m != null:
		var mesh = m.build_mesh(PackedColorArray(), 0, true)
		print("mesh ok: ", mesh != null, " surfaces=", (mesh.get_surface_count() if mesh != null else 0))
	quit(0)
