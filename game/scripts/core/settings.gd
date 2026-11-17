## Autoload "Settings": persistent options (user://settings.cfg) and the
## rebindable input map. Keyboard, mouse and gamepad/HOTAS are all supported.
extends Node

const PATH := "user://settings.cfg"

signal changed

## action -> [display name, default events]
var ACTIONS := {
	"pitch_up": ["Pitch up", [_key(KEY_S), _key(KEY_DOWN), _axis(JOY_AXIS_LEFT_Y, 1.0)]],
	"pitch_down": ["Pitch down", [_key(KEY_W), _key(KEY_UP), _axis(JOY_AXIS_LEFT_Y, -1.0)]],
	"roll_left": ["Roll left", [_key(KEY_A), _key(KEY_LEFT), _axis(JOY_AXIS_LEFT_X, -1.0)]],
	"roll_right": ["Roll right", [_key(KEY_D), _key(KEY_RIGHT), _axis(JOY_AXIS_LEFT_X, 1.0)]],
	"yaw_left": ["Rudder left", [_key(KEY_Q), _axis(JOY_AXIS_RIGHT_X, -1.0)]],
	"yaw_right": ["Rudder right", [_key(KEY_E), _axis(JOY_AXIS_RIGHT_X, 1.0)]],
	"throttle_up": ["Throttle up", [_key(KEY_SHIFT), _key(KEY_EQUAL), _axis(JOY_AXIS_TRIGGER_RIGHT, 1.0)]],
	"throttle_down": ["Throttle down", [_key(KEY_CTRL), _key(KEY_MINUS), _axis(JOY_AXIS_TRIGGER_LEFT, 1.0)]],
	"afterburner": ["Afterburner", [_key(KEY_TAB), _button(JOY_BUTTON_RIGHT_SHOULDER)]],
	"fire": ["Gun", [_key(KEY_SPACE), _mouse(MOUSE_BUTTON_LEFT), _button(JOY_BUTTON_A)]],
	"weapon_select": ["Select weapon (air/AGM/bomb)", [_key(KEY_V), _button(JOY_BUTTON_DPAD_UP)]],
	"missile": ["Release weapon", [_key(KEY_R), _button(JOY_BUTTON_LEFT_SHOULDER)]],
	"countermeasure": ["Countermeasures", [_key(KEY_F), _button(JOY_BUTTON_B)]],
	"camera_cycle": ["Change camera", [_key(KEY_C), _button(JOY_BUTTON_Y)]],
	"brakes": ["Brakes", [_key(KEY_B), _button(JOY_BUTTON_X)]],
	"pause": ["Pause / menu", [_key(KEY_ESCAPE), _button(JOY_BUTTON_START)]],
	"screenshot": ["Screenshot", [_key(KEY_F12)]],
	"autopilot_waypoint": ["Autopilot: follow waypoints (F5)", [_key(KEY_F5), _button(JOY_BUTTON_DPAD_LEFT)]],
	"autopilot_land": ["Autopilot: land at base (F6)", [_key(KEY_F6), _button(JOY_BUTTON_DPAD_RIGHT)]],
	"next_waypoint": ["Fast travel to waypoint (F7)", [_key(KEY_F7), _button(JOY_BUTTON_RIGHT_STICK)]],
	"autopilot_combat": ["AI pilot: fly & fight (F8)", [_key(KEY_F8), _button(JOY_BUTTON_LEFT_STICK)]],
	"auto_land": ["Auto-landing at base (L)", [_key(KEY_L)]],
}

var _cfg := ConfigFile.new()

const DEFAULTS := {
	"video": {"fullscreen": false, "vsync": true, "msaa": 2, "render_scale": 1.0,
		"fov": 70.0, "shadows": true, "smooth_textures": true, "fog": true, "ssao": false, "modern_models": false},
	"controls": {"invert_pitch": false, "mouse_flight": false, "mouse_sensitivity": 1.0,
		"deadzone": 0.12},
	"audio": {"volume": 0.8, "subtitles": true, "music_on": true, "music": 0.6},
	"data": {"game_dir": ""},
}


func _ready() -> void:
	_cfg.load(PATH)
	_apply_input_map()
	apply_video()


func get_value(section: String, key: String, fallback = null):
	var def = DEFAULTS.get(section, {}).get(key, fallback)
	if not _cfg.has_section_key(section, key):
		return def
	return _cfg.get_value(section, key)


func set_value(section: String, key: String, value) -> void:
	_cfg.set_value(section, key, value)
	_cfg.save(PATH)
	if section == "video":
		apply_video()
	if section == "controls" and key == "deadzone":
		_apply_input_map()
	changed.emit()


func apply_video() -> void:
	var win := get_window()
	if win == null:
		return
	var fs: bool = get_value("video", "fullscreen")
	var mode := DisplayServer.WINDOW_MODE_EXCLUSIVE_FULLSCREEN if fs else DisplayServer.WINDOW_MODE_WINDOWED
	if DisplayServer.window_get_mode() != mode and DisplayServer.get_name() != "headless":
		DisplayServer.window_set_mode(mode)
	DisplayServer.window_set_vsync_mode(
		DisplayServer.VSYNC_ENABLED if get_value("video", "vsync") else DisplayServer.VSYNC_DISABLED)
	var vp := get_viewport()
	vp.msaa_3d = int(get_value("video", "msaa")) as Viewport.MSAA
	var scale: float = get_value("video", "render_scale")
	vp.scaling_3d_mode = Viewport.SCALING_3D_MODE_FSR2 if scale < 0.99 else Viewport.SCALING_3D_MODE_BILINEAR
	vp.scaling_3d_scale = scale


# --- input map -------------------------------------------------------------

func _apply_input_map() -> void:
	var dz: float = get_value("controls", "deadzone")
	for action in ACTIONS:
		if InputMap.has_action(action):
			InputMap.erase_action(action)
		InputMap.add_action(action, dz)
		var saved = _cfg.get_value("input", action) if _cfg.has_section_key("input", action) else null
		var events: Array = saved if saved is Array else ACTIONS[action][1]
		for ev in events:
			if ev is InputEvent:
				InputMap.action_add_event(action, ev)


func action_events(action: String) -> Array:
	return InputMap.action_get_events(action)


## Replaces the primary binding of `action` for the device class of `event`.
func rebind(action: String, event: InputEvent) -> void:
	var events := InputMap.action_get_events(action)
	var kept := events.filter(func(e): return not _same_device(e, event))
	kept.push_front(event)
	_cfg.set_value("input", action, kept)
	_cfg.save(PATH)
	_apply_input_map()
	changed.emit()


func reset_bindings() -> void:
	if _cfg.has_section("input"):
		_cfg.erase_section("input")
	_cfg.save(PATH)
	_apply_input_map()
	changed.emit()


static func describe(ev: InputEvent) -> String:
	if ev is InputEventKey:
		return OS.get_keycode_string(ev.physical_keycode if ev.keycode == 0 else ev.keycode)
	if ev is InputEventMouseButton:
		return "Mouse %d" % ev.button_index
	if ev is InputEventJoypadButton:
		return "Pad button %d" % ev.button_index
	if ev is InputEventJoypadMotion:
		return "Pad axis %d%s" % [ev.axis, "+" if ev.axis_value > 0 else "-"]
	return ev.as_text()


static func _same_device(a: InputEvent, b: InputEvent) -> bool:
	var ka := a is InputEventKey or a is InputEventMouseButton
	var kb := b is InputEventKey or b is InputEventMouseButton
	return ka == kb


static func _key(k: Key) -> InputEventKey:
	var e := InputEventKey.new()
	e.physical_keycode = k
	return e


static func _mouse(b: MouseButton) -> InputEventMouseButton:
	var e := InputEventMouseButton.new()
	e.button_index = b
	return e


static func _button(b: JoyButton) -> InputEventJoypadButton:
	var e := InputEventJoypadButton.new()
	e.button_index = b
	e.device = -1
	return e


static func _axis(a: JoyAxis, v: float) -> InputEventJoypadMotion:
	var e := InputEventJoypadMotion.new()
	e.axis = a
	e.axis_value = v
	e.device = -1
	return e
