## Autoload "Sfx": original sound effects (SOUND/DSOUNDFX.PAK) by role.
## The role -> sound index map is a best guess from the waveforms and can be
## changed in Options / Audio (stored as audio/map_<role>).
extends Node

const Voc = preload("res://scripts/formats/voc.gd")

## role -> [default index in DSOUNDFX (-1 = synthesised), loops]
const ROLES := {
	"engine": [23, true],
	"afterburner": [28, true],
	"gun": [-1, true],            # no gun sound found in DSOUNDFX
	"explosion_big": [3, false],
	"explosion_small": [4, false],
	"hit": [13, false],
	"missile_launch": [18, false],
	"flyby": [1, false],
}

## Roles that also offer a synthesised sound (selected with index -1).
const SYNTH := ["gun", "hit"]

var _tones := {}


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	apply_volume()
	Settings.changed.connect(apply_volume)


func apply_volume() -> void:
	var v: float = Settings.get_value("audio", "volume", 0.8)
	AudioServer.set_bus_volume_db(0, linear_to_db(maxf(v, 0.0001)))
	AudioServer.set_bus_mute(0, v <= 0.001)


func index_of(role: String) -> int:
	return int(Settings.get_value("audio", "map_" + role, ROLES[role][0]))


func stream(role: String, loop := true) -> AudioStream:
	if not ROLES.has(role):
		return null
	var i := index_of(role)
	if i < 0:
		return synth(role, loop and ROLES[role][1])
	if not SCData.is_mounted():
		return null
	return SCData.sfx(i, loop and ROLES[role][1])


func synth(role: String, loop: bool) -> AudioStream:
	var key := "%s:%s" % [role, loop]
	if not _tones.has(key):
		match role:
			"gun":
				_tones[key] = gun(loop)
			_:
				_tones[key] = Voc.impact()
	return _tones[key]


## Synthesised Gatling for a calibre preset ("20mm" / "30mm").
func gun(loop := true, preset := "20mm") -> AudioStream:
	var key := "gun_%s:%s" % [preset, loop]
	if not _tones.has(key):
		var g := Voc.gun_loop(preset)
		if not loop:
			g.loop_mode = AudioStreamWAV.LOOP_DISABLED
		_tones[key] = g
	return _tones[key]


## Gun sound for an aircraft: synthesised preset from its original gun
## (30 mm guns get the heavy preset), unless an original sound is selected.
func gun_for(model, loop := true) -> AudioStream:
	if index_of("gun") >= 0:
		return stream("gun", loop)
	return gun(loop, gun_preset(model))


static func gun_preset(model) -> String:
	if model == null:
		return "20mm"
	var wpns = model.object_chunk(["FORM:JETP", "FORM:WEAP", "WPNS"])
	if wpns != null:
		var buf: PackedByteArray = model.buffer
		for o in range(wpns.off, wpns.off + wpns.size - 9, 10):
			var name := buf.slice(o + 2, o + 10).get_string_from_ascii().to_upper()
			if name.begins_with("30MM"):
				return "30mm"
	return "20mm"


## Synthesised cockpit tones: "warning" (fast high beeps), "lock" (steady growl).
func tone(name: String) -> AudioStream:
	if not _tones.has(name):
		match name:
			"warning":
				_tones[name] = Voc.tone(1600.0, 0.09, 0.07, 8)
			"lock":
				_tones[name] = Voc.tone(900.0, 0.5, 0.0, 1)
			_:
				_tones[name] = Voc.tone(1000.0, 0.1, 0.1, 4)
	return _tones[name]


## Radio chatter squak: a short synthesised burst (carrier crackle + open
## click) played under every cockpit radio message, so flying with the radio
## traffic on does not feel silent. pure noise + shaped envelope; mono 22 kHz.
func radio_blip(volume_db := -4.0) -> void:
	if not is_inside_tree():
		return
	if not _tones.has("radio"):
		var rate := 22050
		var n := int(0.42 * rate)
		var buf := PackedByteArray()
		buf.resize(n * 2)
		var phase := 0.0
		for i in n:
			var t := i / float(rate)
			var env := clampf(t * 30.0, 0.0, 1.0) * clampf((0.42 - t) * 14.0, 0.0, 1.0)
			# crackling carrier: white noise through a rough bandpass
			phase = clampf(phase + randf_range(-0.6, 0.6), -3.0, 3.0)
			var carrier := sin(phase * 22.0) * 0.5 + randf_range(-0.8, 0.8) * 0.35
			# two squelch beeps (0.06 s each) at 950 Hz inside the burst
			if (t > 0.05 and t < 0.11) or (t > 0.24 and t < 0.30):
				carrier += sin(TAU * 950.0 * t) * 0.6
			var s := clampf(carrier * env * 0.55, -1.0, 1.0)
			buf.encode_s16(i * 2, int(s * 32000.0))
		var w := AudioStreamWAV.new()
		w.data = buf
		w.format = AudioStreamWAV.FORMAT_16_BITS
		w.mix_rate = rate
		w.stereo = false
		_tones["radio"] = w
	var p := AudioStreamPlayer.new()
	p.stream = _tones["radio"]
	p.volume_db = volume_db
	add_child(p)
	p.finished.connect(p.queue_free)
	p.play()


## Fire-and-forget positional sound.
func play_at(role: String, pos: Vector3, volume_db := 0.0, pitch := 1.0) -> void:
	if not ROLES.has(role) or not is_inside_tree():
		return
	var s := stream(role, false)    # one-shots never loop
	if s == null:
		return
	var p := AudioStreamPlayer3D.new()
	p.stream = s
	p.volume_db = volume_db
	p.pitch_scale = pitch * randf_range(0.95, 1.05)
	p.unit_size = 60.0
	p.max_distance = 9000.0
	p.attenuation_model = AudioStreamPlayer3D.ATTENUATION_INVERSE_DISTANCE
	p.doppler_tracking = AudioStreamPlayer3D.DOPPLER_TRACKING_PHYSICS_STEP
	get_tree().root.add_child(p)
	p.global_position = pos
	p.finished.connect(p.queue_free)
	p.play()


## Non-positional sound (menus, sound test). Plays a raw DSOUNDFX index, or
## the synthesised sound of `role` for index -1.
func play_index(index: int, role := "") -> void:
	var s: AudioStream = synth(role, false) if index < 0 else SCData.sfx(index, false)
	if s == null:
		return
	var p := AudioStreamPlayer.new()
	p.stream = s
	add_child(p)
	p.finished.connect(p.queue_free)
	p.play()


## Looping engine sound attached to an aircraft (other than the player's).
func attach_engine(target: Node3D) -> AudioStreamPlayer3D:
	var s := stream("engine")
	if s == null:
		return null
	var p := AudioStreamPlayer3D.new()
	p.stream = s
	p.volume_db = -4.0
	p.unit_size = 80.0
	p.max_distance = 6000.0
	p.doppler_tracking = AudioStreamPlayer3D.DOPPLER_TRACKING_PHYSICS_STEP
	p.autoplay = true
	target.add_child(p)
	return p
