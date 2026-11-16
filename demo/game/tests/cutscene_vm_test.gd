## Replays every recorded cut-scene timeline against the original art.
## Run: Godot --headless --path game --script res://tests/cutscene_vm_test.gd
extends SceneTree

var failures := 0


func _initialize() -> void:
	await process_frame
	var sc = root.get_node("SCData")
	if not sc.is_mounted():
		sc.auto_mount()
	var VM = load("res://scripts/ui/cutscene_vm.gd")
	var names := []
	for n in [1, 2, 3, 5, 12, 14, 15, 16, 17, 20, 33, 34, 36]:
		names.append("mid%d" % n)
	for n in 18:
		names.append("est%d" % n)    # establishing shots (gameflow effect 08)
	for n in 9:
		names.append("trans%d" % n)  # transport map animations (gameflow effect 12)
	for name in names:
		_check("%s timeline exists" % name, VM.has_timeline(name))
		if not VM.has_timeline(name):
			continue
		var v = VM.new()
		root.add_child(v)
		var f := FileAccess.open("res://data/cutscenes/%s.json" % name, FileAccess.READ)
		var ops: Array = JSON.parse_string(f.get_as_text()).ops
		var lit := 0
		var missing := {}
		var voices := 0
		var subtitles := 0
		var count := 0
		for op in ops:
			v._run(op)
			count += 1
			if count % 40 == 0 and lit == 0:
				lit = _lit(v)
			if op[1] in ["draw", "sdraw"] and String(op[3]) != "MOUSE.SHP" and v._frames(op[3], op[4]).is_empty():
				missing[String(op[3]) + "#" + str(op[4])] = true
			if op[1] == "voice":
				voices += 1
			if op[1] == "subtitle" and String(op[2]) != "":
				subtitles += 1
		_check("%s shapes all found" % name, missing.is_empty(), str(missing.keys().slice(0, 3)))
		if name in ["mid2", "mid12", "mid36"]:
			_check("%s has subtitles" % name, subtitles > 0, str(subtitles))
		_check("%s draws to the screen (%d ops, %d voices, %d subtitles, %.0f s)" % [name, ops.size(), voices, subtitles, float(ops[-1][0]) / 1000.0], lit > 0, str(lit))
		v.free()
	print("cutscene_vm_test failures=%d" % failures)
	quit(failures)


func _lit(v) -> int:
	var img: Image = v._buffers.get(v._screen_key)
	var n := 0
	if img:
		for y in range(0, 200, 8):
			for x in range(0, 320, 8):
				if img.get_pixel(x, y).r > 0.0:
					n += 1
	return n


func _check(name: String, ok: bool, detail := "") -> void:
	print("%s %s %s" % ["PASS" if ok else "FAIL", name, detail])
	if not ok:
		failures += 1
