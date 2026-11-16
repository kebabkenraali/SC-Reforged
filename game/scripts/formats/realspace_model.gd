## RealSpace 3D object (FORM REAL) -> Godot ArrayMesh.
##
## FORM REAL
##   FORM OBJT ...            gameplay data (JETP, DYNM, WEAP, ...)
##   FORM APPR / FORM POLY
##     VERT   n * (i32 x, i32 y, i32 z)         x = right, y = forward, z = up
##     FORM DETA / LVLn       u32 distance, u16 triangle ids
##     FORM TRIS
##       VTRI  n * 8 bytes: shade, v0, v1, v2, color, 0, lod mask, flags
##       UVXY  n * 8 bytes: triangle id, texture id, (u, v) * 3 in texels
##       FORM TXMS / TXMP  name[8], u16 w, u16 h, "LZ" + LZW data | raw pixels
extends RefCounted

const Iff = preload("res://scripts/formats/iff.gd")
const Lzw = preload("res://scripts/formats/lzw.gd")
const Palette = preload("res://scripts/formats/sc_palette.gd")
const MODEL_SHADER = preload("res://shaders/model.gdshader")

## Model units -> metres (an F-16 is ~8000 units long, 15 m in reality).
const MODEL_SCALE := 15.0 / 8000.0

var name := ""
var vertices := PackedVector3Array()
var triangles := []          # [{ v = [a, b, c], color, shade, lod, flags }]
var lods := []               # [{ distance, tris = PackedInt32Array }]
var uv_map := {}             # triangle id -> { tex, uv = [Vector2 * 3] }
var textures := []           # [{ name, w, h, pixels }]
var object_chunks := []      # raw OBJT children for gameplay code
var buffer := PackedByteArray()


static func load_from(buf: PackedByteArray, model_name := ""):
	var m = load("res://scripts/formats/realspace_model.gd").new()
	m.name = model_name
	if not m._parse(buf):
		return null
	return m


## Extents of objects without geometry (e.g. RNWY runways, which the original
## renderer draws itself). EXTE: ..., i32 x_max, x_min, y_max, y_min, z_max,
## z_min at offset 16 in 24.8 fixed-point feet. Returns {} when not present.
static func extents(buf: PackedByteArray) -> Dictionary:
	var nodes := Iff.parse(buf)
	var objt = Iff.find(nodes, ["FORM:REAL", "FORM:OBJT"])
	if objt == null:
		return {}
	var exte = Iff.find(objt.children, ["EXTE"])
	if exte == null or exte.size < 40:
		return {}
	var v := []
	for k in 6:
		v.append(buf.decode_s32(exte.off + 16 + k * 4) / 256.0 * 0.3048)
	return {"min": Vector3(v[1], v[5], -v[2]), "max": Vector3(v[0], v[4], -v[3]),
		"runway": Iff.find(objt.children, ["FORM:RNWY"]) != null}


static func sc_to_godot(x: float, y: float, z: float) -> Vector3:
	return Vector3(x, z, -y) * MODEL_SCALE


func _parse(buf: PackedByteArray) -> bool:
	buffer = buf
	var nodes := Iff.parse(buf)
	var real = Iff.find(nodes, ["FORM:REAL"])
	if real == null:
		return false
	var objt = Iff.find(real.children, ["FORM:OBJT"])
	if objt != null:
		object_chunks = objt.children
	var poly = Iff.find(real.children, ["FORM:APPR", "FORM:POLY"])
	if poly == null:
		return false

	var vert = Iff.find(poly.children, ["VERT"])
	if vert == null:
		return false
	for i in vert.size / 12:
		var o: int = vert.off + i * 12
		vertices.append(sc_to_godot(buf.decode_s32(o), buf.decode_s32(o + 4), buf.decode_s32(o + 8)))

	var vtri = Iff.find(poly.children, ["FORM:TRIS", "VTRI"])
	if vtri != null:
		for i in vtri.size / 8:
			var o: int = vtri.off + i * 8
			triangles.append({"shade": buf[o], "v": [buf[o + 1], buf[o + 2], buf[o + 3]],
				"color": buf[o + 4], "lod": buf[o + 6], "flags": buf[o + 7]})

	var uvxy = Iff.find(poly.children, ["FORM:TRIS", "UVXY"])
	if uvxy != null:
		for i in uvxy.size / 8:
			var o: int = uvxy.off + i * 8
			uv_map[buf[o]] = {"tex": buf[o + 1], "uv": [Vector2(buf[o + 2], buf[o + 3]),
				Vector2(buf[o + 4], buf[o + 5]), Vector2(buf[o + 6], buf[o + 7])]}

	var txms = Iff.find(poly.children, ["FORM:TRIS", "FORM:TXMS"])
	if txms == null:
		txms = Iff.find(poly.children, ["FORM:TXMS"])
	if txms != null:
		for t in txms.children:
			if t.id == "TXMP" or t.id == "TXMA":
				textures.append(_parse_texture(buf, t))

	var deta = Iff.find(poly.children, ["FORM:DETA"])
	if deta != null:
		for lvl in deta.children:
			if not lvl.id.begins_with("LVL"):
				continue
			var ids := PackedInt32Array()
			for k in (lvl.size - 4) / 2:
				ids.append(buf.decode_u16(lvl.off + 4 + k * 2))
			lods.append({"distance": buf.decode_u32(lvl.off), "tris": ids})
	return vertices.size() > 0 and triangles.size() > 0


func _parse_texture(buf: PackedByteArray, node) -> Dictionary:
	var o: int = node.off
	var tex := {"name": Iff.cstr(buf, o, 8), "w": buf.decode_u16(o + 8), "h": buf.decode_u16(o + 10),
		"pixels": PackedByteArray()}
	var count: int = tex.w * tex.h
	if count <= 0 or count > 1024 * 1024:
		return tex
	if buf[o + 12] == 0x4C and buf[o + 13] == 0x5A:  # "LZ"
		tex.pixels = Lzw.decode(Iff.data(buf, node), 14, count)
	else:
		tex.pixels = buf.slice(o + 12, o + 12 + count)
	if tex.pixels.size() < count:
		tex.pixels.resize(count)
	return tex


func triangle_ids_for_lod(lod: int) -> PackedInt32Array:
	if lods.is_empty():
		var all := PackedInt32Array()
		for i in triangles.size():
			all.append(i)
		return all
	return lods[clampi(lod, 0, lods.size() - 1)].tris


func lod_count() -> int:
	return maxi(1, lods.size())


## Builds a flat-shaded mesh. Untextured triangles go to one vertex-colour
## surface; textured triangles are grouped into one surface per texture.
func build_mesh(palette: PackedColorArray, lod := 0, smooth_textures := true) -> ArrayMesh:
	var ids := triangle_ids_for_lod(lod)
	var flip := _winding_flip(ids)
	var groups := {}  # -1 = colour surface, else texture index
	# Enhanced look: smooth shading across facets that meet at under 50 deg
	# (round fuselages), hard edges elsewhere (wing edges, wing roots).
	# Face normals are gathered by vertex POSITION so texture seams do not
	# break the smoothing. Off = the original flat-shaded facets.
	var smooth_cos := cos(deg_to_rad(50.0))
	var corner_faces := {}   # position key -> Array of area-weighted face normals
	if smooth_textures:
		for tid in ids:
			if tid >= triangles.size():
				continue
			var tv: Array = triangles[tid].v
			if tv[0] >= vertices.size() or tv[1] >= vertices.size() or tv[2] >= vertices.size():
				continue
			var q0: Vector3 = vertices[tv[0]]
			var fn: Vector3 = (vertices[tv[1]] - q0).cross(vertices[tv[2]] - q0)
			if fn.length_squared() < 1e-12:
				continue
			fn *= -1.0 if flip else 1.0
			for vi in tv:
				var key3 := Vector3i((vertices[vi] * 1000.0).round())
				if not corner_faces.has(key3):
					corner_faces[key3] = []
				corner_faces[key3].append(fn)
	for tid in ids:
		if tid >= triangles.size():
			continue
		var t: Dictionary = triangles[tid]
		var a: int = t.v[0]
		var b: int = t.v[1]
		var c: int = t.v[2]
		if a >= vertices.size() or b >= vertices.size() or c >= vertices.size():
			continue
		var key := -1
		var uv = uv_map.get(tid)
		if uv != null and uv.tex < textures.size() and textures[uv.tex].w > 0:
			key = uv.tex
		if not groups.has(key):
			groups[key] = {"v": PackedVector3Array(), "n": PackedVector3Array(),
				"c": PackedColorArray(), "uv": PackedVector2Array()}
		var g: Dictionary = groups[key]
		var p := [vertices[a], vertices[b], vertices[c]]
		var n: Vector3 = (p[1] - p[0]).cross(p[2] - p[0])
		if n.length_squared() < 1e-12:
			continue
		n = n.normalized() * (-1.0 if flip else 1.0)
		# Godot treats clockwise triangles as front faces.
		var order := [0, 2, 1] if (p[1] - p[0]).cross(p[2] - p[0]).dot(n) > 0.0 else [0, 1, 2]
		var col: Color = palette[t.color].srgb_to_linear()
		for k in order:
			g.v.append(p[k])
			var vn := n
			if smooth_textures:
				var sum := Vector3.ZERO
				for fn2 in corner_faces.get(Vector3i((p[k] * 1000.0).round()), []):
					if fn2.normalized().dot(n) > smooth_cos:
						sum += fn2
				if sum.length_squared() > 1e-12:
					vn = sum.normalized()
			g.n.append(vn)
			g.c.append(col)
			if key >= 0:
				var tx: Dictionary = textures[key]
				var tuv: Vector2 = uv.uv[k]
				g.uv.append(Vector2((tuv.x + 0.5) / tx.w, (tuv.y + 0.5) / tx.h))

	var mesh := ArrayMesh.new()
	for key in groups:
		var g: Dictionary = groups[key]
		if g.v.is_empty():
			continue
		var arrays := []
		arrays.resize(Mesh.ARRAY_MAX)
		arrays[Mesh.ARRAY_VERTEX] = g.v
		arrays[Mesh.ARRAY_NORMAL] = g.n
		arrays[Mesh.ARRAY_COLOR] = g.c
		if key >= 0:
			arrays[Mesh.ARRAY_TEX_UV] = g.uv
		mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
		mesh.surface_set_material(mesh.get_surface_count() - 1,
			_material(palette, key, smooth_textures))
	return mesh


## RealSpace winding is not documented; vote on whether face normals point
## away from the model centre and flip globally if most of them do not.
func _winding_flip(ids: PackedInt32Array) -> bool:
	var center := Vector3.ZERO
	for v in vertices:
		center += v
	center /= maxf(1.0, vertices.size())
	var score := 0.0
	for tid in ids:
		if tid >= triangles.size():
			continue
		var t: Dictionary = triangles[tid]
		if t.v[0] >= vertices.size() or t.v[1] >= vertices.size() or t.v[2] >= vertices.size():
			continue
		var p0: Vector3 = vertices[t.v[0]]
		var p1: Vector3 = vertices[t.v[1]]
		var p2: Vector3 = vertices[t.v[2]]
		var n := (p1 - p0).cross(p2 - p0)
		score += signf(n.dot((p0 + p1 + p2) / 3.0 - center))
	return score < 0.0


func _material(palette: PackedColorArray, tex_index: int, smooth: bool) -> Material:
	if smooth and tex_index >= 0 and surface_kind(textures[tex_index].name) == 3:
		# Spinning propeller: a see-through blur disc instead of a solid board
		# (the original drew the noise texture opaque).
		var tx0: Dictionary = textures[tex_index]
		var disc := StandardMaterial3D.new()
		disc.albedo_texture = ImageTexture.create_from_image(Palette.to_image(tx0.pixels, tx0.w, tx0.h, palette, 255))
		disc.albedo_color = Color(0.5, 0.5, 0.5, 0.2)
		disc.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
		disc.cull_mode = BaseMaterial3D.CULL_DISABLED
		disc.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		disc.texture_filter = BaseMaterial3D.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS
		return disc
	var mat := ShaderMaterial.new()
	mat.shader = MODEL_SHADER
	mat.set_shader_parameter("textured", tex_index >= 0)
	mat.set_shader_parameter("pixelated", not smooth)
	mat.set_shader_parameter("enhanced", smooth)
	if tex_index >= 0:
		var tx: Dictionary = textures[tex_index]
		mat.set_shader_parameter("kind", surface_kind(tx.name))
		var img := Palette.to_image(tx.pixels, tx.w, tx.h, palette, 255)
		img.generate_mipmaps()
		var tex := ImageTexture.create_from_image(img)
		mat.set_shader_parameter("albedo_tex_px", tex)
		if smooth:
			# Enhanced skin: 4x edge-preserving upscale of the palette indices
			# (Scale2x twice), so linear filtering smooths the edges of the
			# camouflage shapes instead of blurring them into blotches.
			# Runtime only - the original texels are never written to disk.
			# Only flat-colour pixel art (camouflage, markings): noisy photo-like
			# textures (hangar walls) turn blocky under Scale2x.
			if not tx.has("px4"):
				tx["px4"] = []
				if _colour_count(tx.pixels, 17) <= 16:
					var p2: Array = _scale2x(tx.pixels, tx.w, tx.h)
					tx["px4"] = _scale2x(p2[0], p2[1], p2[2])
			var p4: Array = tx.px4
			if not p4.is_empty():
				var big := Palette.to_image(p4[0], p4[1], p4[2], palette, 255)
				big.generate_mipmaps()
				tex = ImageTexture.create_from_image(big)
		mat.set_shader_parameter("albedo_tex", tex)
	return mat


## Material class of a texture from its original name (the naming is
## consistent across the aircraft set): 0 paint, 1 canopy (TF16CPUP,
## M21GGCPU, F18PILU, MRJ-CANP ...), 2 exhaust metal (JETEXHST, MISSEXH4,
## F18EXH, M29-TEXH), 3 propeller.
static func surface_kind(tex_name: String) -> int:
	var n := tex_name.to_upper()
	if n.contains("EXH"):
		return 2
	if n.contains("PROP"):
		return 3
	for k in ["CPU", "CPS", "CKP", "CANP", "PIL"]:
		if n.contains(k):
			return 1
	return 0


## Number of distinct palette indices, counting stops at `limit`.
static func _colour_count(src: PackedByteArray, limit: int) -> int:
	var seen := {}
	for v in src:
		if not seen.has(v):
			seen[v] = true
			if seen.size() >= limit:
				break
	return seen.size()


## Scale2x (EPX) on 8-bit palette indices: doubles the size and rounds the
## staircase edges of pixel art without inventing colours.
## Returns [pixels, w, h].
static func _scale2x(src: PackedByteArray, w: int, h: int) -> Array:
	var w2 := w * 2
	var out := PackedByteArray()
	out.resize(w2 * h * 2)
	for y in h:
		var row := y * w
		var up := (y - 1 if y > 0 else y) * w
		var dn := (y + 1 if y < h - 1 else y) * w
		for x in w:
			var p: int = src[row + x]
			var a: int = src[up + x]
			var b: int = src[row + (x + 1 if x < w - 1 else x)]
			var c: int = src[row + (x - 1 if x > 0 else x)]
			var d: int = src[dn + x]
			var e0 := p
			var e1 := p
			var e2 := p
			var e3 := p
			if b != c and a != d:
				if c == a:
					e0 = a
				if a == b:
					e1 = b
				if d == c:
					e2 = c
				if b == d:
					e3 = d
			var o := (y * 2) * w2 + x * 2
			out[o] = e0
			out[o + 1] = e1
			out[o + w2] = e2
			out[o + w2 + 1] = e3
	return [out, w2, h * 2]


func aabb() -> AABB:
	if vertices.is_empty():
		return AABB()
	var box := AABB(vertices[0], Vector3.ZERO)
	for v in vertices:
		box = box.expand(v)
	return box


## Raw gameplay chunk (e.g. "JETP" children) for future systems.
func object_chunk(path: Array):
	return Iff.find(object_chunks, path)
