## AdLib (OPL2) instrument rendering for the original music.
##
## SOUND/STRIKE.AD is a Miles global timbre library: entries {u8 patch, u8 bank,
## u32 offset} up to patch = bank = 0xFF; at the offset u16 size (14 for a
## two-operator OPL2 timbre), i8 transpose, then the OPL registers modulator
## 20 40 60 80 E0, feedback/connection C0, carrier 20 40 60 80 E0.
##
## Each timbre is synthesised once (two-operator FM with the original
## multipliers, levels, feedback, waveforms and ADSR envelopes) into a sample
## at BASE_HZ; notes are played from it with pitch scaling. Sustaining
## instruments loop a whole number of periods after the decay.
extends RefCounted

const RATE := 22050
const PERIOD := 84                       # samples per cycle at BASE_HZ
const BASE_HZ := float(RATE) / PERIOD     # 262.5 Hz, close to middle C
const BASE_NOTE := 60.0 + 12.0 * log(BASE_HZ / 261.6256) / log(2.0)
const MULT := [0.5, 1, 2, 3, 4, 5, 6, 7, 8, 9, 10, 10, 12, 12, 15, 15]
# Time (s) for a full attack / for a 96 dB decay, by OPL rate 0..15.
const ATTACK_S := [INF, 2.826, 1.413, 0.7065, 0.353, 0.1766, 0.0883, 0.0441, 0.0221,
	0.011, 0.0055, 0.00276, 0.00138, 0.00069, 0.00035, 0.0]
const DECAY_S := [INF, 39.28, 19.64, 9.82, 4.91, 2.455, 1.2276, 0.6138, 0.3069,
	0.1534, 0.0767, 0.0383, 0.0192, 0.0096, 0.0048, 0.0024]
const MOD_DEPTH := TAU          # carrier phase shift at full modulator output
const FEEDBACK := [0.0, PI / 16, PI / 8, PI / 4, PI / 2, PI, TAU, 2 * TAU]


## { (bank << 8) | patch: PackedByteArray(12) } from a .AD library.
static func load_bank(ad: PackedByteArray) -> Dictionary:
	var out := {}
	var i := 0
	while i + 6 <= ad.size():
		var patch := ad[i]
		var bank := ad[i + 1]
		var off := ad.decode_u32(i + 2)
		i += 6
		if patch == 0xFF and bank == 0xFF:
			break
		if off + 14 <= ad.size() and ad.decode_u16(off) == 14:
			out[(bank << 8) | patch] = ad.slice(off + 2, off + 14)
	return out


## Transpose (semitones) of a timbre.
static func transpose(t: PackedByteArray) -> int:
	return t[0] - 256 if t[0] > 127 else t[0]


## Release time (s) of the carrier, for note-off fades.
static func release_s(t: PackedByteArray) -> float:
	return minf(DECAY_S[t[10] & 0x0F], 4.0)


static func _op(r20: int, r40: int, r60: int, r80: int, re0: int) -> Dictionary:
	return {
		"mult": float(MULT[r20 & 0x0F]),
		"sustains": (r20 & 0x20) != 0,
		"level": pow(10.0, -0.75 * (r40 & 0x3F) / 20.0),
		"attack": ATTACK_S[r60 >> 4],
		"decay": DECAY_S[r60 & 0x0F],
		"sustain_db": 93.0 if (r80 >> 4) == 15 else 3.0 * (r80 >> 4),
		"release": DECAY_S[r80 & 0x0F],
		"wave": re0 & 3,
	}


## Envelope gain of an operator at time t (s) while the key is held.
static func _env(o: Dictionary, t: float) -> float:
	var a: float = o.attack
	if a == INF:
		return 0.0
	if t < a:
		return t / a
	var td := t - a
	var db: float = 96.0 * td / o.decay if o.decay != INF else 0.0
	if db > o.sustain_db:
		if o.sustains:
			db = o.sustain_db
		else:
			# past the sustain level a non-sustaining operator keeps falling at the release rate
			var t_sl: float = o.sustain_db / 96.0 * o.decay
			db = o.sustain_db + 96.0 * (td - t_sl) / o.release if o.release != INF else o.sustain_db
	return pow(10.0, -db / 20.0) if db < 96.0 else 0.0


static func _wave(phase: float, w: int) -> float:
	var s := sin(phase)
	match w:
		1:
			return maxf(s, 0.0)
		2:
			return absf(s)
		3:
			return absf(s) if fmod(phase, PI) < PI * 0.5 else 0.0
	return s


## Renders timbre `t` into a sample at BASE_HZ.
static func render(t: PackedByteArray) -> AudioStreamWAV:
	var m := _op(t[1], t[2], t[3], t[4], t[5])
	var c := _op(t[7], t[8], t[9], t[10], t[11])
	var fb: float = FEEDBACK[(t[6] >> 1) & 7]
	var additive := (t[6] & 1) != 0
	# How long to render: until both envelopes settle (sustain) or fall silent.
	var settle := 0.0
	for o in [m, c]:
		var a: float = minf(o.attack, 3.0)
		var d: float = minf(o.decay * o.sustain_db / 96.0, 3.0) if o.decay != INF else 0.0
		settle = maxf(settle, a + d)
	var sustaining: bool = c.sustains
	var seconds := clampf(settle, 0.05, 3.0)
	var loop_periods := 24
	var n := int(seconds * RATE)
	if sustaining:
		n = (n / PERIOD + 1) * PERIOD + loop_periods * PERIOD
	else:
		n = int(minf(seconds + 1.5, 4.0) * RATE)
	var data := PackedByteArray()
	data.resize(n * 2)
	var w := TAU * BASE_HZ / RATE
	var prev1 := 0.0
	var prev2 := 0.0
	var peak := 0.0001
	var samples := PackedFloat32Array()
	samples.resize(n)
	for i in n:
		var tt := float(i) / RATE
		# envelopes change slowly: refresh every 32 samples
		if i % 32 == 0:
			m["g"] = _env(m, tt) * m.level
			c["g"] = _env(c, tt) * c.level
		var pm: float = w * i * m.mult + (prev1 + prev2) * 0.5 * fb
		var mo: float = _wave(pm, m.wave) * m.g
		prev2 = prev1
		prev1 = mo
		var pc: float = w * i * c.mult
		var out: float
		if additive:
			out = (mo + _wave(pc, c.wave) * c.g) * 0.5
		else:
			out = _wave(pc + mo * MOD_DEPTH, c.wave) * c.g
		samples[i] = out
		peak = maxf(peak, absf(out))
	var gain := 0.9 * 32767.0
	for i in n:
		data.encode_s16(i * 2, int(clampf(samples[i], -1.0, 1.0) * gain))
	var s := AudioStreamWAV.new()
	s.format = AudioStreamWAV.FORMAT_16_BITS
	s.mix_rate = RATE
	s.data = data
	if sustaining:
		s.loop_mode = AudioStreamWAV.LOOP_FORWARD
		s.loop_begin = n - loop_periods * PERIOD
		s.loop_end = n
	return s
