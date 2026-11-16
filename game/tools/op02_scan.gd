## Where do the 0x02 opcodes appear in every mission, relative to block ends?
extends SceneTree

func _initialize() -> void:
	await process_frame
	var sc = root.get_node("SCData")
	if not sc.is_mounted():
		sc.auto_mount()
	for mf in sc.list("MISSIONS/"):
		if not mf.ends_with(".IFF"):
			continue
		var m = sc.mission(mf)
		if m == null:
			continue
		for b in m.blocks.size():
			var code: Array = m.block(b)
			for i in code.size():
				if code[i][0] == 0x02:
					var ctx := []
					for k in range(maxi(i - 3, 0), mini(i + 2, code.size())):
						ctx.append("%02x %02x" % [code[k][0], code[k][1]])
					print("%s block %d @%d (len %d): %s" % [mf.get_file(), b, i, code.size(), " ".join(ctx)])
	quit(0)
