## Shown when the original game cannot be found. The engine refuses to run
## without the user's own copy of Strike Commander CD-ROM Edition.
extends Control

const UiTheme = preload("res://scripts/ui/ui_theme.gd")

signal mounted

var _path: LineEdit
var _status: Label
var _dialog: FileDialog


func _ready() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	var bg := ColorRect.new()
	bg.color = Color(0.03, 0.035, 0.05)
	bg.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(bg)

	var center := CenterContainer.new()
	center.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(center)
	var panel := PanelContainer.new()
	panel.custom_minimum_size = Vector2(760, 0)
	center.add_child(panel)
	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 14)
	panel.add_child(box)

	box.add_child(UiTheme.title_label("Strike Commander Reforged", 34))
	var info := Label.new()
	info.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	info.text = "This engine requires the original Strike Commander CD-ROM Edition " + \
		"(e.g. the GOG release). No game content is included – graphics, models and terrain " + \
		"are read directly from your own installation.\n\nSelect the folder that contains SC.dat and LILTRE.TRE."
	box.add_child(info)

	var row := HBoxContainer.new()
	box.add_child(row)
	_path = LineEdit.new()
	_path.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_path.text = Settings.get_value("data", "game_dir", "C:/Gog games/Strike Commander")
	row.add_child(_path)
	var browse := Button.new()
	browse.text = "Browse…"
	browse.pressed.connect(func(): _dialog.popup_centered_ratio(0.6))
	row.add_child(browse)

	var ok := Button.new()
	ok.text = "Use this installation"
	ok.pressed.connect(_try_mount)
	box.add_child(ok)
	_status = Label.new()
	_status.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_status.add_theme_color_override("font_color", Color(1, 0.45, 0.35))
	box.add_child(_status)

	_dialog = FileDialog.new()
	_dialog.file_mode = FileDialog.FILE_MODE_OPEN_DIR
	_dialog.access = FileDialog.ACCESS_FILESYSTEM
	_dialog.use_native_dialog = true
	_dialog.dir_selected.connect(func(d): _path.text = d; _try_mount())
	add_child(_dialog)


func _try_mount() -> void:
	var err: String = SCData.mount(_path.text.strip_edges())
	if err == "":
		mounted.emit()
	else:
		_status.text = err
