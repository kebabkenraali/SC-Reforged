## Plays a story cut-scene (MIDn) from the original art, speech and texts.
## The original staging lives in OPTTEST.EXE code and is not decoded yet, so
## shots are shown in file order, spread over the length of the speech, with
## animations at 10 fps. Click / Space: next shot, Esc: skip.
extends Control

const Midgame = preload("res://scripts/formats/sc_midgame.gd")
const Shape = preload("res://scripts/formats/sc_shape.gd")
const UiTheme = preload("res://scripts/ui/ui_theme.gd")

const FPS := 10.0
const MIN_SHOT := 2.5

signal finished

var number := 1
var _stage: Control
var _base: TextureRect
var _frame: TextureRect
var _sub: Label
var _voice: AudioStreamPlayer
var _skip := false
var _next := false
var _smooth := false


func _ready() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_STOP
	_smooth = Settings.get_value("video", "smooth_textures")
	var black := ColorRect.new()
	black.color = Color.BLACK
	black.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(black)
	var arc := AspectRatioContainer.new()
	arc.ratio = 320.0 / 200.0
	arc.alignment_horizontal = AspectRatioContainer.ALIGNMENT_CENTER
	arc.alignment_vertical = AspectRatioContainer.ALIGNMENT_CENTER
	arc.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	arc.offset_top = 50
	arc.offset_bottom = 50
	add_child(arc)
	_stage = Control.new()
	_stage.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_stage.clip_contents = true
	arc.add_child(_stage)
	_base = _rect()
	_frame = _rect()
	_sub = Label.new()
	_sub.anchor_left = 0.08
	_sub.anchor_right = 0.92
	_sub.anchor_top = 1.0
	_sub.anchor_bottom = 1.0
	_sub.offset_top = -120
	_sub.offset_bottom = -30
	_sub.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_sub.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_sub.add_theme_font_size_override("font_size", 24)
	_sub.add_theme_color_override("font_outline_color", Color.BLACK)
	_sub.add_theme_constant_override("outline_size", 8)
	add_child(_sub)
	var note := Label.new()
	note.text = "Cut-scene %d  ·  approximate staging  ·  Esc: skip" % number
	note.position = Vector2(16, 12)
	note.add_theme_font_size_override("font_size", 13)
	note.add_theme_color_override("font_color", Color(0.6, 0.6, 0.6))
	add_child(note)
	_voice = AudioStreamPlayer.new()
	add_child(_voice)


func _rect() -> TextureRect:
	var t := TextureRect.new()
	t.stretch_mode = TextureRect.STRETCH_SCALE
	t.texture_filter = CanvasItem.TEXTURE_FILTER_LINEAR if _smooth else CanvasItem.TEXTURE_FILTER_NEAREST
	t.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_stage.add_child(t)
	return t


## Places a decoded frame at its 320 x 200 screen position inside the stage.
func _show(t: TextureRect, d: Dictionary, pal: PackedColorArray) -> void:
	var p: Vector2i = Midgame.ORIGIN + d.origin
	t.texture = ImageTexture.create_from_image(Shape.to_image(d, pal))
	t.anchor_left = p.x / 320.0
	t.anchor_top = p.y / 200.0
	t.anchor_right = (p.x + d.w) / 320.0
	t.anchor_bottom = (p.y + d.h) / 200.0
	t.offset_left = 0
	t.offset_top = 0
	t.offset_right = 0
	t.offset_bottom = 0


func play() -> void:
	var m = Midgame.load_number(number)
	var speech := 0.0
	for v in m.voices:
		speech += v.get_length() + 0.3
	var shots: Array = m.shots
	if shots.is_empty() and m.voices.is_empty():
		finished.emit()
		return
	var total := maxf(speech, shots.size() * MIN_SHOT)
	# Recorded VM timelines carry their own music op; this fallback player does
	# not, so start the original midgame score here (entry 2 = story music).
	Music.play("MIDGAMES/AMUSIC.PAK", 2, 0, false)
	_voice_track(m)
	var per := total / maxf(1.0, shots.size())
	for s in shots:
		if _skip:
			break
		_next = false
		var frames: Array = s.frames
		_show(_base, frames[0], s.palette)
		_frame.texture = null
		var t := 0.0
		var shown := -1
		var length := maxf(per, (frames.size() - 1) / FPS) if frames.size() > 1 else per
		while t < length and not _skip and not _next:
			await get_tree().process_frame
			t += get_process_delta_time()
			if frames.size() > 1:
				var k := 1 + int(t * FPS) % (frames.size() - 1)
				if k != shown:
					shown = k
					_show(_frame, frames[k], s.palette)
	while _voice.playing and not _skip:
		await get_tree().process_frame
	_voice.stop()
	finished.emit()


## Speech with subtitles (or the title texts when there is no speech).
func _voice_track(m) -> void:
	if m.voices.is_empty():
		for line in m.titles:
			if _skip:
				return
			_sub.text = line
			await get_tree().create_timer(2.5).timeout
		_sub.text = ""
		return
	var texts: Array = m.texts
	for i in m.voices.size():
		if _skip or not is_inside_tree():
			return
		var j: int = i if texts.size() == m.voices.size() else int(float(i) / m.voices.size() * texts.size())
		_sub.text = texts[j] if j < texts.size() else ""
		_voice.stream = m.voices[i]
		_voice.play()
		await _voice.finished
		await get_tree().create_timer(0.3).timeout
	_sub.text = ""


func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed("ui_cancel") or event.is_action_pressed("pause"):
		_skip = true
		_voice.stop()
		get_viewport().set_input_as_handled()
	elif event.is_action_pressed("ui_accept") or (event is InputEventMouseButton and event.pressed):
		_next = true
		get_viewport().set_input_as_handled()
