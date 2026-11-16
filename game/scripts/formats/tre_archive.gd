## Origin TRE archive: u32 count, u32 data start, then 74-byte entries
## (u8 flag, char name[65], u32 offset, u32 size).
extends RefCounted

const ENTRY_SIZE := 74


## Returns { "OBJECTS/F-16DES.IFF": [source, offset, size], ... }
static func index(source) -> Dictionary:
	var out := {}
	var head: PackedByteArray = source.read(0, 8)
	if head.size() < 8:
		return out
	var count := head.decode_u32(0)
	if count == 0 or count > 100000:
		return out
	var table: PackedByteArray = source.read(8, count * ENTRY_SIZE)
	for i in count:
		var e := i * ENTRY_SIZE
		var name := table.slice(e + 1, e + 66).get_string_from_ascii()
		out[normalize(name)] = [source, table.decode_u32(e + 66), table.decode_u32(e + 70)]
	return out


## "..\..\DATA\OBJECTS\F-16DES.IFF" -> "OBJECTS/F-16DES.IFF"
static func normalize(name: String) -> String:
	var n := name.replace("\\", "/").to_upper()
	while n.begins_with("../"):
		n = n.substr(3)
	if n.begins_with("DATA/"):
		n = n.substr(5)
	return n
