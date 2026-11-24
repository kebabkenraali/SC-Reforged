## Application root: requires a mounted original installation, then switches
## between menu, flight and model viewer screens.
##
## Automation (used for testing): pass after "--"
##   --auto=flight|viewer|menu  --map=CANYON  --plane=OBJECTS/F-16DES.IFF
##   --auto=campaign (new) | --auto=continue  --tactical (play Tactical Operations / GAMEFLO2.IFF)
##   --conv=N (play conversation N)  --story=N (cut-scene MIDn)  --shot_scene=N (establishing shot N)  --transport=N
##   --mission=MISSIONS/MISN-10A.IFF  --spawn_area=2  --log  --autopilot  --endless_ammo  --kill_enemies (cheat)  --god (invincible; also --godmode/--invincible) --no_enemies (no hostile aircraft/defences)  --bomb_run  --debrief=2  --approach  --model=OBJECTS/MIG29.IFF  --cam=0..3  --frames=120  --shot=C:/path.png
##   --fasttravel / --approachjump: F7 repositions the player and friendly aircraft 10 km before each waypoint
extends Node

const Demo = preload("res://scripts/core/demo.gd")

const SetupScreen = preload("res://scripts/ui/setup_screen.gd")
const MainMenu = preload("res://scripts/ui/main_menu.gd")
const FlightScene = preload("res://scripts/game/flight_scene.gd")
const ModelViewer = preload("res://scripts/ui/model_viewer.gd")
const UiTheme = preload("res://scripts/ui/ui_theme.gd")
const Campaign = preload("res://scripts/game/campaign.gd")
const BaseScreen = preload("res://scripts/ui/base_screen.gd")
const Art = preload("res://scripts/core/art.gd")

var current: Node
var campaign
var _tactical_start := false    # --tactical: play Tactical Operations (GAMEFLO2.IFF)
var vr_requested := false       # --vr: whole game runs in the headset
var sbs_mode := false           # --sbs: stereo everywhere, flat UI as a large world panel
var vr_available := false       # OpenXR interface initialized
var vr_active := false          # XR viewport enabled (whole session in VR mode)
var active_flight: Node = null  # flight scene currently on screen
var vr_menu_origin: XROrigin3D = null   # XR rig for flat 2D screens
var vr_menu_camera: XRCamera3D = null
var vr_layer: OpenXRCompositionLayerQuad = null  # flat screens in the headset
var vr_panel_bezel: MeshInstance3D = null
var sbs_panel: MeshInstance3D = null   # large world-locked 2D screen in SBS mode
var ui_viewport: SubViewport = null    # 2D UI rendered into the layer
var vr_pointer: XRController3D = null  # right hand drives the 2D cursor
var vr_cursor: Control = null
var vr_hud: Control = null            # flight HUD moved into the XR layer
var _vr_pressed := false
var _vr_uv := Vector2(-1.0, -1.0)
var _vr_slow_frames := 0        # watchdog: runtime not delivering frames
var _base                       # base screen kept (hidden) while a campaign mission is flown
var args := {}
var _frames_left := -1
var _headless := false          # DisplayServer is "headless": no window, dummy renderer
# Headless run driver (see _headless_tick): stop on mission end, frame budget or wall-clock timeout.
var _hl_frames := 0
var _hl_max_frames := 0         # 0 = no frame limit
var _hl_deadline_ms := 0
var _hl_next_status_ms := 0
var _hl_done := false


func _ready() -> void:
	# Keep screenshots, input and screen switching alive while the game is paused.
	process_mode = Node.PROCESS_MODE_ALWAYS
	_headless = DisplayServer.get_name() == "headless"

	# Options may come after "--" (user args) or directly on the command line
	# (Godot passes arguments it does not recognise through get_cmdline_args()).
	for a in OS.get_cmdline_args() + OS.get_cmdline_user_args():
		if not a.begins_with("--"):
			continue
		var kv: PackedStringArray = a.trim_prefix("--").split("=", true, 1)
		if kv[0].is_empty():
			continue
		args[kv[0]] = kv[1] if kv.size() > 1 else "1"
	if args.has("mode"):
		var m := str(args["mode"]).to_lower()
		if m == "arcade" or m == "realistic":
			Settings.mode_override = m
	if args.has("speed"):
		# test runs only: simulate faster than real time
		Engine.time_scale = float(args.speed)
		Engine.max_physics_steps_per_frame = 8 * int(ceil(float(args.speed)))
	if args.has("fast"):
		# --fast: alias for --speed=10 (10x simulation speed)
		Engine.time_scale = 10.0
		Engine.max_physics_steps_per_frame = 80
	if args.has("ultrafast"):
		# --ultrafast: alias for --speed=100 (100x simulation speed)
		Engine.time_scale = 100.0
		Engine.max_physics_steps_per_frame = 800
	var win := get_window()
	if is_instance_valid(win):
		win.theme = UiTheme.build()
		win.title = "Strike Commander Reforged – Demo" if Demo.enabled() else "Strike Commander Reforged"
		win.min_size = Vector2i(1024, 600)

	_tactical_start = args.has("tactical")
	_init_vr()
	if args.has("dir"):
		SCData.mount(args.dir)
	if not SCData.is_mounted() and not SCData.auto_mount():
		if _headless:
			# The install picker needs a screen and a user.
			printerr("HEADLESS: game data not found. Pass --dir=\"C:/Gog games/Strike Commander\".")
			get_tree().quit(1)
			return
		show_setup()
	else:
		_start()

	if _headless:
		_headless_setup()
	elif args.has("shot"):
		_frames_left = int(args.get("frames", "90"))


## VR mode (--vr): the whole game runs in the headset. Flight is true stereo;
## flat 2D screens are rendered by a SubViewport into an OpenXR composition
## layer quad in front of the head (Godot's plain 2D canvas does not work in XR).
func _init_vr() -> void:
	sbs_mode = args.has("sbs")
	vr_requested = args.has("vr") or sbs_mode
	if not vr_requested:
		return
	var iface = XRServer.find_interface("OpenXR")
	if iface == null or not iface.initialize():
		print("VR: no OpenXR runtime — whole game stays flat")
		return
	XRServer.set_primary_interface(iface)
	vr_available = true
	# Persistent XR rig for the flat screens; the flight rig takes over during
	# a mission and this one is restored afterwards.
	vr_menu_origin = XROrigin3D.new()
	vr_menu_origin.current = true
	add_child(vr_menu_origin)
	vr_menu_camera = XRCamera3D.new()
	vr_menu_camera.near = 0.1
	vr_menu_camera.far = 400000.0
	vr_menu_origin.add_child(vr_menu_camera)
	vr_menu_camera.current = true

	# All flat screens live in this SubViewport. The XR runtime composites its
	# texture on a flat quad AFTER lens distortion, so text stays sharp.
	var win := get_viewport()
	var size: Vector2i = win.size if win != null else Vector2i(1600, 900)
	ui_viewport = SubViewport.new()
	ui_viewport.name = "VRFlatUI"
	ui_viewport.size = size
	ui_viewport.transparent_bg = true
	ui_viewport.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	add_child(ui_viewport)

	vr_layer = OpenXRCompositionLayerQuad.new()
	vr_layer.name = "VRFlatPanel"
	vr_layer.layer_viewport = ui_viewport
	vr_layer.quad_size = Vector2(1.9, 1.9 * float(size.y) / float(size.x))
	vr_layer.alpha_blend = true
	vr_layer.position = Vector3(0.0, 1.5, -1.6)
	vr_menu_origin.add_child(vr_layer)
	# Subtle bezel behind the flat 2D panel gives the section depth in VR.
	var bezel_mesh := QuadMesh.new()
	bezel_mesh.size = vr_layer.quad_size * 1.06
	var bezel := MeshInstance3D.new()
	bezel.name = "VRFlatPanelBezel"
	bezel.mesh = bezel_mesh
	var bmat := StandardMaterial3D.new()
	bmat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	bmat.albedo_color = Color(0.04, 0.07, 0.06)
	bezel.material_override = bmat
	bezel.position = vr_layer.position + Vector3(0, 0, -0.05)
	vr_menu_origin.add_child(bezel)
	vr_panel_bezel = bezel

	if sbs_mode:
		# SBS mode: render the whole flat UI on one large world-locked quad,
		# so both eyes get a full-frame stereo pair and the seated player can
		# look around it with head tracking instead of a small HUD-locked card.
		var q := QuadMesh.new()
		q.size = Vector2(4.5, 4.5 * float(size.y) / float(size.x))
		sbs_panel = MeshInstance3D.new()
		sbs_panel.name = "SBSFullPanel"
		sbs_panel.mesh = q
		var sm := StandardMaterial3D.new()
		sm.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		sm.albedo_texture = ui_viewport.get_texture()
		sm.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
		sm.cull_mode = BaseMaterial3D.CULL_DISABLED
		sm.depth_draw_mode = BaseMaterial3D.DEPTH_DRAW_DISABLED
		sbs_panel.material_override = sm
		sbs_panel.position = Vector3(0.0, 1.6, -2.0)
		vr_menu_origin.add_child(sbs_panel)
		vr_layer.visible = false
		bezel.visible = false
		print("VR: SBS mode — full-frame stereo panel, world-locked")

	# Controller pointer + reticle for the flat UI.
	vr_cursor = Control.new()
	vr_cursor.set_script(preload("res://scripts/ui/vr_cursor.gd"))
	vr_cursor.size = Vector2(30, 30)
	vr_cursor.position = Vector2(-100, -100)
	ui_viewport.add_child(vr_cursor)
	vr_pointer = XRController3D.new()
	vr_pointer.tracker = "/user/hand/right"
	vr_menu_origin.add_child(vr_pointer)

	# Godot needs a viewport flagged for XR output: without this the
	# interface reports "No viewport was marked with use_xr".
	if win != null:
		win.use_xr = true
	# OpenXR drives its own sync; monitor v-sync would cap it at 60 Hz.
	DisplayServer.window_set_vsync_mode(DisplayServer.VSYNC_DISABLED)
	vr_active = true
	print("VR: OpenXR active — flight stereo, other screens flat 2D layer")


## Switch which XR rig is current. The viewport stays in XR for the whole
## session in VR mode.
func _set_vr(active: bool) -> void:
	if not vr_available:
		return
	if active:
		if vr_menu_origin != null:
			vr_menu_origin.current = false
		if vr_menu_camera != null:
			vr_menu_camera.current = false
	elif active_flight == null or not is_instance_valid(active_flight):
		if vr_menu_origin != null:
			vr_menu_origin.current = true
		if vr_menu_camera != null:
			vr_menu_camera.current = true
	if vr_layer != null:
		# The layer shows the flat menus OR, during flight, the HUD over the
		# stereo world. A plain 2D canvas is not rendered correctly by XR.
		vr_layer.visible = not sbs_mode
		if vr_panel_bezel != null and is_instance_valid(vr_panel_bezel):
			vr_panel_bezel.visible = not sbs_mode and not active
		if sbs_panel != null and is_instance_valid(sbs_panel):
			sbs_panel.visible = not active
		if ui_viewport != null:
			var asp := float(ui_viewport.size.y) / float(ui_viewport.size.x)
			if active:
				vr_layer.quad_size = Vector2(3.0, 3.0 * asp)
				vr_layer.position = Vector3(0.0, 1.6, -2.2)
			else:
				vr_layer.quad_size = Vector2(1.9, 1.9 * asp)
				vr_layer.position = Vector3(0.0, 1.5, -1.6)
			if vr_panel_bezel != null and is_instance_valid(vr_panel_bezel):
				vr_panel_bezel.mesh.size = vr_layer.quad_size * 1.06
				vr_panel_bezel.position = vr_layer.position + Vector3(0, 0, -0.05)


## Move the flight HUD into the XR composition layer so it is visible in the
## headset. It is unprojected from the flight camera, so the 2D coordinates
## match the SubViewport size exactly.
func _attach_vr_hud(f: Node) -> void:
	if not vr_active or ui_viewport == null or f == null:
		return
	var hud = f.get("hud")
	if hud == null or hud.get_parent() == ui_viewport:
		return
	if hud.get_parent() != null:
		hud.reparent(ui_viewport)
	else:
		ui_viewport.add_child(hud)
	vr_hud = hud


func _detach_vr_hud() -> void:
	if vr_hud == null:
		return
	if is_instance_valid(vr_hud):
		var f = vr_hud.get("scene")
		var layer = f.get("_layer") if f != null else null
		if layer != null and vr_hud.get_parent() != layer:
			layer.add_child(vr_hud)
	vr_hud = null


## Runtime present but no frames (headset asleep/offline): fall back to flat.
func _disable_vr() -> void:
	vr_active = false
	vr_available = false
	var vp := get_viewport()
	if vp != null:
		vp.use_xr = false
	DisplayServer.window_set_vsync_mode(DisplayServer.VSYNC_ENABLED)
	var iface = XRServer.find_interface("OpenXR")
	if iface != null and iface.is_initialized():
		iface.uninitialize()
	if active_flight != null and is_instance_valid(active_flight):
		var rig = active_flight.get("rig")
		if rig != null:
			rig.vr_active = false
			if rig.camera != null:
				rig.camera.current = true
			if rig.xr_camera != null:
				rig.xr_camera.current = false
			if rig.xr_origin != null:
				rig.xr_origin.current = false
	if vr_menu_origin != null:
		vr_menu_origin.current = false
	if vr_menu_camera != null:
		vr_menu_camera.current = false
	# HUD returns to the flight scene's canvas layer; flat screens return to
	# the main viewport before the XR SubViewport is destroyed.
	_detach_vr_hud()
	if ui_viewport != null:
		if current != null and is_instance_valid(current) and current.get_parent() == ui_viewport:
			ui_viewport.remove_child(current)
			add_child(current)
		if vr_layer != null and is_instance_valid(vr_layer):
			vr_layer.queue_free()
		if sbs_panel != null and is_instance_valid(sbs_panel):
			sbs_panel.queue_free()
		ui_viewport.queue_free()
		ui_viewport = null
		vr_layer = null
		sbs_panel = null
		vr_pointer = null
		vr_cursor = null
	print("VR: runtime produced no frames — restored flat desktop mode")


func _start() -> void:
	match args.get("auto", ""):
		"flight":
			start_flight(args.get("map", "CANYON"), args.get("plane", "OBJECTS/F-16DES.IFF"), args.get("mission", ""))
		"viewer":
			show_viewer()
		"campaign":
			start_campaign(true)
		"continue":
			start_campaign(false)
		_:
			if _tactical_start:
				start_campaign(true)
			elif not _headless:
				show_menu()
			else:
				# Default to flight mode in headless
				start_flight("CANYON", "OBJECTS/F-16DES.IFF", "")


func _switch(node: Node) -> void:
	if current != null:
		if vr_hud != null and is_instance_valid(vr_hud):
			vr_hud.queue_free()
		vr_hud = null
		current.queue_free()
	current = node
	# Flight renders in the main XR viewport; all other screens go into the
	# SubViewport that OpenXR composites as a flat 2D panel.
	var flying := node is FlightScene
	if vr_active and not flying and ui_viewport != null:
		ui_viewport.add_child(node)
	else:
		add_child(node)
	active_flight = node if flying else null
	_set_vr(flying)
	if flying:
		_attach_vr_hud(node)


func show_setup() -> void:
	var s = SetupScreen.new()
	s.mounted.connect(show_menu)
	_switch(s)


func show_menu() -> void:
	_drop_base()
	var m = MainMenu.new()
	m.start_flight.connect(start_flight)
	m.open_viewer.connect(show_viewer)
	m.start_campaign.connect(start_campaign)
	m.start_tactical.connect(start_tactical)
	_switch(m)


## Main-menu entry for the Tactical Operations add-on: same campaign engine,
## but all UI data (gameflow, screens, conversations, art) comes from GAMEFLO2.
func start_tactical() -> void:
	_tactical_start = true
	start_campaign(true)


## Campaign: base screens, conversations and missions from GAMEFLOW.
func start_campaign(new_game: bool) -> void:
	campaign = Campaign.new()
	var resume: bool = not new_game and campaign.load_saved()
	if _tactical_start and not campaign.tactical:
		# --tactical with a base-game save: start a fresh add-on campaign instead
		# of misinterpreting base stage/screen numbers in GAMEFLO2.IFF.
		resume = false
	if not resume:
		campaign.tactical = _tactical_start
		Art.set_active("tactical" if _tactical_start else "base")
	var b = BaseScreen.new()
	b.campaign = campaign
	b.fly_requested.connect(_fly_campaign_mission)
	b.quit_requested.connect(show_menu)
	_switch(b)
	_base = b
	if args.has("conv"):
		await b.play_conversation(int(args.conv))
		return
	if args.has("story"):
		await b.play_story(int(args.story))
		return
	if args.has("transport"):
		await b.play_transport(int(args.transport))
		return
	if args.has("shot_scene"):
		await b.play_cutscene(int(args.shot_scene))
		return
	# Debug: jump straight to a base screen of a given stage (for visual checks).
	if args.has("base"):
		campaign.stage = int(args.get("stage", "0"))
		campaign.screen = int(args.base)
		await get_tree().process_frame
		b._build_screen(campaign.screen)
		return
	if resume and campaign.screen >= 0:
		b._build_screen(campaign.screen)
	elif resume:
		campaign.enter_stage(campaign.stage)
	else:
		campaign.start_new(campaign.tactical)


func _fly_campaign_mission(file: String) -> void:
	_base.visible = false
	_base.process_mode = Node.PROCESS_MODE_DISABLED
	_set_vr(true)   # init OpenXR before the rig builds its XR nodes
	var f = FlightScene.new()
	f.mission_file = file
	f.campaign_mode = true
	f.campaign = campaign  # Pass campaign for loadout access
	f.camera_mode = int(args.get("cam", "0"))
	f.vr_active = vr_active
	# Testing flags also apply to campaign flights (headless autopilot runs).
	f.autopilot = args.has("autopilot")
	f.endless_ammo = args.has("endless_ammo") or args.has("infinite_ammo") or args.has("autopilot")
	f.kill_enemies = args.has("kill_enemies")
	f.no_enemies = args.has("no_enemies")
	f.god_mode = args.has("god") or args.has("godmode") or args.has("invincible")
	f.debug_log = args.has("log")
	f.mission_result.connect(_campaign_flight_done.bind(f))
	f.restart.connect(func(): f.queue_free(); _fly_campaign_mission(file))
	add_child(f)
	_attach_vr_hud(f)
	# Campaign flights keep the base screen as `current`, so track them here.
	active_flight = f


func _campaign_flight_done(success: bool, f: Node) -> void:
	var report: Dictionary = f.campaign_report(success)
	if vr_hud != null and is_instance_valid(vr_hud):
		vr_hud.queue_free()
	vr_hud = null
	active_flight = null
	_set_vr(false)   # restore the flat-screen XR rig
	f.queue_free()
	_base.visible = true
	_base.process_mode = Node.PROCESS_MODE_INHERIT
	_base.flight_done.emit(report)


func _drop_base() -> void:
	if _base != null and is_instance_valid(_base) and _base != current:
		_base.queue_free()
	_base = null


func start_flight(area: String, plane: String, mission := "") -> void:
	_set_vr(true)   # init OpenXR before the rig builds its XR nodes
	var f = FlightScene.new()
	f.area = area
	f.plane_model = plane
	f.mission_file = mission
	f.spawn_area = int(args.get("spawn_area", "-1"))
	f.debug_log = args.has("log")
	f.autopilot = args.has("autopilot")
	f.endless_ammo = args.has("infinite_ammo") or args.has("endless_ammo") or args.has("autopilot")
	f.bomb_run = args.has("bomb_run")
	f.kill_enemies = args.has("kill_enemies")
	f.no_enemies = args.has("no_enemies")
	f.god_mode = args.has("god") or args.has("godmode") or args.has("invincible")
	f.vr_active = vr_active
	f.debrief_after = float(args.get("debrief", "-1"))
	f.approach = args.has("approach")
	f.auto_land_test = args.has("autoland")
	if f.approach and absf(float(args.approach)) > 1.0:   # bare --approach = "1": the 8 km default
		f.approach_dist = float(args.approach)
	f.approach_high = float(args.get("approach_high", "120"))
	f.approach_speed = float(args.get("approach_speed", "115"))
	f.camera_mode = int(args.get("cam", "0"))
	f.exit_to_menu.connect(show_menu)
	f.restart.connect(start_flight.bind(area, plane, mission))
	_switch(f)


func show_viewer() -> void:
	var v = ModelViewer.new()
	v.initial_model = args.get("model", "")
	v.zoom = float(args.get("view_zoom", "1"))
	v.spin = not args.has("view_still")
	if args.has("view_orbit"):
		var o: PackedStringArray = str(args.view_orbit).split(",")
		v.start_orbit = Vector2(float(o[0]), float(o[1]) if o.size() > 1 else 0.3)
	v.back.connect(show_menu)
	_switch(v)


## Desktop mouse/keyboard still drive flat screens inside the XR SubViewport.
func _input(event: InputEvent) -> void:
	if not vr_active or ui_viewport == null or current is FlightScene:
		return
	ui_viewport.push_input(event)
	if event is InputEventMouseMotion and vr_cursor != null:
		var m := event as InputEventMouseMotion
		vr_cursor.position = m.position - Vector2(15, 15)


## Right-hand controller acts as a pointer for the flat UI panel. Based on
## Godot's OpenXR composition-layer UI example (intersects_ray + push_input).
## Keep the flat 2D panels centred in the field of view: head-locked like a
## visor, so the player never has to tilt their head to read a menu or HUD.
func _place_vr_panel() -> void:
	if sbs_mode:
		return   # world-locked full panel, head tracking moves the view instead
	if vr_layer == null or not is_instance_valid(vr_layer):
		return
	var cam := get_viewport().get_camera_3d()
	if cam == null:
		return
	var t: Transform3D = cam.global_transform
	var fwd: Vector3 = -t.basis.z
	var basis := Basis.looking_at(fwd, t.basis.y)
	var center: Vector3 = t.origin + fwd * 1.8
	vr_layer.global_transform = Transform3D(basis, center)
	if vr_panel_bezel != null and is_instance_valid(vr_panel_bezel):
		vr_panel_bezel.global_transform = Transform3D(basis, center + fwd * 0.05)
	if vr_cursor == null or ui_viewport == null:
		return


func _vr_ui_pointer() -> void:
	if not vr_active or vr_layer == null or vr_pointer == null or ui_viewport == null:
		return
	_place_vr_panel()
	var win := get_viewport()
	if win != null and ui_viewport.size != win.size:
		ui_viewport.size = win.size
		vr_layer.quad_size = Vector2(1.9, 1.9 * float(win.size.y) / float(win.size.x))
	if current is FlightScene:
		return
	var t: Transform3D = vr_pointer.global_transform
	var uv: Vector2 = vr_layer.intersects_ray(t.origin, -t.basis.z)
	if uv.x < 0.0 or uv.y < 0.0:
		_vr_pressed = false
		_vr_uv = Vector2(-1.0, -1.0)
		return
	var size := Vector2(ui_viewport.size)
	var pos: Vector2 = uv * size
	if vr_cursor != null:
		vr_cursor.position = pos - Vector2(15, 15)
	var pressed := vr_pointer.is_button_pressed("trigger_click")
	if uv != _vr_uv:
		var motion := InputEventMouseMotion.new()
		motion.position = pos
		motion.relative = pos - (_vr_uv * size if _vr_uv.x >= 0.0 else pos)
		if pressed:
			motion.button_mask = MOUSE_BUTTON_MASK_LEFT
		ui_viewport.push_input(motion)
	if pressed != _vr_pressed:
		var click := InputEventMouseButton.new()
		click.button_index = MOUSE_BUTTON_LEFT
		click.pressed = pressed
		click.position = pos
		ui_viewport.push_input(click)
	_vr_pressed = pressed
	_vr_uv = uv


func _process(delta: float) -> void:
	if _headless:
		_headless_tick()
		return
	if vr_active:
		if delta > 0.8:
			_vr_slow_frames += 1
			if _vr_slow_frames >= 4:
				_disable_vr()
		else:
			_vr_slow_frames = 0
		_vr_ui_pointer()
	if _frames_left > 0:
		_frames_left -= 1
		if _frames_left == 0:
			if args.has("shot"):
				# In stereo/VR mode frame_post_draw may not signal for a plain
				# viewport; never block the frame-budget driver on it.
				await RenderingServer.frame_post_draw
				var vp := get_viewport()
				if vp != null:
					var tex := vp.get_texture()
					if tex != null:
						var img := tex.get_image()
						if img != null:
							img.save_png(args.shot)
							print("Screenshot saved: ", args.shot)
			get_tree().quit()


## Headless runs (--headless): no window and a dummy renderer, so the game runs
## on the normal main loop and this driver decides when to stop:
##   - the flight scene's mission ends (debrief) -> exit 0 on success, 3 otherwise
##   - --frames=N process frames have run (default 90 for free flight, unlimited with a mission)
##   - --timeout=S wall-clock seconds have passed (default 600) -> exit 4
## A status line is printed every --status=S seconds (default 2).
## Do NOT also pass Godot's own --quit: it stops the engine after one frame.
func _headless_setup() -> void:
	var has_mission: bool = args.get("mission", "") != "" or args.get("auto", "") in ["campaign", "continue"]
	_hl_max_frames = int(args.get("frames", "0" if has_mission else "90"))
	_hl_deadline_ms = Time.get_ticks_msec() + int(float(args.get("timeout", "600")) * 1000.0)
	_hl_next_status_ms = 0
	if args.has("shot"):
		print("HEADLESS: --shot ignored: --headless uses a dummy renderer that has no image to save. ",
			"Run without --headless for screenshots.")
	print("HEADLESS: auto=%s mission=%s time_scale=%.0f frames=%s timeout=%ss" % [
		args.get("auto", "flight"), args.get("mission", "-"), Engine.time_scale,
		str(_hl_max_frames) if _hl_max_frames > 0 else "unlimited", args.get("timeout", "600")])


func _headless_tick() -> void:
	if _hl_done:
		return
	_hl_frames += 1
	var f = _flight_scene()
	var now := Time.get_ticks_msec()
	if now >= _hl_next_status_ms:
		_hl_next_status_ms = now + int(float(args.get("status", "2")) * 1000.0)
		_headless_status(f)
	if f != null and f.mission_over:
		_headless_finish(f)
	elif _hl_max_frames > 0 and _hl_frames >= _hl_max_frames:
		_headless_status(f)
		print("HEADLESS: frame budget reached (%d frames)" % _hl_frames)
		_headless_quit(0)
	elif now >= _hl_deadline_ms:
		_headless_status(f)
		printerr("HEADLESS: timeout after %d frames" % _hl_frames)
		_headless_quit(4)


func _flight_scene() -> Node:
	for c in get_children():
		if c is FlightScene and not c.is_queued_for_deletion():
			return c
	return null


func _headless_status(f) -> void:
	if f == null or f.player == null:
		print("HEADLESS: frame %d (no flight scene)" % _hl_frames)
		return
	var p = f.player
	var pos: Vector3 = p.global_position
	var agl: float = pos.y - (f.terrain.height_at(pos.x, pos.z) if f.terrain else 0.0)
	var nav := "-"
	if f.waypoints.size() > 0:
		nav = "%d/%d" % [mini(f.nav_index + 1, f.waypoints.size()), f.waypoints.size()]
	var mode := "land" if f.autopilot_land else ("auto" if f.autopilot else "manual")
	var e: Vector3 = p.global_transform.basis.get_euler()
	print("HEADLESS: frame %d  sim~%.0fs  spd=%.0f m/s  vy=%.0f  pitch=%.0f bank=%.0f  agl=%.0f m  ground=%s  nav=%s  ap=%s  pullup=%s  hull=%d%%  alive=%s" % [
		_hl_frames, Time.get_ticks_msec() / 1000.0 * Engine.time_scale, p.speed(), p.velocity.y,
		rad_to_deg(e.x), rad_to_deg(-e.z), agl, p.on_ground, nav, mode,
		f._terrain_pullup_needed() if p.alive else false, int(p.health), p.alive])
	if args.has("ap_debug") and f.get("_ap_debug"):
		print("HEADLESS:   ap_debug: ", f._ap_debug)


func _headless_finish(f) -> void:
	var report := {}
	for n in f.find_children("*", "", true, false):
		if "report" in n and n.report is Dictionary and not n.report.is_empty():
			report = n.report
			break
	_headless_status(f)
	print("HEADLESS: MISSION OVER result=%s  %s" % [report.get("result", "?"), report.get("reason", "")])
	print("  mission registers: %s  campaign report: %s" % [f._vm_regs, f.campaign_report(report.get("result", "") == "success")])
	for row in report.get("stats", []):
		print("  %s: %s" % [row[0], row[1]])
	for wp in report.get("waypoints", []):
		print("  waypoint %s: %s" % [wp.name, "reached" if wp.reached else "missed"])
	for line in report.get("log", []):
		print("  radio: %s" % line)
	_headless_quit(0 if report.get("result", "") == "success" else 3)


func _headless_quit(code: int) -> void:
	_hl_done = true
	get_tree().paused = false
	get_tree().quit(code)


func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed("screenshot"):
		var dir := OS.get_user_data_dir() + "/screenshots"
		DirAccess.make_dir_recursive_absolute(dir)
		var path := dir + "/sc_%s.png" % Time.get_datetime_string_from_system().replace(":", "-")
		get_viewport().get_texture().get_image().save_png(path)
		print("Screenshot saved: ", path)


