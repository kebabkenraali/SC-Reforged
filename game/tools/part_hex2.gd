## Entry-level probe: which byte in the PART record says enemy/friend? Print
## bytes o+26..o+48 for each part of MISN-1A via the same offsets as the parser.
extends SceneTree

func _initialize() -> void:
	await process_frame
	var sc = root.get_node("SCData")
	if not sc.is_mounted():
		sc.auto_mount()
	var raw: PackedByteArray = sc.read("MISSIONS/MISN-1A.IFF")
	var m = sc.mission("MISSIONS/MISN-1A.IFF")
	# Find the real PART offsets: replicate Iff.find on the parsed container via a
	# generic search: look for "C130des" and "MIG21" strings and dump around.
	for tag in ["C130des", "MIG21", "F-16des"]:
		var search: PackedByteArray = tag.to_ascii_buffer()
		var at := 0
		var hits := 0
		while hits < 4 and at < raw.size() - 8:
			var idx := raw.find(tag.unicode_at(0), at)   # approximate: find first byte
			if idx == -1:
				break
			var ok := true
			for i in tag.length():
				if idx + i >= raw.size() or raw[idx + i] != search[i]:
					ok = false
					break
			at = idx + 1
			if not ok:
				continue
			# part records are 62-byte aligned; the model string starts at o+2
			var o := idx - 2
			var hexline := ""
			for b in range(0, 60):
				hexline += "%02x" % raw[o + b]
			print("%-8s o=%6d: %s" % [tag, o, hexline])
			hits += 1
	quit(0)
