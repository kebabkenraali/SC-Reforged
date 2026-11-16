## Prints every usage of the still-open PROG opcodes (21/24/25/2f/97) with the
## owning part and surrounding instructions, across all missions. The goal:
## infer each opcode's semantics from the data (what value it can push and
## what it is compared against).
extends SceneTree

const OPS := {0x21: "21", 0x24: "24", 0x25: "25", 0x2f: "2f", 0x97: "97"}

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
				var op: int = code[i][0]
				if not OPS.has(op):
					continue
				# who owns this block
				var owner := ""
				for p in m.parts.size():
					if mission_owner_block(m, p, b):
						var part: Dictionary = m.parts[p]
						owner = "%s(id%d side%d)" % [part.model, part.id, part.side]
				var ctx: Array = []
				for k in range(maxi(i - 3, 0), mini(i + 5, code.size())):
					var mark := ">>" if k == i else "  "
					var o: Array = code[k]
					ctx.append("%s%02x %02x" % [mark, o[0], o[1] if o.size() > 1 else 0])
				print("%s blk%d @%d %s: %s" % [mf.get_file().get_basename(), b, i, owner, " ".join(ctx)])

func mission_owner_block(m, pi: int, b: int) -> bool:
	var part: Dictionary = m.parts[pi]
	for s in part.slots:
		if s == b:
			return true
	return false
