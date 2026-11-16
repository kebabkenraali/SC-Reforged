## Shared UI look: dark translucent panels with Strike Commander amber accents.
extends RefCounted

const ACCENT := Color(0.96, 0.62, 0.18)
const TEXT := Color(0.93, 0.93, 0.9)
const PANEL := Color(0.05, 0.06, 0.08, 0.86)


static func build() -> Theme:
	var t := Theme.new()
	t.default_font_size = 18

	var panel := StyleBoxFlat.new()
	panel.bg_color = PANEL
	panel.border_color = Color(ACCENT, 0.5)
	panel.set_border_width_all(1)
	panel.set_corner_radius_all(6)
	panel.set_content_margin_all(18)
	t.set_stylebox("panel", "PanelContainer", panel)
	t.set_stylebox("panel", "Panel", panel)

	var btn := StyleBoxFlat.new()
	btn.bg_color = Color(0.12, 0.13, 0.16, 0.95)
	btn.set_corner_radius_all(4)
	btn.set_content_margin_all(10)
	btn.content_margin_left = 18
	btn.content_margin_right = 18
	var hover := btn.duplicate()
	hover.bg_color = Color(0.22, 0.17, 0.1, 0.95)
	hover.border_color = ACCENT
	hover.set_border_width_all(1)
	var pressed := hover.duplicate()
	pressed.bg_color = Color(ACCENT, 0.35)
	for cls in ["Button", "OptionButton", "CheckBox", "CheckButton"]:
		t.set_stylebox("normal", cls, btn)
		t.set_stylebox("hover", cls, hover)
		t.set_stylebox("pressed", cls, pressed)
		t.set_stylebox("focus", cls, hover)
		t.set_color("font_color", cls, TEXT)
		t.set_color("font_hover_color", cls, ACCENT)
		t.set_color("font_focus_color", cls, ACCENT)
	t.set_color("font_color", "Label", TEXT)
	return t


static func title_label(text: String, size := 42) -> Label:
	var l := Label.new()
	l.text = text
	l.add_theme_font_size_override("font_size", size)
	l.add_theme_color_override("font_color", ACCENT)
	return l
