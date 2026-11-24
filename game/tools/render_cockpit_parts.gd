## Render each live 3D cockpit instrument as its own transparent PNG.
## Parts can be arranged by hand into a layout mock-up, which is then used as
## the model for the in-game placement.
##
## Run (NOT --headless; headless has no 3D renderer):
##   Godot_v4.7.2-stable_win64.exe --path game --script res://tools/render_cockpit_parts.gd
## Output: shots/instruments/*.png  (gitignored)
extends SceneTree

const Instruments := preload("res://scripts/game/cockpit_instruments.gd")

const OUT := "res://../shots/instruments"

# lrs = libRealSpace-style position from CockpitInstruments.LAYOUT,
# w = orthographic view width in cockpit world units, px = output resolution.
const PARTS := {
	"raws":  { "lrs": Vector3(6.15, -1.915, -1.625), "w": 3.3, "px": Vector2i(512, 576) },
	"alti":  { "lrs": Vector3(5.90, -4.160, 0.460), "w": 4.8, "px": Vector2i(512, 640) },
	"speed": { "lrs": Vector3(5.90, -4.160, -0.460), "w": 4.8, "px": Vector2i(512, 640) },
	"mfd_l": { "lrs": Vector3(6.15, -2.650, 2.075), "w": 8.5, "px": Vector2i(640, 800) },
	"mfd_r": { "lrs": Vector3(6.15, -3.450, -2.075), "w": 5.6, "px": Vector2i(640, 660) },
	"comm":  { "lrs": Vector3(6.10, -1.025, 0.0), "w": 1.2, "px": Vector2i(1100, 140) },
	"hud":   { "lrs": Vector3(5.9, -0.250, 0.0), "w": 7.2, "px": Vector2i(1024, 768) },
}

# Static sample values so every dynamic label is visible in the cutouts.
const SAMPLES := {
	"alti_value": "12000",
	"speed_value": "250",
	"stores": "AIM-9 2   GUN 510",
	"comm": "Strike Base: Runway is clear for landing.",
	"hud_warning": "PULL UP",
	"hud_in_range": "IN RNG",
	"hud_closure": "C 120",
	"hud_waypoint": "D 4.1",
}


func _initialize() -> void:
	await process_frame
	var dir := ProjectSettings.globalize_path(OUT)
	DirAccess.make_dir_recursive_absolute(dir)
	var made := 0
	for key in PARTS:
		var cfg: Dictionary = PARTS[key]
		var vp := SubViewport.new()
		vp.size = cfg.px
		vp.transparent_bg = true
		vp.render_target_update_mode = SubViewport.UPDATE_ALWAYS
		root.add_child(vp)

		var holder := Node3D.new()  # setup() expects a Node3D parent
		vp.add_child(holder)
		var inst := Instruments.new()
		holder.add_child(inst)
		inst.setup(null, Vector3.ZERO)
		# The solid bezel plate is drawn in front of the inner quads (depth
		# test is disabled in the instrument materials), so leave it out.
		var bx := [-1.2, 1.3, -1.1, 1.4]
		var by := [1.5, -0.8, 0.6, -1.6]
		for child in inst.get_children():
			child.visible = _group(child.name) == key and not child.name.begins_with("bezel_")
			if key == "raws" and child.name == "face_raws":
				child.visible = false  # let the artificial horizon show through
			if child is Label3D and SAMPLES.has(child.name):
				child.text = SAMPLES[child.name]
			if child.name.begins_with("blip"):
				var i := int(child.name.substr(4))
				if i < 4:
					child.position = inst._pos(Instruments.LAYOUT["mfd_r"]) + Vector3(bx[i], by[i], 0.3)
					child.material_override.albedo_color = Color(1.0, 0.3, 0.25) if i < 3 else Color(0.4, 1.0, 1.0)
				else:
					child.visible = false

		if key == "raws":
			# All horizon parts share the same depth; spread them so the
			# ladder and horizon line are not hidden by the sky/ground quads.
			var adi := inst.get_node("adi_rotation")
			var n := 0
			for c in adi.get_children():
				if c.name == "horizon":
					c.position.z = 0.16
				elif c.name.begins_with("pitch"):
					c.position.z = 0.20
					c.position.y = (n - 3) * 0.36
					n += 1

		var cam := Camera3D.new()
		cam.projection = 1  # PROJECTION_ORTHOGRAPHICAL
		cam.size = cfg.w
		cam.near = 0.01
		cam.far = 200.0
		vp.add_child(cam)
		var center: Vector3 = inst._pos(cfg.lrs)
		cam.global_position = center + Vector3(0, 0, 10)
		cam.look_at(center, Vector3.UP)

		await RenderingServer.frame_post_draw
		await RenderingServer.frame_post_draw
		var img: Image = vp.get_texture().get_image()
		var path: String = dir + "/" + key + ".png"
		if img != null and not img.is_empty() and img.save_png(path) == OK:
			made += 1
			print("PART %s -> %s (%dx%d)" % [key, path, img.get_width(), img.get_height()])
		else:
			print("PART %s FAILED" % key)
		vp.queue_free()
		await process_frame
	print("COCKPIT PARTS %d/%d" % [made, PARTS.size()])
	quit(0 if made == PARTS.size() else 1)


## Which logical instrument a node belongs to, by its name.
func _group(n: String) -> String:
	if n.begins_with("bezel_"):
		return n.substr(6)
	if n.begins_with("face_"):
		return n.substr(5)
	if n.begins_with("adi_rot") or n.begins_with("adi_wing"):
		return "raws"
	if n.begins_with("alti_"):
		return "alti"
	if n.begins_with("speed_"):
		return "speed"
	if n == "stores":
		return "mfd_l"
	if n == "radar_title" or n.begins_with("blip"):
		return "mfd_r"
	if n == "comm":
		return "comm"
	if n.begins_with("hud_"):
		return "hud"
	return ""
