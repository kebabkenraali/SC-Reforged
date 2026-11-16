## Settings overlay: graphics, controls (rebindable), data location.
extends Control

const UiTheme = preload("res://scripts/ui/ui_theme.gd")

var _waiting_action := ""
var _bind_buttons := {}


func _ready() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	var dim := ColorRect.new()
	dim.color = Color(0, 0, 0, 0.6)
	dim.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(dim)
	var center := CenterContainer.new()
	center.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(center)
	var panel := PanelContainer.new()
	panel.custom_minimum_size = Vector2(820, 620)
	center.add_child(panel)
	var root := VBoxContainer.new()
	panel.add_child(root)
	root.add_child(UiTheme.title_label("Options", 30))

	var tabs := TabContainer.new()
	tabs.size_flags_vertical = Control.SIZE_EXPAND_FILL
	root.add_child(tabs)
	tabs.add_child(_video_tab())
	tabs.add_child(_controls_tab())
	tabs.add_child(_audio_tab())
	tabs.add_child(_data_tab())

	var close := Button.new()
	close.text = "Close"
	close.pressed.connect(queue_free)
	root.add_child(close)


func _video_tab() -> Control:
	var g := _grid("Graphics")
	_check(g, "Fullscreen", "video", "fullscreen")
	_check(g, "VSync", "video", "vsync")
	_option(g, "Anti-aliasing (MSAA)", "video", "msaa", [["Off", 0], ["2x", 1], ["4x", 2], ["8x", 3]])
	_option(g, "Render resolution", "video", "render_scale",
		[["100 %", 1.0], ["FSR 2 – quality (67 %)", 0.67], ["FSR 2 – performance (50 %)", 0.5]])
	_slider(g, "Field of view", "video", "fov", 50.0, 110.0, 1.0)
	_check(g, "Shadows", "video", "shadows")
	_check(g, "Atmospheric haze", "video", "fog")
	_check(g, "SSAO", "video", "ssao")
	_check(g, "Smooth textures (off = original pixels)", "video", "smooth_textures")
	return g.get_parent().get_parent()


func _controls_tab() -> Control:
	var g := _grid("Controls")
	_check(g, "Invert pitch", "controls", "invert_pitch")
	_slider(g, "Mouse sensitivity", "controls", "mouse_sensitivity", 0.2, 3.0, 0.1)
	_slider(g, "Controller dead zone", "controls", "deadzone", 0.0, 0.4, 0.01)
	for action in Settings.ACTIONS:
		var l := Label.new()
		l.text = Settings.ACTIONS[action][0]
		g.add_child(l)
		var b := Button.new()
		b.pressed.connect(func(): _waiting_action = action; b.text = "Press a key / button…")
		_bind_buttons[action] = b
		g.add_child(b)
	var reset := Button.new()
	reset.text = "Restore default bindings"
	reset.pressed.connect(func(): Settings.reset_bindings(); _refresh_bindings())
	g.add_child(Label.new())
	g.add_child(reset)
	_refresh_bindings()
	return g.get_parent().get_parent()


## Volume, the role -> original sound mapping and a test player for every sound.
func _audio_tab() -> Control:
	var g := _grid("Audio")
	_slider(g, "Volume", "audio", "volume", 0.0, 1.0, 0.05)
	_check(g, "Cut-scene subtitles", "audio", "subtitles")
	var count: int = SCData.sfx_count()
	for role in Sfx.ROLES:
		_label(g, role.capitalize())
		var row := HBoxContainer.new()
		var o := OptionButton.new()
		if role in Sfx.SYNTH:
			o.add_item("Synthesised", -1)
		for i in count:
			var st = SCData.sfx(i)
			o.add_item("Sound %02d  (%.1f s)" % [i, st.get_length() if st else 0.0], i)
		o.select(o.get_item_index(Sfx.index_of(role)))
		o.item_selected.connect(func(i): Settings.set_value("audio", "map_" + role, o.get_item_id(i)))
		row.add_child(o)
		var play := Button.new()
		play.text = "▶"
		play.pressed.connect(func(): Sfx.play_index(o.get_selected_id(), role))
		row.add_child(play)
		g.add_child(row)
	_label(g, "Sound test (all %d)" % count)
	var flow := HFlowContainer.new()
	flow.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	for i in count:
		var b := Button.new()
		b.text = "%02d" % i
		b.pressed.connect(Sfx.play_index.bind(i))
		flow.add_child(b)
	g.add_child(flow)
	return g.get_parent().get_parent()


func _data_tab() -> Control:
	var g := _grid("Game data")
	var l := Label.new()
	l.text = "Original installation:"
	g.add_child(l)
	var v := Label.new()
	v.text = SCData.game_dir
	g.add_child(v)
	var l2 := Label.new()
	l2.text = "Files in archives:"
	g.add_child(l2)
	var v2 := Label.new()
	v2.text = str(SCData.files.size())
	g.add_child(v2)
	return g.get_parent().get_parent()


func _refresh_bindings() -> void:
	for action in _bind_buttons:
		var names := []
		for ev in Settings.action_events(action):
			names.append(Settings.describe(ev))
		_bind_buttons[action].text = ", ".join(names)


func _input(event: InputEvent) -> void:
	if _waiting_action == "":
		return
	var accept := false
	if event is InputEventKey and event.pressed and not event.echo:
		accept = true
	elif event is InputEventJoypadButton and event.pressed:
		accept = true
	elif event is InputEventJoypadMotion and absf(event.axis_value) > 0.6:
		event = event.duplicate()
		event.axis_value = signf(event.axis_value)
		accept = true
	elif event is InputEventMouseButton and event.pressed and event.button_index > MOUSE_BUTTON_LEFT:
		accept = true
	if accept:
		Settings.rebind(_waiting_action, event)
		_waiting_action = ""
		_refresh_bindings()
		get_viewport().set_input_as_handled()


# --- small widget helpers ---------------------------------------------------

func _grid(title: String) -> GridContainer:
	var scroll := ScrollContainer.new()
	scroll.name = title
	var margin := MarginContainer.new()
	margin.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	margin.add_theme_constant_override("margin_left", 12)
	margin.add_theme_constant_override("margin_right", 12)
	margin.add_theme_constant_override("margin_top", 12)
	scroll.add_child(margin)
	var g := GridContainer.new()
	g.columns = 2
	g.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	g.add_theme_constant_override("h_separation", 24)
	g.add_theme_constant_override("v_separation", 8)
	margin.add_child(g)
	return g


func _label(g: GridContainer, text: String) -> void:
	var l := Label.new()
	l.text = text
	l.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	g.add_child(l)


func _check(g: GridContainer, text: String, section: String, key: String) -> void:
	_label(g, text)
	var c := CheckButton.new()
	c.button_pressed = Settings.get_value(section, key)
	c.toggled.connect(func(on): Settings.set_value(section, key, on))
	g.add_child(c)


func _option(g: GridContainer, text: String, section: String, key: String, items: Array) -> void:
	_label(g, text)
	var o := OptionButton.new()
	var cur = Settings.get_value(section, key)
	for i in items.size():
		o.add_item(items[i][0], i)
		if is_equal_approx(float(items[i][1]), float(cur)):
			o.select(i)
	o.item_selected.connect(func(i): Settings.set_value(section, key, items[i][1]))
	g.add_child(o)


func _slider(g: GridContainer, text: String, section: String, key: String, lo: float, hi: float, step: float) -> void:
	_label(g, text)
	var row := HBoxContainer.new()
	var s := HSlider.new()
	s.min_value = lo
	s.max_value = hi
	s.step = step
	s.value = Settings.get_value(section, key)
	s.custom_minimum_size = Vector2(220, 0)
	var v := Label.new()
	v.text = str(s.value)
	s.value_changed.connect(func(x): v.text = str(snappedf(x, step)); Settings.set_value(section, key, x))
	row.add_child(s)
	row.add_child(v)
	g.add_child(row)
