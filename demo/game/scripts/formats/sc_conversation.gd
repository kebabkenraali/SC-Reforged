## Conversation scripts (GAMEFLOW/CONV.PAK, one LZW-packed entry each).
##
##   00 bg[9]                                   wide shot background
##   01 name[9] x y                             actor in the wide shot
##   02 name[9] x y u8 voc\0 text\0             actor in the wide shot speaks
##   03 name[9] mood bg[9] x y voc\0 text\0 u8  close-up of a speaker
##   04 voc\0 text\0                            same speaker continues
##   0a u8 voc\0 text\0                         caption / narration
##   0b off u8                                  yes/no question: "no" jumps `off` bytes ahead
##   0c off u8                                  jump `off` bytes ahead (skips the "no" branch)
##   0e u8 u8                                   (flight briefing marker)
##   0f                                         choose a wingman ($W)
## voc names refer to VOCLIST.TRE (F:<voc>.VOC); text may contain $N/$S/$C/$W.
extends RefCounted


## Returns a list of steps: { op, ... } with byte positions so jumps can be followed.
static func parse(r: PackedByteArray) -> Array:
	var out := []
	var pos := 0
	while pos < r.size():
		var start := pos
		var op := r[pos]
		var step := {"op": op, "pos": start}
		match op:
			0x00:
				step.bg = _name(r, pos + 1)
				pos += 10
			0x01:
				step.name = _name(r, pos + 1)
				step.at = Vector2i(r.decode_s16(pos + 10), r.decode_s16(pos + 12))
				pos += 14
			0x02:
				step.name = _name(r, pos + 1)
				step.at = Vector2i(r.decode_s16(pos + 10), r.decode_s16(pos + 12))
				pos = _voc_text(r, pos + 15, step)
			0x03:
				step.name = _name(r, pos + 1)
				step.mood = r[pos + 10]
				step.bg = _name(r, pos + 11)
				step.at = Vector2i(r.decode_s16(pos + 20), r.decode_s16(pos + 22))
				pos = _voc_text(r, pos + 24, step) + 1
			0x04:
				pos = _voc_text(r, pos + 1, step)
			0x0a:
				pos = _voc_text(r, pos + 2, step)
			0x0b, 0x0c:
				step.target = pos + 3 + r[pos + 1]
				pos += 3
			0x0e:
				pos += 3
			0x0f:
				pos += 1
			_:
				break
		out.append(step)
		if pos <= start:
			break
	return out


static func _name(r: PackedByteArray, o: int) -> String:
	var e := o
	while e < o + 9 and e < r.size() and r[e] != 0:
		e += 1
	return r.slice(o, e).get_string_from_ascii().to_lower()


static func _voc_text(r: PackedByteArray, o: int, step: Dictionary) -> int:
	var e := o
	while e < r.size() and r[e] != 0:
		e += 1
	step.voc = r.slice(o, e).get_string_from_ascii()
	var t := e + 1
	var te := t
	while te < r.size() and r[te] != 0:
		te += 1
	step.text = r.slice(t, te).get_string_from_ascii().replace("\n", " ")
	return te + 1
