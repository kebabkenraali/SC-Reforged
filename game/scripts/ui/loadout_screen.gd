## Weapon loadout screen – shown after briefing, before flying a mission.
## Lets the player customize the aircraft's weapons (pairs on hardpoints).
## Based on the original Strike Commander weapon loading screen.
extends Control

const Art = preload("res://scripts/core/art.gd")
const Shape = preload("res://scripts/formats/sc_shape.gd")
const Weapons = preload("res://scripts/game/weapons.gd")
const UiTheme = preload("res://scripts/ui/ui_theme.gd")
# SCData and Settings are autoload singletons (see project.godot); do not preload them.

signal fly_requested(loadout: Dictionary)
signal back_requested

var campaign
var plane_model: String = "OBJECTS/F-16DES.IFF"
var _loadout: Dictionary = {}
var _available: Dictionary = {}
var _hardpoints: Array = []
var _profile := "f16"

const HARDPOINTS_F16 := [
	{"type": "tip", "side": -1, "pos": Vector2(-120, -40), "max": 1, "weapons": ["SWINDERM", "SWINDERJ", "AMRAAM"]},
	{"type": "tip", "side": 1, "pos": Vector2(120, -40), "max": 1, "weapons": ["SWINDERM", "SWINDERJ", "AMRAAM"]},
	{"type": "wing", "side": -1, "pos": Vector2(-80, 20), "max": 2, "weapons": ["SWINDERM", "SWINDERJ", "AMRAAM", "AGM-65D", "MK82", "MK20", "DURANDAL"]},
	{"type": "wing", "side": 1, "pos": Vector2(80, 20), "max": 2, "weapons": ["SWINDERM", "SWINDERJ", "AMRAAM", "AGM-65D", "MK82", "MK20", "DURANDAL"]},
	{"type": "center", "side": 0, "pos": Vector2(0, 50), "max": 1, "weapons": ["AGM-65D", "MK82", "MK20", "DURANDAL", "FUEL_TANK"]},
	{"type": "gun", "side": 0, "pos": Vector2(0, -10), "max": 1, "weapons": ["VULCAN"]},
]

## The original loadout screen is specific to the aircraft. The F-16 layout is
## decoded from the game; the other profiles keep the same station layout with
## the hardpoints that aircraft actually carries.
const HARDPOINTS := {
	"f16": HARDPOINTS_F16,
	"mig29": [
		{"type": "tip", "side": -1, "pos": Vector2(-110, -40), "max": 1, "weapons": ["SWINDERM", "AMRAAM"]},
		{"type": "tip", "side": 1, "pos": Vector2(110, -40), "max": 1, "weapons": ["SWINDERM", "AMRAAM"]},
		{"type": "wing", "side": -1, "pos": Vector2(-75, 20), "max": 2, "weapons": ["SWINDERM", "SWINDERJ", "AGM-65D", "MK82"]},
		{"type": "wing", "side": 1, "pos": Vector2(75, 20), "max": 2, "weapons": ["SWINDERM", "SWINDERJ", "AGM-65D", "MK82"]},
		{"type": "gun", "side": 0, "pos": Vector2(0, -10), "max": 1, "weapons": ["VULCAN"]},
	],
	"mig21": [
		{"type": "wing", "side": -1, "pos": Vector2(-70, 15), "max": 1, "weapons": ["SWINDERJ", "MK82"]},
		{"type": "wing", "side": 1, "pos": Vector2(70, 15), "max": 1, "weapons": ["SWINDERJ", "MK82"]},
		{"type": "gun", "side": 0, "pos": Vector2(0, -10), "max": 1, "weapons": ["VULCAN"]},
	],
}

## Original weapon-loading screen (OPTIONS.IFF screen 15). Its background is
## the only picture on this screen - no model-asset aircraft is drawn over it.
const LOADOUT_SCREEN_ID := 15

const RACK_CATEGORIES := [
	{"name": "air", "label": "AIR-TO-AIR", "weapons": ["SWINDERM", "SWINDERJ", "AMRAAM"], "color": Color(0.3, 0.7, 1.0)},
	{"name": "agm", "label": "AIR-TO-GROUND", "weapons": ["AGM-65D"], "color": Color(1.0, 0.6, 0.2)},
	{"name": "bomb", "label": "BOMBS", "weapons": ["MK82", "MK20", "DURANDAL"], "color": Color(0.8, 0.3, 0.3)},
	{"name": "gun", "label": "GUN", "weapons": ["VULCAN"], "color": Color(0.7, 0.7, 0.7)},
]

func _ready() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	
	var bg := ColorRect.new()
	bg.color = Color(0.02, 0.025, 0.04)
	bg.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(bg)
	
	_build_original_background()
	
	var margin := MarginContainer.new()
	margin.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	for side in ["left", "top", "right", "bottom"]:
		margin.add_theme_constant_override("margin_" + side, 20)
	add_child(margin)
	
	var hbox := HBoxContainer.new()
	hbox.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	margin.add_child(hbox)
	
	var left_panel := VBoxContainer.new()
	left_panel.custom_minimum_size = Vector2(280, 0)
	left_panel.size_flags_horizontal = Control.SIZE_SHRINK_BEGIN
	left_panel.add_theme_constant_override("separation", 10)
	hbox.add_child(left_panel)
	
	left_panel.add_child(UiTheme.title_label("ORDNANCE", 24))
	var sub := Label.new()
	sub.text = "Left-click a weapon to load a pair, right-click to unload it. The gun is always available."
	sub.add_theme_font_size_override("font_size", 12)
	sub.add_theme_color_override("font_color", Color(0.7, 0.7, 0.65))
	sub.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	left_panel.add_child(sub)
	left_panel.add_child(HSeparator.new())
	
	_build_racks(left_panel)
	
	var right_panel := VBoxContainer.new()
	right_panel.custom_minimum_size = Vector2(260, 0)
	right_panel.size_flags_horizontal = Control.SIZE_SHRINK_END
	right_panel.add_theme_constant_override("separation", 10)
	hbox.add_child(right_panel)
	
	right_panel.add_child(UiTheme.title_label("LOADOUT", 24))
	right_panel.add_child(HSeparator.new())
	
	var info_label := Label.new()
	info_label.name = "info_label"
	info_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	info_label.add_theme_font_size_override("font_size", 14)
	right_panel.add_child(info_label)
	
	var inv_label := Label.new()
	inv_label.text = "INVENTORY"
	inv_label.add_theme_font_size_override("font_size", 16)
	inv_label.add_theme_color_override("font_color", UiTheme.ACCENT)
	right_panel.add_child(inv_label)
	right_panel.add_child(HSeparator.new())
	
	var inv_list := VBoxContainer.new()
	inv_list.name = "inv_list"
	right_panel.add_child(inv_list)
	
	right_panel.add_child(Control.new())
	
	var btn_box := HBoxContainer.new()
	btn_box.add_theme_constant_override("separation", 20)
	btn_box.alignment = HBoxContainer.ALIGNMENT_CENTER
	right_panel.add_child(btn_box)
	
	var back_btn := Button.new()
	back_btn.text = "Hangar Doorway (Back)"
	back_btn.custom_minimum_size = Vector2(200, 40)
	back_btn.pressed.connect(back_requested.emit)
	btn_box.add_child(back_btn)
	
	var fly_btn := Button.new()
	fly_btn.text = "Select Cockpit (Fly)"
	fly_btn.custom_minimum_size = Vector2(200, 40)
	fly_btn.add_theme_color_override("font_color", Color(0.3, 1.0, 0.3))
	fly_btn.pressed.connect(_on_fly_pressed)
	btn_box.add_child(fly_btn)
	
	_refresh_loadout()
	_refresh_inventory_display()


## Draws the original 320x200 weapon-loading screen art (shape 91 of
## OPTSHPS.PAK) behind the 3D aircraft, using the same palette-index layering
## as the base screens. Missing original data leaves the dark fallback intact.
func _build_original_background() -> void:
	var gf = Art.gameflow()
	var s = gf.screens.get(LOADOUT_SCREEN_ID)
	if s == null or s.back_shapes.is_empty():
		return
	var pal: PackedColorArray = Art.palette("opt", s.back_pals + [s.fore_pal])
	var canvas := Art.new_canvas()
	for shp in s.back_shapes:
		var fr: Array = Art.frames("opt", shp)
		if not fr.is_empty():
			Art.blit(canvas, fr[0], Vector2i.ZERO)
	var rect := TextureRect.new()
	rect.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	rect.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	rect.stretch_mode = TextureRect.STRETCH_SCALE
	rect.mouse_filter = Control.MOUSE_FILTER_IGNORE
	rect.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	rect.texture = ImageTexture.create_from_image(Art.canvas_image(canvas, pal))
	add_child(rect)


func _build_racks(parent: VBoxContainer) -> void:
	var scroll := ScrollContainer.new()
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	parent.add_child(scroll)
	
	var vbox := VBoxContainer.new()
	vbox.add_theme_constant_override("separation", 8)
	scroll.add_child(vbox)
	
	for cat in RACK_CATEGORIES:
		var cat_box := VBoxContainer.new()
		cat_box.add_theme_constant_override("separation", 4)
		vbox.add_child(cat_box)
		
		var hdr := HBoxContainer.new()
		cat_box.add_child(hdr)
		var color_rect := ColorRect.new()
		color_rect.color = cat.color
		color_rect.custom_minimum_size = Vector2(12, 12)
		hdr.add_child(color_rect)
		var lbl := Label.new()
		lbl.text = cat.label
		lbl.add_theme_font_size_override("font_size", 14)
		lbl.add_theme_color_override("font_color", cat.color)
		lbl.custom_minimum_size = Vector2(180, 0)
		hdr.add_child(lbl)
		
		var count_lbl := Label.new()
		count_lbl.name = "count"
		count_lbl.add_theme_font_size_override("font_size", 12)
		count_lbl.add_theme_color_override("font_color", Color(0.7, 0.7, 0.7))
		count_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
		count_lbl.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		hdr.add_child(count_lbl)
		
		for wname in cat.weapons:
			var btn := Button.new()
			btn.text = Weapons.label(wname)
			btn.set_meta("base_text", btn.text)
			btn.tooltip_text = wname
			btn.name = wname
			btn.custom_minimum_size = Vector2(0, 32)
			btn.size_flags_horizontal = Control.SIZE_EXPAND_FILL
			
			if cat.name == "air":
				btn.add_theme_color_override("font_color", Color(0.4, 0.8, 1.0))
			elif cat.name == "agm":
				btn.add_theme_color_override("font_color", Color(1.0, 0.7, 0.3))
			elif cat.name == "bomb":
				btn.add_theme_color_override("font_color", Color(0.9, 0.4, 0.4))
			else:
				btn.add_theme_color_override("font_color", Color(0.8, 0.8, 0.8))
			
			btn.gui_input.connect(func(e): _on_rack_gui_input(e, wname, cat.name))
			cat_box.add_child(btn)
func _on_rack_gui_input(event: InputEvent, wname: String, cat: String) -> void:
	if event is InputEventMouseButton and event.pressed:
		if event.button_index == MOUSE_BUTTON_LEFT:
			_try_add_weapon(wname, cat)
		elif event.button_index == MOUSE_BUTTON_RIGHT:
			_try_remove_weapon(wname, cat)


func _try_add_weapon(wname: String, _cat: String) -> void:
	var avail: int = _available.get(wname, 0)
	if avail < 2:
		_show_toast("Not enough %s in inventory (need 2, have %d)" % [Weapons.label(wname), avail])
		return
	# A pair may be split over two single-slot stations (the wingtips), so
	# count free slots across all compatible hardpoints instead of requiring
	# one station with room for two.
	if _free_slots(wname) < 2:
		_show_toast("No free hardpoint for %s - right-click a weapon to unload it first" % Weapons.label(wname))
		return
	_loadout[wname] = _loadout.get(wname, 0) + 2
	_available[wname] = avail - 2
	_refresh_loadout()
	_refresh_inventory_display()


func _try_remove_weapon(wname: String, _cat: String) -> void:
	var current: int = _loadout.get(wname, 0)
	if current < 2:
		_show_toast("No %s loaded to remove" % Weapons.label(wname))
		return
	_loadout[wname] = current - 2
	if _loadout[wname] == 0:
		_loadout.erase(wname)
	_available[wname] = _available.get(wname, 0) + 2
	_refresh_loadout()
	_refresh_inventory_display()


## Total free slots for `wname` over all compatible hardpoints.
func _free_slots(wname: String) -> int:
	var free := 0
	for hp in _hardpoints:
		if wname in hp.weapons:
			free += maxi(0, int(hp.max) - int(hp.used))
	return free


func _refresh_loadout() -> void:
	_hardpoints.clear()
	var hp_defs: Array = HARDPOINTS.get(_profile, HARDPOINTS_F16)
	
	for hpd in hp_defs:
		var hp: Dictionary = (hpd as Dictionary).duplicate()
		hp.used = 0
		_hardpoints.append(hp)
	
	for wname in _loadout:
		var remaining: int = int(_loadout[wname])
		for hp in _hardpoints:
			if remaining <= 0:
				break
			if wname in hp.weapons:
				var can_take: int = min(remaining, int(hp.max) - int(hp.used))
				if can_take > 0:
					hp.used += can_take
					remaining -= can_take
	
	# Show the loaded count on each rack button so the selection is visible.
	for cat in RACK_CATEGORIES:
		for wname in cat.weapons:
			var btn := find_child(wname, true, false) as Button
			if btn:
				var base: String = btn.get_meta("base_text", btn.text)
				btn.set_meta("base_text", base)
				var n: int = int(_loadout.get(wname, 0))
				btn.text = base if n == 0 else "%s  x%d" % [base, n]


func _refresh_inventory_display() -> void:
	var inv_list := find_child("inv_list", true, false)
	if not inv_list:
		return
	
	for c in inv_list.get_children():
		c.queue_free()
	
	var total_items := 0
	for wname in _available:
		var count: int = int(_available[wname])
		if count > 0:
			var row := HBoxContainer.new()
			inv_list.add_child(row)
			
			var lbl := Label.new()
			lbl.text = "%s x%d" % [Weapons.label(wname), count]
			lbl.add_theme_font_size_override("font_size", 13)
			lbl.size_flags_horizontal = Control.SIZE_EXPAND_FILL
			row.add_child(lbl)
			total_items += 1
	
	if total_items == 0:
		var empty := Label.new()
		empty.text = "(empty)"
		empty.add_theme_font_size_override("font_size", 13)
		empty.add_theme_color_override("font_color", Color(0.5, 0.5, 0.5))
		inv_list.add_child(empty)


func _get_aircraft_profile() -> String:
	var n := plane_model.to_upper()
	if n.contains("MIG29"):
		return "mig29"
	if n.contains("MIG21"):
		return "mig21"
	if n.contains("F-16") or n.contains("F16"):
		return "f16"
	return "f16"


func _on_fly_pressed() -> void:
	# Gun-only is a valid loadout: the player decides what to carry.
	var final_loadout := _loadout.duplicate()
	final_loadout["VULCAN"] = 1000
	
	fly_requested.emit(final_loadout)


func _show_toast(msg: String) -> void:
	var info_label := find_child("info_label", true, false)
	if info_label:
		info_label.text = msg
		info_label.add_theme_color_override("font_color", Color(1.0, 0.4, 0.3))
		var tween := create_tween()
		tween.set_parallel(true)
		tween.tween_property(info_label, "modulate:a", 0.0, 2.0).set_delay(2.0)
		tween.finished.connect(func(): info_label.modulate = Color(1,1,1,1))


func setup_for_mission(camp: Object, model: String, inventory: Dictionary) -> void:
	campaign = camp
	plane_model = model
	_profile = _get_aircraft_profile()
	_available = inventory.duplicate()
	# Start empty: a pre-filled default filled every station, so no weapon
	# could ever be added and the player could not change the configuration.
	_loadout = {}
	_refresh_loadout()
	_refresh_inventory_display()


func get_loadout() -> Dictionary:
	return _loadout.duplicate()
