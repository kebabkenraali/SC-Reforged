## Plays an original story cut-scene (MIDn) or establishing shot from its
## recorded display list.
##
## The staging of the cut-scenes is compiled into OPTTEST.EXE. tools/cutscenes
## runs that code in an emulator and records what it does - which shape frame
## is drawn where, surface copies, fills, palette changes, shading tables and
## speech - as res://data/cutscenes/midN.json. The art and speech themselves
## are read from the player's own copy of the game. Surfaces are kept as
## 8-bit indexed images and the screen is converted through the current VGA
## palette in a shader, so palette fades work like on the original.
## Esc / Start: skip.
extends Control

const Pak = preload("res://scripts/formats/pak_archive.gd")
const Shape = preload("res://scripts/formats/sc_shape.gd")
const Voc = preload("res://scripts/formats/voc.gd")

const DIR := "res://data/cutscenes/"
const W := 320
const H := 200

signal finished

var number := 1
var file := ""            # timeline name without .json; default "mid<number>"
var _ops: Array = []
var _next := 0
var _clock := 0.0
var _surfaces := {}       # name -> buffer key
var _clips := {}          # name -> Rect2i the original clips drawing to
var _buffers := {}        # "seg:base" -> Image (L8, 320 x 200)
var _screen_key := ""
var _tables := {}         # id -> PackedByteArray
var _shapes := {}         # "archive#entry" -> Array of decoded frames
var _archives := {}       # archive -> {entries, flags}
var _palette := Image.create(256, 1, false, Image.FORMAT_RGB8)
var _pal_tex: ImageTexture
var _screen_tex: ImageTexture
var _view: TextureRect
var _dirty := false
var _pal_dirty := false
var _voices: Array[AudioStreamPlayer] = []
var _skip := false
var _subtitle: Label
var _done := false


static func exists(n: int) -> bool:
	return has_timeline("mid%d" % n)


## Story cut-scenes are "midN", establishing shots (gameflow effect 08) "estN".
static func has_timeline(name: String) -> bool:
	return FileAccess.file_exists(DIR + name + ".json")


func _ready() -> void:
	set_process(false)
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_STOP
	var black := ColorRect.new()
	black.color = Color.BLACK
	black.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(black)
	var arc := AspectRatioContainer.new()
	arc.ratio = 4.0 / 3.0
	arc.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(arc)
	_view = TextureRect.new()
	_view.stretch_mode = TextureRect.STRETCH_SCALE
	_view.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	arc.add_child(_view)
	var mat := ShaderMaterial.new()
	mat.shader = Shader.new()
	mat.shader.code = """
shader_type canvas_item;
uniform sampler2D palette : filter_nearest;
void fragment() {
	float i = texture(TEXTURE, UV).r;
	COLOR = vec4(texture(palette, vec2((i * 255.0 + 0.5) / 256.0, 0.5)).rgb, 1.0);
}
"""
	_view.material = mat
	_pal_tex = ImageTexture.create_from_image(_palette)
	mat.set_shader_parameter("palette", _pal_tex)
	# Lines as the original showed them without speech (MIDGAMES.IFF), timed to
	# the speech by tools/cutscenes/subtitles.py.
	_subtitle = Label.new()
	_subtitle.anchor_left = 0.08
	_subtitle.anchor_right = 0.92
	_subtitle.anchor_top = 1.0
	_subtitle.anchor_bottom = 1.0
	_subtitle.offset_top = -130
	_subtitle.offset_bottom = -24
	_subtitle.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_subtitle.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_subtitle.vertical_alignment = VERTICAL_ALIGNMENT_BOTTOM
	_subtitle.add_theme_font_size_override("font_size", 26)
	_subtitle.add_theme_color_override("font_outline_color", Color.BLACK)
	_subtitle.add_theme_constant_override("outline_size", 8)
	_subtitle.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_subtitle.visible = Settings.get_value("audio", "subtitles")
	add_child(_subtitle)
	for i in 4:
		var p := AudioStreamPlayer.new()
		p.bus = "Master"
		add_child(p)
		_voices.append(p)


func play() -> void:
	print("CUTSCENE_VM: play() number=%d" % number)
	if file == "":
		file = "mid%d" % number
	print("CUTSCENE_VM: loading %s" % (DIR + file + ".json"))
	var f := FileAccess.open(DIR + file + ".json", FileAccess.READ)
	if not f:
		print("CUTSCENE_VM: failed to open file")
		finished.emit()
		return
	var text = f.get_as_text()
	print("CUTSCENE_VM: read %d chars" % text.length())
	var result = JSON.parse_string(text)
	if result is Dictionary:
		print("CUTSCENE_VM: parsed as Dictionary, keys: %s" % [result.keys()])
		if result.has("ops"):
			# `Array` does not expose a `get_type()` method, use `typeof()` instead
			print("CUTSCENE_VM: ops type: %s, size: %d" % [typeof(result.ops), result.ops.size()])
			_ops = result.ops
		else:
			print("CUTSCENE_VM: no 'ops' key!")
			finished.emit()
			return
	else:
		print("CUTSCENE_VM: parsed as %s" % result.get_type())
		finished.emit()
		return
	set_process(true)
	await finished
	print("CUTSCENE_VM: finished")


func _process(dt: float) -> void:
	if _done:
		return
	_clock += dt * 1000.0
	while _next < _ops.size() and float(_ops[_next][0]) <= _clock:
		_run(_ops[_next])
		_next += 1
	if _pal_dirty:
		_pal_tex.update(_palette)
		_pal_dirty = false
	if _dirty and _buffers.has(_screen_key):
		var img: Image = _buffers[_screen_key]
		if _screen_tex == null:
			_screen_tex = ImageTexture.create_from_image(img)
			_view.texture = _screen_tex
		else:
			_screen_tex.update(img)
		_dirty = false
	if _next >= _ops.size() or _skip:
		_finish()


func _finish() -> void:
	_done = true
	if _skip:
		Music.stop()
	for p in _voices:
		p.stop()
	finished.emit()


func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed("ui_cancel") or event.is_action_pressed("pause") or event.is_action_pressed("ui_accept"):
		_skip = true
		get_viewport().set_input_as_handled()


# --- display list -------------------------------------------------------------

func _run(op: Array) -> void:
	match op[1]:
		"surface":
			var key := "%d:%d" % [op[3], op[4]]
			if not _buffers.has(key):
				_buffers[key] = Image.create(W, H, false, Image.FORMAT_L8)
			_surfaces[op[2]] = key
			if op.size() > 6:
				var r: Array = op[6]
				_clips[op[2]] = Rect2i(r[0], r[1], r[2] - r[0] + 1, r[3] - r[1] + 1)
			if op[2] == "screen":
				_screen_key = key
		"pal":
			var first: int = op[2]
			var vals: Array = op[3]
			for k in vals.size() / 3:
				var c := Color8(vals[k * 3] * 255 / 63, vals[k * 3 + 1] * 255 / 63, vals[k * 3 + 2] * 255 / 63)
				_palette.set_pixel(first + k, 0, c)
			_pal_dirty = true
		"table":
			_tables[int(op[2])] = PackedByteArray(op[3])
		"fill":
			var img := _surface(op[2])
			if img:
				var r: Array = op[4]
				img.fill_rect(Rect2i(r[0], r[1], r[2] - r[0] + 1, r[3] - r[1] + 1), Color8(op[3], op[3], op[3]))
				_touch(op[2])
		"copy":
			var src := _surface(op[2])
			var dst := _surface(op[3])
			if src and dst:
				var s: Array = op[4]
				var d: Array = op[5]
				var w: int = mini(s[2] - s[0], d[2] - d[0]) + 1
				var h: int = mini(s[3] - s[1], d[3] - d[1]) + 1
				if src == dst:
					src = src.duplicate()
				dst.blit_rect(src, Rect2i(s[0], s[1], w, h), Vector2i(d[0], d[1]))
				_touch(op[3])
		"draw":
			_blit(op, 256, 256, 256, 0, -1)
		"sdraw":
			_blit(op, op[8], op[9], op[10], op[11], op[12])
		"glyph":
			_glyph(op)
		"line":
			_line(op)
		"ellipse":
			_ellipse(op)
		"music":
			Music.play(op[2], int(op[3]), int(op[4]), false)
		"music_stop":
			Music.stop()
		"voice":
			_voice(op[2], op[3])
		"subtitle":
			_subtitle.text = String(op[2])


func _surface(name: String) -> Image:
	return _buffers.get(_surfaces.get(name, ""))


func _touch(name: String) -> void:
	if _surfaces.get(name, "") == _screen_key:
		_dirty = true


func _line(op: Array) -> void:
	var dst := _surface(op[2])
	if dst == null:
		return
	var clip: Rect2i = _clips.get(op[2], Rect2i(0, 0, W, H))
	var c := Color8(op[7], op[7], op[7])
	var x0: int = op[3]
	var y0: int = op[4]
	var x1: int = op[5]
	var y1: int = op[6]
	var dx := absi(x1 - x0)
	var dy := -absi(y1 - y0)
	var sx := 1 if x0 < x1 else -1
	var sy := 1 if y0 < y1 else -1
	var err := dx + dy
	while true:
		if clip.has_point(Vector2i(x0, y0)):
			dst.set_pixel(x0, y0, c)
		if x0 == x1 and y0 == y1:
			break
		var e2 := 2 * err
		if e2 >= dy:
			err += dy
			x0 += sx
		if e2 <= dx:
			err += dx
			y0 += sy
	_touch(op[2])


## Filled ellipse (route markers on the transport map).
func _ellipse(op: Array) -> void:
	var dst := _surface(op[2])
	if dst == null:
		return
	var clip: Rect2i = _clips.get(op[2], Rect2i(0, 0, W, H))
	var cx: int = op[3]
	var cy: int = op[4]
	var rx: int = maxi(op[5], 0)
	var ry: int = maxi(op[6], 0)
	var c := Color8(op[7], op[7], op[7])
	for y in range(-ry, ry + 1):
		var half := rx if ry == 0 else int(floor(rx * sqrt(maxf(0.0, 1.0 - float(y * y) / float(ry * ry))) + 0.5))
		var r := Rect2i(cx - half, cy + y, half * 2 + 1, 1).intersection(clip)
		if r.size.x > 0 and r.size.y > 0:
			dst.fill_rect(r, c)
	_touch(op[2])


## Text: a font frame drawn in a single colour.
func _glyph(op: Array) -> void:
	var dst := _surface(op[2])
	if dst == null:
		return
	var frames: Array = _frames(op[3], op[4])
	var k: int = op[5]
	if k < 0 or k >= frames.size() or frames[k] == null:
		return
	var fr: Dictionary = frames[k]
	var key := "solid_%d" % int(op[8])
	if not fr.has(key):
		var img := Image.create(fr.w, fr.h, false, Image.FORMAT_L8)
		img.fill(Color8(op[8], op[8], op[8]))
		fr[key] = img
	var at := Vector2i(int(op[6]) + fr.origin.x, int(op[7]) + fr.origin.y)
	var clip: Rect2i = _clips.get(op[2], Rect2i(0, 0, W, H))
	var area := Rect2i(at, Vector2i(fr.w, fr.h)).intersection(clip)
	if area.size.x <= 0 or area.size.y <= 0:
		return
	dst.blit_rect_mask(fr[key], fr.mask, Rect2i(area.position - at, area.size), area.position)
	_touch(op[2])


func _blit(op: Array, sx: int, sy: int, first: int, count: int, table: int) -> void:
	var dst := _surface(op[2])
	if dst == null or String(op[3]) == "MOUSE.SHP":
		return
	var frames: Array = _frames(op[3], op[4])
	var k: int = op[5]
	if k < 0 or k >= frames.size() or frames[k] == null:
		return
	var fr: Dictionary = frames[k]
	var x: int = op[6]
	var y: int = op[7]
	var img: Image = fr.image
	var mask: Image = fr.mask
	var ox: int = fr.origin.x
	var oy: int = fr.origin.y
	if sx != 256 or sy != 256:
		var nw := maxi(1, absi(fr.w * sx) / 256)
		var nh := maxi(1, absi(fr.h * sy) / 256)
		img = img.duplicate()
		mask = mask.duplicate()
		img.resize(nw, nh, Image.INTERPOLATE_NEAREST)
		mask.resize(nw, nh, Image.INTERPOLATE_NEAREST)
		if sx < 0:
			img.flip_x(); mask.flip_x()
		if sy < 0:
			img.flip_y(); mask.flip_y()
		ox = ox * sx / 256
		oy = oy * sy / 256
		if sx < 0:
			ox -= nw - 1
		if sy < 0:
			oy -= nh - 1
	var at := Vector2i(x + ox, y + oy)
	var shade: Array = []
	if count > 0:
		# Pixels in [first, first + count) darken / lighten what is under them
		# through a shading table instead of being drawn as colours.
		var key := "shade_%d_%d" % [first, count]
		if not fr.has(key):
			var list := _shade_pixels(fr, first, count)
			var m: Image = fr.mask.duplicate()
			for p in list:
				m.set_pixel(p.x, p.y, Color(0, 0, 0, 0))
			fr[key] = {"pixels": list, "mask": m}
		shade = fr[key].pixels
		mask = fr[key].mask
		if sx != 256 or sy != 256:
			mask = mask.duplicate()
			mask.resize(img.get_width(), img.get_height(), Image.INTERPOLATE_NEAREST)
			if sx < 0: mask.flip_x()
			if sy < 0: mask.flip_y()
	var clip: Rect2i = _clips.get(op[2], Rect2i(0, 0, W, H))
	var area := Rect2i(at, img.get_size()).intersection(clip)
	if area.size.x <= 0 or area.size.y <= 0:
		return
	dst.blit_rect_mask(img, mask, Rect2i(area.position - at, area.size), area.position)
	if not shade.is_empty() and _tables.has(table):
		var tab: PackedByteArray = _tables[table]
		for p in shade:
			var px: int = x + (fr.origin.x + p.x) * sx / 256
			var py: int = y + (fr.origin.y + p.y) * sy / 256
			if not clip.has_point(Vector2i(px, py)):
				continue
			var under := int(round(dst.get_pixel(px, py).r * 255.0))
			var c := tab[p.z * 256 + under]
			dst.set_pixel(px, py, Color8(c, c, c))
	_touch(op[2])


## Pixels of a frame drawn through a shading table: Vector3i(x, y, level).
func _shade_pixels(fr: Dictionary, first: int, count: int) -> Array:
	var out := []
	var px: PackedByteArray = fr.pixels
	var mk: PackedByteArray = fr.mask_bytes
	for i in px.size():
		if mk[i] and px[i] >= first and px[i] < first + count:
			out.append(Vector3i(i % fr.w, i / fr.w, px[i] - first))
	return out


func _frames(archive: String, entry: int) -> Array:
	var key := "%s#%d" % [archive, entry]
	if _shapes.has(key):
		return _shapes[key]
	var shp := PackedByteArray()
	if archive.contains("@"):
		# a shape stored inside another file: "FILE@offset"
		var at := archive.rfind("@")
		var buf := SCData.read(archive.substr(0, at))
		var o := archive.substr(at + 1).to_int()
		if o + 4 <= buf.size():
			shp = buf.slice(o, o + buf.decode_u32(o))
	elif entry < 0:
		shp = SCData.read(archive)
	else:
		if not _archives.has(archive):
			var buf := SCData.read(archive)
			_archives[archive] = {"entries": Pak.entries(buf), "flags": Pak.flags(buf)}
		var a: Dictionary = _archives[archive]
		if entry < a.entries.size():
			shp = Shape.unpack(a.entries[entry], a.flags[entry] if entry < a.flags.size() else -1)
	var out := []
	for f in Shape.frames(shp):
		var d := Shape.decode(f)
		if d.is_empty():
			out.append(null)
			continue
		var m := PackedByteArray()
		m.resize(d.w * d.h * 2)
		var mk: PackedByteArray = d.mask
		for i in d.w * d.h:
			m[i * 2 + 1] = 255 if mk[i] else 0
		out.append({
			"w": d.w, "h": d.h, "origin": d.origin, "pixels": d.pixels, "mask_bytes": d.mask,
			"image": Image.create_from_data(d.w, d.h, false, Image.FORMAT_L8, d.pixels),
			"mask": Image.create_from_data(d.w, d.h, false, Image.FORMAT_LA8, m),
		})
	_shapes[key] = out
	return out


func _voice(archive: String, entry: int) -> void:
	if not _archives.has(archive):
		var buf := SCData.read(archive)
		_archives[archive] = {"entries": Pak.entries(buf), "flags": Pak.flags(buf)}
	var a: Dictionary = _archives[archive]
	if entry < 0 or entry >= a.entries.size():
		return
	var s := Voc.to_stream(a.entries[entry])
	if s == null:
		return
	for p in _voices:
		if not p.playing:
			p.stream = s
			p.play()
			return
	_voices[0].stream = s
	_voices[0].play()
