## ISO 9660 reader for the Strike Commander CD image (GOG ships it as SC.dat,
## a raw 2352-byte/sector Mode 1 image). Plain 2048-byte .iso files work too.
extends RefCounted

const SYNC := [0x00, 0xFF, 0xFF, 0xFF, 0xFF, 0xFF, 0xFF, 0xFF, 0xFF, 0xFF, 0xFF, 0x00]
const LOGICAL := 2048

var path := ""
var sector_size := LOGICAL
var data_offset := 0
## Upper-case path without leading slash -> [logical_offset, size]
var files := {}
var _file: FileAccess


func open(image_path: String) -> Error:
	path = image_path
	_file = FileAccess.open(image_path, FileAccess.READ)
	if _file == null:
		return FileAccess.get_open_error()
	var head := _file.get_buffer(16)
	var raw := head.size() == 16
	for i in SYNC.size():
		if not raw or head[i] != SYNC[i]:
			raw = false
			break
	if raw:
		sector_size = 2352
		data_offset = 24 if head[15] == 2 else 16
	var pvd := read(16 * LOGICAL, LOGICAL)
	if pvd.size() < LOGICAL or pvd.slice(1, 6).get_string_from_ascii() != "CD001":
		return ERR_FILE_UNRECOGNIZED
	var root := pvd.slice(156, 156 + 34)
	_walk(root.decode_u32(2), root.decode_u32(10), "")
	return OK


func _walk(lba: int, size: int, prefix: String) -> void:
	var dir := read(lba * LOGICAL, size)
	var i := 0
	while i < dir.size():
		var rec_len := dir[i]
		if rec_len == 0:
			i = (i / LOGICAL + 1) * LOGICAL
			continue
		var name_len := dir[i + 32]
		var name := dir.slice(i + 33, i + 33 + name_len).get_string_from_ascii()
		if name_len == 1 and dir[i + 33] <= 1:
			i += rec_len
			continue
		name = name.split(";")[0].to_upper()
		var elba := dir.decode_u32(i + 2)
		var esize := dir.decode_u32(i + 10)
		if dir[i + 25] & 2:
			_walk(elba, esize, prefix + name + "/")
		else:
			files[prefix + name] = [elba * LOGICAL, esize]
		i += rec_len


func has_file(name: String) -> bool:
	return files.has(name.to_upper())


## Reads `length` bytes at a logical (2048-byte sector space) offset.
func read(offset: int, length: int) -> PackedByteArray:
	if sector_size == LOGICAL:
		_file.seek(offset)
		return _file.get_buffer(length)
	var out := PackedByteArray()
	var first := offset / LOGICAL
	var last := (offset + length - 1) / LOGICAL
	_file.seek(first * sector_size)
	var raw := _file.get_buffer((last - first + 1) * sector_size)
	for s in range(last - first + 1):
		var base := s * sector_size + data_offset
		if base >= raw.size():
			break
		out.append_array(raw.slice(base, base + LOGICAL))
	var skip := offset - first * LOGICAL
	return out.slice(skip, skip + length)


## Byte source view of one file inside the image.
func file_source(name: String):
	var e = files.get(name.to_upper())
	if e == null:
		return null
	var src = load("res://scripts/formats/iso_file_source.gd").new()
	src.iso = self
	src.base = e[0]
	src.length = e[1]
	src.path = path + ":" + name
	return src
