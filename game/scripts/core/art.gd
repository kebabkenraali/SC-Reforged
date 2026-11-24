## Cached access to the 2D art of the base screens and conversations:
## OPTSHPS / OPTPALS (base screens) and CONVSHPS / CONVPALS (conversations).
extends RefCounted

const Shape = preload("res://scripts/formats/sc_shape.gd")
const Pak = preload("res://scripts/formats/pak_archive.gd")
const Gameflow = preload("res://scripts/formats/sc_gameflow.gd")

const ARCHIVES_BASE := {"opt": ["GAMEFLOW/OPTSHPS.PAK", "GAMEFLOW/OPTPALS.PAK"],
	"conv": ["GAMEFLOW/CONVSHPS.PAK", "GAMEFLOW/CONVPALS.PAK"]}
## Tactical Operations screens/conversations use their own shape sets; its
## conversations still use the original CONVPALS palette archive.
const ARCHIVES_TACTICAL := {"opt": ["GAMEFLOW/OPTSHPS2.PAK", "GAMEFLOW/OPTPALS2.PAK"],
	"conv": ["GAMEFLOW/CONVSHP2.PAK", "GAMEFLOW/CONVPALS.PAK"]}
const SCREEN := Vector2i(320, 200)

## "base" or "tactical" — selects which original data set the whole UI reads.
static var active_set := "base"
static var _paks := {}
static var _frames := {}
static var _gameflow := {}
static var _fonts_set := ""


static func set_active(value: String) -> void:
	if value == active_set and _gameflow.has(value):
		return
	active_set = value if value == "tactical" else "base"
	_paks.clear()
	_frames.clear()
	_fonts.clear()
	_fonts_set = active_set


static func archives() -> Dictionary:
	return ARCHIVES_TACTICAL if active_set == "tactical" else ARCHIVES_BASE


static func gameflow():
	if not _gameflow.has(active_set):
		if active_set == "tactical":
			_gameflow[active_set] = Gameflow.load_from(SCData.read("GAMEFLOW/GAMEFLO2.IFF"),
				SCData.read("GAMEFLOW/OPTIONS2.IFF"), SCData.read("GAMEFLOW/CONVDAT2.IFF"))
		else:
			_gameflow[active_set] = Gameflow.load_from(SCData.read("GAMEFLOW/GAMEFLOW.IFF"),
				SCData.read("GAMEFLOW/OPTIONS.IFF"), SCData.read("GAMEFLOW/CONVDATA.IFF"))
	return _gameflow[active_set]


## The add-on shape archives are overlays: CONVSHP2.PAK has only 3 real shapes
## (indices 93-95) while CONVDAT2.IFF still points faces at the base CONVSHPS
## indices. Merge the base entries with the add-on's non-empty ones.
static func _overlay_base(path: String) -> String:
	match path:
		"GAMEFLOW/OPTSHPS2.PAK": return "GAMEFLOW/OPTSHPS.PAK"
		"GAMEFLOW/CONVSHP2.PAK": return "GAMEFLOW/CONVSHPS.PAK"
		"GAMEFLOW/OPTPALS2.PAK": return "GAMEFLOW/OPTPALS.PAK"
	return ""


static func _pak(path: String) -> Dictionary:
	if not _paks.has(path):
		var base := _overlay_base(path)
		var buf: PackedByteArray = SCData.read(base if base != "" else path)
		var e: Array = Pak.entries(buf).duplicate()
		var f: PackedByteArray = Pak.flags(buf)
		if base != "":
			var obuf: PackedByteArray = SCData.read(path)
			var oe: Array = Pak.entries(obuf)
			var of: PackedByteArray = Pak.flags(obuf)
			while e.size() < oe.size():
				e.append(PackedByteArray())
				f.append(0xFF)
			var is_shapes: bool = path.contains("SHP2") or path.contains("SHPS2")
			for i in oe.size():
				if of[i] == 0xFF:
					continue
				if is_shapes and Shape.frames(Shape.unpack(oe[i], of[i])).is_empty():
					continue  # entry 0 of these PAKs is a filename, not a shape
				e[i] = oe[i]
				f[i] = of[i]
		_paks[path] = {"entries": e, "flags": f}
	return _paks[path]


static func _entries(path: String) -> Array:
	return _pak(path).entries


static func _entry_flags(path: String) -> PackedByteArray:
	return _pak(path).flags


## Decoded frames of shape `index` in archive "opt" or "conv" (cached).
static func frames(archive: String, index: int) -> Array:
	var key := "%s:%s:%d" % [active_set, archive, index]
	if not _frames.has(key):
		var out := []
		var path: String = archives()[archive][0]
		var e := _entries(path)
		var flags := _entry_flags(path)
		if index >= 0 and index < e.size():
			var flag: int = flags[index] if index < flags.size() else -1
			for f in Shape.frames(Shape.unpack(e[index], flag)):
				var d := Shape.decode(f)
				if not d.is_empty():
					out.append(d)
		_frames[key] = out
	return _frames[key]


## Base palette with partial palettes `indices` of the archive applied in order.
static func palette(archive: String, indices: Array) -> PackedColorArray:
	var pal: PackedColorArray = SCData.palette()
	var e := _entries(archives()[archive][1])
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
