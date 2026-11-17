## Cached access to the 2D art of the base screens and conversations:
## OPTSHPS / OPTPALS (base screens) and CONVSHPS / CONVPALS (conversations).
extends RefCounted

const Shape = preload("res://scripts/formats/sc_shape.gd")
const Pak = preload("res://scripts/formats/pak_archive.gd")
const Gameflow = preload("res://scripts/formats/sc_gameflow.gd")

const ARCHIVES := {"opt": ["GAMEFLOW/OPTSHPS.PAK", "GAMEFLOW/OPTPALS.PAK"],
	"conv": ["GAMEFLOW/CONVSHPS.PAK", "GAMEFLOW/CONVPALS.PAK"]}
const SCREEN := Vector2i(320, 200)

static var _paks := {}
static var _frames := {}
static var _gameflow


static func gameflow():
	if _gameflow == null:
		_gameflow = Gameflow.load_from(SCData.read("GAMEFLOW/GAMEFLOW.IFF"),
			SCData.read("GAMEFLOW/OPTIONS.IFF"), SCData.read("GAMEFLOW/CONVDATA.IFF"))
	return _gameflow


static func _entries(path: String) -> Array:
	if not _paks.has(path):
		_paks[path] = Pak.entries(SCData.read(path))
	return _paks[path]


## Decoded frames of shape `index` in archive "opt" or "conv" (cached).
static func frames(archive: String, index: int) -> Array:
	var key := "%s:%d" % [archive, index]
	if not _frames.has(key):
		var out := []
		var e := _entries(ARCHIVES[archive][0])
		if index >= 0 and index < e.size():
			for f in Shape.frames(Shape.unpack(e[index])):
				var d := Shape.decode(f)
				if not d.is_empty():
					out.append(d)
		_frames[key] = out
	return _frames[key]


## Base palette with partial palettes `indices` of the archive applied in order.
static func palette(archive: String, indices: Array) -> PackedColorArray:
	var pal: PackedColorArray = SCData.palette()
	var e := _entries(ARCHIVES[archive][1])
	for i in indices:
		if i >= 0 and i < e.size():
			pal = Shape.apply_palette(pal, e[i])
	return pal


## Index canvas helpers: screens are composed in palette indices first so all
## layers share the final palette.
static func new_canvas() -> Dictionary:
	var px := PackedByteArray()
	px.resize(SCREEN.x * SCREEN.y)
	var mk := PackedByteArray()
	mk.resize(SCREEN.x * SCREEN.y)
	return {"pixels": px, "mask": mk}


static func blit(canvas: Dictionary, d: Dictionary, at: Vector2i) -> void:
	var o: Vector2i = at + d.origin
	var px: PackedByteArray = d.pixels
	var mk: PackedByteArray = d.mask
	var cp: PackedByteArray = canvas.pixels
	var cm: PackedByteArray = canvas.mask
	for y in d.h:
		var sy: int = o.y + y
		if sy < 0 or sy >= SCREEN.y:
			continue
		for x in d.w:
			var i: int = y * d.w + x
			if mk[i] == 0:
				continue
			var sx: int = o.x + x
			if sx >= 0 and sx < SCREEN.x:
				cp[sy * SCREEN.x + sx] = px[i]
				cm[sy * SCREEN.x + sx] = 1
	canvas.pixels = cp
	canvas.mask = cm


static func canvas_image(canvas: Dictionary, pal: PackedColorArray) -> Image:
	return Shape.to_image({"w": SCREEN.x, "h": SCREEN.y, "pixels": canvas.pixels, "mask": canvas.mask}, pal)


## Image of one decoded frame placed on a transparent 320 x 200 layer.
static func layer_image(d: Dictionary, at: Vector2i, pal: PackedColorArray) -> Image:
	var c := new_canvas()
	blit(c, d, at)
	return canvas_image(c, pal)


# --- bitmap fonts (DATA/FONTS/*.SHP: frame n is character code n) ------------------

static var _fonts := {}


## Decoded glyphs of font `name` (e.g. "LEDGFONT"): char code -> frame.
## Empty 1 x 1 frames are characters the font does not have.
static func font(name: String) -> Dictionary:
	if not _fonts.has(name):
		var glyphs := {}
		var raw := SCData.read("FONTS/%s.SHP" % name)
		if raw.size() > 0:
			var fr := Shape.frames(Shape.unpack(raw))
			for i in fr.size():
				var d := Shape.decode(fr[i])
				if not d.is_empty() and (d.w > 1 or d.h > 1):
					glyphs[i] = d
		_fonts[name] = glyphs
	return _fonts[name]


## Width of a missing character (space): about half the font height.
static func _space(glyphs: Dictionary) -> int:
	var d = glyphs.get(48, glyphs.get(65, {}))
	return maxi(3, int(d.get("h", 6)) / 2 + 1)


static func text_width(glyphs: Dictionary, s: String) -> int:
	var w := 0
	for ch in s:
		var d = glyphs.get(ch.unicode_at(0), {})
		w += (d.w + 1) if not d.is_empty() else _space(glyphs)
	return maxi(0, w - 1)


## Draws `s` with its baseline at `at.y`. `color` >= 0 paints every glyph
## pixel with that palette index (ink colour); -1 keeps the font's own colours.
static func draw_text(canvas: Dictionary, glyphs: Dictionary, s: String, at: Vector2i, color := -1) -> int:
	var x := at.x
	for ch in s:
		var d = glyphs.get(ch.unicode_at(0), {})
		if d.is_empty():
			x += _space(glyphs)
			continue
		if color >= 0:
			var g: Dictionary = d.duplicate()
			var px := PackedByteArray()
			px.resize(d.w * d.h)
			px.fill(color)
			g.pixels = px
			blit(canvas, g, Vector2i(x, at.y))
		else:
			blit(canvas, d, Vector2i(x, at.y))
		x += d.w + 1
	return x - at.x


## Palette index closest to colour `c` (for ink colours).
static func nearest(pal: PackedColorArray, c: Color) -> int:
	var best := 0
	var bd := INF
	for i in pal.size():
		var p: Color = pal[i]
		var d: float = Vector3(p.r - c.r, p.g - c.g, p.b - c.b).length_squared()
		if d < bd:
			bd = d
			best = i
	return best
