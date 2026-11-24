## Deep audio audit: every scripted mission radio line and every recorded
## cutscene voice op must decode to a real, non-silent AudioStream.
extends SceneTree


func _initialize() -> void:
	await process_frame
	var sc = root.get_node("SCData")
	if not sc.is_mounted():
		sc.auto_mount()
	var failures := 0
	var radio_checked := 0
	var radio_silent := 0
	var cut_checked := 0
	var cut_silent := 0

	# --- mission scripted radio voices --------------------------------------
	for entry in sc.missions():
		var m = sc.mission(entry.file)
		if m == null:
			continue
		var seen := {}
		for p in m.parts:
			for b in p.slots:
				if b < 0 or b >= m.blocks.size():
					continue
				for ins in m.block(b):
					if ins[0] != 0xab:
						continue
					var caster: String = m.cast[p.id] if p.id >= 0 and p.id < m.cast.size() else ""
					var key := "%s:%d" % [caster, ins[1]]
					if seen.has(key):
						continue
					seen[key] = true
					radio_checked += 1
					# The original SPEECH.PAK bank for PLAYER is entirely empty:
					# the player's mission lines are text-only by design.
					if caster.to_lower() == "player":
						continue
					# Two original files reference text ids that do not exist;
					# those lines are skipped by the game, so no voice is expected.
					if not (sc.radio(caster).msgs.has(ins[1])):
						continue
					# STRIBAS2 id 13 has text but its SPEECH.PAK entry is empty
					# in the original Tactical Operations data.
					if caster.to_lower() == "stribas2" and ins[1] == 13:
						continue
					var s: AudioStream = sc.radio_voice(caster, ins[1])
					if s == null or s.get_length() <= 0.0:
						radio_silent += 1
						if radio_silent <= 12:
							print("SILENT radio %s cast='%s' id=%d" % [entry.file, caster, ins[1]])

	# --- cutscene voice ops -------------------------------------------------
	var VM = load("res://scripts/ui/cutscene_vm.gd")
	var files := []
	var da := DirAccess.open("res://data/cutscenes")
	if da != null:
		for f in da.get_files():
			if f.ends_with(".json"):
				files.append(f.trim_suffix(".json"))
	files.sort()
	for name in files:
		var f := FileAccess.open("res://data/cutscenes/%s.json" % name, FileAccess.READ)
		if f == null:
			continue
		var data = JSON.parse_string(f.get_as_text())
		if not (data is Dictionary) or not (data.get("ops") is Array):
			continue
		var v = VM.new()
		root.add_child(v)
		for op in data.ops:
			if op[1] != "voice":
				continue
			cut_checked += 1
			var s: AudioStream = v._voice_stream(op[2], op[3])
			if s == null or s.get_length() <= 0.0:
				cut_silent += 1
				if cut_silent <= 12:
					print("SILENT cutscene %s archive=%s entry=%s" % [name, op[2], str(op[3])])
		v.free()

	failures = radio_silent + cut_silent
	print("radio voices checked=%d silent=%d" % [radio_checked, radio_silent])
	print("cutscene voices checked=%d silent=%d" % [cut_checked, cut_silent])
	print("voice_audit failures=", failures)
	quit(failures)
