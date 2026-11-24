## Small live tracking window and an event message window inside the cockpit.
##
## The tracking window is a real 3D camera sharing the flight scene's World3D:
## it follows the launched missile/bomb and looks at its target. The event
## window is a 2D SubViewport mapped onto a quad, like the HUD framebuffer.
## Tracking is shown in Arcade mode only; events are shown in both modes.
extends Node3D

const GREEN := Color(0.35, 1.0, 0.45)
const TRACK_SIZE := Vector2i(480, 270)
const EVENT_SIZE := Vector2i(640, 128)
const S_FORWARD := 3.5
const S_LATERAL := 3.5
const S_UP := 2.0

var scene
var seat: Vector3
var arcade: bool = true

var track_vp: SubViewport = null
var track_cam: Camera3D = null
var track_quad: MeshInstance3D = null
var follow: Node3D = null          # missile / bomb in flight
var look: Node3D = null            # target aircraft / ground target
var impact: Marker3D = null        # bomb's predicted impact point
var track_timer: float = 0.0
var track_title: String = ""
var track_label: Label = null

var event_vp: SubViewport = null
var event_label: Label = null
var event_quad: MeshInstance3D = null
var event_timer: float = 0.0


func setup(host_scene, eye_local: Vector3, aircraft: Node3D, arcade_mode: bool) -> void:
	scene = host_scene
	seat = eye_local
	arcade = arcade_mode

	# --- live tracking camera: same world, independent viewpoint -------------
	track_vp = SubViewport.new()
	track_vp.name = "TrackFramebuffer"
	track_vp.size = TRACK_SIZE
	track_vp.transparent_bg = true
	track_vp.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	track_vp.world_3d = aircraft.get_world_3d()
	add_child(track_vp)
	track_cam = Camera3D.new()
	track_cam.name = "TrackCamera"
	track_cam.fov = 55.0
	track_vp.add_child(track_cam)
	var tui := Control.new()
	tui.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	track_vp.add_child(tui)
	track_label = Label.new()
	track_label.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	track_label.add_theme_font_size_override("font_size", 22)
	track_label.modulate = GREEN
	tui.add_child(track_label)
	track_quad = _quad("TargetTrack", _pos(Vector3(5.9, 0.95, 1.25)), Vector2(2.8, 1.58), track_vp.get_texture())

	# --- event text panel ----------------------------------------------------
	event_vp = SubViewport.new()
	event_vp.name = "EventFramebuffer"
	event_vp.size = EVENT_SIZE
	event_vp.transparent_bg = true
	event_vp.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	add_child(event_vp)
	var ui := Control.new()
	ui.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	event_vp.add_child(ui)
	var frame := ColorRect.new()
	frame.color = Color(0.0, 0.08, 0.03, 0.72)
	frame.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	ui.add_child(frame)
	event_label = Label.new()
	event_label.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	event_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	event_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	event_label.add_theme_font_size_override("font_size", 26)
	event_label.modulate = GREEN
	ui.add_child(event_label)
	event_quad = _quad("EventPanel", _pos(Vector3(5.9, 0.18, 1.25)), Vector2(3.2, 0.64), event_vp.get_texture())

	hide_all()


func set_arcade(v: bool) -> void:
	arcade = v
	if not v:
		track_quad.visible = false


## Missile launch: follow the missile and look at its target.
func show_missile(missile: Node3D, target: Node3D, title: String) -> void:
	if not arcade:
		return
	follow = missile
	look = target
	if impact != null:
		impact.free()
		impact = null
	track_title = "MISSILE  " + title
	track_timer = 6.0


## Bomb release: follow the bomb, look at its predicted impact point.
func show_bomb(bomb: Node3D, title: String) -> void:
	if not arcade:
		return
	follow = bomb
	look = null
	if impact == null:
		impact = Marker3D.new()
		if scene != null and scene is Node:
			scene.add_child(impact)
		else:
			add_child(impact)
	track_title = "BOMB  " + title
	track_timer = 6.0


## Important mission event, shown in both modes.
func show_event(text: String, seconds: float = 5.0) -> void:
	if event_label == null:
		return
	event_label.text = text
	event_timer = seconds


func hide_all() -> void:
	if track_quad != null:
		track_quad.visible = false
	if event_quad != null:
		event_quad.visible = false
	track_timer = 0.0
	event_timer = 0.0


func _process(dt: float) -> void:
	track_timer = maxf(0.0, track_timer - dt)
	event_timer = maxf(0.0, event_timer - dt)
	if track_quad != null:
		track_quad.visible = arcade and track_timer > 0.0 and is_instance_valid(follow)
	if event_quad != null:
		event_quad.visible = event_timer > 0.0
	if not track_quad.visible:
		return
	var terrain = scene.get("terrain") if scene != null else null
	if impact != null and is_instance_valid(follow) and follow.has_method("predict_impact") and terrain != null:
		impact.global_position = follow.predict_impact(terrain)
	var aim: Vector3
	if is_instance_valid(look):
		aim = look.center() if look.has_method("center") else look.global_position
	elif impact != null:
		aim = impact.global_position
	else:
		aim = follow.global_position
	var from: Vector3 = follow.global_position
	var to_aim: Vector3 = aim - from
	if to_aim.length() < 1.0:
		return
	var back: Vector3 = from - to_aim.normalized() * 14.0 + Vector3.UP * 4.0
	track_cam.global_position = back
	track_cam.look_at(aim, Vector3.UP)
	if track_label != null:
		track_label.text = track_title


func _pos(lrs: Vector3) -> Vector3:
	return seat + Vector3(-lrs.z * S_LATERAL, lrs.y * S_UP - 1.0, -lrs.x * S_FORWARD)


func _quad(name: String, p: Vector3, sz: Vector2, texture: Texture2D) -> MeshInstance3D:
	var mesh := QuadMesh.new()
	mesh.size = sz
	var mi := MeshInstance3D.new()
	mi.name = name
	mi.mesh = mesh
	mi.position = p
	var mat := StandardMaterial3D.new()
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.albedo_texture = texture
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	mat.cull_mode = BaseMaterial3D.CULL_DISABLED
	mat.no_depth_test = true
	mat.depth_draw_mode = BaseMaterial3D.DEPTH_DRAW_DISABLED
	mi.material_override = mat
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(mi)
	return mi
