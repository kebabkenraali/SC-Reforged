## Flight over an original terrain area: free flight, or an original mission
## (player start, enemy aircraft, base targets, waypoints). Ground objects from
## the terrain's own object lists are always placed. Rendered with modern
## lighting, shadows, fog and post-processing.
extends Node3D

const Aircraft = preload("res://scripts/game/aircraft.gd")
const CameraRig = preload("res://scripts/game/camera_rig.gd")
const Hud = preload("res://scripts/game/hud.gd")
const Effects = preload("res://scripts/game/effects.gd")
const PauseMenu = preload("res://scripts/ui/pause_menu.gd")
const GroundObject = preload("res://scripts/game/ground_object.gd")
const RealSpaceModel = preload("res://scripts/formats/realspace_model.gd")
const Weapons = preload("res://scripts/game/weapons.gd")
const Missile = preload("res://scripts/game/missile.gd")
const Bomb = preload("res://scripts/game/bomb.gd")
const MissionVM = preload("res://scripts/game/mission_vm.gd")
const AircraftMeshes = preload("res://scripts/game/aircraft_meshes.gd")
const ExternalModels = preload("res://scripts/game/external_models.gd")

const ENEMY_MODELS := ["OBJECTS/MIG29.IFF", "OBJECTS/MIG21.IFF", "OBJECTS/MIG29GRA.IFF"]
const BULLET_SPEED := 1050.0
const BULLET_LIFE := 2.0
const DETECT_RANGE := 22000.0     # enemy fighters engage inside this distance
const ALLY_ENGAGE_RANGE := 10000.0  # wingmen break formation for bandits inside this distance
## Non-combat aircraft (model name fragments): they never dogfight.
const TRANSPORT_MODELS := ["C130", "747", "L1011", "E-3", "E3SENTRY", "LEAR", "KC135", "CARGO"]
const LOCK_CONE := 0.52           # player missile lock half-angle (rad)
const SAFE_RADIUS := 8000.0       # terrain AA this close to the player start is friendly

signal exit_to_menu
signal restart
signal mission_result(success: bool)    # campaign mode: leave the debrief

const Debrief = preload("res://scripts/ui/debrief.gd")
const FEET_M := 0.3048         # metres per foot (original units are feet)
const GLIDE_SLOPE := 3.0          # degrees
## Threshold crossing height of the landing autopilot's glide path (m). A path
## from the threshold itself left no margin over the ground 500 m short of the
## MISN-1A runway (8 m above threshold level): full flights hit it.
const GLIDE_TCH := 15.0

var area := "CANYON"
var plane_model := "OBJECTS/F-16DES.IFF"
var camera_mode := 0
var mission_file := ""
var campaign_mode := false
var campaign: Object = null          # Campaign instance (for loadout access)
var spawn_area := -1          # testing: start airborne near this mission area
var debug_log := false        # testing: print player and combat state every second
var autopilot := false        # testing: the player's aircraft attacks the nearest enemy itself
var endless_ammo := false     # testing: missiles/countermeasures are never depleted
var kill_enemies := false     # testing cheat (--kill_enemies): every enemy / target dies as it appears
var _loadout := {}            # the aircraft's original from the WPNS loadout, filled up by endless_ammo
var bomb_run := false         # testing: start at the computed release point for a mission target
var debrief_after := -1.0     # testing: end the mission (as landed) after this many seconds
var approach := false         # testing: start on final approach to the home runway
var aborted := false          # campaign: left through the pause menu (original exit code 5)
var auto_land_test := false   # testing (--autoland): start the auto-landing at once
var approach_dist := 8000.0   # --approach=M: distance from the threshold
var approach_high := 120.0    # --approach_high=M: height above the 3 deg slope
var approach_speed := 115.0   # --approach_speed=M/S

# Autopilot modes (toggled by player input)
var autopilot_waypoint := false   # follow mission waypoints
var autopilot_land := false       # land at home runway
# Fast travel to the active waypoint (time-warp autopilot, toggled by F7).
var fast_travel := false
var _travel_scale := 1.0          # current applied time-warp factor
var _travel_base := 1.0           # Engine.time_scale before travel (1 normally)
const TRAVEL_MAX_SCALE := 8.0     # cap for the time warp
const TRAVEL_SAFE_M := 20000.0    # enemies inside this block / cancel travel
const TRAVEL_ARRIVE_M := 5000.0   # arrival radius (also uses the waypoint radius)
var _ft_auto := false             # headless --fasttravel auto-engage (once)
var _log_timer := 0.0
var _ap_debug := ""
var _ap_run_out := false
var _ap_goaround := false         # landing autopilot: missed approach, fly out and re-enter
var _ap_pr_cmd := NAN             # last pitch-rate command (debug)

var mission
var ground_objects: Array = []
var targets: Array = []       # mission objectives (aircraft and ground objects)
var waypoints: Array = []     # [{ name, pos }]
var mission_complete := false
var _player_start := {}
var _mesh_cache := {}

# Mission script state
var allies: Array = []           # friendly AI aircraft (wingmen, transports)
var nav_index := 0               # current waypoint of the player's route
var flags := {}                  # script flags (52 / 53)
var vm_vars := {}                # script variables (10/11/50/55/56/23)
var _actions := {}               # owner key -> { op, arg, t0 }
var _global_blocks: Array = []   # blocks not referenced by parts or scenes
var _script_timer := 0.0
var _pending_messages: Array = []

# Statistics for the debrief
var stats := {"shots": 0, "missiles": 0, "bombs": 0, "air_kills": 0, "ground_kills": 0, "wingman_air_kills": 0, "wingman_ground_kills": 0}
var radio_log: Array = []
var mission_over := false
var _t_start := 0.0
var _sim_time := 0.0             # simulated seconds (physics time: follows --speed and the time warp)
var _was_airborne := false
var _layer: CanvasLayer

# Cockpit audio (the player's own aircraft is heard non-positionally)
var _snd := {}                   # name -> AudioStreamPlayer
var _player_firing := false
var _hit_sound_cd := 0.0
var home_runway                  # ground object of the runway nearest the start
var _script_success := false     # a "Mission accomplished" radio call was made
var _part_nodes := {}            # PART index -> node
var _escort_ids := {}            # part id -> true when something escorts it (ally transport)
var _dormant := {}               # PART index -> true while waiting for activation
var _scene_wait := {}            # PART index -> scene k: aircraft created when the player enters scene k
var _scene_entered: Array = []
var _chat_timer := 18.0           # cockpit radio chatter cadence
var _scene_timer := 0.0
var _pal: PackedColorArray
var _smooth := true
var _activating := false
var cockpit_model: MeshInstance3D   # original 3D cockpit (visible in cockpit view)

var terrain
var player
var enemies: Array = []
var rig
var hud
var kills := 0
var _bullets: Array = []      # [{ pos, vel, life, owner }]
var _tracers: MultiMeshInstance3D
var _pause: Control
var _respawn_timer := -1.0
var _sun: DirectionalLight3D
var _env: Environment
var _max_object_height := 0.0
var missiles_in_flight: Array = []
var aa_sites: Array = []
var player_lock = null           # enemy aircraft the player's missiles would fire at
var ground_lock = null           # ground object an AGM would be fired at
var weapon_mode := "air"         # Weapons.MODES
var bombs_in_flight: Array = []
var _missile_meshes := {}
var _specs := {}
var _release_cooldown := 0.0


func _ready() -> void:
	
	_travel_base = Engine.time_scale
	var t0 := Time.get_ticks_msec()
	if mission_file != "":
		mission = SCData.mission(mission_file)
		if mission != null:
			area = mission.area
	var pal_name: String = SCData.world_palette(area)
	var world_pal: PackedColorArray = SCData.palette(pal_name)
	var obj_pal: PackedColorArray = SCData.palette()
	var smooth: bool = Settings.get_value("video", "smooth_textures")

	_build_environment()
	terrain = SCData.terrain(area)
	if terrain != null:
		var type_cols: PackedColorArray = terrain.type_colors(SCData.read(pal_name))
		var terrain_mat := _terrain_material(world_pal, smooth)
		for chunk in terrain.build_chunks(type_cols, terrain_mat):
			add_child(chunk)
		_add_outer_ground(type_cols, terrain_mat)

	if terrain != null:
		for o in terrain.objects:
			_add_ground_object(o.model, o.destroyed, o.pos, 0.0, obj_pal, smooth)

	if mission != null:
		_setup_mission(obj_pal, smooth)
	else:
		player = _spawn(plane_model, obj_pal, smooth)
		var sp := Vector3(0, 0, terrain.world_size() * 0.25 if terrain else 0.0)
		sp.y = (terrain.height_at(sp.x, sp.z) if terrain else 0.0) + 1500.0
		_player_start = {"pos": sp, "heading": PI, "air": true}
	player.is_player = true
	player.crashed.connect(_on_player_down)
	player.destroyed.connect(_on_player_down)
	if mission != null and player.has_signal("damaged"):
		var pp = mission.player_part()
		player.set_meta("actor", mission.cast[pp.id] if pp != null and pp.id < mission.cast.size() else "")
		player.damaged.connect(_on_aircraft_damaged)
	_radio_player = AudioStreamPlayer.new()
	_radio_player.volume_db = 2.0
	add_child(_radio_player)
	_place_player()

	for i in (4 if mission == null else 0):
		var e = _spawn(ENEMY_MODELS[i % ENEMY_MODELS.size()], obj_pal, smooth)
		if e == null:
			continue
		e.destroyed.connect(_on_enemy_destroyed)
		e.crashed.connect(_on_enemy_destroyed)
		enemies.append(e)
		var ang := TAU * i / 4.0
		_place(e, Vector3(sin(ang), 0, cos(ang)) * 9000.0, ang + PI * 0.5)

	for e in enemies:
		e.hostile = true
	_setup_air_defences()
	for o in ground_objects:
		_max_object_height = maxf(_max_object_height, o.global_position.y + o.radius * 2.0)

	_tracers = MultiMeshInstance3D.new()
	var mm := MultiMesh.new()
	mm.transform_format = MultiMesh.TRANSFORM_3D
	mm.mesh = Effects.tracer_mesh()
	mm.instance_count = 256
	mm.visible_instance_count = 0
	_tracers.multimesh = mm
	_tracers.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(_tracers)

	rig = CameraRig.new()
	rig.target = player
	rig.mode = camera_mode
	add_child(rig)

	var layer := CanvasLayer.new()
	add_child(layer)
	_layer = layer
	_setup_cockpit_audio()
	_t_start = _sim_time
	_find_home_runway()
	if approach and home_runway != null:
		_setup_approach()
	if debrief_after >= 0.0 and mission != null:
		get_tree().create_timer(debrief_after).timeout.connect(func(): _end_mission("landed"))
	hud = Hud.new()
	hud.scene = self
	layer.add_child(hud)
	for pm in _pending_messages:
		hud.message(pm[0], pm[1])
	_pause = PauseMenu.new()
	_pause.resume.connect(_set_paused.bind(false))
	_pause.quit_to_menu.connect(func():
		get_tree().paused = false
		if campaign_mode:
			aborted = true    # the original's "abort": as if the mission was not flown
			mission_result.emit(false)
		else:
			exit_to_menu.emit())
	_pause.visible = false
	layer.add_child(_pause)
	process_mode = Node.PROCESS_MODE_PAUSABLE
	_pause.process_mode = Node.PROCESS_MODE_WHEN_PAUSED

	Settings.changed.connect(_apply_settings)
	_apply_settings()
	if mission != null:
		var goal: String = " / ".join(mission.messages.slice(0, 3))
		_say("%s (%s): %s. Throttle: Shift, rotate: S." % [mission.name, mission_file.get_file().get_basename(), goal], 8.0)
	else:
		_say("%s - %s. Shoot down the MiGs (Space), C changes camera." % [area, player.display_name], 6.0)
	print("Flight scene ready in %d ms (palette %s)" % [Time.get_ticks_msec() - t0, pal_name])


func _spawn(model_name: String, pal: PackedColorArray, smooth: bool):
	var override_mesh = ExternalModels.override_mesh(model_name)
	var model = SCData.model(model_name)
	var modern: Mesh = null
	if override_mesh == null:
		if model == null:
			# No original data (e.g. the demo): the shipped procedural mesh is
			# the fallback for this aircraft.
			modern = AircraftMeshes.build(model_name)
		elif Settings.get_value("video", "modern_models", false):
			# Explicitly requested: procedural mesh instead of the original data.
			modern = AircraftMeshes.build(model_name)
	var use_mesh: Mesh = override_mesh if override_mesh != null else modern
	if model == null and use_mesh == null:
		push_warning("Model missing: " + model_name)
		return null
	var a = Aircraft.new()
	a.setup(model, pal, smooth, use_mesh, model_name)
	a.terrain = terrain
	if use_mesh == modern and modern != null:
		a.model_instance.set_surface_override_material(AircraftMeshes.ACCENT, AircraftMeshes.accent_material(model_name))
	add_child(a)
	if player != null:            # the player is created first and heard in the cockpit
		Sfx.attach_engine(a)
		_setup_cockpit_model()
	return a


func _setup_mission(pal: PackedColorArray, smooth: bool) -> void:
	_pal = pal
	_smooth = smooth
	# The original tagged escort targets with its own side byte (MISN-1A's
	# cargo is side 1 like the MiGs, yet "C-130 joins you" makes it a
	# friend). An escort (a8) only makes the target a FRIEND when the
	# block owner is on the player's side; enemy escorts (Egypt's AWACS
	# flights) must keep their enemy classification.
	var start = mission.player_part()
	_escort_ids.clear()
	for i in mission.parts.size():
		var p: Dictionary = mission.parts[i]
		if p.side != start.side:
			continue
		for s in p.slots:
			if s >= 0 and s < mission.blocks.size():
				for id in mission.block_args(s, 0xa8):
					_escort_ids[id] = true
	player = _spawn("OBJECTS/%s.IFF" % start.model, pal, smooth)
	if player == null:
		player = _spawn(plane_model, pal, smooth)
	
	# Apply custom loadout from campaign (set by the loadout screen).
	if campaign != null:
		var custom_loadout = campaign._pending_loadout
		if custom_loadout != null and custom_loadout is Dictionary and not custom_loadout.is_empty():
			player.apply_loadout(custom_loadout)
		campaign._pending_loadout = null  # consume it
	
	var ground: float = terrain.height_at(start.pos.x, start.pos.z) if terrain else 0.0
	_player_start = {"pos": start.pos, "heading": -deg_to_rad(start.heading),
		"air": start.pos.y - ground > 30.0}
	_part_nodes[mission.parts.find(start)] = player
	# The player's route block gives the waypoints and their texts; fall back to areas.
	for wp in mission.flight_nav_plan():
		var radius := 0.0
		for a in mission.areas:
			if Vector2(a.pos.x - wp.pos.x, a.pos.z - wp.pos.z).length() < 3000.0:
				radius = maxf(radius, float(a.radius))
		waypoints.append({"name": wp.label if wp.label != "" else "WP %d" % (waypoints.size() + 1),
			"pos": wp.pos, "radius": radius})
	if waypoints.is_empty():
		for a in mission.areas:
			if a.name.length() > 1:
				waypoints.append({"name": a.name, "pos": a.pos, "radius": a.radius})
	for i in mission.dormant_part_indices():
		_dormant[i] = true
	# Aircraft listed in a scene with an area enter the world when the player
	# enters that area, as in the original (MISN-1A's MiGs belong to the
	# "Restricted Airspace" scene and were flying from the first frame).
	# Ground objects stay: they are static and targets must be visible.
	for k in mission.scenes.size():
		var sc: Dictionary = mission.scenes[k]
		if sc.area < 0 or sc.area >= mission.areas.size():
			continue
		for pi in sc.parts:
			if pi < mission.parts.size() and not _part_nodes.has(pi) and not _dormant.has(pi) \
					and mission.parts[pi].id != start.id and _is_aircraft("OBJECTS/%s.IFF" % mission.parts[pi].model):
				_scene_wait[pi] = k
	for i in mission.parts.size():
		if not _part_nodes.has(i) and not _dormant.has(i) and not _scene_wait.has(i):
			_spawn_part(i)
	_link_formations()
	_scene_entered.resize(mission.scenes.size())
	_scene_entered.fill(false)
	# Blocks nobody references are mission-wide logic, run every tick.
	var used := {}
	for p in mission.parts:
		for b in p.slots:
			used[b] = true
	for sc in mission.scenes:
		for b in sc.on_enter:
			used[b] = true
	for b in mission.blocks.size():
		if not used.has(b):
			_global_blocks.append(b)


## Creates the node for one mission PART: airborne aircraft (and wingmen of
## the player) fly; everything else is a ground object.
func _spawn_part(i: int, spawn_pos_override: Variant = null):
	var part: Dictionary = mission.parts[i]
	var start = mission.player_part()
	var model_name: String = "OBJECTS/%s.IFF" % part.model
	if not SCData.has(model_name):
		return null
	var part_pos: Vector3 = spawn_pos_override if spawn_pos_override is Vector3 else part.pos
	var g: float = terrain.height_at(part_pos.x, part_pos.z) if terrain else 0.0
	var is_jet := _is_aircraft(model_name)
	# Aircraft with a speed (or brought in by the script) fly; parked ones have none.
	var airborne: bool = is_jet and (part_pos.y - g > 60.0 or part.speed > 0 or _activating)
	var wingman: bool = is_jet and part.leader == start.id and part.side == start.side
	# Map side to team: 1 = player/ally, 2 = enemy. Escort targets (the
	# transport an `a8` block sends its escorters after) are allies even
	# when their own side byte matches the enemy's.
	var team: int = 1 if (part.side == start.side or _escort_ids.has(part.id)) else 2
	var node
	if airborne or wingman:
		var a = _spawn(model_name, _pal, _smooth)
		var spawn_speed: float = maxf(part.speed * 0.5144, 180.0)
		if _is_transport_model(part.model):
			# The PART speed is the original cruise (C-130: 170 kt = 87 m/s; the
			# shared F-16 model has ~2x the lift needed at that speed). The floor
			# keeps it above the shared F-16 flight model's stall speed.
			a.cruise_speed = maxf(part.speed * 0.5144, 80.0)
			spawn_speed = a.cruise_speed
		if airborne:
			var pos: Vector3 = part_pos
			pos.y = maxf(pos.y, g + 300.0)
			a.respawn(pos, -deg_to_rad(part.heading), spawn_speed)
			# Enemies begin at their briefing position: they do not cruise
			# the whole map from the first frame (the original brought the
			# raiders in with the scenario scene). Wingmen/friendlies fly on.
			if team != 1 and not wingman and not _activating:
				a.standby = true
				a.hud_contact.connect(func(_pname: String): _contact_call(a))
		else:
			a.respawn(Vector3(part.pos.x, g + 2.2, part.pos.z), -deg_to_rad(part.heading), 0.0)
			a.on_ground = true
		a.team = team
		a.home = part_pos
		a.scene_ref = self
		a.patrol_radius = 6000.0
		a.formation_offset = part.offset if part.offset.length() > 1.0 else Vector3(90, 0, 300)
		a.attack_ids = mission.block_args(part.slots[1], 0xa7)
		for sp in mission.block_args(part.slots[1], 0xa5) + mission.block_args(part.slots[3], 0xa5):
			if sp < mission.spots.size():
				a.route.append(mission.spots[sp])
		if team != 1:  # enemy
			a.destroyed.connect(_on_enemy_destroyed)
			a.crashed.connect(_on_enemy_destroyed)
			enemies.append(a)
			targets.append(a)
			a.missile_cooldown = randf_range(8.0, 15.0)
		else:
			allies.append(a)
		node = a
	else:
		# Objects at the player's home (area 0 or absolute) are not targets.
		var home_areas := [-1, 0]
		var ground_team: int = 1 if part.side == start.side else 2
		node = _add_ground_object(part.model, part.destroyed, Vector3(part.pos.x, g, part.pos.z),
			-deg_to_rad(part.heading), _pal, _smooth)
		if node == null:
			return null
		node.team = ground_team
		node.hostile = (team != 1) or not part.area in home_areas
		if not part.area in home_areas and not part.model.begins_with("RWY"):
			node.is_target = true
			targets.append(node)
	_part_nodes[i] = node
	node.set_meta("part_model", part.model)   # original PART data of this aircraft/object
	node.set_meta("part_side", part.side)
	node.set_meta("part_id", part.id)
	# Radio voice: the CAST entry of this part (INTEL/<actor>.IFF + SPEECH.PAK).
	node.set_meta("actor", mission.cast[part.id] if part.id >= 0 and part.id < mission.cast.size() else "")
	if node.has_signal("damaged"):
		node.damaged.connect(_on_aircraft_damaged)
		if team == 1 and node != player:
			node.destroyed.connect(_on_ally_down)
			node.crashed.connect(_on_ally_down)
	if node.get("velocity") != null:
		node.scripted = part.slots[1] >= 0
	node.destroyed.connect(func(_n): _run_block(part.slots[2], part.id))
	if node.has_signal("crashed"):
		node.crashed.connect(func(_n): _run_block(part.slots[2], part.id))
	_run_block(part.slots[0], part.id)
	return node


## PART leader ids -> formation leaders (also used by aa "follow" in AI blocks).
func _link_formations() -> void:
	for i in _part_nodes:
		var n = _part_nodes[i]
		if n == player or not n.get("formation_offset") != null:
			continue
		var part: Dictionary = mission.parts[i]
		var lead_id: int = part.leader
		if lead_id < 0:
			var follow: Array = mission.block_args(part.slots[1], 0xaa)
			lead_id = follow[0] if not follow.is_empty() else -1
		var li: int = mission.part_index(lead_id) if lead_id >= 0 else -1
		if li >= 0 and _part_nodes.has(li) and _part_nodes[li] != n and _part_nodes[li].get("velocity") != null:
			n.formation_leader = _part_nodes[li]


## Executes the side effects of a script block that are understood: activate
## parts (90), set flags (55) and radio texts (ab). Conditions are not decoded,
## so their side effects run unconditionally when the block is triggered.
## HUD message that also works before the HUD exists (start blocks run early).
func _say(text: String, seconds := 3.0) -> void:
	if hud != null:
		hud.message(text, seconds)
	else:
		_pending_messages.append([text, seconds])
	Sfx.radio_blip()   # every cockpit message rides a radio squak


# --- Radio: the original INTEL profiles with their SPEECH.PAK voices ---------
#
# Every CAST actor has a radio profile (INTEL/<actor>.IFF MSGS) whose message
# ids mean the same in every profile; SCData.radio_voice() plays the recording.
#   0 no  1 yes  2..5 status great..critical  6 requesting help  7 I'm hit
#   8 returning to base  9 ejecting / going down  10 hit bad  11 target ahead
#   12 bandits inbound  13 target destroyed  14 friendly fire  15 nice kill
#   16 watch your six  17 missile on you  18 I'll take this one  19 ground fire
#   20..27 mission lines (enemies: death cries)  28 how's it going
#   29 runway clear for takeoff  30 runway clear for landing
const R_STATUS := [2, 3, 4, 5]
const R_DEATH := [9, 23, 24, 25, 26, 27]

var _radio_player: AudioStreamPlayer
var _radio_queue: Array = []        # [{ actor, id, text, speaker }]
var _radio_free_ms := 0             # real time when the channel is free again
var _radio_cool := {}               # "actor:id" -> real time (ms) when allowed again
var _radio_quiet_ms := 0            # last radio line (for the quiet-time chatter)
var _radio_flags := {}              # one-shot calls already made (takeoff, landing)


## Queues radio message `id` of `actor`. Script lines (priority) go first;
## repeated situational calls are rate-limited per actor and line.
func radio_call(actor: String, id: int, cooldown := 25.0, priority := false) -> bool:
	if actor == "" or actor == "NULL":
		return false
	var r: Dictionary = SCData.radio(actor)
	var text: String = String(r.msgs.get(id, "")).strip_edges()
	if text == "" or text == ".":
		return false
	var now := Time.get_ticks_msec()
	var key := "%s:%d" % [actor, id]
	if _radio_cool.get(key, 0) > now:
		return false
	_radio_cool[key] = now + int(cooldown * 1000.0)
	var item := {"actor": actor, "id": id, "text": text, "speaker": r.speaker, "prio": priority}
	if priority:
		# After earlier script lines (keeps their order), before chatter.
		var at := 0
		while at < _radio_queue.size() and _radio_queue[at].prio:
			at += 1
		_radio_queue.insert(at, item)
	else:
		if _radio_queue.size() >= 3:
			return false            # stale chatter is dropped, not delayed
		_radio_queue.append(item)
	return true


func _actor(n) -> String:
	if n == null or not is_instance_valid(n):
		return ""
	return String(n.get_meta("actor", "")) if n.has_meta("actor") else ""


## Real-time pump: one line at a time, voice when the original has one.
func _radio_pump() -> void:
	if _radio_queue.is_empty() or Time.get_ticks_msec() < _radio_free_ms:
		return
	var it: Dictionary = _radio_queue.pop_front()
	var dur: float = clampf(it.text.length() * 0.06, 2.0, 5.0)
	var voice: AudioStreamWAV = SCData.radio_voice(it.actor, it.id)
	Sfx.radio_blip()
	if voice != null and _radio_player != null:
		_radio_player.stream = voice
		_radio_player.play()
		dur = voice.get_length() + 0.5
	radio_log.append("%s: %s" % [it.speaker, it.text])
	if DisplayServer.get_name() == "headless":
		print("RADIO [%s #%d%s] %s: %s" % [it.actor, it.id, " voice %.1fs" % voice.get_length() if voice != null else "", it.speaker, it.text])
	if hud != null:
		hud.message("%s: %s" % [it.speaker, it.text], maxf(dur + 1.0, 3.5))
	_radio_free_ms = Time.get_ticks_msec() + int(dur * 1000.0)
	_radio_quiet_ms = Time.get_ticks_msec()


## Wingman = first live allied aircraft with a radio profile.
func _wingman_actor() -> String:
	for a in allies:
		if is_instance_valid(a) and a.alive and _actor(a) != "":
			return _actor(a)
	return ""


## The base / tower: the player-side part whose profile has the runway calls.
func _base_actor() -> String:
	if mission == null:
		return ""
	var start = mission.player_part()
	for p in mission.parts:
		if p.side == start.side and p.id != start.id and p.id < mission.cast.size():
			var r: Dictionary = SCData.radio(mission.cast[p.id])
			if r.msgs.has(29) and r.msgs.has(30):
				return mission.cast[p.id]
	return ""


## Enemy contact: the wingman calls the bandits (the player has no recordings).
func _contact_call(_n) -> void:
	var wing := _wingman_actor()
	if wing != "":
		radio_call(wing, 12, 40.0)
	else:
		radio_call(_actor(player), 12, 40.0)


func _on_aircraft_damaged(a, amount: float, cause) -> void:
	if amount <= 0.0 or not a.alive:
		return
	var who := _actor(a)
	if a == player:
		radio_call(_wingman_actor(), 16, 30.0)               # watch your six
	elif allies.has(a):
		if cause == player:
			radio_call(who, 14, 30.0)                         # friendly fire
		elif a.health < a.max_health * 0.35:
			radio_call(who, 6, 45.0)                          # requesting assistance
		else:
			radio_call(who, 7, 30.0)                          # I'm hit


func _on_ally_down(a) -> void:
	radio_call(_actor(a), 9, 600.0, true)                     # ejecting / going down


## Quiet-time traffic (replaces the invented chatter lines): the base asks
## how it's going, the wingman answers with its real condition; near home
## after the route the tower clears the landing.
func _radio_chatter() -> void:
	if player == null or not player.alive or mission == null:
		return
	var base := _base_actor()
	if not _radio_flags.has("landing") and nav_index >= waypoints.size() and home_runway != null \
			and player.global_position.distance_to(home_runway.global_position) < 12000.0:
		_radio_flags["landing"] = true
		radio_call(base, 30, 600.0, true)
		return
	if Time.get_ticks_msec() - _radio_quiet_ms < 60000:
		return
	var wing := _wingman_actor()
	if wing == "":
		return
	var w = null
	for a in allies:
		if _actor(a) == wing:
			w = a
	var k: int = clampi(int((1.0 - w.health / maxf(w.max_health, 1.0)) * 4.0), 0, 3)
	if radio_call(base, 28, 180.0):
		radio_call(wing, R_STATUS[k], 180.0)
	else:
		radio_call(wing, 28 if SCData.radio(wing).msgs.has(28) else R_STATUS[k], 180.0)


func _run_block(b: int, key := -1) -> void:
	if mission != null and b >= 0:
		MissionVM.run(mission.block(b), key, self)


func _activate(id: int) -> void:
	var i: int = mission.part_index(id)
	if i >= 0 and _scene_wait.has(i):    # a script may bring a scene ship in early
		_scene_wait.erase(i)
		_dormant[i] = true
	if i < 0 or not _dormant.has(i):
		return
	_dormant.erase(i)
	_activating = true
	var n = _spawn_part(i, _activation_spawn_position(i))
	_activating = false
	if debug_log:
		var pp: Dictionary = mission.parts[i]
		# Where the node actually entered the world (the PART position can be a
		# placeholder below the terrain, see _activation_spawn_position).
		var at: Vector3 = n.global_position if n != null else pp.pos
		var g: float = terrain.height_at(at.x, at.z) if terrain else 0.0
		print("ACTIVATE id=%d %s pos=%s agl=%.0f part_pos=%s node=%s" % [id, pp.model, at.round(), at.y - g, pp.pos.round(), n])
	if n != null:
		_link_formations()
		if n.get("velocity") != null and enemies.has(n):
			_contact_call(n)
		# An escorted aircraft joins the flight (MISN-1A: the C-130 at the
		# Rendezvous): play the join-up with the fighters sliding into formation.
		if _escort_ids.has(id) and n.get("velocity") != null and player.alive and not player.on_ground \
				and n.global_position.distance_to(player.global_position) < 20000.0:
			_start_joinup(n)


func _activation_spawn_position(i: int) -> Variant:
	var part: Dictionary = mission.parts[i]
	if not _is_aircraft("OBJECTS/%s.IFF" % part.model) or part.relative_alt:
		return null
	var part_ground: float = terrain.height_at(part.pos.x, part.pos.z) if terrain else 0.0
	if part.pos.y >= part_ground - 100.0:
		return null

	for sc in mission.scenes:
		if sc.area < 0 or sc.area >= mission.areas.size():
			continue
		var activates_part := false
		for block_id in sc.on_enter:
			if part.id in mission.block_args(block_id, 0x90):
				activates_part = true
				break
		if not activates_part:
			continue
		var pos: Vector3 = mission.areas[sc.area].pos
		var ground: float = terrain.height_at(pos.x, pos.z) if terrain else 0.0
		pos.y = maxf(pos.y, ground + 300.0)
		return pos
	return null


## One script tick: mission-wide blocks, the blocks of entered scenes and the
## AI block of every live part.
func _script_tick() -> void:
	for b in _global_blocks:
		_run_block(b, -100 - b)
	for k in mission.scenes.size():
		if _scene_entered[k]:
			for b in mission.scenes[k].on_enter:
				_run_block(b, -1000 - k)
	for i in _part_nodes.keys():
		var n = _part_nodes[i]
		var part: Dictionary = mission.parts[i]
		if n != player and is_instance_valid(n) and n.alive and part.slots[1] >= 0:
			_run_block(part.slots[1], part.id)


func _node_for(id: int):
	var i: int = mission.part_index(id)
	if i >= 0 and _part_nodes.has(i) and is_instance_valid(_part_nodes[i]):
		return _part_nodes[i]
	return null


# --- host interface for MissionVM ------------------------------------------
# The original interpreter (STRIKE.EXE, see docs/PROG_VM.md) keeps one
# mission-wide variable array: "flags" are variables holding 0 / 1.

var _vm_states := {}      # owner key -> {acc, e, cond}: persists between ticks
var _vm_regs := {}        # mission registers 0..7 (14 n), read by the engine
var _vm_globals := {}     # op -> last argument (0f, d0, c0, 94, 99 ... not decoded)
var _vm_list_flags := {}  # 80 / 81 / 82 n state bytes
var _vm_waits := {}       # owner key -> a0 timer start (sim seconds)

func vm_state(key: int) -> Dictionary:
	if not _vm_states.has(key):
		_vm_states[key] = {"acc": 0, "e": 0, "cond": 0}
	return _vm_states[key]


func vm_block(n: int) -> Array:
	return mission.block(n) if mission != null and n >= 0 and n < mission.blocks.size() else []


func vm_var(n: int) -> int:
	return vm_vars.get(n, 0)


func vm_set_var(n: int, v: int) -> void:
	vm_vars[n] = v


func vm_set_register(n: int, v: int) -> void:
	_vm_regs[n] = v


func vm_global(op: int, arg: int) -> void:
	_vm_globals[op] = arg
	# b6/b7, b8/b9: set / clear object bits 0x10 / 0x20 of part `arg`.
	if op in [0xb6, 0xb7, 0xb8, 0xb9]:
		var n = _node_for(arg)
		if n != null:
			var bit: int = 0x10 if op in [0xb6, 0xb7] else 0x20
			var bits: int = n.get_meta("sc_bits", 0)
			n.set_meta("sc_bits", (bits | bit) if op in [0xb6, 0xb8] else (bits & ~bit))


func vm_list_flag(n: int, on: bool) -> void:
	_vm_list_flags[n] = on


func vm_list_flag_get(n: int) -> bool:
	return _vm_list_flags.get(n, false)


func vm_alive(id: int) -> bool:
	# A scene ship not created yet is alive (it is waiting in its area): the
	# C-130's "all MiGs gone" check passed at once when they counted as dead.
	var i: int = mission.part_index(id)
	if i >= 0 and _scene_wait.has(i):
		return true
	var n = _node_for(id)
	return n != null and n.alive


## 92 alive / 93 destroyed / 98 present in the world (the original tests
## object bit 0 / bit 1 of its state byte and its world-entity pointer).
func vm_part_state(op: int, id: int) -> bool:
	var i: int = mission.part_index(id)
	if i < 0:
		return false
	var n = _node_for(id)
	match op:
		0x92:
			return vm_alive(id)
		0x93:
			return n != null and not n.alive and not n.get_meta("removed", false)
		0x98:
			return n != null and n.alive and not _scene_wait.has(i) and not _dormant.has(i)
	return false


## Script owner usable for actions / distances: alive and in the world.
func vm_owner_ready(key: int) -> bool:
	if key < 0:
		return false
	var n = _node_for(key)
	return n != null and n.alive


## 95 id: 3D distance owner -> part, 96 id: altitude of part, 97 n: 3D
## distance owner -> SPOT n. Original units: 1000 ft (positions are 24.8
## fixed-point feet; the engine divides the length by 1000 and shifts by 8),
## capped at 255. No owner (or no target) gives 0, like the original.
func vm_measure(key: int, op: int, arg: int) -> int:
	if op == 0x96:
		var t = _node_for(arg)
		if t == null:
			return 0
		return mini(int((t.global_position.y / FEET_M - 2250.0) / 100.0), 255)
	var owner = _node_for(key) if key >= 0 else null
	if owner == null:
		return 0
	var target: Vector3
	if op == 0x97:
		if arg < 0 or arg >= mission.spots.size():
			return 0
		target = mission.spots[arg]
	else:
		var i: int = mission.part_index(arg)
		if i < 0:
			return 0
		# A scene ship still waiting in its area is far away (not "here").
		if _scene_wait.has(i):
			return 255
		var t2 = _node_for(arg)
		if t2 == null:
			return 0
		target = t2.global_position
	return mini(int(owner.global_position.distance_to(target) / FEET_M / 1000.0), 255)


## a0 k: wait k seconds on the owner's timer (the original restarts the
## timer on the next a0 once it has run out).
func vm_wait(key: int, secs: int) -> bool:
	if not _vm_waits.has(key):
		_vm_waits[key] = _sim_time
		return secs <= 0
	if _sim_time - _vm_waits[key] >= secs:
		_vm_waits.erase(key)
		return true
	return false


func vm_activate(id: int) -> void:
	_activate(id)


## Removes a part without an explosion (e.g. a transport that has landed).
func vm_remove(id: int) -> void:
	var n = _node_for(id)
	if n == null or not n.alive or n == player:
		return
	n.alive = false
	n.visible = false
	n.set_physics_process(false)
	n.set_meta("removed", true)   # left the mission (landed), not lost: the debrief counts it home


func vm_message(key: int, n: int) -> void:
	if key >= 0 and key < mission.cast.size():
		var r: Dictionary = SCData.radio(mission.cast[key])
		if r.msgs.has(n):
			var text: String = r.msgs[n]
			# Script radio goes first in the queue, with the original voice.
			radio_call(mission.cast[key], n, 30.0, true)
			# The mission's own radio calls tell success or failure.
			if text.to_lower().begins_with("mission accomplished"):
				_script_success = true
				_check_mission()
			elif text.to_lower().begins_with("mission failed"):
				vm_end(false)
			return
	if n < mission.messages.size():
		_say("RADIO: %s" % mission.messages[n], 5.0)


func vm_end(success: bool) -> void:
	if mission_complete:
		return
	if success:
		mission_complete = true
		_say("MISSION COMPLETE", 10.0)
	else:
		_say("MISSION FAILED", 6.0)
		get_tree().create_timer(4.0).timeout.connect(func(): _end_mission("script_failed"))


## Starts an action for the owner unless it is already the current one.
## `extra` is the "09 x" argument that follows the instruction (not used yet).
## Decoded actions: a1 take off, a2 land at SPOT, a3/a4/a5/ac fly to SPOT,
## a7 attack, a8 escort, aa follow. a9, b1-b5 and bf are accepted but not
## decoded yet (they finish at once).
func vm_action(key: int, op: int, arg: int, extra := -1) -> void:
	var cur = _actions.get(key)
	if cur != null and cur.op == op and cur.arg == arg:
		return
	_actions[key] = {"op": op, "arg": arg, "extra": extra, "t0": _sim_time}
	if debug_log:
		print("VMACT key=%d op=%02x arg=%d extra=%d" % [key, op, arg, extra])
	var a = _node_for(key) if key >= 0 else null
	if a == null or a.get("velocity") == null:
		return
	if not op in [0xa1, 0xa2, 0xa3, 0xa4, 0xa5, 0xac, 0xa7, 0xa8, 0xaa]:
		return
	a.takeoff = false
	a.attack_ids = []
	a.route = []
	a.route_index = 0
	a.formation_leader = null
	a.land_at = null
	match op:
		0xa1:
			a.takeoff = a.on_ground
			var pi: int = mission.part_index(key)
			if pi >= 0 and mission.parts[pi].leader == mission.player_id:
				a.takeoff_after = player
		0xa2, 0xa3, 0xa4, 0xa5, 0xac:
			if arg < mission.spots.size():
				a.route = [mission.spots[arg]]
				if op == 0xa2:
					# A real approach: the original checks its script conditions
					# while the landing runs (MISN-1A's "We're safe").
					var sp: Vector3 = mission.spots[arg]
					a.land_at = Vector3(sp.x, terrain.height_at(sp.x, sp.z) if terrain else sp.y, sp.z)
		0xa7:
			a.attack_ids = [arg]
		0xa8, 0xaa:
			var lead = _node_for(arg)
			if lead != null and lead.get("velocity") != null and lead != a:
				a.formation_leader = lead


func vm_action_done(key: int) -> bool:
	var act = _actions.get(key)
	if act == null:
		return true
	var a = _node_for(key) if key >= 0 else null
	match act.op:
		0xa1:
			if a == null or a.get("velocity") == null:
				return true
			var g: float = terrain.height_at(a.global_position.x, a.global_position.z) if terrain else 0.0
			return not a.on_ground and a.global_position.y - g > 200.0
		0xa2, 0xa3, 0xa4, 0xa5, 0xac:
			if a == null or act.arg >= mission.spots.size():
				return true
			var sp: Vector3 = mission.spots[act.arg]
			var flat := Vector2(sp.x - a.global_position.x, sp.z - a.global_position.z).length()
			if act.op == 0xa2:
				# Landed: over the spot and down near the ground.
				var g2: float = terrain.height_at(a.global_position.x, a.global_position.z) if terrain else 0.0
				if flat < 1500.0 and a.global_position.y - g2 < 120.0:
					vm_remove(key)
					return true
				return false
			return flat < 1500.0
		0xa7:
			return not vm_alive(act.arg)
		0xa8, 0xaa:
			return not vm_alive(act.arg)
	return true


## Scene "on enter" blocks run when the player first comes within the area.
func _update_scenes() -> void:
	for k in mission.scenes.size():
		if _scene_entered[k]:
			continue
		var sc: Dictionary = mission.scenes[k]
		var inside: bool = sc.area < 0
		if not inside and sc.area < mission.areas.size():
			var a: Dictionary = mission.areas[sc.area]
			var reach: float = maxf(a.radius, 6000.0)
			# The player, or an escorted ally flying through on its own (MISN-1A:
			# the C-130 crosses the MiGs' restricted airspace on its way to the
			# cargo field - "protect the C-130 until you reach Cargo Destination").
			var who: Array = [player]
			for ally in allies:
				if ally.alive and _escort_ids.has(ally.get_meta("part_id", -1)):
					who.append(ally)
			for w in who:
				if Vector2(a.pos.x - w.global_position.x, a.pos.z - w.global_position.z).length() < reach:
					inside = true
					break
		if inside:
			_scene_entered[k] = true
			# The scene's own aircraft enter the world now.
			var spawned := 0
			for pi in _scene_wait.keys():
				if _scene_wait[pi] == k:
					_scene_wait.erase(pi)
					if _spawn_part(pi) != null:
						spawned += 1
			if spawned > 0:
				_link_formations()
			# Scene entry is a camera cutaway in the original; the radio calls
			# come from the scene's own script blocks (no debug "Scene n" text).
			if rig != null and not player.on_ground and sc.area >= 0:
				rig.start_flyby(4.0)


## Advances the player's route when a waypoint is reached. The original's
## "waypoint" was the scenario area - arrival radius is the area radius.
func _update_nav() -> void:
	# While the time warp is engaged, _update_fast_travel() owns route
	# progression; otherwise it would silently skip past the active waypoint
	# (its 6 km reach is larger than the warp's arrival check) and the plane
	# would fly the whole route without ever stopping.
	if fast_travel:
		return
	if waypoints.is_empty() or nav_index >= waypoints.size() or player.on_ground:
		return
	var wp: Dictionary = waypoints[nav_index]
	var reach := 6000.0
	if wp.has("radius"):
		reach = maxf(6000.0, float(wp.radius))
	if Vector2(wp.pos.x - player.global_position.x, wp.pos.z - player.global_position.z).length() < reach:
		nav_index += 1
		if nav_index < waypoints.size():
			_say("Waypoint %s" % waypoints[nav_index].name, 4.0)
			# Waypoint-to-waypoint fast travel (the original ran these legs with
			# the autopilot at accelerated time when the airspace was clear).
			if rig != null and not player.on_ground and not fast_travel:
				rig.start_flyby(4.0)   # cinematic cutaway as the route turns over
		_check_mission()


## Fast travel to the active waypoint (a standard flight-sim "time warp").
## The plane flies the route on autopilot while time accelerates smoothly to
## TRAVEL_MAX_SCALE. It engages only in clear airspace and drops out at once
## when a threat appears, on damage, on arrival at the waypoint, or when the
## player toggles it off (F7). Progress is shown as a FAST FORWARD HUD line.
func _toggle_fast_travel() -> void:
	if fast_travel:
		_stop_fast_travel("Fast travel off - you have control.")
		return
	if not player.alive or player.on_ground:
		_say("Fast travel: airborne only.", 2.0)
		return
	if waypoints.is_empty() or nav_index >= waypoints.size():
		_say("Fast travel: no active waypoint.", 2.0)
		return
	var nearest := _nearest_active_enemy()
	if nearest < TRAVEL_SAFE_M:
		_say("Cannot fast travel - enemies within %d km." % int(nearest / 1000.0), 2.5)
		return
	# Route-follow autopilot handles the flying; leave combat/landing modes.
	autopilot = false
	autopilot_land = false
	autopilot_waypoint = false
	fast_travel = true
	_say("Fast travel to %s - F7 to cancel." % waypoints[nav_index].name, 3.0)
	print("FASTTRAVEL engage wp=%d/%d dist=%.0f" % [nav_index + 1, waypoints.size(),
		Vector2(waypoints[nav_index].pos.x - player.global_position.x,
			waypoints[nav_index].pos.z - player.global_position.z).length()])
	if rig != null:
		rig.start_flyby(5.0)


## Called every physics frame. Smoothly ramps the time warp while travelling
## and stops travel on threats, damage or arrival.
func _update_fast_travel(dt: float) -> void:
	if not fast_travel:
		return
	if not player.alive or player.on_ground:
		_stop_fast_travel("Fast travel off.")
		return
	# Arrival: hand control back at the active waypoint and advance the route.
	# The warp stops AT the waypoint (using its radius, ~1 km default), not 6 km
	# before it like _update_nav()'s safety-net reach does.
	if nav_index >= waypoints.size():
		_stop_fast_travel("Route complete.")
		return
	var reach := float(waypoints[nav_index].get("radius", 1000.0))
	if reach <= 0.0:
		reach = 1000.0
	var wp: Vector3 = waypoints[nav_index].pos
	var d2wp: float = Vector2(wp.x - player.global_position.x, wp.z - player.global_position.z).length()
	if d2wp <= reach:
		var reached: String = waypoints[nav_index].name
		nav_index += 1
		_check_mission()
		if nav_index < waypoints.size():
			_stop_fast_travel("Waypoint %s reached. Next: %s." % [reached, waypoints[nav_index].name])
		else:
			_stop_fast_travel("Route complete - %s." % reached)
		return
	# A threat or damage cancels the warp immediately (as in most flight sims).
	var nearest := _nearest_active_enemy()
	if nearest < TRAVEL_SAFE_M:
		_stop_fast_travel("Contact! Fast travel off.")
		return
	if player.health < 95.0:
		_stop_fast_travel("Damage - fast travel off.")
		return
	# Ramp the time warp up smoothly (never touch the base scale in test runs
	# that already run accelerated, e.g. --fast).
	if _travel_base <= 1.05:
		_travel_scale = move_toward(_travel_scale, TRAVEL_MAX_SCALE, dt * 6.0)
		Engine.time_scale = _travel_scale


func _stop_fast_travel(msg: String) -> void:
	fast_travel = false
	_travel_scale = 1.0
	if _travel_base <= 1.05:
		Engine.time_scale = 1.0
	if rig != null and not player.on_ground:
		rig.start_flyby(3.0)
	_say(msg, 2.5)
	print("FASTTRAVEL stop: %s (scale=%.1f)" % [msg, Engine.time_scale])


## Nearest live, non-standby (i.e. actively engaging) enemy distance, or a huge
## value when the airspace is clear.
func _nearest_active_enemy() -> float:
	var nearest := 1e12
	for e in enemies:
		if e != null and e.alive and not e.get("standby"):
			nearest = minf(nearest, e.global_position.distance_to(player.global_position))
	return nearest


## Ground weapons (FORM SWPN) become AA guns or SAM launchers. In free flight
## everything beyond SAFE_RADIUS of the player start is hostile.
func _setup_air_defences() -> void:
	var start: Vector3 = _player_start.pos
	for o in ground_objects:
		var m = SCData.model("OBJECTS/%s.IFF" % o.display_name)
		if m == null:
			continue
		var w: Dictionary = Weapons.ground_weapon(m)
		if w.is_empty():
			continue
		o.weapon = w
		o.ammo = w.ammo
		o.cooldown = randf_range(1.0, 4.0)
		if mission == null or not o.has_meta("from_mission"):
			o.hostile = (o.team != 1) or Vector2(o.global_position.x - start.x, o.global_position.z - start.z).length() > SAFE_RADIUS
		aa_sites.append(o)


func _is_aircraft(model_name: String) -> bool:
	var m = SCData.model(model_name)
	return m != null and m.object_chunk(["FORM:JETP"]) != null


func _add_ground_object(model: String, wreck: String, pos: Vector3, heading: float, pal: PackedColorArray, smooth: bool):
	var entry = _cached_mesh(model, pal, smooth)
	if entry == null:
		return null
	var wreck_entry = _cached_mesh(wreck, pal, smooth) if wreck != "" else null
	var obj = GroundObject.new()
	obj.setup(entry.mesh, entry.aabb, wreck_entry.mesh if wreck_entry else null, model)
	var m = SCData.model("OBJECTS/%s.IFF" % model)
	if m != null and Weapons.strength(m) > 0.0:
		obj.health = maxf(10.0, Weapons.strength(m))
	elif obj.blast_only:
		obj.health = 8.0     # RNWY / DAMG in the original runway objects
	add_child(obj)
	obj.global_position = pos
	obj.rotation.y = heading
	obj.destroyed.connect(_on_ground_destroyed)
	if mission != null and _player_start.has("pos"):
		obj.set_meta("from_mission", true)
	ground_objects.append(obj)
	return obj


func _cached_mesh(model: String, pal: PackedColorArray, smooth: bool):
	if not _mesh_cache.has(model):
		var m = SCData.model("OBJECTS/%s.IFF" % model)
		if m != null:
			_mesh_cache[model] = {"mesh": m.build_mesh(pal, 0, smooth), "aabb": m.aabb()}
		else:
			_mesh_cache[model] = _runway_mesh(model)
	return _mesh_cache[model]


## Runways have no polygons in the original data, only extents.
func _runway_mesh(model: String):
	var ext: Dictionary = RealSpaceModel.extents(SCData.read("OBJECTS/%s.IFF" % model))
	if ext.is_empty() or not ext.runway:
		return null
	var size: Vector3 = ext.max - ext.min
	var along_x := size.x > size.z
	var plane := PlaneMesh.new()
	plane.size = Vector2(size.z, size.x) if along_x else Vector2(size.x, size.z)
	var mat := ShaderMaterial.new()
	mat.shader = preload("res://shaders/runway.gdshader")
	mat.set_shader_parameter("length_m", maxf(size.x, size.z))
	mat.set_shader_parameter("width_m", minf(size.x, size.z))
	plane.material = mat
	var mesh := ArrayMesh.new()
	var arrays := plane.get_mesh_arrays()
	if along_x:
		# Rotate the plane 90 degrees so its long axis follows x.
		var verts: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
		for i in verts.size():
			verts[i] = Vector3(verts[i].z, verts[i].y, -verts[i].x)
		arrays[Mesh.ARRAY_VERTEX] = verts
	var center: Vector3 = (ext.max + ext.min) * 0.5
	var verts2: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
	for i in verts2.size():
		verts2[i] += Vector3(center.x, 0.0, center.z)
	arrays[Mesh.ARRAY_VERTEX] = verts2
	mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
	mesh.surface_set_material(0, mat)
	return {"mesh": mesh, "aabb": AABB(Vector3(ext.min.x, 0.0, ext.min.z), Vector3(size.x, 0.01, size.z))}


func _place_player() -> void:
	if bomb_run and _setup_bomb_run():
		return
	if mission != null and spawn_area >= 0 and spawn_area < mission.areas.size():
		var a: Vector3 = mission.areas[spawn_area].pos
		var g: float = terrain.height_at(a.x, a.z + 2500.0) if terrain else 0.0
		player.respawn(Vector3(a.x, g + 450.0, a.z + 2500.0), 0.0, 180.0)
		_rearm_player()
		return
	var pos: Vector3 = _player_start.pos
	if _player_start.air:
		player.respawn(pos, _player_start.heading)
		_rearm_player()
		return
	var g: float = terrain.height_at(pos.x, pos.z) if terrain else 0.0
	player.respawn(Vector3(pos.x, g + 2.2, pos.z), _player_start.heading, 0.0)
	player.on_ground = true
	player.throttle = 0.0
	_rearm_player()


## Testing: put the player where a MK-82 released now lands on the nearest
## ground target, select bombs and release a pair on the next frame.
func _setup_bomb_run() -> bool:
	var tgt = null
	for t in targets:
		if t.has_method("center") and t.hittable:
			tgt = t
			break
	if tgt == null:
		return false
	_rearm_player()
	var alt: float = tgt.global_position.y + 600.0
	var vel := Vector3(0, 0, -220.0)
	var start: Vector3 = tgt.global_position
	for i in range(4):   # refine the release point against the real terrain
		var impact = Bomb.predict_impact(Vector3(start.x, alt, start.z), vel, spec("MK82").drag, terrain)
		if impact == null:
			break
		start += Vector3(tgt.global_position.x - impact.x, 0.0, tgt.global_position.z - impact.z)
	player.respawn(Vector3(start.x, alt, start.z), 0.0, 220.0)
	weapon_mode = "bomb"
	get_tree().create_timer(0.05).timeout.connect(func():
		_player_bomb()
		get_tree().create_timer(0.3).timeout.connect(_player_bomb))
	print("BOMBRUN target=%s at %s" % [tgt.display_name, tgt.global_position])
	return true


func _rearm_player() -> void:
	var m = SCData.model(player.model_name)
	if m != null:
		player.missiles = Weapons.loadout(m)
		_loadout = player.missiles.duplicate()


func _place(a, flat_pos: Vector3, heading: float) -> void:
	var ground: float = terrain.height_at(flat_pos.x, flat_pos.z) if terrain else 0.0
	a.respawn(Vector3(flat_pos.x, ground + 1500.0, flat_pos.z), heading)


func _build_environment() -> void:
	# Modern sky: altitude-graded colours, sun disc and glow from the sun light.
	var sky_mat := ShaderMaterial.new()
	sky_mat.shader = preload("res://shaders/sky.gdshader")
	var sky := Sky.new()
	sky.sky_material = sky_mat
	_env = Environment.new()
	_env.background_mode = Environment.BG_SKY
	_env.sky = sky
	_env.ambient_light_source = Environment.AMBIENT_SOURCE_SKY
	_env.ambient_light_energy = 0.45
	_env.tonemap_mode = Environment.TONE_MAPPER_ACES
	_env.tonemap_exposure = 0.95
	_env.glow_enabled = true
	_env.glow_intensity = 0.6
	_env.glow_bloom = 0.05
	# Increased fog density to hide terrain edges at map boundary (~110km).
	# Original value 0.000012 gave only ~70% fog at map edge.
	# New value 0.000025 gives ~94% fog at 110km, ~99.9% at outer ground (600km).
	_env.fog_light_color = Color(0.68, 0.74, 0.82)
	_env.fog_density = 0.000025
	_env.fog_aerial_perspective = 0.4
	_env.fog_sky_affect = 0.2
	var we := WorldEnvironment.new()
	we.environment = _env
	add_child(we)

	_sun = DirectionalLight3D.new()
	_sun.rotation = Vector3(deg_to_rad(-38.0), deg_to_rad(-35.0), 0.0)
	_sun.light_energy = 1.45
	_sun.light_color = Color(1.0, 0.96, 0.9)
	_sun.directional_shadow_mode = DirectionalLight3D.SHADOW_PARALLEL_4_SPLITS
	_sun.directional_shadow_max_distance = 3000.0
	_sun.shadow_bias = 0.05
	add_child(_sun)
	_add_clouds()


## Two drifting translucent cloud layers add depth and hide the flat horizon.
func _add_clouds() -> void:
	var noise := FastNoiseLite.new()
	noise.frequency = 0.004
	noise.fractal_octaves = 4
	var tex := NoiseTexture2D.new()
	tex.noise = noise
	tex.seamless = true
	tex.width = 512
	tex.height = 512
	for cfg in [[3600.0, 0.5, 0.00006], [4600.0, 0.35, 0.00004]]:
		var plane := PlaneMesh.new()
		plane.size = Vector2(130000, 130000)
		var m := ShaderMaterial.new()
		m.shader = preload("res://shaders/clouds.gdshader")
		m.set_shader_parameter("noise_tex", tex)
		m.set_shader_parameter("alpha", cfg[1])
		m.set_shader_parameter("scale", cfg[2])
		plane.material = m
		var mi := MeshInstance3D.new()
		mi.mesh = plane
		mi.position.y = cfg[0]
		mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		add_child(mi)


## Large skirt around the map so the horizon is not an empty edge.
func _add_outer_ground(type_cols: PackedColorArray, mat: Material) -> void:
	var info: Dictionary = terrain.border_info()
	var c: Color = type_cols[info.type].srgb_to_linear() if info.type < type_cols.size() else Color.GRAY
	c.a = 1.0 if info.type == 0 else 0.0
	var half := 600000.0
	var inner: float = terrain.world_size() * 0.5 - 1.0
	# Place outer ground slightly below the average border height so it blends
	# with the terrain edge and fog hides the transition.
	var y: float = info.height - 50.0
	var verts := PackedVector3Array()
	# Four slabs around the map, leaving the playable square open.
	for r in [Rect2(-half, -half, 2 * half, half - inner), Rect2(-half, inner, 2 * half, half - inner),
			Rect2(-half, -inner, half - inner, 2 * inner), Rect2(inner, -inner, half - inner, 2 * inner)]:
		var a := Vector3(r.position.x, y, r.position.y)
		var b := Vector3(r.end.x, y, r.position.y)
		var d: Vector3 = Vector3(r.end.x, y, r.end.y)
		var e := Vector3(r.position.x, y, r.end.y)
		verts.append_array([a, b, d, a, d, e])
	var arrays := []
	arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX] = verts
	var normals := PackedVector3Array()
	var cols := PackedColorArray()
	var uv2 := PackedVector2Array()
	for v in verts:
		normals.append(Vector3.UP)
		cols.append(c)
		# Use tile 255 (no tile) so the shader uses only the base color + fog
		uv2.append(Vector2(255, 0))
	arrays[Mesh.ARRAY_NORMAL] = normals
	arrays[Mesh.ARRAY_COLOR] = cols
	arrays[Mesh.ARRAY_TEX_UV] = uv2
	arrays[Mesh.ARRAY_TEX_UV2] = uv2
	var mesh := ArrayMesh.new()
	mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
	mesh.surface_set_material(0, mat)
	var mi := MeshInstance3D.new()
	mi.mesh = mesh
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(mi)


func _terrain_material(pal: PackedColorArray, smooth: bool) -> Material:
	var mat := ShaderMaterial.new()
	mat.shader = preload("res://shaders/terrain.gdshader")
	var tiles: Texture2DArray = terrain.tile_array(SCData.read("TXM/TXMPACK.PAK"), pal)
	mat.set_shader_parameter("tiles", tiles)
	mat.set_shader_parameter("tiles_nearest", tiles)
	mat.set_shader_parameter("pixel_tiles", not smooth)
	# Modern touch: procedural detail breaks up the large flat-coloured cells.
	var noise := FastNoiseLite.new()
	noise.frequency = 0.02
	noise.fractal_octaves = 5
	var tex := NoiseTexture2D.new()
	tex.noise = noise
	tex.seamless = true
	tex.width = 512
	tex.height = 512
	tex.generate_mipmaps = true
	mat.set_shader_parameter("detail", tex)
	return mat


func _apply_settings() -> void:
	_sun.shadow_enabled = Settings.get_value("video", "shadows")
	_env.fog_enabled = Settings.get_value("video", "fog")
	_env.ssao_enabled = Settings.get_value("video", "ssao")
	if rig:
		rig.fov = Settings.get_value("video", "fov")


func _set_paused(p: bool) -> void:
	get_tree().paused = p
	_pause.visible = p
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE


func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed("pause"):
		_set_paused(not get_tree().paused)
		get_viewport().set_input_as_handled()
	elif event.is_action_pressed("camera_cycle"):
		rig.cycle()
	elif event.is_action_pressed("missile") and player.alive:
		_player_release()
	elif event.is_action_pressed("weapon_select"):
		_cycle_weapon_mode()
	elif event.is_action_pressed("countermeasure") and player.alive:
		_drop_countermeasure(player)


## Bullet impacts, rate limited so a burst is not a wall of noise.
func _hit_sound(pos: Vector3) -> void:
	if _hit_sound_cd <= 0.0:
		_hit_sound_cd = 0.12
		Sfx.play_at("hit", pos, -4.0)


func _setup_cockpit_audio() -> void:
	for n in ["engine", "afterburner", "gun"]:
		var p := AudioStreamPlayer.new()
		p.stream = Sfx.gun_for(SCData.model(player.model_name)) if n == "gun" else Sfx.stream(n)
		p.volume_db = -80.0
		add_child(p)
		if p.stream != null:
			p.play()
		_snd[n] = p
	for n in ["warning", "lock"]:
		var p := AudioStreamPlayer.new()
		p.stream = Sfx.tone(n)
		p.volume_db = -14.0
		add_child(p)
		_snd[n] = p


## Engine pitch follows throttle and speed; tones follow lock and threats.
func _update_cockpit_audio(dt: float) -> void:
	_hit_sound_cd -= dt
	if _snd.is_empty():
		return
	var alive: bool = player.alive
	var thr: float = player.throttle if alive else 0.0
	_snd.engine.pitch_scale = 0.75 + thr * 0.45 + clampf(player.speed() / 600.0, 0.0, 0.3)
	_snd.engine.volume_db = lerpf(-14.0, -3.0, thr) if alive else -80.0
	_snd.afterburner.volume_db = -2.0 if alive and player.afterburner else -80.0
	_snd.gun.volume_db = 0.0 if alive and _player_firing and not player.on_ground else -80.0
	var threats := 0
	for m in missiles_in_flight:
		if m.alive and m.target == player:
			threats += 1
	_set_tone("warning", alive and threats > 0)
	_set_tone("lock", alive and (player_lock != null or ground_lock != null))


func _set_tone(n: String, on: bool) -> void:
	var p: AudioStreamPlayer = _snd[n]
	if on and not p.playing:
		p.play()
	elif not on and p.playing:
		p.stop()


## Join-up cinematic: the escort `lead` has just appeared; the player and the
## fighter wingmen slide into formation slots behind it (player right, wingman
## left) while the camera sweeps along the transport. The planes ride on the
## scripted pose (their physics paused) and leave with the lead's speed and
## heading. Real time, like the flyby; a camera cycle ends the shot early.
const JOINUP_LEN := 7.0
const JOINUP_SLOTS := [Vector3(65.0, 10.0, 85.0), Vector3(-65.0, 10.0, 85.0), Vector3(-120.0, 18.0, 150.0)]
var _joinup := {}   # {lead, t, planes: [{node, slot, from: Transform3D}]}

func _start_joinup(lead) -> void:
	var planes := [player]
	for a in allies:
		if a != lead and a.alive and not a.on_ground and not _is_transport(a) \
				and a.global_position.distance_to(lead.global_position) < 25000.0:
			planes.append(a)
	var list := []
	var lb: Basis = lead.global_transform.basis.orthonormalized()
	for i in mini(planes.size(), JOINUP_SLOTS.size()):
		var p = planes[i]
		var slot: Vector3 = JOINUP_SLOTS[i]
		var from: Transform3D = p.global_transform
		var slot_world: Vector3 = lead.global_transform.origin + lb * slot
		if from.origin.distance_to(slot_world) > 700.0:
			# Too far to slide in on camera: start just out of the shot, behind
			# and wide of the slot (the original cut between views the same way).
			from = Transform3D(lb, lead.global_transform.origin + lb * (slot + Vector3(signf(slot.x) * 260.0, 40.0, 420.0)))
		p.set_physics_process(false)
		# Kept in the lead's own frame: the slide follows the transport through
		# its turns (a world-space start drifted away while it banked).
		var lead_tf: Transform3D = Transform3D(lb, lead.global_transform.origin)
		list.append({"node": p, "slot": slot, "rel": lead_tf.affine_inverse() * from})
	_joinup = {"lead": lead, "t": 0.0, "planes": list}
	if rig != null:
		rig.start_cinematic(lead, JOINUP_LEN)
	if hud != null:
		hud.visible = false
	_say("Joining up with the %s." % lead.display_name, 4.0)
	print("JOINUP %s: %d aircraft into formation" % [lead.display_name, list.size()])


func _update_joinup(dt: float) -> void:
	var lead = _joinup.lead
	_joinup.t += dt / maxf(Engine.time_scale, 0.001)
	var done: bool = _joinup.t >= JOINUP_LEN or lead == null or not is_instance_valid(lead) or not lead.alive \
			or (rig != null and not rig.cinematic_active() and _joinup.t > 0.2)
	var k: float = smoothstep(0.0, 1.0, clampf(_joinup.t / (JOINUP_LEN * 0.85), 0.0, 1.0))
	for e in _joinup.planes:
		var p = e.node
		if not is_instance_valid(p) or not p.alive:
			continue
		if lead != null and is_instance_valid(lead) and lead.alive:
			var lb: Basis = lead.global_transform.basis.orthonormalized()
			var lead_tf := Transform3D(lb, lead.global_transform.origin)
			# Slide from the start pose to the slot in the lead's own frame.
			var rel: Transform3D = e.rel.interpolate_with(Transform3D(Basis(), e.slot), k)
			p.global_transform = lead_tf * rel
			if debug_log and Engine.get_physics_frames() % 30 == 0:
				print("JOINUP t=%.1f k=%.2f %s rel=%s" % [_joinup.t, k, p.display_name, (lead_tf.affine_inverse() * p.global_transform.origin).round()])
			p.velocity = lead.velocity
			p.on_ground = false
		if done:
			p.set_physics_process(true)
			if p == player:
				player.throttle = clampf(player.throttle, 0.5, 0.9)
	if done:
		_joinup = {}
		if hud != null:
			hud.visible = true


func _physics_process(dt: float) -> void:
	_sim_time += dt
	if auto_land_test and _land_anim.is_empty() and player != null and player.alive and not player.on_ground:
		auto_land_test = false
		start_auto_land()
	if not _land_anim.is_empty():
		_update_auto_land(dt)
	if not _joinup.is_empty():
		_update_joinup(dt)
	_update_cockpit_audio(dt)
	_player_input(dt)
	_update_fast_travel(dt)
	if mission != null and not mission_over and player.alive:
		var agl: float = player.global_position.y - (terrain.height_at(player.global_position.x, player.global_position.z) if terrain else 0.0)
		if not player.on_ground and agl > 100.0:
			_was_airborne = true
		elif player.on_ground and _was_airborne and player.speed() < 15.0:
			_end_mission("landed")
	if mission != null:
		_scene_timer -= dt
		if _scene_timer <= 0.0:
			_scene_timer = 0.5
			_update_scenes()
			_update_nav()
			_script_tick()
		# Radio traffic: the cockpit is never silent - wingmen call their
		# moves, the tower nags about the approach, New Job timing etc.
		_chat_timer -= dt
		if _chat_timer <= 0.0:
			_chat_timer = randf_range(22.0, 45.0)
			_radio_chatter()
		# Tower clears the take-off once the player is on the runway.
		if not _radio_flags.has("takeoff") and player.on_ground and player.alive:
			_radio_flags["takeoff"] = true
			radio_call(_base_actor(), 29, 600.0, true)
		_radio_pump()
	if kill_enemies:
		# Cheat for route / landing tests: credited to the player so the
		# mission script and the debrief see ordinary kills.
		for t in targets:
			if is_instance_valid(t) and t.alive and t.has_method("damage"):
				t.damage(t.health + 1.0, player)
	_update_lock()
	_enemy_ai()
	_air_defences(dt)
	_update_missiles(dt)
	_update_bombs(dt)
	_release_cooldown -= dt
	if endless_ammo:
		# Testing: the original loadout is refilled every tick, harhautteet also.
		player.countermeasures = 30
		for name in _loadout:
			if player.missiles.get(name, 0) < _loadout[name]:
				player.missiles[name] = _loadout[name]
	_update_bullets(dt)
	if debug_log:
		_log_timer += dt
		if _log_timer >= 1.0:
			_log_timer = 0.0
			var g: float = terrain.height_at(player.global_position.x, player.global_position.z) if terrain else 0.0
			var nearest := 1e9
			var info := ""
			for e in enemies:
				if e.alive and e.global_position.distance_to(player.global_position) < nearest:
					nearest = e.global_position.distance_to(player.global_position)
					var to: Vector3 = player.global_position - e.global_position
					var loc: Vector3 = e.global_transform.basis.transposed() * to.normalized()
					info = "ang=%.0f loc=(%.2f,%.2f,%.2f) ctrl=%s bank=%.0f spd=%.0f cd=%.0f msl=%s" % [
						rad_to_deg((-e.global_transform.basis.z).angle_to(to.normalized())), loc.x, loc.y, loc.z,
						e.controls, rad_to_deg(-e.global_transform.basis.get_euler().z), e.speed(), e.missile_cooldown, e.missiles]
			if mission != null:
				var wing := ""
				for a in allies:
					var ga: float = terrain.height_at(a.global_position.x, a.global_position.z)
					var err := -1.0
					if a.formation_leader != null and is_instance_valid(a.formation_leader):
						err = a.global_position.distance_to(a.formation_leader.global_transform * a.formation_offset)
					var land_d: float = -1.0
					if a.get("land_at") is Vector3:
						land_d = Vector2(a.land_at.x - a.global_position.x, a.land_at.z - a.global_position.z).length()
					wing += " %s spd=%.0f agl=%.0f ground=%s takeoff=%s lead=%s slot_err=%.0f route=%d land_d=%.0f atk=%s" % [a.display_name, a.speed(), a.global_position.y - ga,
						a.on_ground, a.takeoff, a.formation_leader != null, err, a.route.size(), land_d, a.attack_point != null]
				wing += " vars=%s" % vm_vars
				print("LOG nav=%d/%d dormant=%d scenes=%s flags=%s enemies=%d%s" % [nav_index, waypoints.size(), _dormant.size(),
					_scene_entered, vm_vars.keys().filter(func(k): return vm_vars[k] == 1), enemies.size(), wing])
			if not _snd.is_empty():
				print("LOG audio engine=%s pitch=%.2f vol=%.0fdB ab=%.0fdB warning=%s lock=%s 3d_players=%d" % [_snd.engine.playing,
					_snd.engine.pitch_scale, _snd.engine.volume_db, _snd.afterburner.volume_db, _snd.warning.playing,
					_snd.lock.playing, get_tree().root.find_children("*", "AudioStreamPlayer3D", true, false).size()])
			print("LOG mode=%s glock=%s targets=%d bombs=%d stores=%s %s" % [weapon_mode, ground_lock.display_name if ground_lock else "-",
				targets_left(), bombs_in_flight.size(), player.missiles, _ap_debug + " ".join(bombs_in_flight.map(func(b): return "b%s v%s" % [b.global_position.round(), b.velocity.round()]))])
			print("LOG agl=%.0f spd=%.0f hp=%.0f alive=%s enemies_alive=%d nearest=%.0f missiles=%d bullets=%d" % [
				player.global_position.y - g, player.speed(), player.health, player.alive,
				enemies.filter(func(e): return e.alive).size(), nearest, missiles_in_flight.size(), _bullets.size()], info)
	if _respawn_timer > 0.0:
		_respawn_timer -= dt
		if _respawn_timer <= 0.0:
			_place_player()
			_say("New aircraft ready.", 3.0)


func _player_input(dt: float) -> void:
	if not player.alive:
		return
	if Input.is_action_just_pressed("auto_land"):
		start_auto_land()
	if not _land_anim.is_empty():
		return    # the auto-landing flies the aircraft

	# Autopilot toggles (F5 = waypoint, F6 = land, F7 = navpoint jump). F1-F4
	# are left free for the original discrete camera views.
	if Input.is_action_just_pressed("autopilot_waypoint"):
		autopilot_waypoint = not autopilot_waypoint
		autopilot_land = false  # mutually exclusive
		_say("Autopilot waypoint %s" % ("ON" if autopilot_waypoint else "OFF"), 2.0)
	if Input.is_action_just_pressed("autopilot_land"):
		autopilot_land = not autopilot_land
		autopilot_waypoint = false  # mutually exclusive
		_say("Autopilot land %s" % ("ON" if autopilot_land else "OFF"), 2.0)
		if autopilot_land:
			# If the base is far away or the geometry is bad, fast-forward:
			# teleport onto a clean 8 km final like the original's approach
			# fast-forward, with a camera cut and a radio note.
			var d_home: float = home_runway.global_position.distance_to(player.global_position) if home_runway != null else 0.0
			if d_home > 25000.0:
				_setup_approach()
				_say("Fast-forwarded onto the approach.", 4.0)
				if rig != null:
					rig.start_flyby(4.0)
	if Input.is_action_just_pressed("next_waypoint"):
		_toggle_fast_travel()
	# Headless test: --fasttravel engages once the plane is clearly airborne.
	if not fast_travel and not _ft_auto \
			and (OS.get_cmdline_args().has("--fasttravel") or OS.get_cmdline_user_args().has("--fasttravel")) \
			and not player.on_ground and player.speed() > 60.0 \
			and player.global_position.y - (terrain.height_at(player.global_position.x, player.global_position.z) if terrain else 0.0) > 120.0:
		_ft_auto = true
		_toggle_fast_travel()

	# F8: hand the aircraft to the AI pilot (it flies, dogfights, shoots guns and
	# launches missiles, then hands over to the landing autopilot). Toggling it
	# off returns control to the player.
	if Input.is_action_just_pressed("autopilot_combat"):
		autopilot = not autopilot
		if autopilot:
			autopilot_waypoint = false
			autopilot_land = false
		_say("AI pilot %s" % ("ON - the computer flies and fights" if autopilot else "OFF - you have the controls"), 2.5)

	# Combat autopilot (original --autopilot flag)
	if autopilot:
		
		if player.on_ground:
			player.throttle = 1.0
			player.afterburner = true
			player.brakes = false
			# Apply pitch up for rotation once we have some speed
			var pitch_input := 0.5 if player.speed() > 50.0 else 0.0
			player.controls = Vector3(pitch_input, 0.0, 0.0)
			return
		_autopilot()
		return

	# Waypoint autopilot: follow mission route
	if autopilot_waypoint:
		_autopilot_waypoint()
		return

	# Fast travel: the same route-follow autopilot, with the time warp applied
	# by _update_fast_travel(). Control returns automatically on arrival.
	if fast_travel:
		_autopilot_waypoint()
		return

	# Landing autopilot: approach and land at home runway
	if autopilot_land:
		_autopilot_land()
		return

	var invert := -1.0 if Settings.get_value("controls", "invert_pitch") else 1.0
	player.controls = Vector3(
		Input.get_axis("pitch_down", "pitch_up") * invert,
		Input.get_axis("roll_left", "roll_right"),
		Input.get_axis("yaw_left", "yaw_right"))
	var dthr := Input.get_action_strength("throttle_up") - Input.get_action_strength("throttle_down")
	player.throttle = clampf(player.throttle + dthr * 0.6 * dt, 0.0, 1.0)
	player.afterburner = Input.is_action_pressed("afterburner") or player.throttle >= 0.999 and Input.is_action_pressed("throttle_up")
	player.brakes = Input.is_action_pressed("brakes")
	_player_firing = Input.is_action_pressed("fire")
	if Input.is_action_pressed("fire") and player.can_fire():
		player.consume_round(0.05)
		_fire(player)


## Terrain pull-up: true when the plane must climb at once - the ballistic
## path in the next ~2 seconds comes closer to the terrain than the pull
## radius allows (a hard turn at high speed cannot recover that).
func _terrain_pullup_needed() -> bool:
	if terrain == null:
		return false
	var v: Vector3 = player.velocity
	if v.length() < 30.0:
		return false
	for t in [0.6, 1.2, 1.8]:
		var pos: Vector3 = player.global_position + v * t + Vector3.DOWN * (4.9 * t * t)
		var g: float = terrain.height_at(pos.x, pos.z)
		if pos.y - g < maxf(250.0, v.length() * 0.4):
			return true
	# Dive recovery: the 1.8 s look-ahead is far too short for a steep, fast
	# dive (418 m/s at -41 deg needs ~700 m to level out, plus G onset time).
	# Height lost in a pull-out on a ~6 G usable circle: r * (1 - cos(dive))
	# plus 1.5 s of sink while the plane rolls upright and the G builds.
	var spd: float = v.length()
	if v.y < 0.0:
		var dive: float = asin(clampf(-v.y / spd, 0.0, 1.0))
		var r: float = spd * spd / (9.81 * 6.0)
		var need: float = r * (1.0 - cos(dive)) - v.y * 1.5 + 300.0
		var p: Vector3 = player.global_position
		var ahead: Vector3 = p + Vector3(v.x, 0.0, v.z) * 2.0
		var ground: float = maxf(terrain.height_at(p.x, p.z), terrain.height_at(ahead.x, ahead.z))
		if p.y - ground < need:
			return true
	return false


## Terrain pull-up: steer at a point 45 deg up along the current horizontal
## track (relative to the plane - steer_towards takes a world position).
func _terrain_pullup() -> void:
	var fwd: Vector3 = -player.global_transform.basis.z
	var out := Vector3(fwd.x, 0.0, fwd.z)
	if out.length() < 0.05:   # nose straight down/up: use the velocity's track
		out = Vector3(player.velocity.x, 0.0, player.velocity.z)
	if out.length() < 0.05:
		out = Vector3.FORWARD
	player.steer_towards(player.global_position + out.normalized() * 9000.0 + Vector3.UP * 9000.0, 1.0, 250.0)
	player.throttle = 1.0
	player.afterburner = player.speed() < 240.0
	player.brakes = false


func _autopilot() -> void:
	# Route complete and no hostiles (or the script called the mission done):
	# hand over to the landing autopilot - the original lands at the base.
	# Checked FIRST: once the goal is met the autopilot must not drift into
	# the ground-attack loop (it never hands over from there).
	var remaining := 0
	for e in enemies:
		if is_instance_valid(e) and e.alive:
			remaining += 1
	# nav_index is a waypoint INDEX: size()-1 is the last stop (the handover
	# fired too late before - the main print shows mini(nav_index+1, size)).
	if waypoints.size() > 0 and nav_index >= waypoints.size() - 1 and (remaining == 0 or _script_success):
		autopilot = false
		autopilot_land = true
		_say("Combat done - autopilot: landing.", 4.0)
		_autopilot_land()
		return
	# Target choice: nearest enemy, but a bandit whose script orders it at an
	# escorted ally (MISN-1A: MiG id 5 hunts the C-130) counts as 15 km
	# closer - losing the escort fails the mission, losing a dogfight does not.
	var best = null
	var best_score := 1e12
	for e in enemies:
		if not e.alive:
			continue
		var score: float = e.global_position.distance_to(player.global_position)
		if _threatens_escort(e):
			score -= 15000.0
		if score < best_score:
			best_score = score
			best = e
	if best == null:
		# Nothing in the air: ground targets if any, otherwise fly the route
		# (scene ships only appear when the route reaches their area).
		var ground_left: bool = false
		for t in targets:
			if is_instance_valid(t) and t.alive and t.has_method("center"):
				ground_left = true
				break
		if ground_left:
			_autopilot_ground()
		elif nav_index < waypoints.size():
			if _terrain_pullup_needed():
				_terrain_pullup()
			else:
				_autopilot_waypoint()
		else:
			autopilot = false
			autopilot_land = true
		return
	var to: Vector3 = best.global_position - player.global_position
	var dist: float = to.length()
	var nose: Vector3 = -player.global_transform.basis.z
	var ang: float = nose.angle_to(to.normalized())
	# Terrain pull-up overrides everything: survived missions need the plane
	# down alive, not down into the hillside.
	if _terrain_pullup_needed():
		_terrain_pullup()
		return
	# Far from any fighter (or out of air-to-air missiles): follow the route
	# like a player would - waypoints trigger the mission script - cruising
	# 1500 m above the ground. Without missiles only inside 2.5 km is the
	# cannon worth chasing after, otherwise the mission route is important.
	var stores := _air_stores()
	_ap_debug = "air tgt=%s dist=%.0f tgt_y=%.0f stores=%d nav=%d/%d left=%d" % [best.display_name, dist, best.global_position.y, stores, nav_index, waypoints.size(), remaining]
	var defend: bool = _threatens_escort(best)
	if ((dist > 12000.0 and not defend) or (stores == 0 and dist > 2500.0)) and nav_index < waypoints.size():
		var wp: Vector3 = waypoints[nav_index].pos
		var cruise := maxf(wp.y, terrain.height_at(wp.x, wp.z) + 1500.0) if terrain else wp.y
		player.steer_towards(Vector3(wp.x, cruise, wp.z), 0.5, 300.0)
		player.throttle = 0.9
		player.afterburner = false
		return
	# Pursuit: aim ahead of the target. Head-on at long range, with the lead
	# shrinking near the gun range (Manual p. 59: the Vulcan's effective range
	# with your target is about 1 nautical mile, 1850 m). Close to the ring
	# the aim becomes the gun pipper: the target plus the shell's flight lead
	# (shell speed 1050 m/s), which the on-screen "predictor gunsight" does.
	var lead_t: float = dist / 1050.0 if dist < 2400.0 else clampf(dist / 900.0, 0.0, 6.0)
	var aim: Vector3 = best.global_position + best.velocity * lead_t
	if player.speed() < 160.0:
		aim.y = minf(aim.y, player.global_position.y - 600.0)
	# Terrain safety: do not let the bandit drag you into the ground. When
	# low, never aim below your own level and keep the aim above the terrain
	# the target flies over.
	if terrain:
		if aim.x != 0.0 or aim.z != 0.0:
			var g_aim: float = terrain.height_at(aim.x, aim.z)
			var agl_self: float = player.global_position.y - terrain.height_at(player.global_position.x, player.global_position.z)
			var floor_m: float = 500.0 if agl_self < 1200.0 else 250.0
			aim.y = maxf(aim.y, g_aim + floor_m)
			if agl_self < 1000.0 and aim.y < player.global_position.y:
				aim.y = player.global_position.y
	player.steer_towards(aim, lerpf(0.05, 1.0, clampf((player.speed() - 120.0) / 110.0, 0.0, 1.0)), 300.0)
	player.throttle = 1.0
	player.afterburner = player.speed() < 250.0 and dist > 1500.0
	# Cannon "IN RNG" pass: inside 1 NM with the nose on the pipper
	# (manual: the 20mm Vulcan fires 30 shells/s).
	var pipper: Vector3 = best.global_position + best.velocity * (dist / 1050.0)
	var ang_pipper: float = nose.angle_to((pipper - player.global_position).normalized())
	var in_gun_range := dist < 1850.0 and ang_pipper < 0.10
	if in_gun_range and player.can_fire():
		player.consume_round(0.033)
		_fire(player)
	# Missiles: only when outside effective gun range and the target is in aspect.
	elif not in_gun_range and player_lock != null and player_lock.alive and player_lock.health > 20.0 \
			and dist > 1500.0 and dist <= Weapons.MISSILES.AMRAAM.range and ang < 0.35 \
			and stores > 0 and player.missile_cooldown <= 0.0:
		player.missile_cooldown = 12.0
		_player_missile()


## True when the script sends this enemy after an escorted, still living ally.
func _threatens_escort(e) -> bool:
	if e.standby or e.attack_ids.is_empty():
		return false
	for id in e.attack_ids:
		if _escort_ids.has(id):
			var n = _node_for(id)
			if n != null and n.alive:
				return true
	return false


## Remaining air-to-air stores (SWINDERM/SWINDERJ/AMRAAM etc.).
func _air_stores() -> int:
	var n := 0
	for name in player.missiles:
		if Weapons.mode_of(name) == "air":
			n += player.missiles.get(name, 0)
	return n


## The air-to-air weapon in range at this distance: Sidewinder inside its
## envelope, otherwise the AMRAAM (the HUD's IN RNG readout uses this).
func aa_weapon_range(dist: float) -> float:
	return Weapons.MISSILES.SWINDERM.range if dist < Weapons.MISSILES.SWINDERM.range \
			else Weapons.MISSILES.AMRAAM.range


## Testing: dive on the nearest live target, launch AGMs, then bomb on the pipper.
var _ap_gtgt = null            # ground target the autopilot works on (no dithering)
var _ap_along := 0.0           # last bomb-run impact offset along track (run-out trigger)


func _autopilot_ground() -> void:
	var tgt = _ap_gtgt
	if tgt == null or not tgt.alive:
		tgt = null
		for t in targets:
			if t.alive and t.has_method("center") and (tgt == null or t.global_position.distance_to(player.global_position) < tgt.global_position.distance_to(player.global_position)):
				tgt = t
		_ap_gtgt = tgt
	if tgt == null:
		player.steer_towards(player.global_position - player.global_transform.basis.z * 3000.0)
		return
	var dist: float = Vector2(tgt.global_position.x - player.global_position.x, tgt.global_position.z - player.global_position.z).length()
	if weapon_mode == "air" or (weapon_mode == "agm" and (player.missiles.get("AGM-65D", 0) == 0 or (ground_lock == null and dist < 2500.0))):
		_cycle_weapon_mode()
	var aim: Vector3 = tgt.center()
	if weapon_mode == "bomb":
		aim.y = maxf(aim.y + 700.0, player.global_position.y - 900.0)   # shallow level pass ~700 m above the target
	elif dist > 6000.0:
		aim.y = maxf(aim.y + 600.0, player.global_position.y)
	# Just fired an AGM inside the site's envelope: break off upwards instead
	# of overflying the point defences.
	if weapon_mode == "agm" and player.missile_cooldown > 5.0 and dist < 4500.0:
		aim = tgt.global_position + Vector3.UP * 2500.0
	player.steer_towards(aim, 0.6, 250.0)
	player.throttle = 0.9
	player.afterburner = player.speed() < 170.0
	if weapon_mode == "agm":
		_ap_debug = "agm dist=%.0f glock=%s cd=%.1f" % [dist, "yes" if ground_lock != null else "no", player.missile_cooldown]
		if ground_lock != null and player.missile_cooldown <= 0.0:
			player.missile_cooldown = 8.0
			_player_agm()
	if weapon_mode == "bomb":
		var sp := next_bomb_spec()
		if not sp.is_empty():
			var impact = Bomb.predict_impact(player.global_position, player.velocity, sp.drag, terrain)
			if impact != null:
				# Release when the impact point sweeps over the target along track.
				var fwd := Vector2(player.velocity.x, player.velocity.z).normalized()
				var miss := Vector2(tgt.global_position.x - impact.x, tgt.global_position.z - impact.z)
				var along := miss.dot(fwd)
				_ap_along = along
				_ap_debug = "dist=%.0f along=%.0f cross=%.0f" % [dist, along, (miss - fwd * along).length()]
				# Impact already ~1 km behind the target: the pass was missed,
				# extend out and come back on a fresh line.
				if along < -1000.0 and not _ap_run_out:
					_ap_run_out = true
				if _ap_run_out:
					var away := Vector3(player.global_position.x - tgt.global_position.x, 0.0, player.global_position.z - tgt.global_position.z).normalized()
					aim = tgt.global_position + away * 13000.0 + Vector3.UP * 600.0
					if dist > 10000.0:
						_ap_run_out = false
					player.steer_towards(aim, 0.6, 250.0)
				elif along < 100.0 and along > -350.0 and (miss - fwd * along).length() < 350.0:
					_player_bomb()



## Navpoint jump: teleport to the next waypoint (the original SC behaviour).
func _jump_next_navpoint() -> void:
	if waypoints.is_empty():
		_say("No waypoints.", 2.0)
		return
	if nav_index + 1 >= waypoints.size() and nav_index >= waypoints.size():
		_say("Already at final waypoint.", 2.0)
		return
	var idx: int = minf(nav_index + 1, waypoints.size())
	if idx < waypoints.size():
		var wp: Dictionary = waypoints[idx]
		var g: float = terrain.height_at(wp.pos.x, wp.pos.z) if terrain else 0.0
		var pos: Vector3 = Vector3(wp.pos.x, maxf(wp.pos.y, g + 1500.0), wp.pos.z)
		player.global_position = pos
		player.velocity = (-player.global_transform.basis.z) * player.speed()
		nav_index = idx
		_say("Jumped to waypoint: %s" % wp.name, 3.0)
		# The original's navpoint jump cut to a flyby of the plane at the new spot.
		if rig != null:
			rig.start_flyby(4.0)
	else:
		nav_index = idx
		_say("Route complete.", 3.0)
	_check_mission()


## Waypoint autopilot: follow the mission route (waypoints from nav_plan).
## Wing Commander style: smooth banking turns, lead turns, altitude management.
func _autopilot_waypoint() -> void:
	if waypoints.is_empty() or nav_index >= waypoints.size():
		# Free flight or route done: cruise straight ahead, keep clear of the ground.
		var fwd: Vector3 = -player.global_transform.basis.z
		var ahead: Vector3 = player.global_position + fwd * 8000.0
		var g: float = terrain.height_at(ahead.x, ahead.z) if terrain else 0.0
		ahead.y = maxf(player.global_position.y, g + 1200.0)
		player.steer_towards(ahead, 0.4, 400.0)
		player.throttle = 0.8
		player.afterburner = false
		return

	var wp: Vector3 = waypoints[nav_index].pos
	var cruise := maxf(wp.y, terrain.height_at(wp.x, wp.z) + 900.0) if terrain else wp.y
	var target_pos := Vector3(wp.x, cruise, wp.z)
	var to: Vector3 = target_pos - player.global_position
	var dist_h: float = Vector2(to.x, to.z).length()

	# Lead turn: start turning before reaching waypoint (Wing Commander style)
	var turn_anticipation := 3000.0  # Start turning 3km before waypoint
	if dist_h < turn_anticipation and nav_index + 1 < waypoints.size():
		# Blend towards next waypoint for smooth turn
		var next_wp: Vector3 = waypoints[nav_index + 1].pos
		var next_cruise := maxf(next_wp.y, terrain.height_at(next_wp.x, next_wp.z) + 900.0) if terrain else next_wp.y
		var next_pos := Vector3(next_wp.x, next_cruise, next_wp.z)
		var blend := 1.0 - (dist_h / turn_anticipation)
		target_pos = target_pos.lerp(next_pos, blend * 0.5)
		cruise = lerpf(cruise, next_cruise, blend * 0.5)
		target_pos.y = cruise

	# If close to waypoint horizontally, the single advance point is
	# _update_nav(); the waypoint autopilot only aims at the current one.
	player.steer_towards(target_pos, 0.55, 300.0)
	player.throttle = 0.75
	player.afterburner = false


## Direct pitch-rate vertical-speed command: rotate the nose until the
## wanted vertical speed is met; used by the landing autopilot phases,
## since the FBW stick cannot command a deeper than trim-default sink.
##
## `k` is the gain on the FLIGHT-PATH ANGLE error (1/s). The old law used
## k on the vertical-speed error (0.08 per m/s = ~13/s in path angle at
## 160 m/s); with the ~1.5 s lag from pitch to flight path that loop had a
## damping ratio of ~0.1 and slammed between +-0.42 rad/s on every approach
## that did not start on the slope (vs -35 .. +13 m/s, crash short of the
## runway in every full MISN-1A flight). k ~0.8 gives a damping ratio ~0.5.
func _ap_vs_pitch(vs_cmd: float, k := 0.8, lmt := 0.3) -> void:
	var v: float = maxf(player.speed(), 50.0)
	var gamma: float = asin(clampf(player.velocity.y / v, -1.0, 1.0))
	var gamma_c: float = asin(clampf(vs_cmd / v, -0.5, 0.5))
	var rate: float = clampf((gamma_c - gamma) * k, -lmt, lmt)
	player.pitch_rate_override = rate
	_ap_pr_cmd = rate
	player.controls.x = 0.0


## Landing autopilot helper: level-bank turn towards `target` (horizontal)
## while a vertical-speed controller holds altitude `alt`, and a throttle /
## speed-brake controller holds `spd` m/s. Stable for targets behind the plane.
func _ap_level_to(target: Vector3, alt: float, max_bank: float, spd: float) -> void:
	player.steer_heading(target, max_bank)
	var vs_cmd: float = clampf((alt - player.global_position.y) / 10.0, -25.0, 20.0)
	_ap_vs_hold(vs_cmd)
	var spd_err: float = spd - player.speed()
	player.throttle = clampf(0.55 + spd_err * 0.02, 0.15, 1.0)
	player.afterburner = spd_err > 40.0
	player.brakes = spd_err < -40.0


## Speed hold with the throttle/brakes pair: the FBW stick only shapes the
## descent; thrust manages the approach speed (a real ILS pairing).
func _ap_autothrottle(spd: float) -> void:
	var err: float = spd - player.speed()
	player.throttle = clampf(player.throttle + err * 0.01, 0.03, 0.9)
	player.brakes = player.speed() > spd + 10.0


## Landing autopilot: approach and land at home runway.
## Phases: far approach -> glide intercept (3°) -> short final on centerline
## -> flare over the threshold -> rollout -> mission end.
## Vertical-speed hold through the fly-by-wire stick: the FBW stick commands
## load factor and its neutral trim already holds the flight path (bank and
## climb compensation), so a load-factor delta reaches the wanted vertical
## speed. `tc` is the catch-up time constant in seconds.
func _ap_vs_hold(vs_cmd: float, tc := 2.0) -> void:
	var vs_err: float = vs_cmd - player.velocity.y
	var dn: float = vs_err / (9.81 * tc)
	# stick >= 0: n = neutral + stick*(max_g - neutral); stick < 0: push maps
	# stick*(neutral + 3). With neutral ~ 1 in level flight: denom 8.0 / 4.0.
	var denom: float = (player.max_g - 1.0) if dn >= 0.0 else 4.0
	player.controls.x = clampf(dn / denom, -1.0, 1.0)


func _autopilot_land() -> void:
	if home_runway == null:
		_say("No home runway found", 3.0)
		autopilot_land = false
		return
	# On the ground: roll out. Done BEFORE landing_info() because that draws
	# no runway box past touchdown (landing_info returns empty) - aborting
	# here bounced the plane back into the air right after contact.
	if player.on_ground:
		player.throttle = 0.0
		player.brakes = true
		player.controls = Vector3(0.0, 0.0, 0.0)
		if player.speed() < 5.0:
			_say("Landed successfully", 3.0)
			autopilot_land = false
			_end_mission("landed")
		return
	var info := landing_info()
	if info.is_empty():
		if mission == null or not player.alive:
			_say("Landing data unavailable", 3.0)
			autopilot_land = false
			return
		# Out of the 20 km approach zone: head for the base at a safe height.
		if _terrain_pullup_needed():
			_terrain_pullup()
			return
		var home: Vector3 = home_runway.global_position
		var alt: float = maxf(home.y + 1200.0, terrain.height_at(player.global_position.x, player.global_position.z) + 900.0)
		_ap_level_to(home, alt, 0.8, 180.0)
		_ap_debug = "land enroute d=%.0f" % player.global_position.distance_to(home_runway.global_position)
		return
	var threshold: Vector3 = info.threshold
	var corners: Array[Vector3] = info.corners
	var center: Vector3 = (corners[0] + corners[2]) * 0.5
	var dir: Vector3 = (center - threshold).normalized()
	var side: Vector3 = dir.cross(Vector3.UP).normalized()
	# Lateral offset shrinks on final: 60 m out wide, dead center inside 1.5 km.
	var lat_m: float = clampf((Vector2(threshold.x, threshold.z).distance_to(
		Vector2(player.global_position.x, player.global_position.z)) - 1500.0) / 6500.0, 0.0, 1.0) * 60.0

	# Level-bank tracking + direct pitch-rate control: the fly-by-wire stick
	# clamps into the trim equilibrium and cannot deepen the descent below
	# ~-3 m/s, so the pitch rate is commanded straight (the stick is zeroed
	# to keep steer_heading's roll in charge of the turn).
	var to_thresh: Vector3 = threshold - player.global_position
	var dist_2d: float = Vector2(to_thresh.x, to_thresh.z).length()
	var agl: float = player.global_position.y - terrain.height_at(player.global_position.x, player.global_position.z)
	var target_agl: float = GLIDE_TCH + tan(deg_to_rad(GLIDE_SLOPE)) * dist_2d
	# Commit target: a point on the runway axis always ahead of the plane
	# (a fixed overrun point ends up behind after the crossed threshold and
	# the bank-only turn then spins 180 in place instead of landing).
	var along_fwd: float = maxf(250.0, (player.global_position - threshold).dot(dir) + 150.0)
	var overrun: Vector3 = threshold + dir * along_fwd
	# Power-the-glide controller: below the glideslope add power, above it cut
	# power. Keeps the 3-degree interception stable: the flight model's
	# throttle/trim equilibrium has a sinking bias, and the old point-steering
	# flip-flopped between climb and dive (phugoid).
	# One datum: the glide slope is a line above the THRESHOLD, so the error is
	# measured from the threshold height, not from the ground under the plane.
	# (With the local AGL, terrain 60-200 m below the field on the MISN-1A
	# approach read as "high" -> dive, then rising ground read as "low".)
	# The local ground only acts as a safety floor (terrain_floor below).
	var h: float = player.global_position.y - threshold.y
	var gs_err: float = h - target_agl
	var terrain_floor: float = minf(target_agl, 40.0 + dist_2d * 0.02)
	var glide_power: float = clampf(0.55 + 0.4 * clampf(-gs_err / 150.0, -0.35, 1.0), 0.2, 0.95)
	_ap_debug = "land d=%.0f h=%.0f agl=%.0f tgt=%.0f pw=%.2f spd=%.0f cs=%.2f pr=%.2f pit=%.2f vs=%.1f gr=%s" % [
		dist_2d, h, agl, target_agl, glide_power, player.speed(),
		player.controls.x, _ap_pr_cmd,
		player.global_transform.basis.get_euler().x,
		player.velocity.y, str(player.on_ground)]

	# Phase 1: Far approach (> 7.5 km): line up 120 m above the glide slope
	# (the original "come in high" briefing) so the descent is steady and the
	# terrain hills are cleared.
	player.brakes = false
	# Along-track position: < 0 on the approach side, > 0 past the threshold.
	var along: float = (player.global_position - threshold).dot(dir)
	# Lateral offset from the extended centreline and the approach cone the
	# final phases need: outside it the plane goes back to phase 1, which
	# joins the line 6.5+ km out (a plane 1 km off the line at the threshold
	# used to "commit" and dive into the ground beside the runway).
	var lat: float = (player.global_position - threshold).dot(side)
	var on_cone: bool = absf(lat) < 300.0 + absf(along) * 0.12
	_ap_debug += " along=%.0f lat=%.0f" % [along, lat]
	var closing: bool = Vector2(player.velocity.x, player.velocity.z).dot(Vector2(to_thresh.x, to_thresh.z)) > 0.0
	# Missed approach: too high or too low on final, flown past the threshold,
	# or heading away inside the final-approach zone. Fly out and re-enter.
	if not _ap_goaround and not player.on_ground and dist_2d <= 7500.0:
		var too_high: bool = dist_2d < 4000.0 and gs_err > 120.0 + dist_2d * 0.03
		var too_low: bool = dist_2d > 1200.0 and gs_err < -maxf(60.0, target_agl * 0.5)
		# Only abandon the approach when the plane is clearly high and already
		# well past the runway. A low pass over the numbers must commit to a
		# touchdown instead of climbing away into the desert.
		var overflown: bool = along > 2600.0 and agl > 160.0
		var leaving: bool = along < 0.0 and dist_2d > 1500.0 and not closing
		# Arriving from the far side of the field (the landing end is fixed
		# by terrain clearance): fly the pattern round instead of landing
		# against the runway direction.
		var wrong_way: bool = along > -2500.0 and Vector2(player.velocity.x, player.velocity.z).dot(Vector2(dir.x, dir.z)) < 0.0
		if too_high or too_low or overflown or leaving or wrong_way:
			_ap_goaround = true
			_say("Go around.", 3.0)
	if _ap_goaround and along < -8500.0:
		# Clear only beyond the 7.5 km gate zone on the approach side: the
		# turn back onto the line then happens in phase 1, which has no gates.
		# (Clearing at 6.5 km re-armed the "leaving" gate at once and the
		# plane looped the pattern until the timeout.)
		_ap_goaround = false
	if dist_2d > 7500.0 or _ap_goaround or not on_cone:
		# Terrain first: the approach line can run below hills between the
		# plane and the base.
		if _terrain_pullup_needed():
			_terrain_pullup()
			return
		var approach_pos: Vector3
		var alt: float
		var ground_here: float = terrain.height_at(player.global_position.x, player.global_position.z)
		if _ap_goaround:
			# Out to a point 9 km down the approach line, 700 m above the
			# field (released at 8.5 km, see above).
			approach_pos = threshold - dir * 9000.0
			# At the glide slope's height at the release point (+80 m), so the
			# plane comes back onto the line instead of 200-350 m above it
			# (the old fixed 700 m re-triggered "too high" -> endless loops).
			alt = maxf(threshold.y + GLIDE_TCH + tan(deg_to_rad(GLIDE_SLOPE)) * 9000.0 + 80.0, ground_here + 300.0)
		else:
			# Aim 3 km ahead along the extended centreline (towards the field):
			# aiming at the abeam point (same distance) puts the target right
			# under the plane once it is on the line, and the turn then
			# circles forever (dive-zoom-stall loop, never lands).
			# Pursue a centreline point 5 km ahead of the plane's own along-track
			# position (>= the ~3.4 km turn radius at 185 m/s): the old 3 km lead
			# overshot the line and swung 5-6 km out to the side.
			var aim_d: float = maxf(-(along + 5000.0), 3500.0) if absf(along) < dist_2d + 1.0 and along < 0.0 else maxf(dist_2d - 3000.0, 6500.0)
			approach_pos = threshold - dir * aim_d
			# On the glide slope at the plane's own distance (+40 m), so phase 2
			# starts on the slope; never closer than 300 m to the ground below.
			alt = maxf(threshold.y + target_agl + 40.0, ground_here + 300.0)
		# Level-bank turn + vertical-speed hold: point-steering (steer_towards)
		# banks 77 deg and zooms at a target behind the plane (stall loops).
		_ap_level_to(approach_pos, alt, 0.8, 170.0)
		_ap_debug += " ga=%s cone=%s" % [_ap_goaround, on_cone]
		return
	# Phase 2: Final approach (3-7.5 km): dead-centre line with the
	# vertical-speed controller (a stable glide hand-off; the point-steering
	# variant oscillated between climb and dive). Pitch is driven through the
	# fly-by-wire stick (load factor): its neutral-trim automatically holds
	# the flight path even banked, so no manual bank compensation needed.
	# Phases are gated by the distance ALONG the centreline, and the lateral
	# steering pursues a point on the centreline ahead of the plane: steering
	# at the runway centre let a plane that came out of the pattern turn
	# a few hundred metres off the line cross the threshold abeam (never
	# inside 500 m of it, so no touchdown) and go around for ever.
	if along < -3000.0:
		player.steer_heading(threshold + dir * (along + 2500.0), 0.5)
		# Nominal glide sink (-v sin 3 deg, ~8 m/s at 150 m/s) plus a
		# correction: below the slope (gs_err < 0) -> sink less.
		var vs_cmd: float = -player.speed() * sin(deg_to_rad(GLIDE_SLOPE)) + clampf(-gs_err / 12.0, -10.0, 7.0)
		if agl < terrain_floor:
			vs_cmd = maxf(vs_cmd, (terrain_floor - agl) * 0.5)
		_ap_vs_pitch(vs_cmd, 0.8, 0.3)
		_ap_autothrottle(160.0)   # bleed to the short-final speed
		player.afterburner = false
		return
	# Phase 3: Short final (0.5-3 km): dead center on the glide slope, slowing
	# for the touchdown speed. Target ~105 m/s: the touch-down check accepts
	# < 165 m/s but < 115 m/s counts as a gentle landing, and the fast touches
	# (160 m/s) used to swing the tail out on the flare. The speed bleeds under
	# the autothrottle; brakes bite only on a real overspeed (+10 m/s).
	if along < -500.0:
		player.steer_heading(threshold + dir * (along + 1500.0), 0.35)
		var vs_cmd2: float = -player.speed() * sin(deg_to_rad(GLIDE_SLOPE)) + clampf(-gs_err / 8.0, -8.0, 5.0)   # above the slope -> sink more
		if agl < terrain_floor:
			vs_cmd2 = maxf(vs_cmd2, (terrain_floor - agl) * 0.5)
		_ap_vs_pitch(vs_cmd2, 0.8, 0.3)
		_ap_autothrottle(145.0)   # touchdown window: the ground model accepts < 140 m/s
		player.afterburner = false
		return
	# Terminal commit: over the runway (or nearly inside 600 m), stop the phase
	# machinery: line up with the runway, push the sink through the last metres
	# and touch down. Widened from 60 m so a slightly high short final still
	# lands on the strip instead of floating past it into a go-around.
	# (The old "or below the slope by 25 m" clause committed a low plane early
	# and pushed it down harder - into the ground short of the runway.)
	if along > -600.0:
		player.steer_heading(overrun, 0.15)
		var sink: float = clampf((agl - 2.5) * 0.35 + 0.9, 1.2, 8.0)   # brisk high, gentle low
		_ap_vs_pitch(-sink, 0.6, 0.2)   # gentle rate near the ground
		player.throttle = 0.04
		player.brakes = false
		player.afterburner = false
		return

	# Phase 4: over the runway (0-500 m): glide to the overrun point.
	if agl > 25.0:
		player.steer_heading(overrun, 0.2)
		var vs_cmd3: float = clampf((5.0 - agl) / 12.0, -3.0, 2.0)
		_ap_vs_pitch(vs_cmd3, 0.8, 0.3)
		_ap_autothrottle(115.0)
		player.afterburner = false
		return

	# Phase 6: On ground - rollout (handled at the top of this function)

	# Fallback: just aim for threshold
	player.steer_towards(threshold, 0.5, 200.0)
	player.throttle = 0.3
	player.afterburner = false


func _fire(shooter, spread_rad := 0.002) -> void:
	if shooter == player:
		stats.shots += 1
	var b: Basis = shooter.global_transform.basis
	var muzzle: Vector3 = shooter.global_position - b.z * 6.0 + b.x * 0.9
	var spread := Vector3(randf_range(-1, 1), randf_range(-1, 1), 0.0) * spread_rad
	var dir := (-b.z + b * spread).normalized()
	_bullets.append({"pos": muzzle, "vel": shooter.velocity + dir * BULLET_SPEED, "life": BULLET_LIFE,
		"owner": shooter, "damage": 12.0, "air_only": false})


# --- combat ------------------------------------------------------------------

## Enemy fighters: patrol until the player is within DETECT_RANGE, then lead
## pursuit with guns and missiles; break and drop countermeasures when shot at.
func _enemy_ai() -> void:
	# Allied fighters (the wingman) run the same combat logic: before this
	# they never fired a shot, so the MiG ordered to attack Stern always won.
	var fighters: Array = enemies.duplicate()
	for a in allies:
		if a.alive and not a.on_ground and not _is_transport(a):
			fighters.append(a)
	for e in fighters:
		if not e.alive:
			continue
		e.evading = not e.incoming.is_empty()
		if e.evading and e.cm_cooldown <= 0.0 and e.countermeasures > 0 and randf() < 0.05:
			_drop_countermeasure(e)

		# Build list of valid hostile targets using team-based IFF. Enemies
		# still holding their briefing position (standby) are not engaged.
		var potential_targets: Array = []
		for c in [player] + allies + enemies:
			if c != e and c.alive and not c.on_ground and not c.standby and e.is_hostile_to(c):
				potential_targets.append(c)
		var engage_range: float = DETECT_RANGE if e.team != 1 else ALLY_ENGAGE_RANGE

		var tgt = null
		if e.scripted and not e.attack_ids.is_empty():
			# Scripted target: only attack if it's hostile
			for id in e.attack_ids:
				var ti: int = mission.part_index(id) if mission != null else -1
				if ti >= 0 and _part_nodes.has(ti) and is_instance_valid(_part_nodes[ti]) and _part_nodes[ti].alive \
						and _part_nodes[ti].get("velocity") != null:
					var candidate = _part_nodes[ti]
					if e.is_hostile_to(candidate):
						tgt = candidate
						break
		else:
			# Free hunt: pick nearest hostile target
			var best_dist := 1e9
			for pt in potential_targets:
				var d: float = pt.global_position.distance_to(e.global_position)
				if d < best_dist:
					best_dist = d
					tgt = pt

		if tgt == null or not tgt.alive or tgt.on_ground:
			e.attack_point = null
			continue
		var to: Vector3 = tgt.global_position - e.global_position
		var dist: float = to.length()
		if dist > engage_range:
			e.attack_point = null
			continue
		e.attack_point = tgt.global_position + tgt.velocity * clampf(dist / 900.0, 0.0, 2.5)
		var fwd: Vector3 = -e.global_transform.basis.z
		var ang := fwd.angle_to(to / maxf(dist, 1.0))

		# Cannon: prefer the gun when in envelope (do not spam missiles at close range).
		var gun_env := dist < 1400.0 and ang < 0.18
		if gun_env and e.can_fire():
			var now := _sim_time
			if e.get_meta("gun_burst_until", 0.0) <= now:
				if randf() < 0.35:
					e.set_meta("gun_burst_until", now + randf_range(0.18, 0.55))
					Sfx.play_at("gun", e.global_position, -2.0)
			if e.get_meta("gun_burst_until", 0.0) > now:
				e.consume_round(0.06)
				_fire(e, 0.01)

		# Missiles: only when outside a good gun shot and the target is in the seeker cone.
		if not gun_env and e.missile_cooldown <= 0.0 and ang < 0.35 and dist > 1200.0:
			for name in e.missiles:
				if Weapons.mode_of(name) == "air" and e.missiles[name] > 0 and dist < Weapons.missile(name).range:
					_launch_missile(e, name, tgt)
					e.missiles[name] -= 1
					e.missile_cooldown = randf_range(10.0, 18.0)
					break



func _is_transport(a) -> bool:
	return _is_transport_model(str(a.get_meta("part_model", a.model_name)))


func _is_transport_model(model: String) -> bool:
	var m: String = model.to_upper()
	for t in TRANSPORT_MODELS:
		if m.contains(t):
			return true
	return false


## AA guns fire leading flak bursts; SAM sites launch guided missiles. Both need
## line of sight over the terrain and the target inside range and ceiling.
func _air_defences(dt: float) -> void:
	# Target all hostile aircraft (player + hostile allies)
	var hostile_aircraft: Array = []
	if player.alive and not player.on_ground and player.team != 1:
		hostile_aircraft.append(player)
	for a in allies:
		if a.alive and not a.on_ground and a.team != 1:
			hostile_aircraft.append(a)

	for o in aa_sites:
		if not o.alive or not o.hostile:
			continue
		o.cooldown -= dt
		if o.cooldown > 0.0:
			continue
		var muzzle: Vector3 = o.center() + Vector3.UP * 3.0
		
		# Find best target among hostile aircraft
		var best_target = null
		var best_dist := 1e9
		for target in hostile_aircraft:
			var muzzle_to_target: Vector3 = target.global_position - muzzle
			var dist: float = muzzle_to_target.length()
			if dist < best_dist and dist <= o.weapon.range and muzzle_to_target.y <= o.weapon.ceiling and _line_of_sight(muzzle, target.global_position):
				best_dist = dist
				best_target = target
		
		if best_target == null:
			o.cooldown = 0.5
			continue
		
		var to: Vector3 = best_target.global_position - muzzle
		var dist: float = to.length()
		
		if o.weapon.missile:
			if o.ammo <= 0:
				continue
			o.ammo -= 1
			o.cooldown = randf_range(10.0, 16.0)
			_launch_missile(o, o.weapon.name, best_target)
		else:
			o.cooldown = 0.11
			var speed := 900.0
			var lead: Vector3 = best_target.global_position + best_target.velocity * (dist / speed)
			var dir := (lead - muzzle).normalized()
			var jitter := Vector3(randf_range(-1, 1), randf_range(-1, 1), randf_range(-1, 1)) * 0.012
			_bullets.append({"pos": muzzle, "vel": (dir + jitter).normalized() * speed,
				"life": dist / speed + 0.6, "owner": o, "damage": 6.0, "air_only": true})


func _line_of_sight(a: Vector3, b: Vector3) -> bool:
	if terrain == null:
		return true
	for i in range(1, 12):
		var p := a.lerp(b, i / 12.0)
		if terrain.height_at(p.x, p.z) > p.y:
			return false
	return true


func _launch_missile(shooter: Node3D, name: String, target: Node3D) -> void:
	var m = Missile.new()
	var from: Vector3
	var dir: Vector3
	var vel := Vector3.ZERO
	if shooter.get("velocity") != null:
		var b: Basis = shooter.global_transform.basis
		from = shooter.global_position - b.y * 1.5
		dir = -b.z
		vel = shooter.velocity
	else:
		from = shooter.center() + Vector3.UP * 4.0
		dir = ((target.global_position - from).normalized() + Vector3.UP * 0.5).normalized()
	if shooter == player:
		stats.missiles += 1
	Sfx.play_at("missile_launch", shooter.global_position, 2.0 if shooter == player else 0.0)
	m.setup(name, _missile_mesh(name), from, dir, vel, spec(name))
	m.target = target
	m.shooter = shooter
	m.detonated.connect(_on_missile_detonated)
	add_child(m)
	missiles_in_flight.append(m)
	target.incoming.append(m)
	if target == player:
		_say("MISSILE WARNING - %s! Countermeasures: F" % Weapons.missile(name).label, 3.0)
		radio_call(_wingman_actor(), 17, 15.0, true)          # watch it, missile on you
	elif allies.has(target):
		radio_call(_actor(target), 17, 15.0, true)


## Weapon parameters with the original WDAT damage / blast radius applied.
func spec(name: String) -> Dictionary:
	if not _specs.has(name):
		var base: Dictionary = Weapons.BOMBS[name] if Weapons.is_bomb(name) else Weapons.missile(name)
		_specs[name] = Weapons.apply_wdat(base, SCData.model(base.model)) if base.get("ground", Weapons.is_bomb(name)) else base
	return _specs[name]


func _on_missile_detonated(m, hit: bool) -> void:
	if m.spec.has("blast"):
		_blast(m.global_position, m.spec.damage, m.spec.blast, m.target if hit else null, m.shooter)


## Splash damage with linear falloff to ground objects and aircraft.
func _blast(pos: Vector3, damage: float, radius: float, exclude = null, cause = null) -> void:
	Sfx.play_at("explosion_big" if radius > 15.0 else "explosion_small", pos, 4.0)
	var fx := Effects.explosion(clampf(radius * 0.35, 4.0, 25.0))
	add_child(fx)
	fx.global_position = pos
	for o in ground_objects:
		if o == exclude or not o.alive or not (o.hittable or o.blast_only):
			continue
		var d: float = maxf(0.0, o.center().distance_to(pos) - o.radius * 0.5)
		if o.blast_only:
			# Long thin runways: distance to the strip, not to its centre.
			var local: Vector3 = o.global_transform.affine_inverse() * pos
			var box: AABB = o.mesh_instance.mesh.get_aabb()
			d = Vector2(maxf(0.0, absf(local.x - box.get_center().x) - box.size.x * 0.5),
				maxf(0.0, absf(local.z - box.get_center().z) - box.size.z * 0.5)).length()
		if d < radius:
			o.damage(damage * clampf(1.0 - d / radius, 0.25, 1.0), cause)
	for a in enemies + allies + [player]:
		if a == exclude or not a.alive:
			continue
		var d: float = a.global_position.distance_to(pos)
		if d < radius:
			a.damage(damage * 0.5 * (1.0 - d / radius), cause)


func _missile_mesh(name: String) -> Mesh:
	if not _missile_meshes.has(name):
		var m = SCData.model((Weapons.BOMBS[name] if Weapons.is_bomb(name) else Weapons.missile(name)).model)
		_missile_meshes[name] = m.build_mesh(SCData.palette(), 0, true) if m != null else null
	return _missile_meshes[name]


func _update_missiles(dt: float) -> void:
	missiles_in_flight = missiles_in_flight.filter(func(m): return m.step(dt, terrain))


func _drop_countermeasure(a) -> void:
	if a.countermeasures <= 0 or a.cm_cooldown > 0.0:
		return
	a.countermeasures -= 1
	a.cm_cooldown = 0.5
	var pos: Vector3 = a.global_position - a.velocity * 0.15 + Vector3.DOWN * 30.0
	var fx := Effects.explosion(1.2)
	add_child(fx)
	fx.global_position = a.global_position - a.velocity * 0.03
	for m in a.incoming:
		m.offer_decoy(a, pos)


## Best hostile aircraft (air mode) or ground target (AGM mode) inside the
## player's forward lock cone.
func _update_lock() -> void:
	player_lock = null
	ground_lock = null
	if not player.alive:
		return
	if weapon_mode == "agm":
		var nose: Vector3 = -player.global_transform.basis.z
		var best_g := 0.35
		for o in ground_objects:
			if not o.alive or not o.hittable or not (o.hostile or o.is_target):
				continue
			var to: Vector3 = o.center() - player.global_position
			if to.length() > Weapons.MISSILES["AGM-65D"].range:
				continue
			var ang := nose.angle_to(to.normalized())
			if ang < best_g and _line_of_sight(player.global_position, o.center() + Vector3.UP * 4.0):
				best_g = ang
				ground_lock = o
		return
	var fwd: Vector3 = -player.global_transform.basis.z
	var best := LOCK_CONE
	for e in enemies:
		if not e.alive:
			continue
		var to: Vector3 = e.global_position - player.global_position
		if to.length() > Weapons.MISSILES.AMRAAM.range:
			continue
		var ang := fwd.angle_to(to.normalized())
		if ang < best:
			best = ang
			player_lock = e


## Selects the next weapon mode that still has stores.
func _cycle_weapon_mode() -> void:
	var i := Weapons.MODES.find(weapon_mode)
	for k in range(1, Weapons.MODES.size() + 1):
		var mode: String = Weapons.MODES[(i + k) % Weapons.MODES.size()]
		for name in player.missiles:
			if player.missiles[name] > 0 and Weapons.mode_of(name) == mode:
				weapon_mode = mode
				_say("Weapon: %s" % Weapons.MODE_LABELS[mode], 1.5)
				return


func _player_release() -> void:
	match weapon_mode:
		"agm":
			_player_agm()
		"bomb":
			_player_bomb()
		_:
			_player_missile()


func _player_agm() -> void:
	if ground_lock == null:
		_say("No ground lock - point the nose at a ground target.", 2.0)
		return
	for name in player.missiles:
		if Weapons.mode_of(name) == "agm" and player.missiles[name] > 0:
			player.missiles[name] -= 1
			_launch_missile(player, name, ground_lock)
			_say("%s launched at %s" % [Weapons.label(name), ground_lock.display_name], 2.0)
			return
	_say("No AGMs left.", 2.0)


func _player_bomb() -> void:
	if _release_cooldown > 0.0:
		return
	for name in player.missiles:
		if Weapons.is_bomb(name) and player.missiles[name] > 0:
			player.missiles[name] -= 1
			_release_cooldown = 0.25
			stats.bombs += 1
			var b = Bomb.new()
			b.setup(name, spec(name), _missile_mesh(name), player.global_position - player.global_transform.basis.y * 1.8, player.velocity)
			b.shooter = player
			b.impacted.connect(func(bomb, pos): _blast(pos, bomb.spec.damage, bomb.spec.blast, null, bomb.shooter))
			add_child(b)
			bombs_in_flight.append(b)
			return
	_say("No bombs left.", 2.0)


func _update_bombs(dt: float) -> void:
	bombs_in_flight = bombs_in_flight.filter(func(b): return b.step(dt, terrain, ground_objects))


## Drag of the bomb that would be released next (for the CCIP pipper).
func next_bomb_spec() -> Dictionary:
	for name in player.missiles:
		if Weapons.is_bomb(name) and player.missiles[name] > 0:
			return spec(name)
	return {}


## Short range: heat seeker first; otherwise radar missile.
func _player_missile() -> void:
	if player_lock == null:
		_say("No lock - turn towards an enemy.", 2.0)
		return
	var dist: float = player_lock.global_position.distance_to(player.global_position)
	var order := ["SWINDERM", "AMRAAM"] if dist < Weapons.MISSILES.SWINDERM.range else ["AMRAAM"]
	for name in order:
		if player.missiles.get(name, 0) > 0 and dist < Weapons.missile(name).range:
			player.missiles[name] -= 1
			_launch_missile(player, name, player_lock)
			_say("%s launched at %s" % [Weapons.missile(name).label, player_lock.display_name], 2.0)
			return
	_say("No suitable missiles left.", 2.0)


func _update_bullets(dt: float) -> void:
	var mm := _tracers.multimesh
	var alive_bullets := []
	for bl in _bullets:
		var from: Vector3 = bl.pos
		bl.vel += Vector3.DOWN * 9.81 * dt
		bl.pos = from + bl.vel * dt
		bl.life -= dt
		var hit := false
		for e in enemies + allies + [player]:
			if e == bl.owner or not e.alive:
				continue
			if Geometry3D.segment_intersects_sphere(from, bl.pos, e.global_position, e.radius).size() > 0:
				e.damage(bl.damage, bl.owner)
				_hit_sound(bl.pos)
				hit = true
				break
		if not hit and not bl.air_only and bl.pos.y < _max_object_height:
			for o in ground_objects:
				if o != bl.owner and o.alive and o.hittable and Geometry3D.segment_intersects_sphere(from, bl.pos, o.center(), o.radius).size() > 0:
					o.damage(bl.damage, bl.owner)
					_hit_sound(bl.pos)
					hit = true
					break
		if terrain and bl.pos.y < terrain.height_at(bl.pos.x, bl.pos.z):
			hit = true
		if not hit and bl.life > 0.0:
			alive_bullets.append(bl)
	_bullets = alive_bullets
	var n := mini(_bullets.size(), mm.instance_count)
	for i in n:
		var bl: Dictionary = _bullets[i]
		var v: Vector3 = bl.vel
		var xf := Transform3D(Basis.looking_at(v.normalized(), Vector3.UP if absf(v.normalized().y) < 0.99 else Vector3.RIGHT), bl.pos)
		mm.set_instance_transform(i, xf)
	mm.visible_instance_count = n


func _on_ground_destroyed(o) -> void:
	if o.is_target or o.hostile:
		if o.get("last_hit_by") == player or o.get("last_hit_by") == null:
			stats.ground_kills += 1
		else:
			stats.wingman_ground_kills += 1
	kills += 1
	_say("%s destroyed!" % o.display_name, 3.0)
	_check_mission()


## Runway object nearest the player's start: target of the landing aid.
func _find_home_runway() -> void:
	if not _player_start.has("pos"):
		return
	var best := 1e12
	for o in ground_objects:
		if o.blast_only:
			var d: float = o.global_position.distance_squared_to(_player_start.pos)
			if d < best:
				best = d
				home_runway = o


## Landing aid for the HUD: runway corners, approach direction, glide slope
## and centre-line deviations. Empty when not heading home or too far away.
func landing_info() -> Dictionary:
	if mission == null or home_runway == null or not player.alive or player.on_ground:
		return {}
	var heading_home: bool = nav_index >= waypoints.size() - 1 or mission_complete or _script_success
	var box: AABB = home_runway.mesh_instance.mesh.get_aabb()
	var xf: Transform3D = home_runway.mesh_instance.global_transform
	var center: Vector3 = xf * box.get_center()
	if not heading_home or center.distance_to(player.global_position) > 20000.0:
		return {}
	var along_x := box.size.x > box.size.z
	var axis: Vector3 = (xf.basis * (Vector3.RIGHT if along_x else Vector3.BACK)).normalized()
	axis.y = 0.0
	axis = axis.normalized()
	var half := maxf(box.size.x, box.size.z) * 0.5
	var width := minf(box.size.x, box.size.z)
	# Land from the end with the clear approach (see _landing_end_sign), fixed
	# for the whole flight. Picking the end nearest the aircraft sent every
	# full MISN-1A flight over a hump that rises 24 m above the 3 deg slope
	# just before the north threshold.
	axis *= _landing_end_sign(center, axis, half)
	var threshold: Vector3 = center + axis * half
	var dir := -axis
	var rel: Vector3 = player.global_position - threshold
	var dist := maxf(0.0, -rel.dot(dir))
	var ideal := threshold.y + tan(deg_to_rad(GLIDE_SLOPE)) * dist
	var side := dir.cross(Vector3.UP)
	var corners: Array[Vector3] = []
	for k in [Vector2(-1, -1), Vector2(1, -1), Vector2(1, 1), Vector2(-1, 1)]:
		corners.append(center + axis * half * k.x + side * width * 0.5 * k.y)
	var hdg := fposmod(rad_to_deg(atan2(dir.x, -dir.z)), 360.0)
	return {"distance": dist, "gs_error": player.global_position.y - ideal,
		"loc_error": rel.dot(side), "corners": corners, "runway": "%02d" % int(roundf(hdg / 10.0)) if roundf(hdg / 10.0) > 0 else "36",
		"threshold": threshold}


## Which runway end to land from: +1 / -1 along `axis`. The end whose 3 deg
## glide slope (0.3-10 km out) keeps the most clearance over the terrain
## wins; computed once per runway and kept for the flight, so the approach
## does not flip while the plane manoeuvres around the field.
var _land_end := {}   # runway node -> sign
func _landing_end_sign(center: Vector3, axis: Vector3, half: float) -> float:
	if _land_end.has(home_runway):
		return _land_end[home_runway]
	var best_sign := 1.0
	var best_clear := -1e9
	for s in [1.0, -1.0]:
		var thr: Vector3 = center + axis * s * half
		var worst := 1e9
		var d := 300.0
		while d <= 10000.0:
			var p: Vector3 = thr + axis * s * d
			var slope_y: float = thr.y + tan(deg_to_rad(GLIDE_SLOPE)) * d
			worst = minf(worst, slope_y - (terrain.height_at(p.x, p.z) if terrain else 0.0))
			d += 100.0
		if worst > best_clear:
			best_clear = worst
			best_sign = s
	_land_end[home_runway] = best_sign
	if debug_log or DisplayServer.get_name() == "headless":
		print("LANDING: runway end %+d, min glide-slope clearance %.0f m" % [best_sign, best_clear])
	return best_sign


## Testing: 8 km final, slightly high and left, heading for the home runway.
func _setup_approach() -> void:
	nav_index = max(0, waypoints.size() - 1)
	# Place the aircraft on a stable final: 8 km out from the nearest runway
	# end, on the extended centreline, 120 m above the 3° glide slope,
	# facing into the runway. Computed horizontally so the threshold
	# end-pick in landing_info() stays consistent.
	player.on_ground = false
	var box: AABB = home_runway.mesh_instance.mesh.get_aabb()
	var xf: Transform3D = home_runway.mesh_instance.global_transform
	var center: Vector3 = xf * box.get_center()
	var along_x := box.size.x > box.size.z
	var axis: Vector3 = (xf.basis * (Vector3.RIGHT if along_x else Vector3.BACK)).normalized()
	axis.y = 0.0
	axis = axis.normalized()
	var half := maxf(box.size.x, box.size.z) * 0.5
	var side: Vector3 = axis.cross(Vector3.UP).normalized()
	# The same end the landing autopilot uses (terrain clearance), so this
	# test flies the approach a full mission really gets.
	axis *= _landing_end_sign(center, axis, half)
	var threshold_end: Vector3 = center + axis * half
	var pos: Vector3 = center + axis * (half + approach_dist) - side * 60.0
	pos.y = threshold_end.y + tan(deg_to_rad(GLIDE_SLOPE)) * approach_dist + approach_high
	player.global_position = pos
	# Face from the spawn point toward the runway interior.
	var face := axis
	player.respawn(pos, atan2(face.x, face.z), approach_speed)
	player.throttle = 0.65
	autopilot_land = true   # --approach: the landing autopilot takes over at once


## Virtual cockpit: the original CD-ROM edition had a 3D cockpit model
## (OBJECTS/<plane>-CKPT.IFF reads through the same RealSpace loader).
## Attach it to the player; the camera rig shows it in cockpit view.
func _setup_cockpit_model() -> void:
	var base: String = player.display_name.to_upper()
	for suffix in ["DES", "GRAY", "GRA", "DEF", "EARLY"]:
		if base.ends_with(suffix):
			base = base.substr(0, base.length() - suffix.length())
	for name in ["OBJECTS/%s-CKPT.IFF" % base, "OBJECTS/%sCKPT.IFF" % base]:
		if not SCData.has(name):
			continue
		var m = SCData.model(name)
		if m == null:
			continue
		var ckpt := MeshInstance3D.new()
		ckpt.mesh = m.build_mesh(_pal, 0, _smooth)
		ckpt.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		player.add_child(ckpt)   # aligned with the aircraft body
		ckpt.visible = false
		cockpit_model = ckpt
		print("cockpit model attached: ", name)
		return


## Flight results for the campaign, as the original STRIKE.EXE writes them to
## misn2op.iff: mission registers (STAT; reg 0 = success, reg 1 = payment in
## k$), planes lost (JETS: the player's and the squadron's fighters), the
## player's kills (KILL) and the abort flag (EXIT 5).
func campaign_report(success: bool) -> Dictionary:
	var jets := 0 if player.alive else 1
	for a in allies:
		if not a.alive and not a.get_meta("removed", false) and not _is_transport(a):
			jets += 1
	return {"ok": success, "aborted": aborted, "regs": _vm_regs.duplicate(),
		"jets_lost": jets, "kills_air": stats.air_kills, "kills_ground": stats.ground_kills}


# --- auto-landing animation (L) -----------------------------------------------
# A precomputed, physics-free landing: the aircraft follows a fixed path
# (join the centreline, 3 deg glide, flare, touchdown, roll-out) instead of the
# flight model, so it cannot balloon or climb away. Far from the field the
# view cuts to 9 km final first, like the original autopilot's jumps. The
# original also refused the autopilot with enemies inside 10 nm.
const AUTOLAND_TOUCHDOWN_SPEED := 72.0
var _land_anim := {}

func start_auto_land() -> void:
	if not _land_anim.is_empty() or mission_over or player == null or not player.alive or player.on_ground:
		return
	if home_runway == null:
		_say("Auto-landing: no runway.", 3.0)
		return
	if _nearest_active_enemy() < 18520.0:
		_say("Auto-landing not available: enemies within 10 nm.", 3.0)
		return
	var fr := _runway_frame()
	var t: Vector3 = fr.threshold
	var dir: Vector3 = fr.dir
	var tan_gs: float = tan(deg_to_rad(GLIDE_SLOPE))
	var curve := Curve3D.new()
	curve.bake_interval = 4.0
	var p: Vector3 = player.global_position
	var along: float = (p - t).dot(dir)
	var final_d := 6000.0
	var f: Vector3 = t - dir * final_d
	f.y = t.y + GLIDE_TCH + tan_gs * final_d
	var start_d := final_d
	var cut: bool = p.distance_to(f) > 12000.0 or along > -2500.0
	if cut:
		# Jump to a 9 km final on the extended centreline.
		start_d = 9000.0
		var c: Vector3 = t - dir * start_d
		c.y = maxf(t.y + GLIDE_TCH + tan_gs * start_d, _ground(c) + 150.0)
		curve.add_point(c)
	else:
		# Smooth join from the present track onto the centreline at 6 km.
		var h: Vector3 = Vector3(player.velocity.x, 0.0, player.velocity.z)
		h = h.normalized() if h.length() > 1.0 else Vector3(dir.x, 0.0, dir.z)
		var k: float = clampf(p.distance_to(f) * 0.4, 800.0, 4000.0)
		var c1: Vector3 = p + h * k
		var c2: Vector3 = f - dir * k
		for i in 40:
			var u: float = i / 40.0
			var q: Vector3 = p.bezier_interpolate(c1, c2, f, u)
			q.y = maxf(q.y, _ground(q) + 120.0)
			curve.add_point(q)
	# 3 deg glide down to the threshold crossing height.
	var d := start_d if cut else final_d
	d -= 150.0
	while d > 0.0:
		var g: Vector3 = t - dir * d
		g.y = maxf(t.y + GLIDE_TCH + tan_gs * d, _ground(g) + (25.0 if d > 1000.0 else 8.0))
		curve.add_point(g)
		d -= 150.0
	# Flare over the first 300 m, touchdown, roll-out inside the runway.
	var touchdown: float = 300.0
	for i in range(1, 7):
		var u2: float = i / 6.0
		var fl: Vector3 = t + dir * (touchdown * u2)
		var gy: float = _ground(fl) + 2.2
		fl.y = lerpf(t.y + GLIDE_TCH, gy, 1.0 - pow(1.0 - u2, 2.0))
		curve.add_point(fl)
	var stop_at: float = maxf(touchdown + 400.0, fr.length - 150.0)
	var r := touchdown + 100.0
	while r <= stop_at:
		var ro: Vector3 = t + dir * r
		ro.y = _ground(ro) + 2.2
		curve.add_point(ro)
		r += 100.0
	var length: float = curve.get_baked_length()
	# Arc length of the touchdown point: nearest baked offset to it.
	var td_point: Vector3 = t + dir * touchdown
	var s_td: float = curve.get_closest_offset(Vector3(td_point.x, _ground(td_point) + 2.2, td_point.z))
	_land_anim = {"curve": curve, "s": 0.0, "length": length, "s_td": s_td,
		"v0": 150.0 if cut else clampf(player.speed(), 110.0, 220.0), "bank": 0.0}
	player.set_physics_process(false)
	autopilot = false
	autopilot_land = false
	autopilot_waypoint = false
	if fast_travel:
		_stop_fast_travel("")
	if cut and rig != null:
		rig.start_flyby(3.0)
	_say("AUTO-LANDING", 4.0)
	print("AUTOLAND start: path %.0f m, touchdown at %.0f m, cut=%s" % [length, s_td, cut])


func _ground(q: Vector3) -> float:
	return terrain.height_at(q.x, q.z) if terrain else 0.0


## Landing end of the home runway: threshold, landing direction, length.
func _runway_frame() -> Dictionary:
	var box: AABB = home_runway.mesh_instance.mesh.get_aabb()
	var xf: Transform3D = home_runway.mesh_instance.global_transform
	var center: Vector3 = xf * box.get_center()
	var along_x := box.size.x > box.size.z
	var axis: Vector3 = (xf.basis * (Vector3.RIGHT if along_x else Vector3.BACK)).normalized()
	axis.y = 0.0
	axis = axis.normalized()
	var half := maxf(box.size.x, box.size.z) * 0.5
	axis *= _landing_end_sign(center, axis, half)
	return {"threshold": center + axis * half, "dir": -axis, "length": half * 2.0}


func _update_auto_land(dt: float) -> void:
	var a: Dictionary = _land_anim
	var curve: Curve3D = a.curve
	var s: float = a.s
	var s_td: float = a.s_td
	var v: float
	if s < s_td:
		v = lerpf(a.v0, AUTOLAND_TOUCHDOWN_SPEED, clampf(s / maxf(s_td, 1.0), 0.0, 1.0))
	else:
		var decel: float = AUTOLAND_TOUCHDOWN_SPEED * AUTOLAND_TOUCHDOWN_SPEED / (2.0 * maxf(a.length - s_td, 50.0))
		v = sqrt(maxf(0.0, AUTOLAND_TOUCHDOWN_SPEED * AUTOLAND_TOUCHDOWN_SPEED - 2.0 * decel * (s - s_td)))
		v = maxf(v, 2.0)
	s = minf(s + v * dt, a.length)
	a.s = s
	var pos: Vector3 = curve.sample_baked(s, true)
	var ahead: Vector3 = curve.sample_baked(minf(s + 30.0, a.length), true)
	var behind: Vector3 = curve.sample_baked(maxf(s - 30.0, 0.0), true)
	var fwd: Vector3 = (ahead - behind)
	if fwd.length() < 0.1:
		fwd = -player.global_transform.basis.z
	fwd = fwd.normalized()
	# Bank from the turn rate one second ahead.
	var far: Vector3 = curve.sample_baked(minf(s + maxf(v, 20.0), a.length), true)
	var far2: Vector3 = curve.sample_baked(minf(s + maxf(v, 20.0) + 30.0, a.length), true)
	var fwd2: Vector3 = (far2 - far)
	var bank_target := 0.0
	if fwd2.length() > 0.1 and s < s_td:
		var h1 := Vector2(fwd.x, fwd.z).normalized()
		var h2 := Vector2(fwd2.x, fwd2.z).normalized()
		var turn: float = h1.angle_to(h2)            # rad per second (look-ahead = 1 s)
		bank_target = clampf(atan(v * turn / 9.81), -0.5, 0.5)
	a.bank = lerpf(a.bank, bank_target, clampf(dt * 2.0, 0.0, 1.0))
	var b := Basis.looking_at(fwd, Vector3.UP)
	b = Basis(fwd, a.bank) * b
	# Nose attitude: a few degrees up on the glide, more in the flare, level
	# on the roll-out.
	var aoa := 0.08
	if s > s_td - 400.0 and s < s_td:
		aoa = lerpf(0.08, 0.15, clampf((s - (s_td - 400.0)) / 400.0, 0.0, 1.0))
	elif s >= s_td:
		aoa = lerpf(0.15, 0.0, clampf((s - s_td) / 250.0, 0.0, 1.0))
	b = Basis(b.x, aoa) * b
	player.global_transform = Transform3D(b, pos)
	player.velocity = fwd * v
	player.on_ground = s >= s_td
	player.throttle = 0.35 if s < s_td else 0.0
	player.brakes = s >= s_td
	player.afterburner = false
	_was_airborne = true
	if s >= a.length - 0.5 or (s >= s_td and v <= 2.0):
		player.velocity = Vector3.ZERO
		player.on_ground = true
		player.set_physics_process(true)
		_land_anim = {}
		print("AUTOLAND done")


## Ends a mission and shows the debrief. reason: landed / lost / script_failed / quit
func _end_mission(reason: String) -> void:
	if mission_over or mission == null:
		return
	mission_over = true
	var done: bool = mission_complete or _script_success or targets_left() == 0
	var result := "failed"
	var why := ""
	match reason:
		"landed":
			var home: bool = home_runway == null or player.global_position.distance_to(home_runway.global_position) < 4000.0
			result = "success" if done and home else "incomplete"
			why = "Landed at base." if home else "Landed away from base."
			if not done:
				why += " Objectives not completed."
		"lost":
			why = "Aircraft lost."
		"script_failed":
			why = "Mission failed."
		_:
			result = "success" if done else "incomplete"
			why = "Mission aborted."
	var wps := []
	for i in waypoints.size():
		wps.append({"name": waypoints[i].name, "reached": i < nav_index or (result == "success" and i == waypoints.size() - 1)})
	var t := _sim_time - _t_start
	var allies_alive := 0
	for a in allies:
		if is_instance_valid(a) and (a.alive or a.get_meta("removed", false)):
			allies_alive += 1
	var targets_dead := 0
	for tgt in targets:
		if is_instance_valid(tgt) and not tgt.alive:
			targets_dead += 1
	var d = Debrief.new()
	d.report = {"result": result, "reason": why, "mission": mission.name, "file": mission_file.get_file().get_basename(),
		"waypoints": wps, "log": radio_log,
		"stats": [["Flight time", "%d:%02d" % [int(t) / 60, int(t) % 60]],
			["Targets destroyed", "%d / %d" % [targets_dead, targets_dead + targets_left()]],
			["Air kills", stats.air_kills], ["Ground kills", stats.ground_kills],
			["Wingman kills", stats.wingman_air_kills + stats.wingman_ground_kills],
			["Rounds fired", stats.shots], ["Missiles fired", stats.missiles], ["Bombs dropped", stats.bombs],
			["Hull", "%d %%" % int(maxf(player.health, 0.0)) if player.alive else "lost"],
			["Wingmen", "%d / %d" % [allies_alive, allies.size()]]]}
	d.process_mode = Node.PROCESS_MODE_WHEN_PAUSED
	d.fly_again.connect(func(): get_tree().paused = false; restart.emit())
	d.campaign_mode = campaign_mode
	d.main_menu.connect(func():
		get_tree().paused = false
		if campaign_mode:
			mission_result.emit(result == "success")
		else:
			exit_to_menu.emit())
	_layer.add_child(d)
	get_tree().paused = true
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE


func _check_mission() -> void:
	if mission == null or mission_complete:
		return
	if targets_left() > 0 and not _script_success:
		return
	# The original route ends at "Head Home" (the base, SPOT 2); a2 02 lands
	# there. Do not call the mission complete until the player has flown the
	# whole route - i.e. every waypoint including the final one is reached
	# (nav_index has advanced past the last entry).
	if nav_index < waypoints.size():
		if not flags.has(-1):
			flags[-1] = true
			_say("Targets destroyed - return to %s to finish." % waypoints[waypoints.size() - 1].name, 6.0)
		return
	mission_complete = true
	_say("MISSION COMPLETE", 10.0)


func targets_left() -> int:
	# Enemy aircraft of scenes not entered yet are targets still to come.
	var pending := 0
	if mission != null:
		var side: int = mission.player_part().side
		for pi in _scene_wait:
			var p: Dictionary = mission.parts[pi]
			if p.side != side and not _escort_ids.has(p.id):
				pending += 1
	var alive: int = 0
	for t in targets:
		if is_instance_valid(t) and t.alive:
			alive += 1
	return alive + pending


func _on_enemy_destroyed(e) -> void:
	if e.is_player:
		return
	kills += 1
	# Kill attribution: only kills where the last damage came from the player
	# count on the debrief's own line; wingman kills get their own tally.
	if e.get("last_hit_by") == player or e.get("last_hit_by") == null:
		stats.air_kills += 1
	else:
		stats.wingman_air_kills += 1
	_say("%s destroyed! (%d)" % [e.display_name, kills], 3.0)
	# Radio: the victim's own last words, then the wingman's call on the kill.
	var victim := _actor(e)
	var cries: Array = []
	if victim != "":
		for id in R_DEATH:
			if SCData.radio(victim).msgs.has(id):
				cries.append(id)
	if not cries.is_empty():
		radio_call(victim, cries[randi() % cries.size()], 5.0)
	if e.get("last_hit_by") == player or e.get("last_hit_by") == null:
		radio_call(_wingman_actor(), 15 if randf() < 0.3 else 13, 20.0)
	_check_mission()
	if mission != null:
		return
	await get_tree().create_timer(12.0).timeout
	if is_inside_tree():
		var ang := randf() * TAU
		_place(e, player.global_position * Vector3(1, 0, 1) + Vector3(sin(ang), 0, cos(ang)) * 12000.0, ang + PI)


func _on_player_down(_p) -> void:
	if mission != null:
		_say("Aircraft lost.", 3.0)
		get_tree().create_timer(3.0).timeout.connect(func(): _end_mission("lost"))
		return
	_say("Aircraft lost - new aircraft in 4 seconds.", 4.0)
	_respawn_timer = 4.0
