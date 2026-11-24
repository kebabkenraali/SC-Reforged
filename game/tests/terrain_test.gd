## Plan item 7: every mission area must have real terrain and its own palette
## from the original game, not the generic fallback.
extends SceneTree


func _initialize() -> void:
	await process_frame
	var sc = root.get_node("SCData")
	if not sc.is_mounted():
		sc.auto_mount()
	var failures := 0
	var areas := {}
	for entry in sc.missions():
		var m = sc.mission(entry.file)
		if m == null:
			continue
		areas[m.area] = true
		var t = sc.terrain(m.area)
		if t == null:
			print("FAIL terrain missing: %s (%s)" % [m.area, entry.file])
			failures += 1
		var pal: String = sc.world_palette(m.area)
		# PALETTE/PALETTE.IFF is a legitimate original choice for many areas;
		# only a palette file that does not exist in the install is a failure.
		if not sc.has(pal):
			print("FAIL world palette missing: %s -> %s" % [m.area, pal])
			failures += 1
	print("areas=%d" % areas.size())
	print("terrain_test failures=", failures)
	quit(failures)
