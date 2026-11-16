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
	var Art = load("res://scripts/core/art.gd")
	var names := []
	var story_ids := {1: true} # MID1 is played directly when a new campaign starts.
	var transport_ids := {}
	var gf = Art.gameflow()
	for stage in gf.stages:
		_collect_cutscene_ids(story_ids, transport_ids, stage.effects)
		for sprites in stage.scenes.values():
			for sprite in sprites:
				_collect_cutscene_ids(story_ids, transport_ids, sprite.effects)
	var unresolved_transports := []
	for n in transport_ids:
		if not VM.has_timeline("trans%d" % n):
			unresolved_transports.append(n)
	unresolved_transports.sort()
	if not unresolved_transports.is_empty():
		print("CUTSCENE_AUDIT: effect-12 references without a matching timeline; ",
			"meaning/mapping unresolved: ", unresolved_transports)
	var sorted_story_ids: Array = story_ids.keys()
	sorted_story_ids.sort()
	for n in sorted_story_ids:
		names.append("mid%d" % n)
	# Keep the recorded but currently unreferenced MID33 covered as well.
	if not names.has("mid33"):
		names.append("mid33")
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
		if f == null:
			_check("%s timeline is readable" % name, false)
			v.free()
			continue
		var data = JSON.parse_string(f.get_as_text())
		var valid_ops := false
		if data is Dictionary:
			var parsed_ops = data.get("ops", [])
			valid_ops = parsed_ops is Array and not parsed_ops.is_empty()
		_check("%s timeline has ops" % name, valid_ops)
		if not valid_ops:
			v.free()
			continue
		var ops: Array = data["ops"]
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


func _collect_cutscene_ids(story_ids: Dictionary, transport_ids: Dictionary, effects: Array) -> void:
	for effect in effects:
		match int(effect[0]):
			0x02:
				story_ids[int(effect[1])] = true
			0x12:
				transport_ids[int(effect[1])] = true


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
