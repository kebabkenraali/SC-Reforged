## List the IFF chunk structure of the cockpit models to see why the
## RealSpace loader rejects them.
extends SceneTree

func _initialize() -> void:
	await process_frame
	var sc = root.get_node("SCData")
	if not sc.is_mounted():
		sc.auto_mount()
	var Iff = load("res://scripts/formats/iff.gd")
	for name in ["OBJECTS/F16-CKPT.IFF", "OBJECTS/F22-CKPT.IFF", "OBJECTS/F-16DES.IFF"]:
		var buf: PackedByteArray = sc.read(name)
		print("== ", name, " size=", buf.size())
		var nodes = Iff.parse(buf)
		_dump(nodes, 0)
	quit(0)

func _dump(nodes: Array, depth: int) -> void:
	for n in nodes:
		print("%s%s size=%d off=%d" % ["  ".repeat(depth), n.get("id", "?"), n.get("size", 0), n.get("off", -1)])
		if n.has("children"):
			_dump(n.children, depth + 1)
