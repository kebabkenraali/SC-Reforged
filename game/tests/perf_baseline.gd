## Plan item 9: performance baseline before adding more content. Measures the
## cost of indexing the player's original install and listing all missions.
extends SceneTree


func _initialize() -> void:
	var sc = root.get_node("SCData")
	var t0 := Time.get_ticks_msec()
	sc.auto_mount()
	var mount_ms := Time.get_ticks_msec() - t0
	var files_count: int = sc.files.size()
	var t1 := Time.get_ticks_msec()
	var ms: Array = sc.missions()
	var list_ms := Time.get_ticks_msec() - t1
	var t2 := Time.get_ticks_msec()
	for m in ms:
		sc.mission(m.file)
	var parse_ms := Time.get_ticks_msec() - t2
	var gf_ms := -1
	var t3 := Time.get_ticks_msec()
	var Art = load("res://scripts/core/art.gd")
	Art.gameflow()
	gf_ms = Time.get_ticks_msec() - t3
	print("PERF mount_ms=%d files=%d missions=%d list_ms=%d parse_all_ms=%d gameflow_ms=%d" \
		% [mount_ms, files_count, ms.size(), list_ms, parse_ms, gf_ms])
	quit(0)
