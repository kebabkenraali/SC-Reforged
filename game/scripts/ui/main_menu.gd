## Main menu over a live 3D backdrop of an original aircraft model.
extends Control

const Demo = preload("res://scripts/core/demo.gd")

const UiTheme = preload("res://scripts/ui/ui_theme.gd")
const SettingsMenu = preload("res://scripts/ui/settings_menu.gd")

signal start_flight(area: String, plane: String, mission: String)
signal open_viewer
signal start_campaign(new_game: bool)

static var _aircraft_cache := PackedStringArray()

var _areas: OptionButton
var _planes: OptionButton
var _missions: OptionButton
var _spinner: Node3D


func _ready() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_build_backdrop()

	var margin := MarginContainer.new()
	margin.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	for side in ["left", "top", "bottom"]:
		margin.add_theme_constant_override("margin_" + side, 70)
	add_child(margin)
	var panel := PanelContainer.new()
	panel.size_flags_horizontal = Control.SIZE_SHRINK_BEGIN
	panel.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	margin.add_child(panel)
	var box := VBoxContainer.new()
	box.custom_minimum_size = Vector2(440, 0)
	box.add_theme_constant_override("separation", 12)
	panel.add_child(box)

	var demo := Demo.enabled()
	box.add_child(UiTheme.title_label("STRIKE COMMANDER", 44))
	var sub := Label.new()
	sub.text = "Demo – the opening and the first mission" if demo else "Reforged – a modern engine for the original data"
	sub.add_theme_color_override("font_color", Color(0.75, 0.75, 0.72))
	box.add_child(sub)
	box.add_child(HSeparator.new())

	var fly: Button = null
	if not demo:
		box.add_child(_caption("Mission"))
		_missions = OptionButton.new()
		_missions.add_item("Free flight (no mission)")
		_missions.set_item_metadata(0, "")
		for m in SCData.missions():
			_missions.add_item("%s – %s" % [m.file.get_file().get_basename(), m.name])
			_missions.set_item_metadata(_missions.item_count - 1, m.file)
		_missions.item_selected.connect(func(_i): _update_mission())
		box.add_child(_missions)

		box.add_child(_caption("Theatre"))
		_areas = OptionButton.new()
		for a in SCData.terrain_names():
			_areas.add_item(a)
			if a == "CANYON":
				_areas.select(_areas.item_count - 1)
		box.add_child(_areas)

		box.add_child(_caption("Aircraft"))
		_planes = OptionButton.new()
		for p in aircraft_models():
			_planes.add_item(p.get_file().get_basename())
			_planes.set_item_metadata(_planes.item_count - 1, p)
			if p == "OBJECTS/F-16DES.IFF":
				_planes.select(_planes.item_count - 1)
		_planes.item_selected.connect(func(_i): _show_plane())
		box.add_child(_planes)

		fly = Button.new()
		fly.text = "Fly"
		fly.pressed.connect(func(): start_flight.emit(_areas.get_item_text(_areas.selected), _selected_plane(),
			_missions.get_item_metadata(_missions.selected)))
		box.add_child(fly)
	var camp := Button.new()
	camp.text = "Start demo" if demo else "New campaign"
	camp.pressed.connect(func(): start_campaign.emit(true))
	box.add_child(camp)
	if load("res://scripts/game/campaign.gd").has_save():
		var cont := Button.new()
		cont.text = "Continue demo" if demo else "Continue campaign"
		cont.pressed.connect(func(): start_campaign.emit(false))
		box.add_child(cont)
	if not demo:
		var viewer := Button.new()
		viewer.text = "Model viewer"
		viewer.pressed.connect(func(): open_viewer.emit())
		box.add_child(viewer)
	var settings := Button.new()
	settings.text = "Options"
	settings.pressed.connect(func(): add_child(SettingsMenu.new()))
	box.add_child(settings)
	var quit := Button.new()
	quit.text = "Quit"
	quit.pressed.connect(func(): get_tree().quit())
	box.add_child(quit)

	var foot := Label.new()
	foot.text = "Data: " + SCData.game_dir
	foot.add_theme_font_size_override("font_size", 13)
	foot.add_theme_color_override("font_color", Color(0.6, 0.6, 0.6))
	box.add_child(foot)
	if demo:
		camp.grab_focus()
	else:
		fly.grab_focus()
	_show_plane()


static func aircraft_models() -> PackedStringArray:
	if _aircraft_cache.is_empty():
		var tag := "JETP".to_ascii_buffer()
		for n in SCData.list("OBJECTS/", ".IFF"):
			if "CKPT" in n or "DEB" in n or "LOAD" in n:
				continue
			var buf: PackedByteArray = SCData.read(n)
			if _find(buf, tag) >= 0 and SCData.model(n) != null:
				_aircraft_cache.append(n)
	return _aircraft_cache


static func _find(buf: PackedByteArray, tag: PackedByteArray) -> int:
	var i := buf.find(tag[0])
	while i >= 0 and i + 4 <= buf.size():
		if buf[i + 1] == tag[1] and buf[i + 2] == tag[2] and buf[i + 3] == tag[3]:
			return i
		i = buf.find(tag[0], i + 1)
	return -1


## A mission decides the area and the aircraft.
func _update_mission() -> void:
	var file: String = _missions.get_item_metadata(_missions.selected)
	_areas.disabled = file != ""
	_planes.disabled = file != ""
	if file == "":
		return
	for m in SCData.missions():
		if m.file == file:
			for i in _areas.item_count:
				if _areas.get_item_text(i) == m.area:
					_areas.select(i)


func _selected_plane() -> String:
	if _planes == null or _planes.item_count == 0:
		return "OBJECTS/F-16DES.IFF"
	return _planes.get_item_metadata(_planes.selected)


func _caption(t: String) -> Label:
	var l := Label.new()
	l.text = t
	l.add_theme_font_size_override("font_size", 15)
	l.add_theme_color_override("font_color", UiTheme.ACCENT)
	return l


func _build_backdrop() -> void:
	var svc := SubViewportContainer.new()
	svc.stretch = true
	svc.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	svc.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(svc)
	var vp := SubViewport.new()
	vp.msaa_3d = Viewport.MSAA_4X
	svc.add_child(vp)
	var world := Node3D.new()
	vp.add_child(world)

	var sky_mat := ProceduralSkyMaterial.new()
	sky_mat.sky_top_color = Color(0.05, 0.08, 0.18)
	sky_mat.sky_horizon_color = Color(0.85, 0.45, 0.2)
	sky_mat.ground_horizon_color = Color(0.4, 0.22, 0.12)
	sky_mat.ground_bottom_color = Color(0.05, 0.04, 0.04)
	var sky := Sky.new()
	sky.sky_material = sky_mat
	var env := Environment.new()
	env.background_mode = Environment.BG_SKY
	env.sky = sky
	env.ambient_light_source = Environment.AMBIENT_SOURCE_SKY
	env.tonemap_mode = Environment.TONE_MAPPER_ACES
	env.glow_enabled = true
	var we := WorldEnvironment.new()
	we.environment = env
	world.add_child(we)
	var sun := DirectionalLight3D.new()
	sun.rotation = Vector3(deg_to_rad(-20), deg_to_rad(30), 0)
	sun.light_color = Color(1.0, 0.75, 0.5)
	sun.light_energy = 1.6
	sun.shadow_enabled = true
	world.add_child(sun)
	var cam := Camera3D.new()
	cam.position = Vector3(0, 3.5, 30)
	cam.fov = 45
	world.add_child(cam)
	cam.look_at(Vector3(-5.5, 0, 0))
	_spinner = Node3D.new()
	_spinner.position = Vector3(3.0, 0, 0)
	world.add_child(_spinner)


func _show_plane() -> void:
	for c in _spinner.get_children():
		c.queue_free()
	var m = SCData.model(_selected_plane())
	if m == null:
		return
	var mi := MeshInstance3D.new()
	mi.mesh = m.build_mesh(SCData.palette(), 0, Settings.get_value("video", "smooth_textures"))
	mi.position = -m.aabb().get_center()
	_spinner.add_child(mi)


func _process(dt: float) -> void:
	if _spinner:
		_spinner.rotate_y(dt * 0.25)
