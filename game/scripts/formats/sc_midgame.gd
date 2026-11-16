## Story cut-scenes (MIDGAMES/MIDn.PAK, MIDnVOC.PAK, MIDGAMES.IFF).
##
## MIDn.PAK holds the shots (shape files: 320 x 200 or 320 x 128 stills and
## multi-frame animations, origin at screen row 24) followed by partial
## palettes. MIDnVOC.PAK holds the recorded lines (VOC) and MIDGAMES.IFF the
## texts (FORM MGnn / FORM DATA and FORM SPOK / TEXT). The original staging -
## which palette goes with which shot, timing, pans - is compiled into
## OPTTEST.EXE, so this loader pairs each shot with the palette under which its
## picture is smoothest (smallest colour steps between neighbouring pixels).
extends RefCounted

const Art = preload("res://scripts/core/art.gd")
const Shape = preload("res://scripts/formats/sc_shape.gd")
const Pak = preload("res://scripts/formats/pak_archive.gd")
const Iff = preload("res://scripts/formats/iff.gd")
const Voc = preload("res://scripts/formats/voc.gd")

const ORIGIN := Vector2i(0, 24)
const CACHE := "user://midgame_palettes.json"

var number := 0
var shots := []       # [{ frames: [decoded], palette: PackedColorArray }]
var voices := []      # [AudioStreamWAV]
var texts := []       # spoken lines / captions in order
var titles := []      # on-screen titles (FORM DATA when there is no speech text)


static func exists(n: int) -> bool:
	return SCData.has("MIDGAMES/MID%d.PAK" % n) or SCData.has("MIDGAMES/MID%dVOC.PAK" % n)


static func load_number(n: int):
	var m = load("res://scripts/formats/sc_midgame.gd").new()
	m.number = n
	m._load()
	return m


func _load() -> void:
	var entries: Array = Pak.entries(SCData.read("MIDGAMES/MID%d.PAK" % number))
	var shapes := []
	var palettes := []
	for e in entries:
		if e.size() < 8:
			continue
		# Palettes may be stored raw or LZW packed; check both forms.
		if _is_palette(e):
			palettes.append(e)
			continue
		var raw := Shape.unpack(e)
		if _is_palette(raw):
			palettes.append(raw)
			continue
		var fr := Shape.frames(raw)
		if fr.is_empty():
			continue
		var decoded := []
		for f in fr:
			var d := Shape.decode(f)
			if not d.is_empty():
				decoded.append(d)
		# Only pictures that fill a good part of the screen: small overlays (muzzle
		# flashes etc.) were drawn over live 3D scenes or at positions we do not know.
		if not decoded.is_empty() and decoded[0].w >= 300 and _coverage(decoded) >= 0.15:
			shapes.append(decoded)
	# Palettes shared by all cut-scenes (MIDGAMES.PAK) are candidates too.
	for e in Pak.entries(SCData.read("MIDGAMES/MIDGAMES.PAK")):
		if _is_palette(e):
			palettes.append(e)
	var cands := _candidates(palettes)
	var cache := _read_cache()
	var key := str(number)
	var picks: Array = cache.get(key, [])
	if picks.size() != shapes.size():
		picks = []
		for s in shapes:
			picks.append(_best(s[0], cands))
		cache[key] = picks
		_write_cache(cache)
	for i in shapes.size():
		shots.append({"frames": shapes[i], "palette": cands[clampi(int(picks[i]), 0, cands.size() - 1)]})

	for e in Pak.entries(SCData.read("MIDGAMES/MID%dVOC.PAK" % number)):
		if e.size() > 26:
			var s := Voc.to_stream(e)
			if s != null:
				voices.append(s)
	_load_texts()


func _load_texts() -> void:
	var buf := SCData.read("MIDGAMES/MIDGAMES.IFF")
	var mg = Iff.find(Iff.parse(buf), ["FORM:MG%02d" % number])
	if mg == null:
		return
	for part in mg.children:
		var lines := []
		for t in Iff.find_all(part.children, "TEXT"):
			var s := Iff.cstr(buf, t.off, t.size).replace("\n", " ").strip_edges()
			while s.contains("  "):
				s = s.replace("  ", " ")
			if s != "":
				lines.append(s)
		if part.id == "FORM:SPOK" or (part.id == "FORM:DATA" and not voices.is_empty()):
			texts.append_array(lines)
		else:
			titles.append_array(lines)


## Largest share of the 320 x 200 screen covered by one of the first frames.
static func _coverage(frames: Array) -> float:
	var best := 0
	for k in mini(frames.size(), 8):
		var n := 0
		for m in frames[k].mask:
			n += m
		best = maxi(best, n)
	return best / 64000.0


static func _is_palette(b: PackedByteArray) -> bool:
	if b.size() < 7:
		return false
	var first := b.decode_u16(0)
	var count := b.decode_u16(2)
	return count > 0 and first + count <= 256 and b.size() == 4 + count * 3


# --- palette matching --------------------------------------------------------------

func _candidates(palettes: Array) -> Array:
	var base: PackedColorArray = SCData.palette()
	var out := [base]
	var parts := []
	for p in palettes:
		var full: bool = p.decode_u16(0) == 0 and p.decode_u16(2) == 256
		out.append(Shape.apply_palette(base, p))
		if not full:
			parts.append(p)
	for a in parts:
		for b in parts:
			if a != b and a.decode_u16(0) != b.decode_u16(0):
				out.append(Shape.apply_palette(Shape.apply_palette(base, a), b))
	return out


## Index of the candidate palette with the smallest mean colour step between
## horizontal neighbours (sampled every 3rd row and column for speed).
static func _best(d: Dictionary, cands: Array) -> int:
	var best := 0
	var best_score := INF
	var px: PackedByteArray = d.pixels
	var mk: PackedByteArray = d.mask
	for c in cands.size():
		var pal: PackedColorArray = cands[c]
		var total := 0.0
		var n := 0
		for y in range(0, d.h, 3):
			for x in range(0, d.w - 1, 3):
				var i: int = y * d.w + x
				if mk[i] == 0 or mk[i + 1] == 0:
					continue
				var a: Color = pal[px[i]]
				var b: Color = pal[px[i + 1]]
				total += absf(a.r - b.r) + absf(a.g - b.g) + absf(a.b - b.b)
				n += 1
		var score := total / maxf(1.0, n)
		if score < best_score:
			best_score = score
			best = c
	return best


static func _read_cache() -> Dictionary:
	var f := FileAccess.open(CACHE, FileAccess.READ)
	if f == null:
		return {}
	var d = JSON.parse_string(f.get_as_text())
	return d if d is Dictionary else {}


static func _write_cache(d: Dictionary) -> void:
	var f := FileAccess.open(CACHE, FileAccess.WRITE)
	if f != null:
		f.store_string(JSON.stringify(d))
