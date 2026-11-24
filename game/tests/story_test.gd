## Story data: gameflow / options / conversations parse and render.
## Run: Godot --headless --path game --script res://tests/story_test.gd -- <outdir>
extends SceneTree

var failures := 0


func _initialize() -> void:
	await process_frame
	var sc = root.get_node("SCData")
	if not sc.is_mounted():
		sc.auto_mount()
	var Art = load("res://scripts/core/art.gd")
	var Conv = load("res://scripts/formats/sc_conversation.gd")
	var Pak = load("res://scripts/formats/pak_archive.gd")
	var Shape = load("res://scripts/formats/sc_shape.gd")
	var out: String = OS.get_cmdline_user_args()[0] if OS.get_cmdline_user_args().size() > 0 else ""

	var gf = Art.gameflow()
	_check("49 campaign stages", gf.stages.size() == 49, str(gf.stages.size()))
	_check("13 base screens", gf.screens.size() == 13, str(gf.screens.keys()))
	_check("conversation backgrounds", gf.backs.has("ha1_cu") and gf.backs.has("han_int"), str(gf.backs.size()))
	_check("faces", gf.faces.get("miguel", -1) == 0x36, str(gf.faces.get("miguel", -1)))

	# Render the bar screen (id 6) like the base screen does.
	var s: Dictionary = gf.screens[6]
	var pal = Art.palette("opt", s.back_pals + [s.fore_pal])
	var canvas = Art.new_canvas()
	for shp in s.back_shapes:
		var fr: Array = Art.frames("opt", shp)
		if not fr.is_empty():
			Art.blit(canvas, fr[0], Vector2i.ZERO)
	var covered := 0
	for m in canvas.mask:
		covered += m
	_check("bar background covers the screen", covered > 60000, str(covered))
	if out != "":
		Art.canvas_image(canvas, pal).save_png(out + "/story_bar.png")

	# Conversations
	var conv: Array = Pak.entries(sc.read("GAMEFLOW/CONV.PAK"))
	var steps: Array = Conv.parse(Shape.unpack(conv[12]))
	_check("conv 12 first line", steps[0].op == 3 and steps[0].text.begins_with("So how are our planes"), str(steps[0]))
	var parsed := 0
	var clean := 0
	for e in conv:
		if e.size() < 8:
			continue
		parsed += 1
		var st: Array = Conv.parse(Shape.unpack(e))
		if not st.is_empty() and st[-1].op in [0, 1, 2, 3, 4, 0x0a, 0x0b, 0x0c, 0x0e, 0x0f]:
			clean += 1
	_check("all conversations parse to the end", clean == parsed, "%d / %d" % [clean, parsed])
	var voc: PackedByteArray = sc.read("F:2AI431.VOC")
	_check("speech file for conv 12 line 1", voc.size() > 1000, str(voc.size()))

	# Close-up: background layers + speaker face (conv 12, Miguel's first line).
	var line: Dictionary = steps[1]
	var cu = _closeup(Art, gf, line)
	_check("close-up renders", cu != null)
	if out != "" and cu != null:
		cu.save_png(out + "/story_closeup.png")
		_closeup(Art, gf, steps[0]).save_png(out + "/story_closeup_air.png")

	print("story_test failures=%d" % failures)
	quit(failures)


func _check(name: String, ok: bool, detail := "") -> void:
	print("%s %s %s" % ["PASS" if ok else "FAIL", name, detail])
	if not ok:
		failures += 1


func _closeup(Art, gf, line: Dictionary) -> Image:
	var canvas = Art.new_canvas()
	var pals := []
	for layer in gf.backs.get(line.bg, []):
		var arch: String = "opt" if layer.archive == 1 else "conv"
		var fr: Array = Art.frames(arch, layer.shape)
		if not fr.is_empty():
			Art.blit(canvas, fr[0], Vector2i(0, layer.y))
		pals.append(layer.palette)
	var face: int = gf.faces.get(line.name, -1)
	var ffr: Array = Art.frames("conv", face)
	print("face %s idx %d frames %d mood %d" % [line.name, face, ffr.size(), line.mood])
	if not ffr.is_empty():
		Art.blit(canvas, ffr[0], line.at)
	var arch0: String = "opt" if not gf.backs.get(line.bg, []).is_empty() and gf.backs[line.bg][0].archive == 1 else "conv"
	var pal = Art.palette(arch0, pals)
	pal = Art.palette("conv", []) if pals.is_empty() else pal
	var e = Art._entries(Art.archives()["conv"][1])
	if gf.face_palette >= 0:
		pal = load("res://scripts/formats/sc_shape.gd").apply_palette(pal, e[gf.face_palette])
	return Art.canvas_image(canvas, pal)
