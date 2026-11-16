## Dump every block referencing a given part id (MISN-1A cargo) + the part slots.
extends SceneTree

func _initialize() -> void:
	await process_frame
	var sc = root.get_node("SCData")
	if not sc.is_mounted():
		sc.auto_mount()
	var m = sc.mission("MISSIONS/MISN-1A.IFF")
	for i in m.parts.size():
		var p: Dictionary = m.parts[i]
		print("part %d %s side=%d id=%d slots=%s" % [i, p.model, p.side, p.id, p.slots])
	print("--- blocks that mention id 2 (cargo) ---")
	for b in m.blocks.size():
		var ins: Array = m.block(b)
		for o in ins:
			if o.size() >= 2 and (o[1] == 2 or o[1] == 102 or (o[0] in [0x92, 0x93, 0x95, 0xaa, 0xa7, 0xa2] and o[1] == 2)):
				print("block %d: %s" % [b, str(o)])
	print("--- all blocks summary ---")
	for b in m.blocks.size():
		var ops := []
		for o in m.block(b):
			ops.append("%02x %02x" % [o[0], o[1] if o.size() > 1 else 0])
		print("block %d: %s" % [b, " ".join(ops)])
	quit(0)
