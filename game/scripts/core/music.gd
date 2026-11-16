## Music player for the original XMIDI scores (autoload "Music").
##
## Uses the AdLib versions (SOUND/GAMEFLOW.ADL, SOUND/COMBAT.ADL,
## MIDGAMES/AMUSIC.PAK) with the instruments of SOUND/STRIKE.AD, rendered by
## FmSynth. Notes are played on a pool of sample players; timing runs at the
## XMIDI rate of 120 ticks per second. Channel 10 (index 9) plays the
## percussion bank 127 (patch = drum key).
extends Node

const Xmidi = preload("res://scripts/formats/xmidi.gd")
const FmSynth = preload("res://scripts/audio/fm_synth.gd")
const Pak = preload("res://scripts/formats/pak_archive.gd")

const VOICES := 20
const DRUMS := 9

var _bank := {}
var _samples := {}            # timbre key -> AudioStreamWAV
var _players: Array[AudioStreamPlayer] = []
var _voice_end: Array = []     # tick at which each voice is released (-1 = free)
var _voice_note: Array = []    # [channel, note] per voice
var _seq: Dictionary = {}
var _events: Array = []
var _next := 0
var _tick := 0.0
var _length := 0
var _loop := true
var _playing := false
var _program := []
var _bankno := []
var _volume := []
var _bend := []
var current := ""              # what is playing ("" = nothing)
var _pending := []
var _rendered = null           # filled by the render task
var _task := -1


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	for i in VOICES:
		var p := AudioStreamPlayer.new()
		add_child(p)
		_players.append(p)
		_voice_end.append(-1)
		_voice_note.append([-1, -1])
	apply_volume()


func apply_volume() -> void:
	var v: float = Settings.get_value("audio", "music", 0.6)
	for p in _players:
		p.set_meta("base_db", linear_to_db(maxf(v, 0.0001)))


## Plays sequence `index` of an XMIDI file or of PAK entry `entry` (>= 0).
func play(file: String, entry := -1, index := 0, loop := true) -> void:
	var key := "%s#%d#%d" % [file, entry, index]
	if key == current and _playing:
		return
	stop()
	if not Settings.get_value("audio", "music_on", true):
		return
	var buf := SCData.read(file)
	if entry >= 0:
		var e := Pak.entries(buf)
		buf = e[entry] if entry < e.size() else PackedByteArray()
	var seqs := Xmidi.sequences(buf)
	if index >= seqs.size():
		return
	current = key
	_seq = seqs[index]
	_events = _seq.events
	_loop = loop
	_length = 0
	for ev in _events:
		_length = maxi(_length, ev[0] + ev[4])
	_reset_channels()
	_next = 0
	_tick = 0.0
	# Render the instruments this sequence needs off the main thread; start
	# once they are ready.
	if _bank.is_empty():
		_bank = FmSynth.load_bank(SCData.read("SOUND/STRIKE.AD"))
	var keys := []
	for tb in _seq.timbres:
		var k: int = (tb[1] << 8) | tb[0]
		if not _samples.has(k):
			keys.append(k)
	_pending = keys
	if keys.is_empty():
		_playing = true
	else:
		_task = WorkerThreadPool.add_task(_render_pending)


func stop() -> void:
	_playing = false
	current = ""
	for i in VOICES:
		_players[i].stop()
		_voice_end[i] = -1


func _reset_channels() -> void:
	_program = []
	_bankno = []
	_volume = []
	_bend = []
	for ch in 16:
		_program.append(0)
		_bankno.append(0)
		_volume.append(127)
		_bend.append(1.0)


const CACHE := "user://music_cache/"


func _render_pending() -> void:
	DirAccess.make_dir_recursive_absolute(CACHE)
	var done := {}
	for k in _pending:
		done[k] = _load_or_render(k)
	_rendered = done


func _load_or_render(key: int) -> AudioStreamWAV:
	if not _bank.has(key):
		return null
	var path := CACHE + "%d_%s.res" % [key, _bank[key].hex_encode()]
	if FileAccess.file_exists(path):
		var r = ResourceLoader.load(path)
		if r is AudioStreamWAV:
			return r
	var s := FmSynth.render(_bank[key])
	ResourceSaver.save(s, path)
	return s


func _sample(key: int) -> AudioStreamWAV:
	if not _samples.has(key):
		_samples[key] = _load_or_render(key)
	return _samples[key]


func _process(dt: float) -> void:
	if _task >= 0 and WorkerThreadPool.is_task_completed(_task):
		WorkerThreadPool.wait_for_task_completion(_task)
		_task = -1
		if _rendered is Dictionary:
			_samples.merge(_rendered, true)
		_rendered = null
		if current != "":
			_playing = true
	if not _playing:
		return
	_tick += dt * Xmidi.TICK_HZ
	while _next < _events.size() and _events[_next][0] <= _tick:
		_event(_events[_next])
		_next += 1
	for i in VOICES:
		if _voice_end[i] >= 0 and _tick >= _voice_end[i]:
			_release(i)
	if _next >= _events.size() and _tick >= _length:
		if _loop:
			_next = 0
			_tick = 0.0
			_reset_channels()
		else:
			_playing = false


func _event(ev: Array) -> void:
	var status: int = ev[1]
	var ch := status & 0x0F
	match status & 0xF0:
		0x90:
			if ev[3] > 0:
				_note_on(ch, ev[2], ev[3], ev[0] + ev[4])
		0xB0:
			match ev[2]:
				7:
					_volume[ch] = ev[3]
				114:                     # AIL: timbre bank select
					_bankno[ch] = ev[3]
		0xC0:
			_program[ch] = ev[2]
		0xE0:
			var v: int = (ev[3] << 7) | ev[2]
			_bend[ch] = pow(2.0, (v - 8192) / 8192.0 * 2.0 / 12.0)


func _note_on(ch: int, note: int, vel: int, end_tick: int) -> void:
	var key: int
	var pitch: float
	if ch == DRUMS:
		key = (127 << 8) | note
		if not _bank.has(key):
			return
		var t: PackedByteArray = _bank[key]
		pitch = float(t[0]) if t[0] > 0 else 60.0
	else:
		key = (_bankno[ch] << 8) | _program[ch]
		if not _bank.has(key):
			key = _program[ch]
		if not _bank.has(key):
			return
		pitch = note + FmSynth.transpose(_bank[key])
	var s := _sample(key)
	if s == null:
		return
	var v := _free_voice()
	var p := _players[v]
	# Fix: use has_meta check before get_meta to avoid error on first use
	var old = null
	if p.has_meta("tween"):
		old = p.get_meta("tween")
	if old is Tween and old.is_valid():
		old.kill()
	p.stream = s
	p.pitch_scale = clampf(pow(2.0, (pitch - FmSynth.BASE_NOTE) / 12.0) * _bend[ch], 0.01, 16.0)
	var gain: float = (vel / 127.0) * (_volume[ch] / 127.0)
	var base_db = 0.0
	if p.has_meta("base_db"):
		base_db = float(p.get_meta("base_db"))
	p.volume_db = base_db + 40.0 * log(maxf(gain, 0.001)) / log(10.0) * 0.5 - 6.0
	p.set_meta("release", FmSynth.release_s(_bank[key]))
	p.play()
	_voice_end[v] = end_tick
	_voice_note[v] = [ch, note]


func _free_voice() -> int:
	var oldest := 0
	for i in VOICES:
		if _voice_end[i] < 0 and not _players[i].playing:
			return i
		if _voice_end[i] >= 0 and _voice_end[i] < _voice_end[oldest]:
			oldest = i
	_players[oldest].stop()
	return oldest


func _release(i: int) -> void:
	_voice_end[i] = -1
	var p := _players[i]
	var r: float = 0.2
	if p.has_meta("release"):
		r = float(p.get_meta("release"))
	r = clampf(r, 0.02, 3.0)
	var tw := create_tween()
	tw.tween_property(p, "volume_db", p.volume_db - 48.0, r)
	tw.tween_callback(p.stop)
	p.set_meta("tween", tw)
