## Application root: requires a mounted original installation, then switches
## between menu, flight and model viewer screens.
##
## Automation (used for testing): pass after "--"
##   --auto=flight|viewer|menu  --map=CANYON  --plane=OBJECTS/F-16DES.IFF
##   --auto=campaign (new) | --auto=continue  --conv=N (play conversation N)  --story=N (cut-scene MIDn)  --shot_scene=N (establishing shot N)  --transport=N
##   --mission=MISSIONS/MISN-10A.IFF  --spawn_area=2  --log  --autopilot  --endless_ammo  --kill_enemies (cheat)  --bomb_run  --debrief=2  --approach  --model=OBJECTS/MIG29.IFF  --cam=0..2  --frames=120  --shot=C:/path.png
extends Node

const Demo = preload("res://scripts/core/demo.gd")

const SetupScreen = preload("res://scripts/ui/setup_screen.gd")
const MainMenu = preload("res://scripts/ui/main_menu.gd")
const FlightScene = preload("res://scripts/game/flight_scene.gd")
const ModelViewer = preload("res://scripts/ui/model_viewer.gd")
const UiTheme = preload("res://scripts/ui/ui_theme.gd")
const Campaign = preload("res://scripts/game/campaign.gd")
const BaseScreen = preload("res://scripts/ui/base_screen.gd")

var current: Node
var campaign
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
			if not _headless:
				show_menu()
			else:
				# Default to flight mode in headless
				start_flight("CANYON", "OBJECTS/F-16DES.IFF", "")


func _switch(node: Node) -> void:
	if current != null:
		current.queue_free()
	current = node
	add_child(node)


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
	_switch(m)


## Campaign: base screens, conversations and missions from GAMEFLOW.
func start_campaign(new_game: bool) -> void:
	campaign = Campaign.new()
	var resume: bool = not new_game and campaign.load_saved()
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
		campaign.start_new()


func _fly_campaign_mission(file: String) -> void:
	_base.visible = false
	_base.process_mode = Node.PROCESS_MODE_DISABLED
	var f = FlightScene.new()
	f.mission_file = file
	f.campaign_mode = true
	f.campaign = campaign  # Pass campaign for loadout access
	f.camera_mode = int(args.get("cam", "0"))
	# Testing flags also apply to campaign flights (headless autopilot runs).
	f.autopilot = args.has("autopilot")
	f.endless_ammo = args.has("endless_ammo") or args.has("infinite_ammo") or args.has("autopilot")
	f.kill_enemies = args.has("kill_enemies")
	f.debug_log = args.has("log")
	f.mission_result.connect(_campaign_flight_done.bind(f))
	f.restart.connect(func(): f.queue_free(); _fly_campaign_mission(file))
	add_child(f)


func _campaign_flight_done(success: bool, f: Node) -> void:
	f.queue_free()
	_base.visible = true
	_base.process_mode = Node.PROCESS_MODE_INHERIT
	_base.flight_done.emit(success)


func _drop_base() -> void:
	if _base != null and is_instance_valid(_base) and _base != current:
		_base.queue_free()
	_base = null


func start_flight(area: String, plane: String, mission := "") -> void:
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
	f.debrief_after = float(args.get("debrief", "-1"))
	f.approach = args.has("approach")
	if f.approach and float(args.approach) > 1.0:   # bare --approach = "1": the 8 km default
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
	v.back.connect(show_menu)
	_switch(v)


func _process(_delta: float) -> void:
	if _headless:
		_headless_tick()
		return
	if _frames_left > 0:
		_frames_left -= 1
		if _frames_left == 0:
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


