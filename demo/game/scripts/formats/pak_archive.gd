## Origin PAK container: u32 total size followed by u32 entry offsets whose top
## byte holds flags (0xE0 = plain, 0x20 = nested/compressed payload).
extends RefCounted


static func entries(buf: PackedByteArray) -> Array[PackedByteArray]:
	var out: Array[PackedByteArray] = []
	if buf.size() < 8:
		return out
	var first := buf.decode_u32(4) & 0xFFFFFF
	if first < 8 or first > buf.size():
		return out
	var offs := PackedInt32Array()
	var i := 4
	while i < first:
		offs.append(buf.decode_u32(i) & 0xFFFFFF)
		i += 4
	offs.append(buf.size())
	for k in offs.size() - 1:
		out.append(buf.slice(offs[k], maxi(offs[k], offs[k + 1])))
	return out


## Top-byte flags of each entry (0x20 = LZW packed, 0xE0 = stored as is).
static func flags(buf: PackedByteArray) -> PackedByteArray:
	var out := PackedByteArray()
	if buf.size() < 8:
		return out
	var first := buf.decode_u32(4) & 0xFFFFFF
	if first < 8 or first > buf.size():
		return out
	for i in range(4, first, 4):
		out.append(buf.decode_u32(i) >> 24)
	return out
