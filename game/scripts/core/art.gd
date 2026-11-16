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
