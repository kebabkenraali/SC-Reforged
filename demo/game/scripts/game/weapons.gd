## Weapon data. Loadouts and ground-weapon ranges come from the original
## objects (JETP/WEAP/WPNS, SWPN/DATA); flight characteristics of guided
## missiles are tuned here because their DYNM data is not decoded yet.
extends RefCounted

const FEET := 0.3048

## name -> guided missile parameters (speeds m/s, ranges m, turn rad/s)
const MISSILES := {
	"SWINDERM": {"label": "AIM-9", "speed": 650.0, "range": 7000.0, "turn": 0.55, "life": 18.0,
		"damage": 70.0, "seeker": "ir", "model": "OBJECTS/SWINDERM.IFF"},
	"SWINDERJ": {"label": "AIM-9J", "speed": 600.0, "range": 5500.0, "turn": 0.45, "life": 12.0,
		"damage": 65.0, "seeker": "ir", "model": "OBJECTS/SWINDERJ.IFF"},
	"AMRAAM": {"label": "AIM-120", "speed": 900.0, "range": 16000.0, "turn": 0.4, "life": 22.0,
		"damage": 80.0, "seeker": "radar", "model": "OBJECTS/AMRAAM.IFF"},
	"SA2": {"label": "SA-2", "speed": 700.0, "range": 9000.0, "turn": 0.32, "life": 20.0,
		"damage": 90.0, "seeker": "radar", "model": "OBJECTS/SA2.IFF"},
	"SA6": {"label": "SA-6", "speed": 750.0, "range": 8000.0, "turn": 0.45, "life": 18.0,
		"damage": 80.0, "seeker": "radar", "model": "OBJECTS/SA6.IFF"},
	# Air-to-ground: damage and blast radius are replaced by the original WDAT values.
	"AGM-65D": {"label": "AGM-65", "speed": 340.0, "range": 10000.0, "turn": 0.6, "life": 40.0,
		"damage": 250.0, "blast": 12.0, "seeker": "tv", "ground": true, "model": "OBJECTS/AGM-65D.IFF"},
}

## Unguided bombs; damage / blast radius come from the original WDAT.
const BOMBS := {
	"MK82": {"label": "MK-82", "damage": 350.0, "blast": 23.0, "drag": 0.004, "model": "OBJECTS/MK82.IFF"},
	"MK20": {"label": "MK-20", "damage": 100.0, "blast": 61.0, "drag": 0.006, "model": "OBJECTS/MK20.IFF"},
	"DURANDAL": {"label": "DURANDAL", "damage": 195.0, "blast": 15.0, "drag": 0.01, "model": "OBJECTS/DURANDAL.IFF"},
}

## Player weapon modes, cycled with "weapon_select".
const MODES := ["air", "agm", "bomb"]
const MODE_LABELS := {"air": "AIR", "agm": "AGM", "bomb": "BOMB"}

## Chance that one countermeasure decoys a missile of the given seeker type.
## The manual's doctrine: decoys distract (they even steer the AIM-9 at the
## sun), but a competent launch usually still connects - hence low odds and
## only inside the very last stretch of flight.
const DECOY_CHANCE := {"ir": 0.30, "radar": 0.15}


static func is_missile(name: String) -> bool:
	return MISSILES.has(name)


## Original "Kill Number" damage model (Playtester's Guide pp. 86-96): every
## aircraft needs a specific number of damage points before it comes apart.
## The tables are printed per aircraft in the guide; values we could not read
## fall back to a class default. Sides differ only for the F-16 in the guide.
const AIR_KILL_NUMBERS := {
	"MIG21": 22, "MIG21EW": 22, "MIG29": 31, "MIG29GRA": 31, "MIG25": 60,
	"MIRAGE": 27, "F15": 37, "F4": 42, "A10": 47, "TORNCG": 39, "SU27": 40,
	"F18": 40, "C130": 90, "E3": 140, "747": 250, "LEARJET": 20, "L-1011": 250,
}

## Returns the aircraft's total damage resistance by its model name.
## `team` 1 = player/allied side, 2 = enemy (used where the guide gives
## different values, e.g. the F-16: 77 as a friend, 36 as an enemy).
static func kill_number(model_name: String, team := 0) -> int:
	var base: String = model_name.get_file().get_basename().to_upper().replace(".IFF", "")
	if base in AIR_KILL_NUMBERS:
		return AIR_KILL_NUMBERS[base]
	for suffix in ["DES", "GRAY", "GRA", "EW", "DEF", "EARLY"]:
		if base.ends_with(suffix) and base.substr(0, base.length() - suffix.length()) in AIR_KILL_NUMBERS:
			return AIR_KILL_NUMBERS[base.substr(0, base.length() - suffix.length())]
	return 100


static func missile(name: String) -> Dictionary:
	return MISSILES.get(name, MISSILES.SWINDERM)


static func is_bomb(name: String) -> bool:
	return BOMBS.has(name)


## Which player mode a store belongs to.
static func mode_of(name: String) -> String:
	if is_bomb(name):
		return "bomb"
	return "agm" if MISSILES.get(name, {}).get("ground", false) else "air"


static func label(name: String) -> String:
	return (BOMBS[name] if is_bomb(name) else missile(name)).label


## Original WDAT of a weapon object: u16 damage @0, u16 blast radius (ft) @2.
## Overrides the table values when the object exists in the data.
static func apply_wdat(spec: Dictionary, model) -> Dictionary:
	if model == null:
		return spec
	for form in ["FORM:BOMB", "FORM:MISS", "FORM:DURD"]:
		var w = model.object_chunk([form, "WDAT"])
		if w != null and w.size >= 4:
			var out := spec.duplicate()
			out.damage = float(model.buffer.decode_u16(w.off))
			out.blast = maxf(model.buffer.decode_u16(w.off + 2) * FEET, 5.0)
			return out
	return spec


## Structural strength of an object from its OBJT DAMG chunk (0 = unknown).
static func strength(model) -> float:
	for c in model.object_chunks:
		if c.id.begins_with("FORM:"):
			for k in c.children:
				if k.id == "DAMG" and k.size >= 2:
					return float(model.buffer.decode_u16(k.off))
	return 0.0


## Aircraft loadout from FORM JETP / FORM WEAP / WPNS: n * (u16 count, char name[8]).
static func loadout(model) -> Dictionary:
	var out := {}
	var wpns = model.object_chunk(["FORM:JETP", "FORM:WEAP", "WPNS"])
	if wpns == null:
		return out
	var buf: PackedByteArray = model.buffer
	var o: int = wpns.off
	while o + 10 <= wpns.off + wpns.size:
		var count := buf.decode_u16(o)
		var name := _cstr(buf, o + 2, 8).to_upper()
		if (is_missile(name) or is_bomb(name)) and count > 0:
			out[name] = out.get(name, 0) + count
		o += 10
	return out


## Ground weapon from FORM SWPN / DATA: u32 @0 (ammo for launchers), u32 range
## @4 (ft), u32 ceiling @8 (ft), weapon name @21.
static func ground_weapon(model) -> Dictionary:
	var data = model.object_chunk(["FORM:SWPN", "DATA"])
	if data == null or data.size < 24:
		return {}
	var buf: PackedByteArray = model.buffer
	var o: int = data.off
	var name := _cstr(buf, o + 21, data.size - 21).to_upper()
	var w := {"name": name, "range": buf.decode_u32(o + 4) * FEET,
		"ceiling": buf.decode_u32(o + 8) * FEET, "ammo": buf.decode_u32(o)}
	w["missile"] = is_missile(name)
	if w.missile:
		# Launchers: interpreted ceiling is low for SAMs; use the missile's reach.
		w.range = maxf(w.range, missile(name).range)
		w.ceiling = maxf(w.ceiling * 3.0, 6000.0)
		w.ammo = clampi(w.ammo, 1, 8)
	return w


static func _cstr(buf: PackedByteArray, off: int, maxlen: int) -> String:
	var e := off
	while e < off + maxlen and e < buf.size() and buf[e] >= 32:
		e += 1
	return buf.slice(off, e).get_string_from_ascii()
