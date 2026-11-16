## Point-and-click base screens of the campaign (bar, hangar, office, ...),
## drawn from the original art (OPTIONS.IFF / OPTSHPS / OPTPALS). Hotspots and
## their actions come from GAMEFLOW.IFF via the campaign. Mouse, keyboard
## (Tab / Enter) and gamepad (D-pad / A) all work.
extends Control

const Art = preload("res://scripts/core/art.gd")
const ConversationPlayer = preload("res://scripts/ui/conversation_player.gd")
const CutscenePlayer = preload("res://scripts/ui/cutscene_player.gd")
const CutsceneVM = preload("res://scripts/ui/cutscene_vm.gd")
const Midgame = preload("res://scripts/formats/sc_midgame.gd")
const UiTheme = preload("res://scripts/ui/ui_theme.gd")
const LoadoutScreen = preload("res://scripts/ui/loadout_screen.gd")
const Weapons = preload("res://scripts/game/weapons.gd")
# SCData and Settings are autoload singletons (see project.godot); do not preload them.

signal fly_requested(mission_file: String)
signal flight_done(success: bool)
signal quit_requested
signal _loadout_done(success: bool)

var campaign
var _stage: Control
var _bg: TextureRect
var _sprites: Control
var _highlight: Panel
var _label: Label
var _toast: Label
var _hotspots: Array = []        # [{ gf: gameflow sprite, rect: Rect2i, label, frames, node }]
var _focus := -1
var _anim_t := 0.0
var _auto_activated := false
var _visited_hotspots: Dictionary = {}  # screen_id -> Array of hotspot labels already tried
var _smooth := false
var _loadout_screen: Control        # weapon loadout screen instance
var _inventory: Dictionary = {}     # campaign weapon inventory {weapon_name: count}
var _pending_mission_file: String = ""  # mission file to fly after loadout
var _selected_loadout: Dictionary = {}  # loadout chosen in the loadout screen


func _ready() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_smooth = Settings.get_value("video", "smooth_textures")
	var black := ColorRect.new()
	black.color = Color.BLACK
	black.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(black)
	var arc := AspectRatioContainer.new()
	arc.ratio = 4.0 / 3.0
	arc.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(arc)
	_stage = Control.new()
	arc.add_child(_stage)
	_stage.gui_input.connect(_stage_input)
	_stage.mouse_exited.connect(func(): _set_focus(-1))
	_bg = _picture()
	_stage.add_child(_bg)
	_sprites = Control.new()
	_sprites.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_sprites.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_stage.add_child(_sprites)
	_highlight = Panel.new()
	var hs := StyleBoxFlat.new()
	hs.bg_color = Color(1, 1, 1, 0.04)
	hs.border_color = Color(UiTheme.ACCENT, 0.8)
	hs.set_border_width_all(2)
	hs.set_corner_radius_all(4)
	_highlight.add_theme_stylebox_override("panel", hs)
	_highlight.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_highlight.visible = false
	_stage.add_child(_highlight)

	_label = Label.new()
	_label.anchor_left = 0.0
	_label.anchor_right = 1.0
	_label.anchor_top = 1.0
	_label.anchor_bottom = 1.0
	_label.offset_top = -60
	_label.offset_bottom = -20
	_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_label.add_theme_font_size_override("font_size", 26)
	_label.add_theme_color_override("font_color", UiTheme.ACCENT)
	_label.add_theme_color_override("font_outline_color", Color.BLACK)
	_label.add_theme_constant_override("outline_size", 6)
	add_child(_label)
	_toast = Label.new()
	_toast.anchor_right = 1.0
	_toast.offset_top = 20
	_toast.offset_bottom = 60
	_toast.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_toast.add_theme_font_size_override("font_size", 20)
	_toast.add_theme_color_override("font_outline_color", Color.BLACK)
	_toast.add_theme_constant_override("outline_size", 6)
	add_child(_toast)

	campaign.host = self
	campaign.screen_changed.connect(_build_screen)
	campaign.message.connect(toast)
	if campaign.screen >= 0:
		_build_screen(campaign.screen)


func _picture() -> TextureRect:
	var t := TextureRect.new()
	t.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	t.stretch_mode = TextureRect.STRETCH_SCALE
	t.texture_filter = CanvasItem.TEXTURE_FILTER_LINEAR if _smooth else CanvasItem.TEXTURE_FILTER_NEAREST
	t.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return t


func toast(text: String) -> void:
	_toast.text = text
	var tw := create_tween()
	_toast.modulate.a = 1.0
	tw.tween_interval(2.5)
	tw.tween_property(_toast, "modulate:a", 0.0, 0.6)


# --- screens ----------------------------------------------------------------------

func _build_screen(id: int) -> void:
	var gf = Art.gameflow()
	var s = gf.screens.get(id)
	for c in _sprites.get_children():
		c.queue_free()
	_hotspots.clear()
	_set_focus(-1)
	_auto_activated = false  # Reset for new screen
	if s == null:
		_bg.texture = null
		return
	var pal = Art.palette("opt", s.back_pals + [s.fore_pal])
	var canvas = Art.new_canvas()
	for shp in s.back_shapes:
		var fr: Array = Art.frames("opt", shp)
		if not fr.is_empty():
			Art.blit(canvas, fr[0], Vector2i.ZERO)
	_bg.texture = ImageTexture.create_from_image(Art.canvas_image(canvas, pal))
	# Hotspots: the sprites the current stage defines for this screen.
	for gs in campaign.screen_sprites():
		if not campaign.available(gs):
			continue
		var os = null
		for cand in s.sprites:
			if cand.id == gs.id:
				os = cand
				break
		if os == null:
			continue
		var h := {"gf": gs, "rect": os.rect, "label": os.label, "frames": [], "node": null, "overlay": null}
		var fr: Array = Art.frames("opt", os.shape) if os.shape >= 0 else []
		# Foreground shapes are full 320x200 layers with the sprite already at
		# its position; draw them at the top-left (as the original engine does).
		var place := Vector2i.ZERO
		if not fr.is_empty():
			# Frame 0 is the picture; the SEQU frames animate on top of it.
			var t := _picture()
			t.texture = ImageTexture.create_from_image(Art.layer_image(fr[0], place, pal))
			_sprites.add_child(t)
			h.node = t
			var cache := {}
			for k in os.sequence:
				var idx := clampi(k, 0, fr.size() - 1)
				if idx == 0:
					h.frames.append(null)
					continue
				if not cache.has(idx):
					cache[idx] = ImageTexture.create_from_image(Art.layer_image(fr[idx], place, pal))
				h.frames.append(cache[idx])
			if not h.frames.is_empty():
				var o := _picture()
				_sprites.add_child(o)
				h.overlay = o
		_hotspots.append(h)
	if OS.is_debug_build():
		print("BASE screen=%d stage=%d hotspots=%s" % [id, campaign.stage, _hotspots.map(func(x): return "%s%s" % [x.label, "*" if x.node else ""])])


func _process(dt: float) -> void:
	_anim_t += dt
	var step := int(_anim_t * 8.0)
	for h in _hotspots:
		if h.overlay != null:
			h.overlay.texture = h.frames[step % h.frames.size()]

	# Auto-activate hotspots only for unattended testing: headless runs or an
	# explicit --autoplay flag. An interactive campaign start (--auto=campaign
	# with a window) must wait for the player to click the hotspots.
	var is_auto := DisplayServer.get_name() == "headless" or OS.get_cmdline_user_args().has("--autoplay")
	if is_auto and not _auto_activated:
		print("BASE _process: checking auto-activate, hotspots=%d" % _hotspots.size())
		print("BASE: AUTO-ACTIVATE BLOCK ENTERED, _auto_activated was=%s" % _auto_activated)
		if not _auto_activated:
			_auto_activated = true
			print("BASE: _auto_activated set to true, entering priority loop")
			# Priority order: Transport > Fly Mission > Conversation > Other
			var priority_order := ["Transport", "Fly", "Talk", "Enter", "Look", "Return"]
			var best_hotspot := {}
			var best_priority := priority_order.size()
			print("BASE: PRIORITY LOOP START, hotspots=%d" % _hotspots.size())
			
			# Get visited hotspots for this screen
			var visited: Array = _visited_hotspots.get(campaign.screen, [])
			
			for h in _hotspots:
				print("BASE: checking hotspot '%s', gf=%s, available=%s" % [h.label, h.gf, campaign.available(h.gf) if h.gf else 'no gf'])
				if not h.gf or not campaign.available(h.gf):
					continue
				# Skip already-tried hotspots on this screen
				if h.label in visited:
					print("BASE: skipping already-visited hotspot '%s'" % h.label)
					continue
				var label: String = h.label
				var priority := priority_order.size()
				for i in range(priority_order.size()):
					if label.contains(priority_order[i]):
						priority = i
						break
				print("BASE: hotspot '%s' priority=%d" % [label, priority])
				if priority < best_priority:
					best_priority = priority
					best_hotspot = h
			
			if best_hotspot:
				print("BASE: auto-activating hotspot %s (priority %d)" % [best_hotspot.label, best_priority])
				# Mark as visited
				if not _visited_hotspots.has(campaign.screen):
					_visited_hotspots[campaign.screen] = []
				_visited_hotspots[campaign.screen].append(best_hotspot.label)
				_activate(_hotspots.find(best_hotspot))
			elif _hotspots.size() > 0:
				# Fallback: first available non-visited hotspot
				for h in _hotspots:
					if h.gf and campaign.available(h.gf):
						var seen: Array = _visited_hotspots.get(campaign.screen, [])
						if h.label in seen:
							continue
						print("BASE: auto-activating fallback hotspot %s" % h.label)
						if not _visited_hotspots.has(campaign.screen):
							_visited_hotspots[campaign.screen] = []
						_visited_hotspots[campaign.screen].append(h.label)
						_activate(_hotspots.find(h))
						break

# --- input -------------------------------------------------------------------------

func _to_screen(p: Vector2) -> Vector2i:
	var sz := _stage.size
	return Vector2i(int(p.x / sz.x * 320.0), int(p.y / sz.y * 200.0))


func _stage_input(event: InputEvent) -> void:
	if campaign.busy:
		return
	if event is InputEventMouseMotion:
		var p := _to_screen(event.position)
		var hit := -1
		for k in range(_hotspots.size()):
			if _hotspots[k].rect.has_point(p):
				hit = k
		_set_focus(hit)
	elif event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT:
		if _focus >= 0:
			_activate(_focus)


func _unhandled_input(event: InputEvent) -> void:
	if campaign.busy:
		return
	if event.is_action_pressed("ui_focus_next") or event.is_action_pressed("ui_right") or event.is_action_pressed("ui_down"):
		_set_focus((_focus + 1) % maxi(1, _hotspots.size()))
	elif event.is_action_pressed("ui_focus_prev") or event.is_action_pressed("ui_left") or event.is_action_pressed("ui_up"):
		_set_focus((_focus - 1 + _hotspots.size()) % maxi(1, _hotspots.size()))
	elif event.is_action_pressed("ui_accept") and _focus >= 0:
		_activate(_focus)
	elif event.is_action_pressed("pause"):
		campaign.save()
		quit_requested.emit()
	else:
		return
	get_viewport().set_input_as_handled()


func _set_focus(k: int) -> void:
	_focus = k if k < _hotspots.size() else -1
	if _focus < 0:
		_highlight.visible = false
		_label.text = ""
		return
	var r: Rect2i = _hotspots[_focus].rect
	var sc := _stage.size / Vector2(320, 200)
	_highlight.position = Vector2(r.position) * sc
	_highlight.size = Vector2(r.size) * sc
	_highlight.visible = true
	_label.text = _hotspots[_focus].label


func _activate(k: int) -> void:
	var gs = _hotspots[k].gf
	_set_focus(-1)
	await campaign.activate(gs)
	if is_inside_tree() and campaign.screen >= 0:
		_build_screen(campaign.screen)


# --- host interface for the campaign --------------------------------------------------

## Returns { accepted } (the yes / no answer, read by effects 14 / 15).
func play_conversation(n: int) -> Dictionary:
	var p = ConversationPlayer.new()
	p.campaign = campaign
	p.conv_index = n
	add_child(p)
	var r: Dictionary = await p.play()
	p.queue_free()
	return r


## Establishing shot n (gameflow effect 08): a short animated scene from
## OPTIONS.IFF (FORM ESTB / SHOT), played from its recorded timeline.
func play_cutscene(n: int) -> void:
	if not CutsceneVM.has_timeline("est%d" % n):
		await get_tree().process_frame
		return
	var v = CutsceneVM.new()
	v.file = "est%d" % n
	add_child(v)
	await v.play()
	v.queue_free()


## Story cut-scene MIDn with its recorded speech.
func play_story(n: int) -> void:
	# Original staging recorded from OPTTEST.EXE when available.
	if CutsceneVM.exists(n):
		var v = CutsceneVM.new()
		v.number = n
		add_child(v)
		await v.play()
		v.queue_free()
		return
	if not Midgame.exists(n):
		return
	var p = CutscenePlayer.new()
	p.number = n
	add_child(p)
	await p.play()
	p.queue_free()


## Transport between bases (effect 12 n): the original route animation on the
## world map, played from its recorded timeline.
func play_transport(n: int) -> void:
	if not CutsceneVM.has_timeline("trans%d" % n):
		toast("Transport %d is not recorded." % n)
		return
	var v = CutsceneVM.new()
	v.file = "trans%d" % n
	add_child(v)
	await v.play()
	v.queue_free()


func fly_mission(n: int) -> bool:
	var files: Array = campaign.mission_files()
	if n < 0 or n >= files.size():
		toast("Mission %d is not available." % n)
		return true
	
	_pending_mission_file = files[n]
	
	# Automated runs (headless testing or --autopilot) skip the interactive
	# loadout screen and fly with the aircraft's default weapons. Interactive
	# play shows the weapon-loading screen after the briefing, as in the
	# original game.
	var automated := DisplayServer.get_name() == "headless" \
		or OS.get_cmdline_user_args().has("--autopilot")
	if automated:
		campaign._pending_loadout = null
	else:
		_show_loadout_screen(files[n])
		var went: bool = await _loadout_done
		if not went:
			# The player backed out of the loadout screen: the mission is not flown.
			return true
		campaign._pending_loadout = _selected_loadout
	
	# Fly the mission and wait for it to finish before continuing the campaign.
	fly_requested.emit(_pending_mission_file)
	_pending_mission_file = ""
	var ok: bool = await flight_done
	return ok


func _show_loadout_screen(mission_file: String) -> void:
	# Get mission data to determine aircraft
	var mission = SCData.mission(mission_file)
	var plane_model: String = "OBJECTS/F-16DES.IFF"
	if mission != null:
		var pp = mission.player_part()
		if pp != null:
			plane_model = "OBJECTS/%s.IFF" % pp.model
	
	# Build inventory from campaign (simplified - in full game this would come from ledger)
	var inventory: Dictionary = _build_inventory()
	
	_loadout_screen = LoadoutScreen.new()
	_loadout_screen.setup_for_mission(campaign, plane_model, inventory)
	_loadout_screen.fly_requested.connect(_on_loadout_fly_requested)
	_loadout_screen.back_requested.connect(_on_loadout_back_requested)
	add_child(_loadout_screen)
	
	# Hide base screen while loadout is shown
	_stage.visible = false
	_label.visible = false
	_highlight.visible = false


func _on_loadout_fly_requested(loadout: Dictionary) -> void:
	# Store the chosen loadout; fly_mission() reads it and starts the flight.
	_selected_loadout = loadout
	_loadout_screen.queue_free()
	_loadout_screen = null
	_stage.visible = true
	_label.visible = true
	_loadout_done.emit(true)


func _on_loadout_back_requested() -> void:
	_loadout_screen.queue_free()
	_loadout_screen = null
	_stage.visible = true
	_label.visible = true
	_selected_loadout = {}
	# Signal that we're back (mission not flown)
	_loadout_done.emit(false)


func _build_inventory() -> Dictionary:
	# Simplified inventory - in full game this reads from campaign ledger
	# For now, return generous amounts of all weapons
	var inv := {}
	var model_data = SCData.model("OBJECTS/F-16DES.IFF")
	if model_data != null:
		var default_loadout = Weapons.loadout(model_data)
		for wname in default_loadout:
			inv[wname] = int(default_loadout[wname]) * 3  # 3x the default loadout
	# Add all weapon types
	for wname in ["SWINDERM", "SWINDERJ", "AMRAAM", "AGM-65D", "MK82", "MK20", "DURANDAL"]:
		if not inv.has(wname):
			inv[wname] = 12
	return inv


## Demo build: shown after the first mission has been flown successfully.
func end_demo() -> void:
	campaign.save()
	var dim := ColorRect.new()
	dim.color = Color(0, 0, 0, 0.82)
	dim.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	dim.mouse_filter = Control.MOUSE_FILTER_STOP
	add_child(dim)
	var center := CenterContainer.new()
	center.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	dim.add_child(center)
	var panel := PanelContainer.new()
	center.add_child(panel)
	var box := VBoxContainer.new()
	box.custom_minimum_size = Vector2(560, 0)
	box.add_theme_constant_override("separation", 14)
	panel.add_child(box)
	box.add_child(UiTheme.title_label("END OF DEMO", 36))
	var text := Label.new()
	text.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	text.text = "Mission accomplished, %s. That concludes the demo of Strike Commander Reforged.\n\nThe full game continues the Wildcats' campaign from here." % campaign.names.get("N", "Commander")
	box.add_child(text)
	var back := Button.new()
	back.text = "Main menu"
	back.pressed.connect(func(): quit_requested.emit())
	box.add_child(back)
	back.grab_focus()
