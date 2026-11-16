## Origin 2D shapes (*.SHP, entries of OPTSHPS.PAK / CONVSHPS.PAK).
##
## A shape file is u32 total size followed by u32 frame offsets. A frame starts
## with i16 x2, x1, y1, y2 (extent right/left/up/down of the origin) followed
## by line records: u16 key (0 = end; count = key >> 1), i16 dx, i16 dy, then
## either `count` raw pixels (key even) or RLE data (key odd) made of bytes
## b: n = b >> 1, b odd -> repeat the next byte n times, even -> copy n bytes.
## dx/dy are relative to the origin; for full-screen art the origin is the
## top-left corner of the 320 x 200 screen.
extends RefCounted

const Lzw = preload("res://scripts/formats/lzw.gd")


## PAK entry -> shape file bytes (packed entries are u32 size + LZW).
## With the entry's PAK flag known, 0x20 means LZW and anything else is stored
## as is (0xE0 entries may carry extra data after the shape).
static func unpack(entry: PackedByteArray, flag := -1) -> PackedByteArray:
	if entry.size() < 8:
		return PackedByteArray()
	if flag >= 0 and flag != 0x20:
		return entry.slice(0, mini(entry.size(), entry.decode_u32(0)))
	if entry.decode_u32(0) == entry.size():
		return entry
	return Lzw.decode(entry, 4, entry.decode_u32(0))


static func frames(shp: PackedByteArray) -> Array[PackedByteArray]:
	var out: Array[PackedByteArray] = []
	if shp.size() < 8:
		return out
	var first := shp.decode_u32(4)
	if first < 8 or first > shp.size():
		return out
	var offs := PackedInt32Array()
	for i in range(4, first, 4):
		offs.append(shp.decode_u32(i))
	offs.append(shp.size())
	for i in offs.size() - 1:
		out.append(shp.slice(offs[i], maxi(offs[i], offs[i + 1])))
	return out


## Decodes one frame into palette indices plus a coverage mask.
## Returns { w, h, origin: Vector2i (top-left relative to the shape origin),
## pixels: PackedByteArray, mask: PackedByteArray } or {} on bad data.
static func decode(f: PackedByteArray) -> Dictionary:
	if f.size() < 8:
		return {}
	var x2 := f.decode_s16(0)
	var x1 := f.decode_s16(2)
	var y1 := f.decode_s16(4)
	var y2 := f.decode_s16(6)
	var w := x1 + x2 + 1
	var h := y1 + y2 + 1
	if w <= 0 or h <= 0 or w > 2048 or h > 2048:
		return {}
	var pixels := PackedByteArray()
	pixels.resize(w * h)
	var mask := PackedByteArray()
	mask.resize(w * h)
	var i := 8
	var n := f.size()
	while i + 6 <= n:
		var key := f.decode_u16(i)
		if key == 0:
			break
		var dx := f.decode_s16(i + 2)
		var dy := f.decode_s16(i + 4)
		i += 6
		var count := key >> 1
		var x := dx + x1
		var y := dy + y1
		var row_ok := y >= 0 and y < h
		if key & 1:
			var end := x + count
			while x < end and i < n:
				var b := f[i]
				i += 1
				var run := b >> 1
				if b & 1:
					var c := f[i] if i < n else 0
					i += 1
					for k in run:
						_put(pixels, mask, w, x + k, y, c, row_ok)
				else:
					for k in run:
						_put(pixels, mask, w, x + k, y, f[i + k] if i + k < n else 0, row_ok)
					i += run
				x += run
		else:
			for k in count:
				_put(pixels, mask, w, x + k, y, f[i + k] if i + k < n else 0, row_ok)
			i += count
	return {"w": w, "h": h, "origin": Vector2i(-x1, -y1), "pixels": pixels, "mask": mask}


static func _put(pixels: PackedByteArray, mask: PackedByteArray, w: int, x: int, y: int, c: int, row_ok: bool) -> void:
	if row_ok and x >= 0 and x < w:
		pixels[y * w + x] = c
		mask[y * w + x] = 1


static func to_image(d: Dictionary, palette: PackedColorArray) -> Image:
	var rgba := PackedByteArray()
	rgba.resize(d.w * d.h * 4)
	var px: PackedByteArray = d.pixels
	var mk: PackedByteArray = d.mask
	for i in d.w * d.h:
		if mk[i]:
			var c := palette[px[i]]
			rgba[i * 4] = c.r8
			rgba[i * 4 + 1] = c.g8
			rgba[i * 4 + 2] = c.b8
			rgba[i * 4 + 3] = 255
	return Image.create_from_data(d.w, d.h, false, Image.FORMAT_RGBA8, rgba)


## Partial VGA palette (u16 first index, u16 count, count * RGB 6-bit) applied
## on top of `base`.
static func apply_palette(base: PackedColorArray, entry: PackedByteArray) -> PackedColorArray:
	var out := base.duplicate()
	if entry.size() < 4:
		return out
	var first := entry.decode_u16(0)
	var count := entry.decode_u16(2)
	for k in count:
		var o := 4 + k * 3
		if first + k > 255 or o + 2 >= entry.size():
			break
		out[first + k] = Color8(entry[o] * 255 / 63, entry[o + 1] * 255 / 63, entry[o + 2] * 255 / 63)
	return out
