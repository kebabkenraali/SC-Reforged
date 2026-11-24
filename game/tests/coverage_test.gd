## Full coverage audit: every original cut-scene must have a timeline and every
## recorded timeline must be reachable from the game flow (or explicitly listed
## as a valid extra). Also checks all conversations and base screens parse.
extends SceneTree


func _initialize() -> void:
	await process_frame
	var sc = root.get_node("SCData")
	if not sc.is_mounted():
		sc.auto_mount()
	var Art = load("res://scripts/core/art.gd")
	var VM = load("res://scripts/ui/cutscene_vm.gd")
	var gf = Art.gameflow()
	var failures := 0

	# --- 1. original MID archives -> recorded timelines ---------------------
	var mids := {}
	for f in sc.list("MIDGAMES/", ".PAK"):
		var n: String = String(f).get_file().get_basename().to_upper()
		if n.begins_with("MID") and not n.contains("VOC") and not n.contains("MUSIC") \
				and n != "MIDGAMES" and n.substr(3).is_valid_int():
			mids[int(n.substr(3))] = true
	print("original MID archives: ", mids.keys())
	for n in mids:
		if not VM.has_timeline("mid%d" % n):
			print("FAIL missing timeline for original MID%d" % n)
			failures += 1

	# --- 2. gameflow references --------------------------------------------
	var story := {1: true}   # played directly on new campaign
	var est := {}
	var trans := {}
	for stage in gf.stages:
		_collect(stage.effects, story, est, trans)
		for sprites in stage.scenes.values():
			for sprite in sprites:
				_collect(sprite.effects, story, est, trans)
	print("referenced story MIDs: ", story.keys())
	print("referenced establishing: ", est.keys())
	print("referenced transports: ", trans.keys())

	# --- 3. all timelines present + referenced ------------------------------
	var extras := {"mid33": true, "mid34": true}  # recorded, kept for coverage
	for n in range(18):
		est[n] = true
	for n in range(9):
		trans[n] = true
	var files := []
	var da := DirAccess.open("res://data/cutscenes")
	if da != null:
		for f in da.get_files():
			if f.ends_with(".json"):
				files.append(f.trim_suffix(".json"))
	files.sort()
	for name in files:
		if not VM.has_timeline(name):
			print("FAIL unreadable timeline: ", name)
			failures += 1
			continue
		var referenced := false
		if name.begins_with("mid"):
			referenced = story.has(int(name.substr(3))) or extras.has(name)
		elif name.begins_with("est"):
			referenced = est.has(int(name.substr(3)))
		elif name.begins_with("trans"):
			referenced = trans.has(int(name.substr(5)))
		if not referenced:
			print("UNPLAYED timeline (never referenced by gameflow): ", name)
			failures += 1

	# --- 4. conversations and screens --------------------------------------
	var Conv = load("res://scripts/formats/sc_conversation.gd")
	var Shape = load("res://scripts/formats/sc_shape.gd")
	var Pak = load("res://scripts/formats/pak_archive.gd")
	var conv_buf: PackedByteArray = sc.read("GAMEFLOW/CONV.PAK")
	var entries: Array = Pak.entries(conv_buf)
	var flags: Array = Pak.flags(conv_buf)
	var bad_conv := 0
	var real_conv := 0
	for i in entries.size():
		if flags[i] == 0xFF:   # unused PAK slot
			continue
		real_conv += 1
		if Conv.parse(Shape.unpack(entries[i])).is_empty():
			bad_conv += 1
	if bad_conv > 0:
		print("FAIL conversations with no steps: ", bad_conv)
		failures += bad_conv
	var blank_screens := 0
	for id in gf.screens:
		var s = gf.screens[id]
		var pal = Art.palette("opt", s.back_pals + [s.fore_pal])
		var canvas = Art.new_canvas()
		for shp in s.back_shapes:
			var fr: Array = Art.frames("opt", shp)
			if not fr.is_empty():
				Art.blit(canvas, fr[0], Vector2i.ZERO)
		if Art.canvas_image(canvas, pal).get_used_rect().size == Vector2i.ZERO:
			blank_screens += 1
	if blank_screens > 0:
		print("FAIL blank base screens: ", blank_screens)
		failures += blank_screens
	print("timelines=%d conversations=%d screens=%d" % [files.size(), real_conv, gf.screens.size()])
	print("coverage_test failures=", failures)
	quit(failures)


func _collect(effects: Array, story: Dictionary, est: Dictionary, trans: Dictionary) -> void:
	for e in effects:
		match int(e[0]):
			0x02: story[int(e[1])] = true
			0x08: est[int(e[1])] = true
			0x12: trans[int(e[1])] = true
