## Byte source for a single file stored inside an ISO image.
extends RefCounted

var iso
var base := 0
var length := 0
var path := ""


func size() -> int:
	return length


func read(offset: int, len: int) -> PackedByteArray:
	return iso.read(base + offset, len)
