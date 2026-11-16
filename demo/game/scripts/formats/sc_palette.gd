## VGA palettes from PALETTE/*.IFF (FORM PALT -> PALT: 4 byte header + 256 RGB, 6 bit).
extends RefCounted

const Iff = preload("res://scripts/formats/iff.gd")


static func from_iff(buf: PackedByteArray) -> PackedColorArray:
	var nodes := Iff.parse(buf)
	var pal = Iff.find(nodes, ["FORM:PALT", "PALT"])
	if pal == null:
		return grayscale()
	return from_vga(buf, pal.off + 4)


static func from_vga(buf: PackedByteArray, off: int) -> PackedColorArray:
	var out := PackedColorArray()
	out.resize(256)
	for i in 256:
		var o := off + i * 3
		if o + 2 >= buf.size():
			break
		out[i] = Color8(buf[o] * 255 / 63, buf[o + 1] * 255 / 63, buf[o + 2] * 255 / 63)
	return out


static func grayscale() -> PackedColorArray:
	var out := PackedColorArray()
	for i in 256:
		out.append(Color8(i, i, i))
	return out


## 8-bit indexed pixels -> RGBA8 image. `transparent` index (-1 = none) gets alpha 0.
static func to_image(pixels: PackedByteArray, w: int, h: int, palette: PackedColorArray,
		transparent := 255) -> Image:
	var rgba := PackedByteArray()
	rgba.resize(w * h * 4)
	for i in mini(pixels.size(), w * h):
		var idx := pixels[i]
		var c := palette[idx]
		rgba[i * 4] = c.r8
		rgba[i * 4 + 1] = c.g8
		rgba[i * 4 + 2] = c.b8
		rgba[i * 4 + 3] = 0 if idx == transparent else 255
	return Image.create_from_data(w, h, false, Image.FORMAT_RGBA8, rgba)
