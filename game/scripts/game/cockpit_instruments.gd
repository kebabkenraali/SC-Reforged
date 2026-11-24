## Live instruments inside the original 3D cockpit. Placement follows
## libRealSpace SCJetVirtualCockpit::f16Layout() (FORM:CKPT quads): eye at the
## origin, instruments ~6 units ahead, MFDs at +/-2.1 lateral, RAWS/ALTI/
## SPEED/COMM below. Built from real 3D quads + Label3D text so they are
## stereoscopic in VR and stay attached to the aircraft when the head turns.
extends Node3D

const GREEN := Color(0.32, 1.0, 0.42)
const AMBER := Color(1.0, 0.72, 0.25)
const RED := Color(1.0, 0.30, 0.25)
const CYAN := Color(0.40, 1.0, 1.0)
const DARK := Color(0.01, 0.07, 0.03)
const DARK_GREEN := Color(0.01, 0.12, 0.05)  # left MFD: stores / weapons

const LAYOUT := {
	"raws":  Vector3(6.15, -1.915, -1.625),
	"alti":  Vector3(5.90, -3.535, 0.460),
	"speed": Vector3(5.90, -3.535, -0.460),
	"mfd_l": Vector3(6.15, -3.450, 2.075),
	"mfd_r": Vector3(6.15, -3.450, -2.075),
	"comm":  Vector3(6.10, -1.025, 0.0),
}
const SIZE := {
	"raws":  Vector2(3.4, 3.8),
	"alti":  Vector2(3.2, 2.8),
	"speed": Vector2(3.2, 2.8),
	"mfd_l": Vector2(6.6, 6.8),
	"mfd_r": Vector2(6.6, 6.8),
	"comm":  Vector2(13.5, 0.6),
}

const S_FORWARD := 3.5
const S_LATERAL := 3.5
const S_UP := 2.0

var scene
var body: Node3D = null
var eye_local: Vector3
var alti_label: Label3D
var speed_label: Label3D
var comm_label: Label3D
var store_label: Label3D
var g_label: Label3D
var heading_label: Label3D
var range_label: Label3D
var warn_label: Label3D
var inrange_label: Label3D
var closure_label: Label3D
var waypoint_label: Label3D
var adi_rot: Node3D
var pitch_lines: Array[MeshInstance3D] = []
var blips: Array[MeshInstance3D] = []
var quads: Array[MeshInstance3D] = []
var hud_viewport: SubViewport = null
var hud_quad: MeshInstance3D = null
var hud_node: Control = null
var hud_home: Node = null


func setup(host_scene, seat: Vector3) -> void:
	scene = host_scene
	body = get_parent()
	eye_local = seat
	# Bevelled backing plates give the flat instrument faces real depth.
	for key in LAYOUT:
		var sz: Vector2 = SIZE[key]
		var p := _pos(LAYOUT[key])
		var face := sz * 0.72
		_quad("bezel_" + key, p + Vector3(0, 0, 0.12), face * 1.10, Color(0.10, 0.14, 0.12))
		_quad("face_" + key, p, face, DARK_GREEN if key == "mfd_l" else DARK)

	# Artificial horizon: blue/brown halves on a node rotated by aircraft bank.
	adi_rot = Node3D.new()
	adi_rot.name = "adi_rotation"
	adi_rot.position = _pos(LAYOUT["raws"])
	add_child(adi_rot)
	_quad_child(adi_rot, "sky", Vector2(0, 0.68), Vector2(2.3, 1.36), Color(0.12, 0.38, 0.66))
	_quad_child(adi_rot, "ground", Vector2(0, -0.68), Vector2(2.3, 1.36), Color(0.42, 0.26, 0.13))
	_quad_child(adi_rot, "horizon", Vector2.ZERO, Vector2(2.3, 0.06), Color.WHITE)
	for i in 7:
		var line := _quad_child(adi_rot, "pitch%d" % i, Vector2(0, 0), Vector2(1.1, 0.05), Color.WHITE)
		pitch_lines.append(line)
	# Fixed aircraft symbol in front of the rotating ball.
	_quad("adi_wing_l", adi_rot.position + Vector3(-0.8, 0, 0.25), Vector2(0.7, 0.10), AMBER)
	_quad("adi_wing_r", adi_rot.position + Vector3(0.8, 0, 0.25), Vector2(0.7, 0.10), AMBER)

	alti_label = _label("alti_value", _pos(LAYOUT["alti"]) + Vector3(0, -0.4, 0.3), "0", 30, AMBER)
	speed_label = _label("speed_value", _pos(LAYOUT["speed"]) + Vector3(0, -0.4, 0.3), "0", 30, AMBER)
	_label("alti_title", _pos(LAYOUT["alti"]) + Vector3(0, -1.6, 0.3), "ALT", 18, GREEN)
	_label("speed_title", _pos(LAYOUT["speed"]) + Vector3(0, -1.6, 0.3), "KTS", 18, GREEN)
	store_label = _label("stores", _pos(LAYOUT["mfd_l"]) + Vector3(0, 0, 0.3), "STORES", 26, GREEN)
	# HUD text anchored to the aircraft (libRealSpace f16Layout HUD quad:
	# corners 5.8..6.0 forward, +2.0..-0.8 up, -1.22..1.35 lateral).
	g_label = _label("hud_g", _pos(Vector3(5.8, 1.8, 1.0)), "G 1.0", 22, GREEN)
	heading_label = _label("hud_heading", _pos(Vector3(5.9, -0.6, 0.065)), "000", 24, GREEN)
	range_label = _label("hud_range", _pos(Vector3(6.0, -0.5, -1.0)), "R 0.0", 20, GREEN)
	warn_label = _label("hud_warning", _pos(Vector3(5.9, 0.4, 0.0)), "", 30, AMBER)
	inrange_label = _label("hud_in_range", _pos(Vector3(6.0, -0.9, 1.1)), "", 20, AMBER)
	closure_label = _label("hud_closure", _pos(Vector3(6.0, -0.9, -1.0)), "", 20, GREEN)
	waypoint_label = _label("hud_waypoint", _pos(Vector3(6.0, -1.3, -1.0)), "", 20, GREEN)
	comm_label = _label("comm", _pos(LAYOUT["comm"]) + Vector3(0, 0, 0.3), "", 22, GREEN)
	_label("radar_title", _pos(LAYOUT["mfd_r"]) + Vector3(0, 2.7, 0.3), "AIR RADAR 20", 20, GREEN)
	for i in 8:
		blips.append(_quad("blip%d" % i, _pos(LAYOUT["mfd_r"]), Vector2(0.25, 0.25), RED, false))


## libRealSpace way: render the HUD into a framebuffer and map that texture
## onto a quad in cockpit space (f16Layout: x 5.8..6.0, y +2.0..-0.8,
## z -1.22..+1.35). The HUD then stays attached to the aircraft instead of
## sliding across the screen when the pilot turns their head.
func attach_hud(hud: Control, home: Node) -> void:
	if hud == null:
		return
	hud_node = hud
	hud_home = home
	hud_viewport = SubViewport.new()
	hud_viewport.name = "HUDFramebuffer"
	hud_viewport.size = Vector2i(1600, 900)
	hud_viewport.transparent_bg = true
	hud_viewport.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	add_child(hud_viewport)
	var q := QuadMesh.new()
	q.size = Vector2(18.0, 18.0 * 900.0 / 1600.0)
	hud_quad = MeshInstance3D.new()
	hud_quad.name = "HUDGlass"
	hud_quad.mesh = q
	var mat := StandardMaterial3D.new()
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.albedo_texture = hud_viewport.get_texture()
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	mat.cull_mode = BaseMaterial3D.CULL_DISABLED
	mat.depth_draw_mode = BaseMaterial3D.DEPTH_DRAW_DISABLED
	mat.no_depth_test = true
	hud_quad.material_override = mat
	# HUD quad centre from the original layout, scaled to our pit mesh.
	hud_quad.position = _pos(Vector3(5.9, 3.0, 0.065))
	body.add_child(hud_quad)


func _pos(lrs: Vector3) -> Vector3:
	# Aircraft forward is -Z, screen right is -X, up is +Y.
	return eye_local + Vector3(-lrs.z * S_LATERAL, lrs.y * S_UP - 1.0, -lrs.x * S_FORWARD)


func _mat(color: Color) -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	m.albedo_color = color
	m.cull_mode = BaseMaterial3D.CULL_DISABLED
	# Transparent pass draws after the opaque pit mesh; with depth test off the
	# luminous gauges sit on top of the panel at any camera angle.
	m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	m.no_depth_test = true
	m.depth_draw_mode = BaseMaterial3D.DEPTH_DRAW_DISABLED
	return m


func _quad(name: String, p: Vector3, sz: Vector2, color: Color, vis := true) -> MeshInstance3D:
	var mesh := QuadMesh.new()
	mesh.size = sz
	var mi := MeshInstance3D.new()
	mi.name = name
	mi.mesh = mesh
	mi.position = p
	mi.material_override = _mat(color)
	mi.visible = vis
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(mi)
	quads.append(mi)
	return mi


func _quad_child(parent: Node3D, name: String, p: Vector2, sz: Vector2, color: Color) -> MeshInstance3D:
	var mesh := QuadMesh.new()
	mesh.size = sz
	var mi := MeshInstance3D.new()
	mi.name = name
	mi.mesh = mesh
	mi.position = Vector3(p.x, p.y, 0.10)
	mi.material_override = _mat(color)
	parent.add_child(mi)
	return mi


func _label(name: String, p: Vector3, text: String, size: int, color: Color) -> Label3D:
	var l := Label3D.new()
	l.name = name
	l.text = text
	l.font_size = size
	l.pixel_size = 0.02
	l.modulate = color
	l.no_depth_test = true
	l.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	l.position = p
	add_child(l)
	return l


func _process(_dt: float) -> void:
	if scene == null or scene.player == null or not visible:
		return
	if hud_node != null and hud_viewport != null:
		# VR uses its own composition layer path; do not fight main.gd there.
		if not scene.vr_active:
			var seat_view: bool = scene.rig.mode in [1, 2]
			var want: Node = hud_viewport if seat_view else hud_home
			if want != null and hud_node.get_parent() != want:
				hud_node.reparent(want)
			if hud_quad != null:
				hud_quad.visible = seat_view
	var p = scene.player
	var b: Basis = p.global_transform.basis
	var forward := -b.z
	var pitch := rad_to_deg(asin(clampf(forward.y, -1.0, 1.0)))
	var roll := rad_to_deg(atan2(b.x.y, b.y.y))
	adi_rot.rotation.z = deg_to_rad(roll)
	for i in pitch_lines.size():
		var deg := (i - 3) * 20
		var y := clampf((deg - pitch) * 0.045, -1.7, 1.7)
		pitch_lines[i].position.y = y
		pitch_lines[i].visible = absf(deg - pitch) < 55.0

	alti_label.text = "%d" % int(p.global_position.y * 3.28084)
	speed_label.text = "%d" % int(p.speed() * 1.94384)
	var stores: Array[String] = []
	for key in p.missiles:
		stores.append("%s %d" % [key, p.missiles[key]])
	store_label.text = "  ".join(stores) if stores.size() else "EMPTY"
	if scene.hud != null and scene.hud._msg_time > 0.0:
		comm_label.text = scene.hud._msg
	else:
		comm_label.text = ""

	var heading := fposmod(rad_to_deg(atan2(-b.z.x, b.z.z)), 360.0)
	heading_label.text = "%03d" % int(heading)
	g_label.text = "G %.1f" % p.g_force
	if scene.player_lock != null and scene.player_lock.alive:
		var lp: Vector3 = scene.player_lock.global_position
		var d: float = p.global_position.distance_to(lp) / 1852.0
		range_label.text = "R %.1f" % d
		var dir: Vector3 = (lp - p.global_position).normalized()
		var closing: float = -(p.velocity - scene.player_lock.velocity).dot(dir) * 1.94384
		closure_label.text = "C %.0f" % closing
		var rng: float = scene.aa_weapon_range(p.global_position.distance_to(lp))
		inrange_label.text = "IN RNG" if p.global_position.distance_to(lp) <= rng or p.global_position.distance_to(lp) < 1850.0 else ""
	else:
		range_label.text = ""
		closure_label.text = ""
		inrange_label.text = ""
	if scene.mission != null and scene.nav_index < scene.waypoints.size():
		var wpos: Vector3 = scene.waypoints[scene.nav_index].pos
		waypoint_label.text = "D %.1f" % (Vector2(wpos.x - p.global_position.x, wpos.z - p.global_position.z).length() / 1852.0)
	else:
		waypoint_label.text = ""
	warn_label.text = ""
	if scene.missiles_in_flight.any(func(m): return m != null and m.alive and m.target == p):
		warn_label.text = "MISSILE"
	elif p.on_ground == false and (p.global_position.y - (scene.terrain.height_at(p.global_position.x, p.global_position.z) if scene.terrain else 0.0)) * 3.28084 < 500:
		warn_label.text = "PULL UP"

	# Radar blips, relative to the aircraft heading.
	var fwd := Vector3(-b.z.x, 0, -b.z.z).normalized()
	var right := fwd.cross(Vector3.UP)
	var center := _pos(LAYOUT["mfd_r"])
	var idx := 0
	for group in [scene.enemies, scene.allies]:
		for e in group:
			if idx >= blips.size(): break
			if e == null or not e.alive or e == p: continue
			var rel: Vector3 = e.global_position - p.global_position
			if rel.dot(fwd) <= 0 or rel.length() > 20000.0: continue
			var xy := Vector2(rel.dot(right) / 20000.0, -rel.dot(fwd) / 20000.0) * 5.5
			blips[idx].position = center + Vector3(xy.x, xy.y, 0.3)
			blips[idx].material_override.albedo_color = RED if group == scene.enemies else CYAN
			blips[idx].visible = true
			idx += 1
	for i in range(idx, blips.size()):
		blips[i].visible = false
