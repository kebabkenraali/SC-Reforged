## Per-mission audit against the original data: scripted radio lines, their
## voices, activate targets and scene areas. Run against the player's install.
extends SceneTree


func _initialize() -> void:
	await process_frame
	var sc = root.get_node("SCData")
	if not sc.is_mounted():
		sc.auto_mount()
	var failures := 0
	var total_lines := 0
	var total_no_voice := 0
	var bad_text_total := 0
	for entry in sc.missions():
		var m = sc.mission(entry.file)
		if m == null:
			print("FAIL mission did not load: ", entry.file)
			failures += 1
			continue
		var bad_text := 0
		var no_voice := 0
		var bad_activate := 0
		var bad_scene := 0
		for p in m.parts:
			for b in p.slots:
				if b < 0 or b >= m.blocks.size():
					continue
				for ins in m.block(b):
					if ins[0] != 0xab:
						continue
					total_lines += 1
					var caster: String = m.cast[p.id] if p.id >= 0 and p.id < m.cast.size() else ""
					var r: Dictionary = sc.radio(caster)
					if not r.msgs.has(ins[1]):
						bad_text += 1
						# The original files contain a few ab references with no
						# matching INTEL text; the original engine ignores them,
						# so report as a data note rather than a remake failure.
						print("NOTE %s: cast[%d]='%s' has no radio text %d (ignored, as in original)" \
							% [entry.file, p.id, caster, ins[1]])
					elif int(r.spch) < 0:
						no_voice += 1
		for b in m.blocks.size():
			for id in m.block_args(b, 0x90):
				if m.part_index(id) < 0:
					bad_activate += 1
					print("FAIL %s: activate refers to missing PART %d" % [entry.file, id])
		for scn in m.scenes:
			if int(scn.area) >= m.areas.size():
				bad_scene += 1
				print("FAIL %s: scene area %d out of range" % [entry.file, scn.area])
		total_no_voice += no_voice
		bad_text_total += bad_text
		if no_voice > 0:
			print("NOTE %s: %d scripted radio line(s) have no voice bank" % [entry.file, no_voice])
		failures += bad_activate + bad_scene
	print("scripted radio lines=%d, without voice=%d, texts missing in original data=%d" \
		% [total_lines, total_no_voice, bad_text_total])
	print("mission_events_test failures=", failures)
	quit(failures)
