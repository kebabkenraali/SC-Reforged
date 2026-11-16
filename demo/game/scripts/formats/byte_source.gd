## Random-access byte source. Archives are read in place from the user's
## original game installation; nothing is extracted or copied.
extends RefCounted

var _file: FileAccess
var path := ""


static func open_file(file_path: String):
	var f := FileAccess.open(file_path, FileAccess.READ)
	if f == null:
		return null
	var s = load("res://scripts/formats/byte_source.gd").new()
	s._file = f
	s.path = file_path
	return s


func size() -> int:
	return _file.get_length()


func read(offset: int, length: int) -> PackedByteArray:
	_file.seek(offset)
	return _file.get_buffer(length)
