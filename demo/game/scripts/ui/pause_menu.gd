## In-flight pause menu with access to settings.
extends Control

const UiTheme = preload("res://scripts/ui/ui_theme.gd")
const SettingsMenu = preload("res://scripts/ui/settings_menu.gd")

signal resume
signal quit_to_menu


func _ready() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	var dim := ColorRect.new()
	dim.color = Color(0, 0, 0, 0.5)
	dim.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(dim)
	var center := CenterContainer.new()
	center.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(center)
	var panel := PanelContainer.new()
	center.add_child(panel)
	var box := VBoxContainer.new()
	box.custom_minimum_size = Vector2(360, 0)
	box.add_theme_constant_override("separation", 10)
	panel.add_child(box)
	box.add_child(UiTheme.title_label("Paused", 32))
	for entry in [["Resume", func(): resume.emit()],
			["Options", _open_settings],
			["Main menu", func(): quit_to_menu.emit()]]:
		var b := Button.new()
		b.text = entry[0]
		b.pressed.connect(entry[1])
		box.add_child(b)


func _open_settings() -> void:
	var s = SettingsMenu.new()
	s.process_mode = Node.PROCESS_MODE_WHEN_PAUSED
	add_child(s)
