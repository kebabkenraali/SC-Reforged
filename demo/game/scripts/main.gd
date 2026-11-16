## Application root: requires a mounted original installation, then switches
## between menu, flight and model viewer screens.
##
## Automation (used for testing): pass after "--"
##   --auto=flight|viewer|menu  --map=CANYON  --plane=OBJECTS/F-16DES.IFF
##   --auto=campaign (new) | --auto=continue  --conv=N (play conversation N)  --story=N (cut-scene MIDn)  --shot_scene=N (establishing shot N)  --transport=N
##   --mission=MISSIONS/MISN-10A.IFF  --spawn_area=2  --log  --autopilot  --endless_ammo  --bomb_run  --debrief=2  --approach  --model=OBJECTS/MIG29.IFF  --cam=0..2  --frames=120  --shot=C:/path.png
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


func _ready() -> void:
	# Keep screenshots, input and screen switching alive while the game is paused.
	process_mode = Node.PROCESS_MODE_ALWAYS
	
	for a in OS.get_cmdline_user_args():
		var kv := a.trim_prefix("--").split("=", true, 1)
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
	if Demo.enabled():
		get_window().title = "Strike Commander Reforged – Demo"
	get_window().theme = UiTheme.build()
	if not Demo.enabled():
		get_window().title = "Strike Commander Reforged"
	get_window().min_size = Vector2i(1024, 600)

	if args.has("dir"):
		SCData.mount(args.dir)
	if not SCData.is_mounted() and not SCData.auto_mount():
		show_setup()
	else:
		_start()
	if args.has("shot"):
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
			show_menu()


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
	f.camera_mode = int(args.get("cam", "0"))
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
	f.debrief_after = float(args.get("debrief", "-1"))
	f.approach = args.has("approach")
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
	if _frames_left > 0:
		_frames_left -= 1
		if _frames_left == 0:
			await RenderingServer.frame_post_draw
			get_viewport().get_texture().get_image().save_png(args.shot)
			print("Screenshot saved: ", args.shot)
			get_tree().quit()


func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed("screenshot"):
		var dir := OS.get_user_data_dir() + "/screenshots"
		DirAccess.make_dir_recursive_absolute(dir)
		var path := dir + "/sc_%s.png" % Time.get_datetime_string_from_system().replace(":", "-")
		get_viewport().get_texture().get_image().save_png(path)
		print("Screenshot saved: ", path)


