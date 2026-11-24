## Small reticle drawn in the flat 2D UI viewport, moved by the VR controller
## pointer (or by the mouse when using a virtual desktop).
extends Control


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	z_index = 100


func _draw() -> void:
	var c := Color(1.0, 1.0, 1.0, 0.95)
	draw_arc(Vector2.ZERO, 9.0, 0.0, TAU, 24, c, 2.0, true)
	draw_line(Vector2(-14, 0), Vector2(-4, 0), c, 2.0)
	draw_line(Vector2(4, 0), Vector2(14, 0), c, 2.0)
	draw_line(Vector2(0, -14), Vector2(0, -4), c, 2.0)
	draw_line(Vector2(0, 4), Vector2(0, 14), c, 2.0)
