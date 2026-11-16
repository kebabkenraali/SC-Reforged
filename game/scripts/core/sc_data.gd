## Autoload "SCData": locates the user's original Strike Commander install and
## exposes its archives as one virtual file system. The engine ships no game
## content; every asset is read on demand from the original files.
extends Node

const ByteSource = preload("res://scripts/formats/byte_source.gd")
const IsoImage = preload("res://scripts/formats/iso_image.gd")
const Tre = preload("res://scripts/formats/tre_archive.gd")
const Iff = preload("res://scripts/formats/iff.gd")
const Palette = preload("res://scripts/formats/sc_palette.gd")
const RealSpaceModel = preload("res://scripts/formats/realspace_model.gd")
const Terrain = preload("res://scripts/formats/sc_terrain.gd")
const Mission = preload("res://scripts/formats/sc_mission.gd")
const Pak = preload("res://scripts/formats/pak_archive.gd")
const Lzw = preload("res://scripts/formats/lzw.gd")
const Voc = preload("res://scripts/formats/voc.gd")

const CD_IMAGES := ["SC.dat", "SC.iso", "STRIKE.iso", "SC.cue"]
const CANDIDATE_DIRS := [
	"C:/Gog games/Strike Commander",
	"C:/GOG Games/Strike Commander",
	"D:/GOG Games/Strike Commander",
	"C:/Program Files (x86)/GOG Galaxy/Games/Strike Commander",
	"C:/Program Files (x86)/GOG.com/Strike Commander",
	"C:/Program Files/GOG Galaxy/Games/Strike Commander",
]
## A file that only exists in the genuine data, used to validate the install.
const REQUIRED_ASSET := "OBJECTS/F-16DES.IFF"

signal mounted

var game_dir := ""
var iso
var files := {}           # normalized name -> [source, offset, size]
var _palettes := {}
var _models := {}
var _world_palettes := {}
var _missions := []
var _radio := {}
var _speech_banks: Array = []    # INTEL/SPEECH.PAK entries (one nested PAK per actor bank)
var _speech_entries := {}        # bank -> its entries
var _voice_cache := {}           # "bank:id" -> AudioStreamWAV or null
var _sfx_cache := {}
var _sfx_raw: Array = []


func is_mounted() -> bool:
	return files.has(REQUIRED_ASSET)


## Tries the saved path, then common install locations.
func auto_mount() -> bool:
	var saved: String = Settings.get_value("data", "game_dir", "")
	for d in [saved] + CANDIDATE_DIRS:
		if d != "" and mount(d) == "":
			return true
	return false


## Mounts an install directory. Returns "" on success or an error message.
func mount(dir: String) -> String:
	dir = dir.replace("\\", "/").rstrip("/")
	if not DirAccess.dir_exists_absolute(dir):
		return "Folder not found: %s" % dir
	files.clear()
	_palettes.clear()
	_models.clear()
	_world_palettes.clear()
	_missions.clear()
	iso = null

	var image_path := ""
	for f in CD_IMAGES:
		if FileAccess.file_exists(dir + "/" + f) and not f.ends_with(".cue"):
			image_path = dir + "/" + f
			break
	if image_path == "":
		return "CD image (SC.dat) not found in this folder. Strike Commander CD-ROM Edition is required (e.g. GOG)."
	var img = IsoImage.new()
	if img.open(image_path) != OK:
		return "Could not read the CD image: %s" % image_path
	iso = img

	# Loose files in the CD root (terrain PAKs etc.).
	for n in img.files:
		if not "/" in n:
			files[n] = [img.file_source(n), 0, img.files[n][1]]
	# Archive search order follows SC.CFG: liltre, bigtre, voclist (first wins).
	for tre_name in ["VOCLIST.TRE", "BIGTRE.TRE"]:
		var src = img.file_source(tre_name)
		if src != null:
			files.merge(Tre.index(src), true)
	var lil = ByteSource.open_file(dir + "/LILTRE.TRE")
	if lil == null:
		lil = img.file_source("LILTRE.TRE")
	if lil != null:
		files.merge(Tre.index(lil), true)
	# Loose files next to the image override CD contents (patched installs).
	var da := DirAccess.open(dir)
	if da != null:
		for f in da.get_files():
			if f.get_extension().to_upper() in ["PAK", "IFF"]:
				var s = ByteSource.open_file(dir + "/" + f)
				if s != null:
					files[f.to_upper()] = [s, 0, s.size()]

	if not is_mounted():
		files.clear()
		return "The data found does not look like the original Strike Commander (%s is missing)." % REQUIRED_ASSET
	game_dir = dir
	Settings.set_value("data", "game_dir", dir)
	mounted.emit()
	return ""


func has(name: String) -> bool:
	return files.has(name.to_upper())


func read(name: String) -> PackedByteArray:
	var e = files.get(name.to_upper())
	if e == null:
		return PackedByteArray()
	return e[0].read(e[1], e[2])


func list(prefix: String, extension := "") -> PackedStringArray:
	var out := PackedStringArray()
	prefix = prefix.to_upper()
	for n in files:
		if n.begins_with(prefix) and (extension == "" or n.ends_with(extension.to_upper())):
			out.append(n)
	out.sort()
	return out


func palette(name := "PALETTE/PALETTE.IFF") -> PackedColorArray:
	if not _palettes.has(name):
		var buf := read(name)
		_palettes[name] = Palette.from_iff(buf) if buf.size() > 0 else Palette.grayscale()
	return _palettes[name]


func model(name: String):
	if not _models.has(name):
		var buf := read(name)
		_models[name] = RealSpaceModel.load_from(buf, name) if buf.size() > 0 else null
	return _models[name]


## Terrain areas present in the CD root.
func terrain_names() -> PackedStringArray:
	var out := PackedStringArray()
	for n in files:
		if n.ends_with(".PAK") and not "/" in n:
			var e = files[n]
			var head: PackedByteArray = e[0].read(e[1], 8)
			if head.size() < 8:
				continue
			var first := head.decode_u32(4) & 0xFFFFFF
			var form: PackedByteArray = e[0].read(e[1] + first, 12)
			if form.size() == 12 and form.slice(8, 12).get_string_from_ascii() == "TERA":
				out.append(n.get_basename())
	out.sort()
	return out


func terrain(area: String):
	var buf := read(area + ".PAK")
	return Terrain.load_from(buf, area) if buf.size() > 0 else null


## Palette a terrain area uses, found from the mission files (WRLD/TERA + PALT).
func world_palette(area: String) -> String:
	if _world_palettes.is_empty():
		for m in list("MISSIONS/", ".IFF"):
			var buf := read(m)
			var nodes := Iff.parse(buf)
			var tera = Iff.find(nodes, ["FORM:WRLD", "TERA"])
			var palt = Iff.find(nodes, ["FORM:WRLD", "PALT"])
			if tera != null and palt != null:
				var t := Iff.cstr(buf, tera.off, 8).to_upper()
				if not _world_palettes.has(t):
					_world_palettes[t] = "PALETTE/%s.IFF" % Iff.cstr(buf, palt.off, 8).to_upper()
	var p: String = _world_palettes.get(area.to_upper(), "PALETTE/PALETTE.IFF")
	return p if has(p) else "PALETTE/PALETTE.IFF"


func mission(name: String):
	var buf := read(name)
	return Mission.load_from(buf, name) if buf.size() > 0 else null


## Playable missions: [{ file, name, area }], only those whose terrain exists.
func missions() -> Array:
	if _missions.is_empty():
		var areas := terrain_names()
		for f in list("MISSIONS/", ".IFF"):
			var m = mission(f)
			if m != null and m.area in areas and m.player_part() != null:
				_missions.append({"file": f, "name": m.name, "area": m.area})
	return _missions


## Radio messages of a mission actor (INTEL/<NAME>.IFF, FORM PROF / FORM RADI):
## INFO holds the call sign, MSGS is a list of (u8 id, zero-terminated text).
func radio(actor: String) -> Dictionary:
	if _radio.has(actor):
		return _radio[actor]
	var out := {"speaker": actor.capitalize(), "msgs": {}, "spch": -1}
	var buf := read("INTEL/%s.IFF" % actor.to_upper())
	if buf.size() > 0:
		var nodes := Iff.parse(buf)
		var spch = Iff.find(nodes, ["FORM:PROF", "FORM:RADI", "SPCH"])
		if spch != null and spch.size >= 1:
			out.spch = buf[spch.off]
		var info = Iff.find(nodes, ["FORM:PROF", "FORM:RADI", "INFO"])
		if info != null and info.size > 3:
			var parts := Iff.data(buf, info).slice(2)
			var strings := []
			var start := 0
			for i in parts.size():
				if parts[i] == 0:
					if i > start:
						strings.append(parts.slice(start, i).get_string_from_ascii())
					start = i + 1
			if not strings.is_empty():
				out.speaker = strings[-1]
		var msgs = Iff.find(nodes, ["FORM:PROF", "FORM:RADI", "MSGS"])
		if msgs != null:
			var i: int = msgs.off
			var end: int = msgs.off + msgs.size
			while i < end:
				var id := buf[i]
				var j := i + 1
				while j < end and buf[j] != 0:
					j += 1
				out.msgs[id] = buf.slice(i + 1, j).get_string_from_ascii().replace("\n", " ")
				i = j + 1
	_radio[actor] = out
	return out


## Recorded voice of radio message `id` of an INTEL profile, or null.
## RADI/SPCH (1 byte) picks the actor's bank in INTEL/SPEECH.PAK; a bank is a
## nested PAK whose entry index is the MSGS id (missing lines are empty
## entries). Entries are VOC files, most LZW packed (u32 size + LZW) like
## SOUND/DSOUNDFX.PAK.
func radio_voice(actor: String, id: int) -> AudioStreamWAV:
	var r: Dictionary = radio(actor)
	var bank: int = r.get("spch", -1)
	if bank < 0:
		return null
	var key := "%d:%d" % [bank, id]
	if _voice_cache.has(key):
		return _voice_cache[key]
	if _speech_banks.is_empty():
		_speech_banks = Pak.entries(read("INTEL/SPEECH.PAK"))
	var stream: AudioStreamWAV = null
	if bank < _speech_banks.size():
		if not _speech_entries.has(bank):
			_speech_entries[bank] = Pak.entries(_speech_banks[bank])
		var lines: Array = _speech_entries[bank]
		if id >= 0 and id < lines.size() and lines[id].size() > 8:
			var e: PackedByteArray = lines[id]
			var voc := e if e.slice(0, 4).get_string_from_ascii() == "Crea" else Lzw.decode(e, 4, e.decode_u32(0))
			if voc.size() > 26:
				stream = Voc.to_stream(voc)
	_voice_cache[key] = stream
	return stream


## Number of sound effects in SOUND/DSOUNDFX.PAK (a PAK holding one nested PAK
## of VOC files; most are LZW packed: u32 size + LZW).
func sfx_count() -> int:
	return _sfx_entries().size()


## Sound effect `index` as an AudioStreamWAV (cached), or null.
func sfx(index: int, loop := false) -> AudioStreamWAV:
	var key := "%d:%s" % [index, loop]
	if _sfx_cache.has(key):
		return _sfx_cache[key]
	var entries := _sfx_entries()
	var stream: AudioStreamWAV = null
	if index >= 0 and index < entries.size() and entries[index].size() > 8:
		var e: PackedByteArray = entries[index]
		var voc := e if e.slice(0, 4).get_string_from_ascii() == "Crea" else Lzw.decode(e, 4, e.decode_u32(0))
		stream = Voc.to_stream(voc, loop)
	_sfx_cache[key] = stream
	return stream


func _sfx_entries() -> Array:
	if _sfx_raw.is_empty():
		var outer := Pak.entries(read("SOUND/DSOUNDFX.PAK"))
		if not outer.is_empty():
			_sfx_raw = Pak.entries(outer[0])
	return _sfx_raw
