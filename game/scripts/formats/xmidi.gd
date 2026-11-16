## Miles XMIDI music (SOUND/*.ADL|.ROL|.MID, MIDGAMES/?MUSIC.PAK entries).
##
## FORM XDIR (INFO: sequence count) + CAT XMID with one FORM XMID per sequence,
## or a bare FORM XMID. Each XMID has TIMB (u16 count + count x {patch, bank}:
## the timbres it needs) and EVNT: MIDI events without running status, where
## bytes below 0x80 are delays in 120 Hz ticks (consecutive ones add up) and a
## note-on is followed by its duration as a variable-length number (no note-off).
## Controllers 116 / 117 mark FOR / NEXT loops.
extends RefCounted

const TICK_HZ := 120.0


## All sequences in an XDIR / XMID file. Each: { timbres: [[patch, bank]],
## events: [[tick, status, a, b, duration]] } (status = type | channel).
static func sequences(buf: PackedByteArray) -> Array:
	var out := []
	_walk(buf, 0, buf.size(), out)
	return out


static func _walk(buf: PackedByteArray, from: int, to: int, out: Array) -> void:
	var i := from
	while i + 8 <= to:
		var tag := buf.slice(i, i + 4).get_string_from_ascii()
		var size := _u32be(buf, i + 4)
		var body := i + 8
		if tag == "FORM" or tag == "CAT ":
			var kind := buf.slice(body, body + 4).get_string_from_ascii()
			if kind == "XMID" and tag == "FORM":
				out.append(_sequence(buf, body + 4, body + size))
			else:
				_walk(buf, body + 4, body + size, out)
		i = body + size + (size & 1)


static func _sequence(buf: PackedByteArray, from: int, to: int) -> Dictionary:
	var seq := {"timbres": [], "events": []}
	var i := from
	while i + 8 <= to:
		var tag := buf.slice(i, i + 4).get_string_from_ascii()
		var size := _u32be(buf, i + 4)
		var body := i + 8
		if tag == "TIMB":
			var n := buf.decode_u16(body)
			for k in n:
				seq.timbres.append([buf[body + 2 + k * 2], buf[body + 3 + k * 2]])
		elif tag == "EVNT":
			seq.events = _events(buf, body, body + size)
		i = body + size + (size & 1)
	return seq


static func _events(buf: PackedByteArray, from: int, to: int) -> Array:
	var ev := []
	var tick := 0
	var i := from
	while i < to:
		var b := buf[i]
		if b < 0x80:
			tick += b
			i += 1
			continue
		i += 1
		var kind := b & 0xF0
		match kind:
			0x90:
				var note := buf[i]
				var vel := buf[i + 1]
				i += 2
				var r := _vlq(buf, i)
				i = r[1]
				ev.append([tick, b, note, vel, r[0]])
			0x80, 0xA0, 0xB0, 0xE0:
				ev.append([tick, b, buf[i], buf[i + 1], 0])
				i += 2
			0xC0, 0xD0:
				ev.append([tick, b, buf[i], 0, 0])
				i += 1
			0xF0:
				if b == 0xFF:
					var type := buf[i]
					var r := _vlq(buf, i + 1)
					i = r[1] + r[0]
					if type == 0x2F:
						break
				else:
					var r := _vlq(buf, i)
					i = r[1] + r[0]
	return ev


static func _vlq(buf: PackedByteArray, i: int) -> Array:
	var v := 0
	while i < buf.size():
		var b := buf[i]
		i += 1
		v = (v << 7) | (b & 0x7F)
		if b < 0x80:
			break
	return [v, i]


static func _u32be(buf: PackedByteArray, i: int) -> int:
	return (buf[i] << 24) | (buf[i + 1] << 16) | (buf[i + 2] << 8) | buf[i + 3]
