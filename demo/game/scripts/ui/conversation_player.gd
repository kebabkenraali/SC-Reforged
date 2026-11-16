## Plays one conversation from GAMEFLOW/CONV.PAK with the original backgrounds,
## talking faces, wide shots and recorded speech (VOCLIST.TRE). Lines advance
## when the speech ends or on click / Space / Enter; Esc skips the conversation.
## Yes/no questions (0b) and wingman choices (0f) show buttons.
extends Control

const Art = preload("res://scripts/core/art.gd")
const Shape = preload("res://scripts/formats/sc_shape.gd")
const Conv = preload("res://scripts/formats/sc_conversation.gd")
const Voc = preload("res://scripts/formats/voc.gd")
const Pak = preload("res://scripts/formats/pak_archive.gd")
const UiTheme = preload("res://scripts/ui/ui_theme.gd")

const MOUTH := [2, 3, 4, 5, 6, 7, 8, 9, 10, 11]
const BLINK := 12                  # eyes closed
const HAIR := 1                    # hair and forehead, drawn over the features
const SHOULDERS := 34              # clothes / shoulders
const WINGMEN := ["Gwen", "Tex", "Lyle", "Janet", "Miguel", "Billy"]

signal finished(result: Dictionary)

var campaign
var conv_index := 0
var result := {"accepted": true}

var _stage: Control
var _bg: TextureRect
var _face: TextureRect
var _mouth: TextureRect
var _figures: Control
var _name: Label
var _text: Label
var _choices: HBoxContainer
var _voice: AudioStreamPlayer
var _advance := false
var _skip := false
var _talking := false
var _mouth_frames: Array = []
var _blink_tex: Texture2D
var _face_still: Texture2D
var _anim_t := 0.0
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
	arc.ratio = 4.0 / 3.0
	arc.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(arc)
	_stage = Control.new()
	_stage.mouse_filter = Control.MOUSE_FILTER_IGNORE
	arc.add_child(_stage)
	_bg = _layer()
	_figures = Control.new()
	_figures.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_figures.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_stage.add_child(_figures)
	_face = _layer()
	_mouth = _layer()

	# Subtitle panel over the lower part of the picture (where the original printed text).
	var panel := PanelContainer.new()
	panel.anchor_left = 0.08
	panel.anchor_right = 0.92
	panel.anchor_top = 1.0
	panel.anchor_bottom = 1.0
	panel.offset_top = -170
	panel.offset_bottom = -24
	add_child(panel)
	var box := VBoxContainer.new()
	panel.add_child(box)
	_name = Label.new()
	_name.add_theme_color_override("font_color", UiTheme.ACCENT)
	box.add_child(_name)
	_text = Label.new()
	_text.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_text.add_theme_font_size_override("font_size", 22)
	box.add_child(_text)
	_choices = HBoxContainer.new()
	_choices.add_theme_constant_override("separation", 12)
	box.add_child(_choices)
	var hint := Label.new()
	hint.text = "Click / Space: next    Esc: skip"
	hint.add_theme_font_size_override("font_size", 13)
	hint.add_theme_color_override("font_color", Color(0.6, 0.6, 0.6))
	hint.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	box.add_child(hint)
	_voice = AudioStreamPlayer.new()
	add_child(_voice)


func _layer() -> TextureRect:
	var t := TextureRect.new()
	_window(t)
	t.stretch_mode = TextureRect.STRETCH_SCALE
	t.texture_filter = CanvasItem.TEXTURE_FILTER_LINEAR if _smooth else CanvasItem.TEXTURE_FILTER_NEAREST
	t.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_stage.add_child(t)
	return t


## Plays the conversation; resolves with { accepted: bool }.
func play() -> Dictionary:
	var entries: Array = Pak.entries(SCData.read("GAMEFLOW/CONV.PAK"))
	if conv_index < 0 or conv_index >= entries.size():
		return result
	var steps: Array = Conv.parse(Shape.unpack(entries[conv_index]))
	var speaker := ""
	var i := 0
	while i < steps.size() and not _skip:
		var s: Dictionary = steps[i]
		i += 1
		match s.op:
			0x00:
				_show_wide(s.bg)
			0x01:
				_add_figure(s.name, s.at)
			0x02:
				speaker = s.name
				await _say(speaker, s.voc, s.text)
			0x03:
				speaker = s.name
				_show_closeup(s.bg, s.name, s.at, int(s.mood))
				await _say(speaker, s.voc, s.text)
			0x04:
				await _say(speaker, s.voc, s.text)
			0x0a:
				_face.texture = null
				_mouth.texture = null
				await _say("", s.voc, s.text)
			0x0b:
				result.accepted = await _ask(["Yes", "No"]) == 0
				if not result.accepted:
					i = _index_at(steps, s.target)
			0x0c:
				i = _index_at(steps, s.target)
			0x0f:
				var pick := await _ask(WINGMEN)
				if campaign != null:
					campaign.wingman = WINGMEN[pick]
	_voice.stop()
	finished.emit(result)
	return result


static func _index_at(steps: Array, pos: int) -> int:
	for k in steps.size():
		if steps[k].pos >= pos:
			return k
	return steps.size()


# --- pictures ------------------------------------------------------------------

func _window(c: Control) -> void:
	c.anchor_left = 0.0
	c.anchor_right = 1.0
	c.anchor_top = 24.0 / 200.0
	c.anchor_bottom = 152.0 / 200.0
	c.offset_left = 0
	c.offset_right = 0
	c.offset_top = 0
	c.offset_bottom = 0


func _compose_back(name: String) -> Dictionary:
	var gf = Art.gameflow()
	var canvas := Art.new_canvas()
	var layers: Array = gf.backs.get(name, [])
	var pal: PackedColorArray = SCData.palette()
	for layer in layers:
		# each layer brings its partial palette from its own archive (OPTPALS / CONVPALS)
		var archive := "opt" if layer.archive == 1 else "conv"
		var fr: Array = Art.frames(archive, layer.shape)
		if not fr.is_empty():
			Art.blit(canvas, fr[0], Vector2i(0, layer.y))
		var pals := Art._entries(Art.ARCHIVES[archive][1])
		if layer.palette >= 0 and layer.palette < pals.size():
			pal = Shape.apply_palette(pal, pals[layer.palette])
	return {"canvas": canvas, "palette": pal}


## The original shows rows 0-127 of its 320 x 200 picture in a window at
## screen rows 24-151 (the layers are anchored there).
func _tex(img: Image) -> ImageTexture:
	return ImageTexture.create_from_image(img.get_region(Rect2i(0, 0, 320, 128)))


func _show_wide(bg: String) -> void:
	var b := _compose_back(bg)
	var pal: PackedColorArray = b.palette
	var gf = Art.gameflow()
	if gf.figure_palette >= 0:
		pal = Shape.apply_palette(pal, Art._entries(Art.ARCHIVES.conv[1])[gf.figure_palette])
	_bg.set_meta("palette", pal)
	_bg.texture = _tex(Art.canvas_image(b.canvas, pal))
	_face.texture = null
	_mouth.texture = null
	for c in _figures.get_children():
		c.queue_free()


func _add_figure(name: String, at: Vector2i) -> void:
	var gf = Art.gameflow()
	var fr: Array = Art.frames("conv", gf.figures.get(name, -1))
	if fr.is_empty() or not _bg.has_meta("palette"):
		return
	var t := TextureRect.new()
	_window(t)
	t.stretch_mode = TextureRect.STRETCH_SCALE
	t.texture_filter = _bg.texture_filter
	# Composite figure layers like closeup: head(0), hair(1), shoulders(34)
	# Figures don't have expressions/mouth/blink, just static layers
	var layers := [0]
	if 1 < fr.size():
		layers.append(1)      # hair/forehead
	if 34 < fr.size():
		layers.append(34)     # shoulders/clothes
	t.texture = _tex(_face_image(fr, layers, at, _bg.get_meta("palette")))
	_figures.add_child(t)


func _show_closeup(bg: String, name: String, at: Vector2i, mood := 255) -> void:
	for c in _figures.get_children():
		c.queue_free()
	var b := _compose_back(bg)
	var gf = Art.gameflow()
	var pal: PackedColorArray = b.palette
	if gf.face_palette >= 0:
		pal = Shape.apply_palette(pal, Art._entries(Art.ARCHIVES.conv[1])[gf.face_palette])
	var fr: Array = Art.frames("conv", gf.faces.get(name, -1))
	_bg.texture = _tex(Art.canvas_image(b.canvas, pal))
	_mouth.texture = null
	_mouth_frames.clear()
	_blink_tex = null
	if fr.is_empty():
		_face.texture = null
		return
	# Layer order of the original: head, expression (the line's mood), mouth,
	# then hair / forehead (frame 1) and shoulders (frame 34) over them.
	var expr: int = mood if mood != 255 and mood < fr.size() else -1
	_face_still = _tex(_face_image(fr, [expr], at, pal))
	_face.texture = _face_still
	for k in MOUTH:
		if k < fr.size():
			_mouth_frames.append(_tex(_face_image(fr, [expr, k], at, pal)))
	if BLINK < fr.size():
		_blink_tex = _tex(_face_image(fr, [BLINK], at, pal))


func _face_image(fr: Array, features: Array, at: Vector2i, pal: PackedColorArray) -> Image:
	var canvas := Art.new_canvas()
	var order := [0]
	for k in features:
		if k >= 0:
			order.append(k)
	order.append_array([HAIR, SHOULDERS])
	for k in order:
		if k < fr.size():
			Art.blit(canvas, fr[k], at)
	return Art.canvas_image(canvas, pal)


# --- speech -----------------------------------------------------------------------

func _say(speaker: String, voc: String, text: String) -> void:
	_name.text = _display_name(speaker)
	_text.text = campaign.substitute(text) if campaign != null else text
	_advance = false
	var stream: AudioStream = null
	if voc != "":
		var data := SCData.read("F:%s.VOC" % voc.to_upper())
		if data.size() > 0:
			stream = Voc.to_stream(data)
	var duration := maxf(2.0, text.length() * 0.06)
	if stream != null:
		_voice.stream = stream
		_voice.play()
		duration = stream.get_length() + 0.35
	_talking = stream != null and not _mouth_frames.is_empty()
	# Auto-advance in demo/headless mode (--demo or --auto)
	var auto_advance := OS.get_cmdline_user_args().has("--demo") or OS.get_cmdline_user_args().has("--auto")
	var t := 0.0
	while t < duration and not _advance and not _skip and not auto_advance:
		await get_tree().process_frame
		t += get_process_delta_time()
		if _voice.playing == false and stream != null and t > stream.get_length():
			_talking = false
	_talking = false
	_face.texture = _face_still if _face.texture != null else null
	_voice.stop()


func _display_name(n: String) -> String:
	if n == "" :
		return ""
	if n.begins_with("air"):
		return "%s %s" % [campaign.names.N, campaign.names.S] if campaign != null else "You"
	var names := {"far": "Farhad", "muh": "Muhammed", "men": "Mendez", "pri": "Prideaux",
		"walt": "Walters", "bill": "Billy"}
	var base := n.rstrip("0123456789")
	return names.get(base, base.capitalize())


func _ask(options: Array) -> int:
	for c in _choices.get_children():
		c.queue_free()
	var picked := [-1]
	for k in options.size():
		var b := Button.new()
		b.text = options[k]
		b.pressed.connect(func(): picked[0] = k)
		_choices.add_child(b)
	_choices.get_child(0).grab_focus()
	# Auto-answer in demo/headless mode: Yes (0) for yes/no, first wingman for wingman selection
	var auto_advance := OS.get_cmdline_user_args().has("--demo") or OS.get_cmdline_user_args().has("--auto")
	if auto_advance:
		picked[0] = 0
	while picked[0] < 0 and not _skip and not auto_advance:
		await get_tree().process_frame
	for c in _choices.get_children():
		c.queue_free()
	return maxi(picked[0], 0)


func _process(dt: float) -> void:
	_anim_t += dt
	if _face.texture == null or _face_still == null:
		return
	if _talking and not _mouth_frames.is_empty():
		if fmod(_anim_t, 0.09) < dt:
			_face.texture = _mouth_frames[randi() % _mouth_frames.size()]
	elif _blink_tex != null:
		_face.texture = _blink_tex if fmod(_anim_t, 3.7) < 0.14 else _face_still


func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed("ui_cancel") or event.is_action_pressed("pause"):
		_skip = true
		get_viewport().set_input_as_handled()
	elif _choices.get_child_count() == 0 and (event.is_action_pressed("ui_accept") or
			(event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT)):
		_advance = true
		get_viewport().set_input_as_handled()
