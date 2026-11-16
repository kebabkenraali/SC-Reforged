## LZW decoder used by Strike Commander CD data ("LZ" textures, terrain blocks).
## LSB-first codes, 9 to 12 bits, 256 = reset, 257 = end of stream.
extends RefCounted

const CLEAR := 256
const END := 257
const FIRST := 258
const MAX_CODES := 4096


static func decode(data: PackedByteArray, start := 0, expected := -1) -> PackedByteArray:
	var prefix := PackedInt32Array()
	prefix.resize(MAX_CODES)
	var suffix := PackedByteArray()
	suffix.resize(MAX_CODES)
	var lens := PackedInt32Array()
	lens.resize(MAX_CODES)
	for i in 256:
		prefix[i] = -1
		suffix[i] = i
		lens[i] = 1

	var out := PackedByteArray()
	out.resize(expected if expected > 0 else maxi(data.size() * 4, 256))
	var out_len := 0
	var next := FIRST
	var nbits := 9
	var prev := -1
	var bitpos := start * 8
	var total := data.size() * 8
	var n := data.size()

	while bitpos + nbits <= total:
		var bi := bitpos >> 3
		var v := data[bi]
		if bi + 1 < n:
			v |= data[bi + 1] << 8
		if bi + 2 < n:
			v |= data[bi + 2] << 16
		var code := (v >> (bitpos & 7)) & ((1 << nbits) - 1)
		bitpos += nbits

		if code == CLEAR:
			next = FIRST
			nbits = 9
			prev = -1
			continue
		if code == END:
			break

		var emit_code := code
		var extra := false
		if prev != -1 and code >= next:
			emit_code = prev
			extra = true
		var length := lens[emit_code] + (1 if extra else 0)
		if out_len + length > out.size():
			out.resize(maxi(out.size() * 2, out_len + length))
		var p := out_len + lens[emit_code] - 1
		var c := emit_code
		while c != -1:
			out[p] = suffix[c]
			p -= 1
			c = prefix[c]
		var first_char := out[out_len]
		if extra:
			out[out_len + length - 1] = first_char
		out_len += length

		if prev != -1 and next < MAX_CODES:
			prefix[next] = prev
			suffix[next] = first_char
			lens[next] = lens[prev] + 1
			next += 1
		prev = code
		if next >= (1 << nbits) and nbits < 12:
			nbits += 1

	out.resize(out_len)
	return out
