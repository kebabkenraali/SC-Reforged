## Mission debrief: result, objectives (route), statistics and what happened
## to the flight. Shown when the player lands, is shot down or quits a mission.
extends Control

const UiTheme = preload("res://scripts/ui/ui_theme.gd")

signal fly_again
signal main_menu

## { result: "success" | "incomplete" | "failed", reason, mission, file,
##   waypoints: [{ name, reached }], stats: [[label, value]], log: [String] }
var report := {}
var campaign_mode := false


func _ready() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_STOP
	var dim := ColorRect.new()
	dim.color = Color(0.02, 0.025, 0.035, 0.82)
	dim.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(dim)
	var center := CenterContainer.new()
	center.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(center)
	var panel := PanelContainer.new()
	panel.custom_minimum_size = Vector2(900, 0)
	center.add_child(panel)
	var root := VBoxContainer.new()
	root.add_theme_constant_override("separation", 14)
	panel.add_child(root)

	var colors := {"success": Color(0.4, 1.0, 0.5), "incomplete": UiTheme.ACCENT, "failed": Color(1.0, 0.35, 0.3)}
	var titles := {"success": "MISSION ACCOMPLISHED", "incomplete": "MISSION INCOMPLETE", "failed": "MISSION FAILED"}
	var result: String = report.get("result", "incomplete")
	var title := UiTheme.title_label(titles.get(result, "DEBRIEF"), 38)
	title.add_theme_color_override("font_color", colors.get(result, UiTheme.ACCENT))
	root.add_child(title)
	var sub := Label.new()
	sub.text = "%s  (%s)\n%s" % [report.get("mission", ""), report.get("file", ""), report.get("reason", "")]
	sub.add_theme_color_override("font_color", Color(0.8, 0.8, 0.78))
	root.add_child(sub)
	root.add_child(HSeparator.new())

	var cols := HBoxContainer.new()
	cols.add_theme_constant_override("separation", 40)
	root.add_child(cols)

	var left := VBoxContainer.new()
	left.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	cols.add_child(left)
	left.add_child(_caption("Route"))
	for w in report.get("waypoints", []):
		var l := Label.new()
		l.text = "%s  %s" % ["✔" if w.reached else "–", w.name]
		l.add_theme_color_override("font_color", Color(0.5, 0.9, 1.0) if w.reached else Color(0.55, 0.55, 0.55))
		left.add_child(l)
	if not report.get("log", []).is_empty():
		left.add_child(_caption("Radio log"))
		for line in report.log.slice(-6):
			var l := Label.new()
			l.text = line
			l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
			l.add_theme_font_size_override("font_size", 15)
			l.add_theme_color_override("font_color", Color(0.8, 0.8, 0.75))
			left.add_child(l)

	var right := GridContainer.new()
	right.columns = 2
	right.add_theme_constant_override("h_separation", 24)
	right.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	cols.add_child(right)
	var cap := _caption("Statistics")
	right.add_child(cap)
	right.add_child(Control.new())
	for row in report.get("stats", []):
		var k := Label.new()
		k.text = row[0]
		right.add_child(k)
		var v := Label.new()
		v.text = str(row[1])
		v.add_theme_color_override("font_color", UiTheme.ACCENT)
		right.add_child(v)

	root.add_child(HSeparator.new())
	var buttons := HBoxContainer.new()
	buttons.alignment = BoxContainer.ALIGNMENT_END
	buttons.add_theme_constant_override("separation", 12)
	root.add_child(buttons)
	var again := Button.new()
	again.text = "Fly again"
	again.pressed.connect(func(): fly_again.emit())
	buttons.add_child(again)
	var menu := Button.new()
	menu.text = "Back to base" if campaign_mode else "Main menu"
	menu.pressed.connect(func(): main_menu.emit())
	buttons.add_child(menu)
	again.grab_focus()


func _caption(t: String) -> Label:
	var l := Label.new()
	l.text = t
	l.add_theme_font_size_override("font_size", 16)
	l.add_theme_color_override("font_color", UiTheme.ACCENT)
	return l
