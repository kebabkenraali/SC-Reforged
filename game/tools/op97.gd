## 97-query evidence: prints the parts (id -> model) of the missions that use
## opcode 97, plus the full block around each usage.
extends SceneTree

func _initialize() -> void:
	await process_frame
	var sc = root.get_node("SCData")
	if not sc.is_mounted():
		sc.auto_mount()
	for mf in ["MISSIONS/MISN-1A.IFF", "MISSIONS/MISN-1C.IFF"]:
		var m = sc.mission(mf)
		print("== ", mf.get_file())
		for i in m.parts.size():
			var p: Dictionary = m.parts[i]
			print("  part %d id=%d %s side=%d slots=%s" % [i, p.id, p.model, p.side, p.slots])
		for b in m.blocks.size():
			var code: Array = m.block(b)
			for i in code.size():
				if code[i][0] == 0x97 or code[i][0] == 0x95:
					var ctx: Array = []
					for k in range(maxi(i - 4, 0), mini(i + 6, code.size())):
						var o: Array = code[k]
						ctx.append("%02x %02x" % [o[0], o[1] if o.size() > 1 else 0])
					print("  blk%d @%d: %s" % [b, i, " ".join(ctx)])
	quit(0)
