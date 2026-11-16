## Creative Voice File (VOC) -> AudioStreamWAV. Strike Commander uses 8-bit
## unsigned mono blocks (type 1 = sound data with rate, type 2 = continuation).
extends RefCounted


static func to_stream(v: PackedByteArray, loop := false) -> AudioStreamWAV:
	if v.size() < 26 or v.slice(0, 19).get_string_from_ascii() != "Creative Voice File":
		return null
	var i := v.decode_u16(20)
	var rate := 11025
	var pcm := PackedByteArray()
	while i + 4 <= v.size():
		var t := v[i]
		if t == 0:
			break
		var ln := v[i + 1] | (v[i + 2] << 8) | (v[i + 3] << 16)
		var start := i + 4
		if t == 1 and ln >= 2:
			rate = int(1000000.0 / (256 - v[start]))
			pcm.append_array(v.slice(start + 2, start + ln))
		elif t == 2:
			pcm.append_array(v.slice(start, start + ln))
		i = start + ln
	# Godot's 8-bit format is signed.
	for k in pcm.size():
		pcm[k] = (pcm[k] - 128) & 0xFF
	var s := AudioStreamWAV.new()
	s.format = AudioStreamWAV.FORMAT_8_BITS
	s.mix_rate = rate
	s.stereo = false
	s.data = pcm
	if loop:
		s.loop_mode = AudioStreamWAV.LOOP_FORWARD
		s.loop_begin = 0
		s.loop_end = pcm.size()
	return s


## Synthesised beep pattern (16-bit) for cockpit tones the data does not have.
static func tone(freq: float, on_s: float, off_s: float, repeats: int, rate := 22050) -> AudioStreamWAV:
	var data := PackedByteArray()
	var period := on_s + off_s
	var n := int(period * repeats * rate)
	data.resize(n * 2)
	for k in n:
		var t := float(k) / rate
		var on := fmod(t, period) < on_s
		var v := int(sin(TAU * freq * t) * 9000.0) if on else 0
		data.encode_s16(k * 2, v)
	var s := AudioStreamWAV.new()
	s.format = AudioStreamWAV.FORMAT_16_BITS
	s.mix_rate = rate
	s.data = data
	s.loop_mode = AudioStreamWAV.LOOP_FORWARD
	s.loop_end = n
	return s


## Gatling gun presets. "20mm": modern fighter cannon, fast ripping burst.
## "30mm": GAU-8 style, slower and heavier. Noise only - no tonal parts, so the
## burst never turns into a whistle.
const GUN_PRESETS := {
	"20mm": {"rate": 110.0, "decay": 0.003, "body": 1.0, "crack": 0.7, "jitter": 0.15},
	"30mm": {"rate": 65.0, "decay": 0.006, "body": 1.4, "crack": 0.4, "jitter": 0.1},
}


## Synthesised Gatling burst: one short noise burst per round (slightly jittered
## so the rate does not become a pitch), split into a low thump and a high
## crack. Holds a whole number of rounds so it loops seamlessly.
static func gun_loop(preset := "20mm", rate := 44100) -> AudioStreamWAV:
	var p: Dictionary = GUN_PRESETS.get(preset, GUN_PRESETS["20mm"])
	var period: float = 1.0 / p.rate
	var rounds := int(roundf(0.5 / period))
	var n := int(roundf(rounds * period * rate))
	var raw := PackedFloat32Array()
	raw.resize(n)
	var rng := RandomNumberGenerator.new()
	rng.seed = 6600
	var burst := int(p.decay * 5.0 * rate)
	for r in rounds:
		var start := int((r + rng.randf_range(-p.jitter, p.jitter)) * period * rate)
		var gain := rng.randf_range(0.75, 1.0)
		for k in burst:
			var i := posmod(start + k, n)        # wrap so the loop point is seamless
			raw[i] += rng.randf_range(-1.0, 1.0) * exp(-float(k) / rate / p.decay) * gain
	# Low thump (one-pole low-pass) + high crack (signal minus a faster low-pass).
	var data := PackedByteArray()
	data.resize(n * 2)
	var low := 0.0
	var mid := 0.0
	for pass_i in 2:                          # second pass settles the filters across the loop point
		for i in n:
			low += (raw[i] - low) * 0.12
			mid += (raw[i] - mid) * 0.55
			if pass_i == 1:
				var v: float = (low * p.body * 2.2 + (raw[i] - mid) * p.crack) * 1.9
				data.encode_s16(i * 2, int(clampf(v, -1.0, 1.0) * 26000.0))
	var s := AudioStreamWAV.new()
	s.format = AudioStreamWAV.FORMAT_16_BITS
	s.mix_rate = rate
	s.data = data
	s.loop_mode = AudioStreamWAV.LOOP_FORWARD
	s.loop_end = n
	return s


## Synthesised bullet impact: sharp noise burst with a short metallic ring.
static func impact(rate := 22050) -> AudioStreamWAV:
	var n := int(0.18 * rate)
	var data := PackedByteArray()
	data.resize(n * 2)
	var rng := RandomNumberGenerator.new()
	rng.seed = 13
	for k in n:
		var t := float(k) / rate
		var v := rng.randf_range(-1.0, 1.0) * exp(-t / 0.025) + sin(TAU * 1900.0 * t) * 0.35 * exp(-t / 0.04)
		data.encode_s16(k * 2, int(clampf(v, -1.0, 1.0) * 24000.0))
	var s := AudioStreamWAV.new()
	s.format = AudioStreamWAV.FORMAT_16_BITS
	s.mix_rate = rate
	s.data = data
	return s
