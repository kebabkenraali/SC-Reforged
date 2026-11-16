## Resolution-independent vector HUD: heading tape, speed/altitude boxes,
## pitch ladder (cockpit view), flight path marker, target boxes and status.
extends Control

const GREEN := Color(0.35, 1.0, 0.45, 0.9)
const AMBER := Color(1.0, 0.7, 0.25, 0.95)
const RED := Color(1.0, 0.25, 0.2, 0.95)
const MS_TO_KTS := 1.94384
const M_TO_FT := 3.28084

var scene
var _msg := ""
var _msg_time := 0.0
var _msg_len := 0.0


func _ready() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_IGNORE


func message(text: String, seconds := 3.0) -> void:
	_msg = text
	_msg_time = seconds
	_msg_len = seconds


## Seconds since the current message appeared (30 when none is showing), for
## the radio pacing. The old "30 - time left" made a fresh message look 26 s
## old, so chatter overwrote mission messages at once.
func last_message_age() -> float:
	return _msg_len - _msg_time if _msg_time > 0.0 else 30.0


func _process(dt: float) -> void:
	# Real time: under fast travel (time_scale 8) messages must stay readable.
	_msg_time -= dt / maxf(Engine.time_scale, 0.001)
	queue_redraw()


func _draw() -> void:
	if scene == null or scene.player == null or size.y < 100.0:
		return
	var p = scene.player
	var cam: Camera3D = scene.rig.camera
	var sz := size
	var c := sz * 0.5
	var u := sz.y / 1080.0   # scale unit
	var font := get_theme_default_font()
	var fs := int(20 * u)
	var b: Basis = p.global_transform.basis

	# Heading tape
	var heading := fposmod(rad_to_deg(atan2(-b.z.x, b.z.z)), 360.0)
	var tape_y := 60.0 * u
	draw_line(Vector2(c.x - 220 * u, tape_y), Vector2(c.x + 220 * u, tape_y), GREEN, 2.0)
	for d in range(-30, 31, 5):
		var hd := fposmod(roundf(heading / 5.0) * 5.0 + d, 360.0)
		var off := (hd - heading)
		if off > 180: off -= 360
		if off < -180: off += 360
		var x := c.x + off * 7.0 * u
		if absf(off) > 32: continue
		var major := int(hd) % 10 == 0
		draw_line(Vector2(x, tape_y), Vector2(x, tape_y - (14 if major else 7) * u), GREEN, 2.0)
		if major:
			_text(font, "%03d" % int(hd), Vector2(x, tape_y - 20 * u), fs * 0.8, GREEN)
	draw_line(Vector2(c.x, tape_y + 4 * u), Vector2(c.x, tape_y + 16 * u), AMBER, 3.0)

	# Speed and altitude boxes
	var kts: float = p.speed() * MS_TO_KTS
	var alt_ft: float = p.global_position.y * M_TO_FT
	var agl_ft: float = (p.global_position.y - (scene.terrain.height_at(p.global_position.x, p.global_position.z) if scene.terrain else 0.0)) * M_TO_FT
	_box(font, Vector2(c.x - 380 * u, c.y), "%d" % kts, "KTS  M%.2f" % (p.speed() / 340.0), u)
	_box(font, Vector2(c.x + 380 * u, c.y), "%d" % alt_ft, "FT  R%d" % agl_ft, u)

	# Flight path marker and pitch ladder (cockpit only, where it is conformal)
	if scene.rig.mode == 1:
		_ladder(cam, p, u, font)
	var fpm_world: Vector3 = p.global_position + p.velocity.normalized() * 500.0
	if p.speed() > 10.0 and not cam.is_position_behind(fpm_world):
		var s := cam.unproject_position(fpm_world)
		draw_arc(s, 9 * u, 0, TAU, 20, GREEN, 2.0)
		draw_line(s + Vector2(9, 0) * u, s + Vector2(22, 0) * u, GREEN, 2.0)
		draw_line(s - Vector2(9, 0) * u, s - Vector2(22, 0) * u, GREEN, 2.0)
		draw_line(s - Vector2(0, 9) * u, s - Vector2(0, 18) * u, GREEN, 2.0)
	# Gun cross
	var gun: Vector3 = p.global_position - b.z * 900.0
	if not cam.is_position_behind(gun):
		var g := cam.unproject_position(gun)
		draw_line(g - Vector2(10, 0) * u, g + Vector2(10, 0) * u, AMBER, 2.0)
		draw_line(g - Vector2(0, 10) * u, g + Vector2(0, 10) * u, AMBER, 2.0)

	# Target boxes with range - enemies (FOE, red). Standby ships (briefed
	# raiders that have not been called in yet) are not shown - they have
	# not "appeared" in the scenario yet.
	for e in scene.enemies:
		if not e.alive or e.get("standby"):
			continue
		var wp: Vector3 = e.global_position
		var dist := wp.distance_to(cam.global_position)
		if dist > 60000.0:
			continue
		if cam.is_position_behind(wp):
			continue
		var s := cam.unproject_position(wp)
		if s.x < -20 or s.x > sz.x + 20 or s.y < -20 or s.y > sz.y + 20:
			# Off-screen: an arrow on the bezel so the threat can't be missed.
			var edge := Vector2(clampf(s.x, 40 * u, sz.x - 40 * u), clampf(s.y, 90 * u, sz.y - 150 * u))
			var d := (s - c).normalized()
			draw_circle(edge, 6 * u, RED)
			draw_line(edge, edge + d * 16 * u, RED, 3.0)
			continue
		var r := clampf(e.radius * 600.0 / maxf(dist, 1.0), 10.0, 60.0) * u
		draw_rect(Rect2(s - Vector2(r, r), Vector2(r, r) * 2.0), RED, false, 2.0)
		_text(font, "%s %.1f km" % [e.display_name, dist / 1000.0], s + Vector2(0, r + 18 * u), fs * 0.75, RED)

	# Friendly aircraft boxes (cyan, an X through the box; the player itself
	# is not marked - the camera sits inside them in cockpit view)
	for a in scene.allies:
		if not a.alive or a == p:
			continue
		var wp: Vector3 = a.global_position
		var dist := wp.distance_to(cam.global_position)
		if cam.is_position_behind(wp):
			continue
		var s := cam.unproject_position(wp)
		var r := clampf(a.radius * 600.0 / maxf(dist, 1.0), 10.0, 60.0) * u
		var friendly_color := Color(0.35, 1.0, 1.0, 0.95)  # Cyan for friendlies
		draw_rect(Rect2(s - Vector2(r, r), Vector2(r, r) * 2.0), friendly_color, false, 2.0)
		# Friendly IFF: an X through the box (manual p. 60, "Friendly Target")
		draw_line(s - Vector2(r, r), s + Vector2(r, r), friendly_color, 2.0)
		draw_line(s + Vector2(r, -r), s + Vector2(-r, r), friendly_color, 2.0)
		_text(font, "%s %.1f km" % [a.display_name, dist / 1000.0], s + Vector2(0, r + 18 * u), fs * 0.75, friendly_color)

	# Missile lock
	if scene.player_lock != null and scene.player_lock.alive:
		var lp: Vector3 = scene.player_lock.global_position
		var ldist: float = lp.distance_to(p.global_position)
		if not cam.is_position_behind(lp):
			var s := cam.unproject_position(lp)
			draw_arc(s, 34 * u, 0, TAU, 32, GREEN, 3.0)
			_text(font, "LOCK", s - Vector2(0, 42 * u), fs * 0.8, GREEN)
		# Original HUD readouts: IN RNG (weapon in effective range),
		# "R n.m" (range to target) and "C knots" (closure rate).
		var rng: float = scene.aa_weapon_range(ldist)
		if ldist <= rng or ldist < 1850.0:
			_text(font, "IN RNG", c + Vector2(0, 38 * u), fs * 0.9, AMBER)
		var closing := 0.0
		if ldist > 1.0:
			var dir: Vector3 = (lp - p.global_position) / ldist
			closing = -(p.velocity - scene.player_lock.velocity).dot(dir) * 1.94384
		_text(font, "R %.1f" % (ldist / 1852.0), c + Vector2(0, 60 * u), fs * 0.9, GREEN)
		_text(font, "C %.0f" % closing, c + Vector2(0, 76 * u), fs * 0.9, GREEN)

	# AGM ground lock
	if scene.ground_lock != null and scene.ground_lock.alive:
		var gp: Vector3 = scene.ground_lock.center()
		if not cam.is_position_behind(gp):
			var s := cam.unproject_position(gp)
			var r := 22.0 * u
			draw_rect(Rect2(s - Vector2(r, r), Vector2(r, r) * 2.0), GREEN, false, 2.0)
			draw_line(s - Vector2(r * 1.6, 0), s - Vector2(r * 0.6, 0), GREEN, 2.0)
			draw_line(s + Vector2(r * 0.6, 0), s + Vector2(r * 1.6, 0), GREEN, 2.0)
			_text(font, "AGM LOCK %.1f km" % (gp.distance_to(p.global_position) / 1000.0), s - Vector2(0, r + 8 * u), fs * 0.8, GREEN)

	# CCIP: where a bomb released now would hit, joined to the flight path marker
	if scene.weapon_mode == "bomb" and p.alive and not p.on_ground:
		var sp: Dictionary = scene.next_bomb_spec()
		if not sp.is_empty():
			var impact = preload("res://scripts/game/bomb.gd").predict_impact(p.global_position, p.velocity, sp.drag, scene.terrain)
			if impact != null and not cam.is_position_behind(impact):
				var s := cam.unproject_position(impact)
				draw_arc(s, 14 * u, 0, TAU, 24, AMBER, 2.0)
				draw_circle(s, 2.5 * u, AMBER)
				var fpm3: Vector3 = p.global_position + p.velocity.normalized() * 500.0
				if not cam.is_position_behind(fpm3):
					draw_line(cam.unproject_position(fpm3), s, Color(AMBER, 0.6), 1.5)

	# Incoming missiles: red marker on the missile and a blinking warning
	var threats := 0
	for m in scene.missiles_in_flight:
		if not m.alive or m.target != p:
			continue
		threats += 1
		if not cam.is_position_behind(m.global_position):
			var s := cam.unproject_position(m.global_position)
			draw_rect(Rect2(s - Vector2(8, 8) * u, Vector2(16, 16) * u), RED, false, 2.0)
	if threats > 0 and fmod(Time.get_ticks_msec() / 250.0, 2.0) < 1.3:
		_text(font, "MISSILE WARNING ×%d" % threats, c + Vector2(0, -170 * u), fs * 1.6, RED)

	# Mission ground targets and waypoints
	for o in scene.targets:
		if not o.alive or not o.has_method("center"):
			continue
		var wp: Vector3 = o.center()
		if cam.is_position_behind(wp):
			continue
		var s := cam.unproject_position(wp)
		var dist := wp.distance_to(cam.global_position)
		var r := 12.0 * u
		draw_polyline(PackedVector2Array([s + Vector2(0, -r), s + Vector2(r, 0), s + Vector2(0, r),
			s + Vector2(-r, 0), s + Vector2(0, -r)]), Color(1, 0.35, 0.25), 2.0)
		if dist < 15000.0:
			_text(font, "%s %.1f km" % [o.display_name, dist / 1000.0], s + Vector2(0, r + 16 * u), fs * 0.7, Color(1, 0.35, 0.25))
	# Route: the current waypoint is highlighted, the others are dimmed.
	var nav_col := Color(0.5, 0.85, 1.0)
	for i in scene.waypoints.size():
		var w: Dictionary = scene.waypoints[i]
		var wp: Vector3 = w.pos
		if cam.is_position_behind(wp) or (scene.mission != null and i < scene.nav_index):
			continue
		var current: bool = scene.mission != null and i == scene.nav_index
		var col := nav_col if current or scene.mission == null else Color(nav_col, 0.35)
		var s := cam.unproject_position(wp)
		var r := (13.0 if current else 8.0) * u
		draw_arc(s, r, 0, TAU, 16, col, 2.5 if current else 1.5)
		if current or scene.mission == null:
			_text(font, "%s %.0f km" % [w.name, p.global_position.distance_to(wp) / 1000.0], s - Vector2(0, r + 6 * u), fs * 0.75, col)
	if scene.mission != null and scene.nav_index < scene.waypoints.size():
		# Steering caret on the heading tape
		var to: Vector3 = scene.waypoints[scene.nav_index].pos - p.global_position
		var brg := fposmod(rad_to_deg(atan2(to.x, -to.z)), 360.0)
		var off := brg - heading
		if off > 180: off -= 360
		if off < -180: off += 360
		var cx := c.x + clampf(off, -30.0, 30.0) * 7.0 * u
		draw_colored_polygon(PackedVector2Array([Vector2(cx, tape_y + 6 * u), Vector2(cx - 7 * u, tape_y + 18 * u),
			Vector2(cx + 7 * u, tape_y + 18 * u)]), nav_col)

	# Landing aid: runway outline, glide slope and localizer deviation
	var land: Dictionary = scene.landing_info()
	if not land.is_empty():
		var pts := PackedVector2Array()
		for corner in land.corners:
			if cam.is_position_behind(corner):
				pts.clear()
				break
			pts.append(cam.unproject_position(corner))
		if pts.size() == 4:
			pts.append(pts[0])
			draw_polyline(pts, GREEN, 2.0)
		var gx := c.x + 300 * u
		var lx := c.y + 200 * u
		draw_line(Vector2(gx, c.y - 120 * u), Vector2(gx, c.y + 120 * u), Color(GREEN, 0.5), 2.0)
		draw_line(Vector2(c.x - 120 * u, lx), Vector2(c.x + 120 * u, lx), Color(GREEN, 0.5), 2.0)
		for k in [-2, -1, 1, 2]:
			draw_circle(Vector2(gx, c.y + k * 48 * u), 3 * u, Color(GREEN, 0.5))
			draw_circle(Vector2(c.x + k * 48 * u, lx), 3 * u, Color(GREEN, 0.5))
		# One dot = 30 m vertically / 60 m laterally, like a coarse ILS.
		# ILS convention: the needles show where the glide path is (high -> diamond below).
		var gs := clampf(land.gs_error / 30.0, -2.5, 2.5)
		var lc := clampf(-land.loc_error / 60.0, -2.5, 2.5)
		var dia := func(p0: Vector2): return PackedVector2Array([p0 + Vector2(0, -9) * u, p0 + Vector2(9, 0) * u,
			p0 + Vector2(0, 9) * u, p0 + Vector2(-9, 0) * u, p0 + Vector2(0, -9) * u])
		draw_polyline(dia.call(Vector2(gx, c.y + gs * 48 * u)), AMBER, 2.5)
		draw_polyline(dia.call(Vector2(c.x + lc * 48 * u, lx)), AMBER, 2.5)
		_text(font, "ILS RWY %s   %.1f km   GS %+d m   SPD 150 KT" % [land.runway, land.distance / 1000.0, int(land.gs_error)],
			Vector2(c.x, lx + 34 * u), fs * 0.85, GREEN)

	# Status block
	var Weapons = preload("res://scripts/game/weapons.gd")
	var arms := []
	for name in p.missiles:
		if Weapons.mode_of(name) == scene.weapon_mode:
			arms.append("%s %d" % [Weapons.label(name), p.missiles[name]])
	var lines := [
		"HULL %3d%%" % int(maxf(p.health, 0.0)),
		"WPN %s: %s  CM %d" % [Weapons.MODE_LABELS[scene.weapon_mode], "  ".join(arms) if arms.size() else "empty", p.countermeasures],
		"THR %3d%%%s" % [int(p.throttle * 100), "  AB" if p.afterburner else ""],
		"G %4.1f   AOA %4.1f°" % [p.g_force, rad_to_deg(p.aoa)],
		"CAMERA: %s" % scene.rig.mode_name(),
		"KILLS: %d" % scene.kills,
	]
	if scene.mission != null and scene.nav_index < scene.waypoints.size():
		var w: Dictionary = scene.waypoints[scene.nav_index]
		lines.append("NAV %d/%d: %s %.1f km" % [scene.nav_index + 1, scene.waypoints.size(), w.name,
			Vector2(w.pos.x - p.global_position.x, w.pos.z - p.global_position.z).length() / 1000.0])
	if scene.fast_travel:
		lines.append("FAST FORWARD x%.0f  (F7 to cancel)  ~%.1f km" % [
			Engine.time_scale,
			(Vector2(scene.waypoints[scene.nav_index].pos.x - p.global_position.x,
				scene.waypoints[scene.nav_index].pos.z - p.global_position.z).length() / 1000.0)
			if scene.nav_index < scene.waypoints.size() else 0.0])
	if scene.mission != null:
		lines.append("MISSION: %s" % ("COMPLETE" if scene.mission_complete else "targets %d/%d" % [scene.targets_left(), scene.targets.size()]))
	if p.brakes: lines.append("BRAKES")
	if p.on_ground: lines.append("ON GROUND")
	for i in lines.size():
		draw_string(font, Vector2(40 * u, sz.y - (40 + (lines.size() - 1 - i) * 28) * u), lines[i],
			HORIZONTAL_ALIGNMENT_LEFT, -1, fs, GREEN)
	if p.alive and agl_ft < 500 and p.velocity.y < -15 and not p.on_ground:
		_text(font, "PULL UP", c + Vector2(0, 140 * u), fs * 1.8, Color(1, 0.3, 0.2))
	# Radar MFD (the original air-to-air radar, manual p. 62-64: forward
	# 180° sweep; different icons for friendly and enemy blips).
	_radar(font, c, sz, u, fs)
	if _msg_time > 0.0:
		_text(font, _msg, Vector2(c.x, sz.y - 120 * u), fs, AMBER)


func _ladder(cam: Camera3D, p, u: float, font: Font) -> void:
	var origin: Vector3 = cam.global_position
	var b: Basis = p.global_transform.basis
	var fwd_flat := Vector3(-b.z.x, 0, -b.z.z).normalized()
	if fwd_flat.length_squared() < 0.01:
		return
	var right_flat := fwd_flat.cross(Vector3.UP)
	for deg in range(-60, 61, 10):
		var a := deg_to_rad(deg)
		var dir := fwd_flat * cos(a) + Vector3.UP * sin(a)
		var center := origin + dir * 1000.0
		if cam.is_position_behind(center):
			continue
		var l := cam.unproject_position(center - right_flat * 60.0)
		var r := cam.unproject_position(center + right_flat * 60.0)
		var col := GREEN if deg >= 0 else Color(GREEN, 0.6)
		if deg == 0:
			l = cam.unproject_position(center - right_flat * 200.0)
			r = cam.unproject_position(center + right_flat * 200.0)
		var m := (l + r) * 0.5
		draw_line(l, m - (r - l).normalized() * 30 * u, col, 2.0)
		draw_line(m + (r - l).normalized() * 30 * u, r, col, 2.0)
		if deg != 0:
			_text(font, str(deg), r + (r - l).normalized() * 18 * u, int(15 * u), col)


func _box(font: Font, pos: Vector2, value: String, label: String, u: float) -> void:
	var rect := Rect2(pos - Vector2(70, 22) * u, Vector2(140, 44) * u)
	draw_rect(rect, GREEN, false, 2.0)
	_text(font, value, pos + Vector2(0, 9 * u), int(26 * u), GREEN)
	_text(font, label, pos + Vector2(0, 46 * u), int(16 * u), GREEN)


func _text(font: Font, s: String, at: Vector2, fs: float, col: Color) -> void:
	var w := font.get_string_size(s, HORIZONTAL_ALIGNMENT_LEFT, -1, int(fs)).x
	draw_string(font, at - Vector2(w * 0.5, 0), s, HORIZONTAL_ALIGNMENT_LEFT, -1, int(fs), col)


## Air-to-air / RAW radar MFD, centre-bottom like the original cockpit MFD:
## forward-looking 180° sector, 20 km ring, blips up to the range.
## Icons (manual): enemy = square, friendly = triangle, ground radar emitter =
## small circle. Also blinking: missiles aimed at the player.
func _radar(font: Font, c: Vector2, sz: Vector2, u: float, fs: float) -> void:
	var p = scene.player
	if p == null or not p.alive:
		return
	var size := 170.0 * u
	var half := size * 0.5
	var origin := Vector2(sz.x - size - 40 * u, sz.y - size - 120 * u)
	draw_rect(Rect2(origin, Vector2(size, size)), Color(0.02, 0.10, 0.02, 0.55), true)
	draw_rect(Rect2(origin, Vector2(size, size)), GREEN, false, 2.0)
	var horizon := origin.y + half * 0.86   # aircraft symbol row (bottom centre)
	# range rings at 10 / 20 km (the radar default range: enemies past it are off-screen)
	draw_arc(origin + Vector2(half, size * 0.5), size * 0.25, 0, PI, 24, Color(GREEN, 0.5), 1.0)
	draw_arc(origin + Vector2(half, size * 0.5), size * 0.44, 0, PI, 24, Color(GREEN, 0.5), 1.0)
	# player symbol at the bottom centre
	draw_colored_polygon(PackedVector2Array([Vector2(origin.x + half, horizon - 7 * u), Vector2(origin.x + half - 6 * u, horizon + 5 * u),
		Vector2(origin.x + half + 6 * u, horizon + 5 * u)]), GREEN)
	draw_circle(origin + Vector2(half, size * 0.5), 2.5 * u, GREEN)
	var b: Basis = p.global_transform.basis
	var fwd := Vector3(-b.z.x, 0.0, -b.z.z).normalized()
	var right := fwd.cross(Vector3.UP)
	var rng := 20000.0
	for e in scene.enemies:
		if e == null or not e.alive:
			continue
		_blip(e.global_position - p.global_position, fwd, right, origin, size, rng,
			func(pos: Vector2):
				draw_rect(Rect2(pos - Vector2(5, 5) * u, Vector2(10, 10) * u),
					AMBER if e.health > e.max_health * 0.35 else RED, false, 2.0))
	for a in scene.allies:
		if a == null or a == p or not a.alive:
			continue
		_blip(a.global_position - p.global_position, fwd, right, origin, size, rng,
			func(pos: Vector2):
				var tri := PackedVector2Array([pos + Vector2(0, -6 * u), pos + Vector2(-5.5, 5) * u,
					pos + Vector2(5.5, 5) * u])
				draw_colored_polygon(tri, Color(0.35, 1.0, 1.0)))
	for o in scene.ground_objects:
		if o == null or not o.alive or not o.hostile or o.weapon.is_empty():
			continue
		_blip(o.global_position - p.global_position, fwd, right, origin, size, rng,
			func(pos: Vector2): draw_circle(pos, 3.5 * u, Color(1.0, 0.8, 0.3)))
	for m in scene.missiles_in_flight:
		if m != null and m.alive and m.target == p:
			_blip(m.global_position - p.global_position, fwd, right, origin, size, rng,
				func(pos: Vector2): draw_circle(pos, 4 * u, RED))
	_text(font, "AIR RADAR 20 KM", origin + Vector2(0, -10 * u), fs * 0.8, GREEN)


static func _blip(rel: Vector3, fwd: Vector3, right: Vector3, origin: Vector2, size: float, rng: float, draw) -> void:
	var along := rel.dot(fwd)
	if along <= 0.0:
		return   # the original basic radar scans a 180° arc ahead
	if rel.length() > rng:
		return
	var lateral := rel.dot(right)
	var pos: Vector2 = origin + Vector2(size * 0.5, size * 0.5) + Vector2(lateral / rng * size * 0.44, -along / rng * size * 0.44)
	draw.call(pos)
