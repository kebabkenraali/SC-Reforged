## Mission file (MISSIONS/*.IFF, FORM MISN).
##
## Coordinates are i32 fixed point 24.8 in feet: x = east, y = north, z = up,
## origin at the centre of the terrain area. Godot: (x, z, -y) * 0.3048.
##
##   NAME   mission name           FORM WRLD / FILE   terrain area ("rhodei")
##   AREA   records: u8 type, char name[32], x @33, y @37, z @41, then by type:
##          'S' radius @45 (49 bytes), 'B' 5 dims @45.. (65), 'C' height @45, radius @49 (53)
##   CAST   n * 9: actor names; the index of "PLAYER" is the player's part id
##   MSGS   zero-separated waypoint / objective texts
##   PART   n * 62: u16 id, char model[8], char destroyed[8], char loadout[8],
##          i16 area @26 (-1 = absolute), u8 side @28, x @29, y @33, z @37
##          (relative to the area), u16 heading @41 (degrees), u16 speed @43 (knots),
##          i16 formation leader id @46, i16 offset x/y/z @48 (ft),
##          i16 script blocks @54 start, @56 AI, @58 destroyed, @60 route
##   SPOT   n * 14: i16 area, i32 x, y, z (24.8 ft, relative to the area)
##   PROG   bytecode of 2-byte instructions (op, arg); blocks end with 00 00
##   FORM PLAY / SCNE  scenes: u8, i16 area @1, i16 blocks @3 (on enter) @5 @7,
##          u8 @9 (1 = position follows), then u16 PART indices from @24
##
## Known PROG opcodes (decoded from usage, the conditional ops 45..4f are not):
##   a5 / a6 n  waypoint at SPOT n      ab n   text MSGS[n] for the waypoint / radio
##   a7 id      attack PART id          aa id  follow / escort PART id
##   90 id      activate PART id        55 n   set flag n
extends RefCounted

const Iff = preload("res://scripts/formats/iff.gd")

const FEET := 0.3048
## AREA record size per type byte: 'S' sphere 49, 'B' box 65 (x,y,z + 5 dims),
## 'C' cylinder 53 (x,y,z + height @45 + radius @49).
const AREA_SIZE := {0x53: 49, 0x42: 65, 0x43: 53}

var file := ""
var name := ""
var info := ""
var area := ""              # terrain area, upper case (e.g. "RHODEI")
var areas := []             # [{ name, pos: Vector3 (m), radius (m) }]
var parts := []             # [{ id, model, destroyed, loadout, area, side, pos, heading, speed }]
var cast := PackedStringArray()
var messages := PackedStringArray()
var player_id := -1
var spots := []             # [Vector3] navigation points (m)
var blocks := []            # PROG blocks: [[[op, arg], ...], ...]
var scenes := []            # [{ area, on_enter: [block], parts: [part index] }]


static func load_from(buf: PackedByteArray, file_name := ""):
	var m = load("res://scripts/formats/sc_mission.gd").new()
	m.file = file_name
	if not m._parse(buf):
		return null
	return m


static func fixed(buf: PackedByteArray, off: int) -> float:
	return buf.decode_s32(off) / 256.0


static func to_godot(x_ft: float, y_ft: float, z_ft: float) -> Vector3:
	return Vector3(x_ft, z_ft, -y_ft) * FEET


func _parse(buf: PackedByteArray) -> bool:
	var nodes := Iff.parse(buf)
	var root = Iff.find(nodes, ["FORM:MISN"])
	if root == null:
		return false
	var c: Array = root.children
	var wrld = Iff.find(c, ["FORM:WRLD", "FILE"])
	if wrld == null:
		return false
	area = Iff.cstr(buf, wrld.off, wrld.size).to_upper()
	var n = Iff.find(c, ["NAME"])
	if n != null:
		name = Iff.cstr(buf, n.off, n.size)
	var inf = Iff.find(c, ["INFO"])
	if inf != null:
		info = Iff.cstr(buf, inf.off, inf.size)
	if name == "":
		name = file.get_file().get_basename()

	# AREA records have a type-dependent size (checked against all 52
	# missions: every chunk is consumed exactly). Reading every record as 49
	# bytes shifted all areas after the first 'B'/'C' one (MISN-1A lost
	# Cargo Destination, Nouakchott and Rendezvous -> SPOTs at the origin).
	var ar = Iff.find(c, ["AREA"])
	if ar != null:
		var o: int = ar.off
		var end: int = ar.off + ar.size
		while o + 49 <= end:
			var t: int = buf[o]
			var rec: int = AREA_SIZE.get(t, 49)
			# radius: 'S' / 'B' fixed @45 (the old u16 @46 read the same value),
			# 'C' (cylinder) fixed @49, with its height at @45.
			var r_off: int = 49 if t == 0x43 else 45
			areas.append({"name": Iff.cstr(buf, o + 1, 32), "type": char(t) if t >= 32 else "?",
				"pos": to_godot(fixed(buf, o + 33), fixed(buf, o + 37), fixed(buf, o + 41)),
				"radius": fixed(buf, o + r_off) * FEET})
			o += rec

	var ca = Iff.find(c, ["CAST"])
	if ca != null:
		for i in ca.size / 9:
			cast.append(Iff.cstr(buf, ca.off + i * 9, 9))
	player_id = cast.find("PLAYER")

	var ms = Iff.find(c, ["MSGS"])
	if ms != null:
		var start: int = ms.off
		for i in range(ms.off, ms.off + ms.size):
			if buf[i] == 0:
				if i > start:
					messages.append(buf.slice(start, i).get_string_from_ascii().replace("\n", " "))
				start = i + 1

	var pa = Iff.find(c, ["PART"])
	if pa != null:
		for i in pa.size / 62:
			var o: int = pa.off + i * 62
			var area_idx := buf.decode_s16(o + 26)
			var rel := to_godot(fixed(buf, o + 29), fixed(buf, o + 33), fixed(buf, o + 37))
			var base := Vector3.ZERO
			if area_idx >= 0 and area_idx < areas.size():
				base = areas[area_idx].pos
			parts.append({"id": buf.decode_u16(o), "model": Iff.cstr(buf, o + 2, 8),
				"destroyed": Iff.cstr(buf, o + 10, 8), "loadout": Iff.cstr(buf, o + 18, 8),
				"area": area_idx, "side": buf[o + 28],
				"pos": base + rel, "relative_alt": area_idx >= 0,
				"heading": buf.decode_u16(o + 41), "speed": buf.decode_u16(o + 43),
				"leader": buf.decode_s16(o + 46),
				"offset": Vector3(buf.decode_s16(o + 48), buf.decode_s16(o + 52), -buf.decode_s16(o + 50)) * FEET,
				"slots": [buf.decode_s16(o + 54), buf.decode_s16(o + 56), buf.decode_s16(o + 58), buf.decode_s16(o + 60)]})

	var sp = Iff.find(c, ["SPOT"])
	if sp != null:
		for i in sp.size / 14:
			var o: int = sp.off + i * 14
			var a := buf.decode_s16(o)
			var rel := to_godot(fixed(buf, o + 2), fixed(buf, o + 6), fixed(buf, o + 10))
			spots.append((areas[a].pos if a >= 0 and a < areas.size() else Vector3.ZERO) + rel)

	var pr = Iff.find(c, ["PROG"])
	if pr != null:
		var cur := []
		for i in range(pr.off, pr.off + pr.size - 1, 2):
			if buf[i] == 0 and buf[i + 1] == 0:
				blocks.append(cur)
				cur = []
			else:
				cur.append([buf[i], buf[i + 1]])
		if not cur.is_empty():
			blocks.append(cur)

	var play = Iff.find(c, ["FORM:PLAY"])
	if play != null:
		for sc in Iff.find_all(play.children, "SCNE"):
			var o: int = sc.off
			var sc_parts := []
			if sc.size >= 24 and buf[o + 9] == 0:
				for k in (sc.size - 24) / 2:
					sc_parts.append(buf.decode_u16(o + 24 + k * 2))
			var enter := []
			for off in [3, 7]:
				var b := buf.decode_s16(o + off)
				if b >= 0:
					enter.append(b)
			scenes.append({"area": buf.decode_s16(o + 1), "on_enter": enter, "parts": sc_parts})
	return true


func block(i: int) -> Array:
	return blocks[i] if i >= 0 and i < blocks.size() else []


## Arguments of every `op` in a block, in order.
func block_args(i: int, op: int) -> Array:
	var out := []
	for ins in block(i):
		if ins[0] == op:
			out.append(ins[1])
	return out


## Player route from the route block: [{ pos, label }]. a5/a6 name a SPOT,
## the following ab gives its MSGS text.
func nav_plan() -> Array:
	var p = player_part()
	if p == null:
		return []
	var out := []
	for ins in block(p.slots[3]):
		if (ins[0] == 0xa5 or ins[0] == 0xa6) and ins[1] < spots.size():
			out.append({"pos": spots[ins[1]], "label": ""})
		elif ins[0] == 0xab and not out.is_empty() and out[-1].label == "" and ins[1] < messages.size():
			out[-1].label = messages[ins[1]]
	return out


## Gameplay route; preserves the IFF route except for MISN-1A's recommended
## Nouakchott-first tactic.
func flight_nav_plan() -> Array:
	var plan: Array = nav_plan()
	if file.get_file().get_basename().to_upper() != "MISN-1A":
		return plan

	var cargo_index := -1
	var nouakchott_index := -1
	for i in plan.size():
		var label: String = str(plan[i].get("label", "")).to_lower()
		if cargo_index < 0 and label == "land cargo":
			cargo_index = i
		elif nouakchott_index < 0 and label == "scenic nouakchott":
			nouakchott_index = i

	if cargo_index < 0 or nouakchott_index < 0:
		push_warning("MISN-1A route override could not find Cargo Destination and Nouakchott waypoints.")
		return plan

	var cargo = plan[cargo_index]
	plan[cargo_index] = plan[nouakchott_index]
	plan[nouakchott_index] = cargo
	return plan


## Parts that are only brought in by an "activate" (90) instruction.
func dormant_part_indices() -> Array:
	var in_scene := {}
	for sc in scenes:
		for i in sc.parts:
			in_scene[i] = true
	var activated_ids := {}
	for b in blocks.size():
		for id in block_args(b, 0x90):
			activated_ids[id] = true
	var out := []
	for i in parts.size():
		if not in_scene.has(i) and activated_ids.has(parts[i].id):
			out.append(i)
	return out


func part_index(id: int) -> int:
	for i in parts.size():
		if parts[i].id == id:
			return i
	return -1


func player_part():
	for p in parts:
		if p.id == player_id:
			return p
	return null
