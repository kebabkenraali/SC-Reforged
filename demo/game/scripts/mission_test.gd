## Headless check of mission and ground object parsing against the original data.
extends SceneTree


func _initialize() -> void:
	await process_frame
	var sc = root.get_node("SCData")
	if not sc.is_mounted():
		sc.auto_mount()
	var failures := 0
	var ms: Array = sc.missions()
	print("missions: ", ms.size())
	for m in ms.slice(0, 6):
		print("  ", m.file, " | ", m.name, " | ", m.area)
	if ms.size() < 10:
		failures += 1

	var m = sc.mission("MISSIONS/MISN-10A.IFF")
	var p = m.player_part()
	var t = sc.terrain(m.area)
	var ground: float = t.height_at(p.pos.x, p.pos.z)
	print("MISN-10A area=%s player=%s pos=%s ground=%.1f heading=%d" % [m.area, p.model, p.pos, ground, p.heading])
	print("  areas: ", m.areas.map(func(a): return a.name))
	print("  msgs: ", m.messages)
	if absf(p.pos.y - ground) > 15.0:
		failures += 1

	var bad := 0
	for o in t.objects:
		if absf(o.pos.y - t.height_at(o.pos.x, o.pos.z)) > 30.0:
			bad += 1
	print("terrain objects=%d off-ground=%d first=%s" % [t.objects.size(), bad, t.objects[0] if t.objects.size() else null])
	if t.objects.is_empty() or bad > t.objects.size() / 5:
		failures += 1
	var missing := {}
	for o in t.objects:
		if not sc.has("OBJECTS/%s.IFF" % o.model):
			missing[o.model] = true
	print("missing models: ", missing.keys())
	print("mission_test failures=%d" % failures)
	quit(failures)
