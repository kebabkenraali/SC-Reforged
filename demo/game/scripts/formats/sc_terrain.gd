## Strike Commander terrain area (CANYON.PAK, EGYPT.PAK, ... in the CD root).
##
## PAK entries: 0 = FORM TERA (ELEV/ATRI/OBJS/TXMS info), 1..3 = block PAKs for
## LOD 0..2 (18 x 18 blocks; 20/10/5 vertices per side), 4..5 = object lists,
## 6 = per-block summary. Entry 5 holds named ground objects per block:
## u16 count + 70-byte records (char model[13], char destroyed[9], i32 x/y/z in
## 24.8 fixed-point feet at 22/26/30; x = east, y = north). Each block is u32 size + LZW data containing
## 6-byte vertices: i16 height (ft), u8 shade noise, u8 terrain type,
## u8 tile for the quad triangle u > v / u < v (index into DATA/TXM/TXMPACK.PAK,
## 255 = none).
##
## Terrain types 0..6 = water, desert, rough, grass, forest, rock, snow; their
## base colours come from the RANG table of the area palette, in that order.
extends RefCounted

const Iff = preload("res://scripts/formats/iff.gd")
const Pak = preload("res://scripts/formats/pak_archive.gd")
const Lzw = preload("res://scripts/formats/lzw.gd")

const FEET := 0.3048
const NO_TILE := 255
const TILE_TRANSPARENT := [255, 229, 230]

var name := ""
var blocks_per_side := 18
var verts_per_block := 20
var block_size_units := 20000.0
var grid_size := 360
var heights := PackedFloat32Array()     # metres, grid_size^2
var shades := PackedByteArray()
var types := PackedByteArray()
var tile_lower := PackedByteArray()
var tile_upper := PackedByteArray()
var texture_names := PackedStringArray()
var objects := []                       # [{ model, destroyed, pos: Vector3 (m) }]


static func load_from(buf: PackedByteArray, area_name := ""):
	var t = load("res://scripts/formats/sc_terrain.gd").new()
	t.name = area_name
	if not t._parse(buf):
		return null
	return t


## World size in metres along one side.
func world_size() -> float:
	return grid_size * spacing()


## Distance between neighbouring vertices in metres.
func spacing() -> float:
	return block_size_units / verts_per_block * FEET


func _parse(buf: PackedByteArray) -> bool:
	var e := Pak.entries(buf)
	if e.size() < 4:
		return false
	var tera := Iff.parse(e[0])
	var elev = Iff.find(tera, ["FORM:TERA", "FORM:BLOX", "ELEV"])
	if elev != null and elev.size >= 18:
		blocks_per_side = e[0].decode_u16(elev.off + 12)
		verts_per_block = e[0].decode_u16(elev.off + 14)
		block_size_units = e[0].decode_u32(elev.off + 16)
	var maps = Iff.find(tera, ["FORM:TERA", "FORM:TXMS", "MAPS"])
	if maps != null:
		var o: int = maps.off
		while o + 12 <= maps.off + maps.size:
			texture_names.append(Iff.cstr(e[0], o + 2, 8))
			o += 12

	if e.size() > 5:
		_parse_objects(e[5])
	grid_size = blocks_per_side * verts_per_block
	var n := grid_size * grid_size
	heights.resize(n)
	shades.resize(n)
	types.resize(n)
	tile_lower.resize(n)
	tile_upper.resize(n)
	var blocks := Pak.entries(e[1])
	var vpb := verts_per_block
	for bi in mini(blocks.size(), blocks_per_side * blocks_per_side):
		var raw: PackedByteArray = blocks[bi]
		if raw.size() < 5:
			continue
		var data := Lzw.decode(raw, 4, raw.decode_u32(0))
		var bx := bi % blocks_per_side
		var by := bi / blocks_per_side
		for k in mini(vpb * vpb, data.size() / 6):
			var gi := (by * vpb + k / vpb) * grid_size + bx * vpb + k % vpb
			heights[gi] = maxf(0.0, data.decode_s16(k * 6)) * FEET
			shades[gi] = data[k * 6 + 2]
			types[gi] = data[k * 6 + 3]
			tile_lower[gi] = data[k * 6 + 4]
			tile_upper[gi] = data[k * 6 + 5]
	return true


func _parse_objects(buf: PackedByteArray) -> void:
	for block in Pak.entries(buf):
		if block.size() < 2:
			continue
		var count := block.decode_u16(0)
		if count == 0 or (block.size() - 2) % count != 0:
			continue
		var rs := (block.size() - 2) / count
		if rs < 34:
			continue
		for k in count:
			var o := 2 + k * rs
			objects.append({"model": Iff.cstr(block, o, 13), "destroyed": Iff.cstr(block, o + 13, 9),
				"pos": Vector3(block.decode_s32(o + 22), block.decode_s32(o + 30), -block.decode_s32(o + 26)) / 256.0 * FEET})


## Bilinear height at world position (x, z) in metres, map centred on origin.
func height_at(x: float, z: float) -> float:
	var s := spacing()
	var fx := x / s + grid_size * 0.5
	var fz := z / s + grid_size * 0.5
	var ix := clampi(int(floor(fx)), 0, grid_size - 2)
	var iz := clampi(int(floor(fz)), 0, grid_size - 2)
	var tx := clampf(fx - ix, 0.0, 1.0)
	var tz := clampf(fz - iz, 0.0, 1.0)
	var h00 := heights[iz * grid_size + ix]
	var h10 := heights[iz * grid_size + ix + 1]
	var h01 := heights[(iz + 1) * grid_size + ix]
	var h11 := heights[(iz + 1) * grid_size + ix + 1]
	return lerpf(lerpf(h00, h10, tx), lerpf(h01, h11, tx), tz)


func vertex_position(gx: int, gz: int) -> Vector3:
	var s := spacing()
	return Vector3((gx - grid_size * 0.5) * s, heights[gz * grid_size + gx], (gz - grid_size * 0.5) * s)


## Base colours per terrain type from the palette's RANG chunk.
static func type_colors(palette_iff: PackedByteArray) -> PackedColorArray:
	var out := PackedColorArray([Color8(12, 104, 136), Color8(204, 164, 100), Color8(124, 104, 80),
		Color8(120, 140, 72), Color8(60, 96, 36), Color8(148, 148, 148), Color8(252, 252, 252)])
	var rang = Iff.find(Iff.parse(palette_iff), ["FORM:PALT", "RANG"])
	if rang == null:
		return out
	var count := palette_iff.decode_u16(rang.off)
	for i in mini(count, 16):
		var o: int = rang.off + 2 + i * 13
		if o + 9 > rang.off + rang.size:
			break
		var c := Color8(palette_iff[o + 6] * 255 / 63, palette_iff[o + 7] * 255 / 63, palette_iff[o + 8] * 255 / 63)
		if i < out.size():
			out[i] = c
		else:
			out.append(c)
	return out


## Original 64x64 ground tiles (DATA/TXM/TXMPACK.PAK) as one texture array.
static func tile_array(pak_buf: PackedByteArray, palette: PackedColorArray) -> Texture2DArray:
	var images: Array[Image] = []
	for entry in Pak.entries(pak_buf):
		var w := entry.decode_u16(0) if entry.size() >= 4 else 0
		var h := entry.decode_u16(2) if entry.size() >= 4 else 0
		var rgba := PackedByteArray()
		rgba.resize(64 * 64 * 4)
		if w == 64 and h == 64 and entry.size() >= 4 + 4096:
			for i in 4096:
				var idx := entry[4 + i]
				if idx in TILE_TRANSPARENT:
					continue
				var c := palette[idx]
				rgba[i * 4] = c.r8
				rgba[i * 4 + 1] = c.g8
				rgba[i * 4 + 2] = c.b8
				rgba[i * 4 + 3] = 255
		var img := Image.create_from_data(64, 64, false, Image.FORMAT_RGBA8, rgba)
		img.generate_mipmaps()
		images.append(img)
	while images.size() < 256:
		var blank := Image.create(64, 64, true, Image.FORMAT_RGBA8)
		images.append(blank)
	var arr := Texture2DArray.new()
	arr.create_from_images(images)
	return arr


## Builds the terrain as square chunks (frustum-culled by Godot). Each quad is
## split along its (0,0)-(1,1) diagonal like the original tiles; UV holds the
## position inside the quad, UV2.x the tile index, COLOR the type colour
## (alpha = 1 for water so the shader can make it reflective).
func build_chunks(type_cols: PackedColorArray, material: Material, chunk_quads := 40) -> Array[MeshInstance3D]:
	var out: Array[MeshInstance3D] = []
	var g := grid_size
	var vcol := PackedColorArray()
	vcol.resize(g * g)
	var norms := PackedVector3Array()
	norms.resize(g * g)
	for i in g * g:
		var t := types[i]
		var c: Color = type_cols[t] if t < type_cols.size() else Color.MAGENTA
		c = c.srgb_to_linear() * (0.86 + 0.28 * shades[i] / 255.0)
		c.a = 1.0 if t == 0 else 0.0
		vcol[i] = c
		norms[i] = _normal(i % g, i / g)

	for cz in range(0, g - 1, chunk_quads):
		for cx in range(0, g - 1, chunk_quads):
			var verts := PackedVector3Array()
			var nrm := PackedVector3Array()
			var cols := PackedColorArray()
			var uvs := PackedVector2Array()
			var uv2s := PackedVector2Array()
			for z in range(cz, mini(cz + chunk_quads, g - 1)):
				for x in range(cx, mini(cx + chunk_quads, g - 1)):
					var i00 := z * g + x
					var corners := [i00, i00 + 1, i00 + g + 1, i00 + g]   # (0,0) (1,0) (1,1) (0,1)
					var cuv := [Vector2(0, 0), Vector2(1, 0), Vector2(1, 1), Vector2(0, 1)]
					var cpos := [vertex_position(x, z), vertex_position(x + 1, z),
						vertex_position(x + 1, z + 1), vertex_position(x, z + 1)]
					# Triangle u > v (0,1,2) uses the first tile byte, u < v (0,2,3) the second.
					for tri in [[[0, 1, 2], tile_lower[i00]], [[0, 2, 3], tile_upper[i00]]]:
						var ids: Array = tri[0]
						if (cpos[ids[1]] - cpos[ids[0]]).cross(cpos[ids[2]] - cpos[ids[0]]).y > 0.0:
							ids = [ids[0], ids[2], ids[1]]
						for k in ids:
							verts.append(cpos[k])
							nrm.append(norms[corners[k]])
							cols.append(vcol[corners[k]])
							uvs.append(cuv[k])
							uv2s.append(Vector2(tri[1], 0.0))
			var arrays := []
			arrays.resize(Mesh.ARRAY_MAX)
			arrays[Mesh.ARRAY_VERTEX] = verts
			arrays[Mesh.ARRAY_NORMAL] = nrm
			arrays[Mesh.ARRAY_COLOR] = cols
			arrays[Mesh.ARRAY_TEX_UV] = uvs
			arrays[Mesh.ARRAY_TEX_UV2] = uv2s
			var mesh := ArrayMesh.new()
			mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
			mesh.surface_set_material(0, material)
			var mi := MeshInstance3D.new()
			mi.mesh = mesh
			out.append(mi)
	return out


## Average height and most common terrain type along the map border, used to
## extend the world beyond the playable area.
func border_info() -> Dictionary:
	var g := grid_size
	var counts := {}
	var total := 0.0
	var n := 0
	for i in g:
		for gi in [i, (g - 1) * g + i, i * g, i * g + g - 1]:
			total += heights[gi]
			n += 1
			counts[types[gi]] = counts.get(types[gi], 0) + 1
	var best := 0
	for t in counts:
		if counts[t] > counts.get(best, 0):
			best = t
	return {"height": total / maxf(1.0, n), "type": best}


func _normal(gx: int, gz: int) -> Vector3:
	var g := grid_size
	var l := heights[gz * g + maxi(gx - 1, 0)]
	var r := heights[gz * g + mini(gx + 1, g - 1)]
	var d := heights[maxi(gz - 1, 0) * g + gx]
	var u := heights[mini(gz + 1, g - 1) * g + gx]
	return Vector3(l - r, 2.0 * spacing(), d - u).normalized()
