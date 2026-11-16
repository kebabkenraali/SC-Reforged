## Browse every RealSpace object in the original data with modern rendering.
extends Control

const UiTheme = preload("res://scripts/ui/ui_theme.gd")

signal back

var initial_model := ""
var _list: ItemList
var _info: Label
var _lod: SpinBox
var _pivot: Node3D
var _cam: Camera3D
var _orbit := Vector2(0.8, 0.3)
var _dist := 30.0
var _current := ""


func _ready() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	var svc := SubViewportContainer.new()
	svc.stretch = true
	svc.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(svc)
	var vp := SubViewport.new()
	vp.msaa_3d = Viewport.MSAA_4X
	svc.add_child(vp)
	var world := Node3D.new()
	vp.add_child(world)
	var sky_mat := ProceduralSkyMaterial.new()
	var sky := Sky.new()
	sky.sky_material = sky_mat
	var env := Environment.new()
	env.background_mode = Environment.BG_SKY
	env.sky = sky
	env.ambient_light_source = Environment.AMBIENT_SOURCE_SKY
	env.tonemap_mode = Environment.TONE_MAPPER_ACES
	env.ssao_enabled = true
	var we := WorldEnvironment.new()
	we.environment = env
	world.add_child(we)
	var sun := DirectionalLight3D.new()
	sun.rotation = Vector3(deg_to_rad(-45), deg_to_rad(-30), 0)
	sun.shadow_enabled = true
	world.add_child(sun)
	var ground := MeshInstance3D.new()
	var pm := PlaneMesh.new()
	pm.size = Vector2(400, 400)
	var fm := StandardMaterial3D.new()
	fm.albedo_color = Color(0.32, 0.33, 0.3)
	pm.material = fm
	ground.mesh = pm
	world.add_child(ground)
	_pivot = Node3D.new()
	world.add_child(_pivot)
	_cam = Camera3D.new()
	_cam.far = 5000
	world.add_child(_cam)

	var panel := PanelContainer.new()
	panel.position = Vector2(20, 20)
	panel.custom_minimum_size = Vector2(340, 0)
	panel.size_flags_vertical = Control.SIZE_EXPAND_FILL
	panel.anchor_bottom = 1.0
	panel.offset_bottom = -20
	add_child(panel)
	var box := VBoxContainer.new()
	panel.add_child(box)
	box.add_child(UiTheme.title_label("Model viewer", 26))
	_list = ItemList.new()
	_list.size_flags_vertical = Control.SIZE_EXPAND_FILL
	box.add_child(_list)
	var row := HBoxContainer.new()
	var ll := Label.new()
	ll.text = "LOD"
	row.add_child(ll)
	_lod = SpinBox.new()
	_lod.min_value = 0
	_lod.max_value = 3
	_lod.value_changed.connect(func(_v): _show(_current))
	row.add_child(_lod)
	box.add_child(row)
	_info = Label.new()
	_info.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	box.add_child(_info)
	var b := Button.new()
	b.text = "Back"
	b.pressed.connect(func(): back.emit())
	box.add_child(b)

	var sel := 0
	for n in SCData.list("OBJECTS/", ".IFF"):
		if SCData.model(n) == null:
			continue
		_list.add_item(n.get_file().get_basename())
		_list.set_item_metadata(_list.item_count - 1, n)
		if n == initial_model or (initial_model == "" and n == "OBJECTS/F-16DES.IFF"):
			sel = _list.item_count - 1
	_list.item_selected.connect(func(i): _show(_list.get_item_metadata(i)))
	if _list.item_count > 0:
		_list.select(sel)
		_list.ensure_current_is_visible()
		_show(_list.get_item_metadata(sel))


func _show(name: String) -> void:
	_current = name
	for c in _pivot.get_children():
		c.queue_free()
	var m = SCData.model(name)
	if m == null:
		return
	var mi := MeshInstance3D.new()
	mi.mesh = m.build_mesh(SCData.palette(), int(_lod.value), Settings.get_value("video", "smooth_textures"))
	var box: AABB = m.aabb()
	mi.position = -box.get_center() + Vector3.UP * box.size.y * 0.5
	_pivot.add_child(mi)
	_dist = maxf(4.0, box.size.length() * 1.1)
	var tris := 0
	for s in mi.mesh.get_surface_count():
		tris += mi.mesh.surface_get_array_len(s) / 3
	_info.text = "%s\nSize: %.1f × %.1f × %.1f m\n%d vertices, %d triangles (LOD %d/%d)\n%d textures" % [
		name, box.size.x, box.size.z, box.size.y, m.vertices.size(), tris, int(_lod.value),
		m.lod_count() - 1, m.textures.size()]


func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventMouseMotion and Input.is_mouse_button_pressed(MOUSE_BUTTON_LEFT):
		_orbit += Vector2(-event.relative.x, event.relative.y) * 0.006
		_orbit.y = clampf(_orbit.y, -0.2, 1.4)
	elif event is InputEventMouseButton and event.pressed:
		if event.button_index == MOUSE_BUTTON_WHEEL_UP:
			_dist *= 0.9
		elif event.button_index == MOUSE_BUTTON_WHEEL_DOWN:
			_dist *= 1.1
	elif event.is_action_pressed("pause"):
		back.emit()


func _process(dt: float) -> void:
	if not Input.is_mouse_button_pressed(MOUSE_BUTTON_LEFT):
		_orbit.x += dt * 0.2
	var h: float = _pivot.get_child(0).mesh.get_aabb().size.y * 0.5 if _pivot.get_child_count() > 0 else 1.0
	var dir := Vector3(sin(_orbit.x) * cos(_orbit.y), sin(_orbit.y), cos(_orbit.x) * cos(_orbit.y))
	_cam.position = Vector3(0, h, 0) + dir * _dist
	_cam.look_at(Vector3(0, h, 0))
