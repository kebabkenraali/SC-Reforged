## Hex-dump the raw PART records of MISN-1A around offset 26..40 to find the
## true side byte (the C-130 is an escort target in the story but reads as
## side=1 today).
extends SceneTree

func _find_tags(buf: PackedByteArray, tag: String) -> Array:
	var tagb := tag.to_ascii_buffer()
	var out := []
	var start := 0
	while start < buf.size() - 4:
		var ok := true
		for i in 4:
			if buf[start + i] != tagb[i]:
				ok = false
				break
		if ok:
			out.append(start)
		start += 1
	return out

func _initialize() -> void:
	await process_frame
	var sc = root.get_node("SCData")
	if not sc.is_mounted():
		sc.auto_mount()
	var buf: PackedByteArray = sc.read("MISSIONS/MISN-1A.IFF")
	var tags := _find_tags(buf, "PART")
	for t in min(tags.size(), 9):
		var off: int = tags[t] + 8
		var hexline := ""
		for b in range(0, 56):
			hexline += "%02x " % buf[off + b]
		print("PART@%-8d %s" % [off, hexline])
	quit(0)
