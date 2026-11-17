## The office screens of the base: the ledger (gameflow effect 19), the kill
## board (13 and 1a) and the weapons catalog (17). Layout, fonts and rules
## follow the original OPTTEST.EXE (see docs/GAMEFLOW_VM.md, "Ruudut"); all
## art and fonts are read from the player's own install.
##   ledger   scene 128 art (book shape 140, palette 18), LEDGFONT; page 1 the
##            money, page 2 the weapon stock; page turn = shape 41.
##   kills    whiteboard shape 123, palette 22, BOARDFNT; click anywhere.
##   catalog  scene 30 art (shape 92, palette 13): five spreads of pages,
##            receipts 101 + record with digit shapes 155 / 156, CALCFONT on
##            the calculator (available / spent / balance).
extends Control

const Art = preload("res://scripts/core/art.gd")
const UiTheme = preload("res://scripts/ui/ui_theme.gd")

signal closed

var campaign
var kind := "ledger"            # ledger / kills / catalog
var auto_close := false         # unattended runs: close after a moment

var _stage: Control
var _pic: TextureRect
var _label: Label
var _pal: PackedColorArray
var _page := 0                  # ledger page 0 / 1, catalog spread 0..4
var _order := {}                # catalog visit (campaign.catalog_open)
var _flip := -1                 # ledger page-turn frame on screen, -1 none
var _turning := false
var _done := false
var _note := ""                 # one-off message replacing the hover label

const LEDGER_ROWS_Y := [59, 65, 70, 76, 82, 87, 93, 99, 105, 111]
const LEDGER_LABEL_X := 68
const LEDGER_VALUE_RIGHT := 218
const LEDGER_THOUSANDS_X := 222
const LEDGER_TURN := [Rect2i(61, 59, 193, 113), Rect2i(258, 57, 61, 115)]
const LEDGER_EXIT_H := 40

const BOARD_HEAD_Y := 45
const BOARD_ROW_Y := 60
const BOARD_ROW_STEP := 15
const BOARD_NAME_X := 83
const BOARD_GROUND_RIGHT := 250
const BOARD_AIR_RIGHT := 290

const CATALOG_EXIT_H := 50
const CALC_RIGHT := 295
const CALC_LINES_Y := [35, 41, 47]
## Spreads of the catalog: page layers over the base picture and the records
## on the left and right page (two records: top and bottom half).
const SPREADS := [
	{"layers": [], "left": [0, 1], "right": [2, 4]},
	{"layers": [93, 94], "left": [3, 8], "right": [5, 6]},
	{"layers": [95, 96], "left": [7], "right": [9]},
	{"layers": [97, 98], "left": [10], "right": [11]},
	{"layers": [99, 100], "left": [12], "right": [13]}]
const RECEIPT_SHAPE := 101
const DIGIT_SHAPES := [155, 156]
const RECEIPT_STYLE := [1, 1, 1, 1, 1, 1, 0, 0, 0, 1, 0, 1, 1, 1]
const RECEIPT_TENS := [Vector2i(27, 192), Vector2i(86, 177), Vector2i(87, 189), Vector2i(168, 156),
	Vector2i(169, 170), Vector2i(152, 186), Vector2i(253, 129), Vector2i(246, 138), Vector2i(248, 148),
	Vector2i(244, 175), Vector2i(246, 95), Vector2i(230, 89), Vector2i(237, 79), Vector2i(227, 69)]
const RECEIPT_ONES := [Vector2i(33, 191), Vector2i(92, 176), Vector2i(93, 188), Vector2i(174, 156),
	Vector2i(174, 170), Vector2i(159, 185), Vector2i(260, 129), Vector2i(252, 138), Vector2i(254, 148),
	Vector2i(251, 173), Vector2i(252, 95), Vector2i(236, 89), Vector2i(243, 78), Vector2i(233, 68)]
## The open book on the catalog picture: page quads (top-left, top-right,
## bottom-right, bottom-left) and the page corners that turn the pages.
const LEFT_PAGE := [Vector2(15, 95), Vector2(110, 65), Vector2(137, 157), Vector2(27, 187)]
const RIGHT_PAGE := [Vector2(110, 65), Vector2(200, 53), Vector2(235, 128), Vector2(137, 157)]
const CORNER_BACK := Vector2(17, 97)
const CORNER_FORWARD := Vector2(196, 56)
const CORNER_R := 20.0


func _ready() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_STOP
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
	_pic = TextureRect.new()
	_pic.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_pic.stretch_mode = TextureRect.STRETCH_SCALE
	var smooth: bool = Settings.get_value("video", "smooth_textures")
	_pic.texture_filter = CanvasItem.TEXTURE_FILTER_LINEAR if smooth else CanvasItem.TEXTURE_FILTER_NEAREST
	_pic.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_stage.add_child(_pic)
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
	_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_label)
	if kind == "catalog":
		_order = campaign.catalog_open()
	_refresh()
	print("OFFICE %s opened" % kind)
	if auto_close:
		get_tree().create_timer(0.6).timeout.connect(_close)


## The screen as a 320 x 200 image (also used by the tests).
func compose() -> Image:
	var c := Art.new_canvas()
	match kind:
		"ledger":
			_pal = Art.palette("opt", [18])
			_layer(c, 140)
			if _flip >= 0:
				_layer(c, 41, _flip)
			else:
				_draw_ledger(c)
		"kills":
			_pal = Art.palette("opt", [22])
			_layer(c, 123)
			_draw_board(c)
		"catalog":
			_pal = Art.palette("opt", [13])
			_layer(c, 92)
			for s in SPREADS[_page].layers:
				_layer(c, s)
			_draw_receipts(c)
			_draw_calculator(c)
	return Art.canvas_image(c, _pal)


func _layer(c: Dictionary, shape: int, frame := 0) -> void:
	var fr: Array = Art.frames("opt", shape)
	if fr.size() > frame:
		Art.blit(c, fr[frame], Vector2i.ZERO)


## Text position: the original's y is the top of the writing line (the
## ledger rows are its ruled lines); glyphs hang from their baseline.
static func _at(f: Dictionary, x: int, y: int) -> Vector2i:
	var g = f.get(48, f.get(65, {}))
	return Vector2i(x, y + 1 - int(g.get("origin", Vector2i.ZERO).y))


func _refresh() -> void:
	if _pic != null:
		_pic.texture = ImageTexture.create_from_image(compose())


# --- drawing ---------------------------------------------------------------------

func _draw_ledger(c: Dictionary) -> void:
	var f := Art.font("LEDGFONT")
	var ink := Art.nearest(_pal, Color(0.13, 0.15, 0.36))
	if _page == 0:
		var rows: Array = campaign.ledger_rows()
		for i in rows.size():
			if rows[i][0] == "":
				continue
			var y: int = LEDGER_ROWS_Y[i]
			var v := str(rows[i][1])
			Art.draw_text(c, f, rows[i][0], _at(f, LEDGER_LABEL_X, y), ink)
			Art.draw_text(c, f, v, _at(f, LEDGER_VALUE_RIGHT - Art.text_width(f, v), y), ink)
			Art.draw_text(c, f, "000", _at(f, LEDGER_THOUSANDS_X, y), ink)
	else:
		for i in campaign.WEAPON_NAMES.size():
			var y: int = LEDGER_ROWS_Y[i]
			var v := str(campaign.weapons[i])
			Art.draw_text(c, f, campaign.WEAPON_NAMES[i], _at(f, LEDGER_LABEL_X, y), ink)
			Art.draw_text(c, f, v, _at(f, LEDGER_VALUE_RIGHT - Art.text_width(f, v), y), ink)


func _draw_board(c: Dictionary) -> void:
	var f := Art.font("BOARDFNT")
	Art.draw_text(c, f, "GROUND", _at(f, BOARD_GROUND_RIGHT - Art.text_width(f, "GROUND"), BOARD_HEAD_Y))
	Art.draw_text(c, f, "AIR", _at(f, BOARD_AIR_RIGHT - Art.text_width(f, "AIR"), BOARD_HEAD_Y))
	var y := BOARD_ROW_Y
	for r in campaign.kill_board():
		var air := str(r[1])
		var ground := str(r[2])
		Art.draw_text(c, f, r[0], _at(f, BOARD_NAME_X, y))
		Art.draw_text(c, f, ground, _at(f, BOARD_GROUND_RIGHT - Art.text_width(f, ground), y))
		Art.draw_text(c, f, air, _at(f, BOARD_AIR_RIGHT - Art.text_width(f, air), y))
		y += BOARD_ROW_STEP


func _draw_receipts(c: Dictionary) -> void:
	for rec in _order.counts.size():
		var n: int = _order.counts[rec]
		if n <= 0:
			continue
		_layer(c, RECEIPT_SHAPE + rec)
		var digits: Array = Art.frames("opt", DIGIT_SHAPES[RECEIPT_STYLE[rec]])
		if digits.size() < 10:
			continue
		if n > 9:
			Art.blit(c, digits[(n / 10) % 10], RECEIPT_TENS[rec])
		Art.blit(c, digits[n % 10], RECEIPT_ONES[rec])


func _draw_calculator(c: Dictionary) -> void:
	var f := Art.font("CALCFONT")
	var ink := Art.nearest(_pal, Color(0.05, 0.1, 0.08))
	var vals := [_order.avail, _order.spent, _order.avail - _order.spent]
	for i in 3:
		var s := str(vals[i]) + ("000" if vals[i] != 0 else "")
		Art.draw_text(c, f, s, _at(f, CALC_RIGHT - Art.text_width(f, s), CALC_LINES_Y[i]), ink)


# --- input -----------------------------------------------------------------------

func _to_screen(p: Vector2) -> Vector2:
	var sz := _stage.size
	return Vector2(p.x / sz.x * 320.0, p.y / sz.y * 200.0)


func _return_label() -> String:
	return "Return to Tent" if campaign.screen == 29 else "Return to Office"


## What is under screen point p: {what: exit / back / forward / turn / item /
## receipt / none, rec, label}.
func hit(p: Vector2) -> Dictionary:
	match kind:
		"kills":
			return {"what": "exit", "label": _return_label()}
		"ledger":
			if p.y < LEDGER_EXIT_H:
				return {"what": "exit", "label": _return_label()}
			for r in LEDGER_TURN:
				if Rect2(r).has_point(p):
					return {"what": "turn", "label": "Turn page"}
		"catalog":
			if p.y < CATALOG_EXIT_H:
				return {"what": "exit", "label": _return_label()}
			for rec in range(_order.counts.size() - 1, -1, -1):
				if _order.counts[rec] > 0 and _mask_hit(RECEIPT_SHAPE + rec, p):
					return {"what": "receipt", "rec": rec, "label": "Cancel %s order" % _item_name(rec)}
			if _page < SPREADS.size() - 1 and p.distance_to(CORNER_FORWARD) < CORNER_R:
				return {"what": "forward", "label": "Turn forward"}
			if _page > 0 and p.distance_to(CORNER_BACK) < CORNER_R:
				return {"what": "back", "label": "Turn back"}
			for side in [["left", LEFT_PAGE], ["right", RIGHT_PAGE]]:
				var quad := PackedVector2Array(side[1])
				if not Geometry2D.is_point_in_polygon(p, quad):
					continue
				var recs: Array = SPREADS[_page][side[0]]
				var rec: int = recs[0]
				if recs.size() > 1:
					var a: Vector2 = quad[0].lerp(quad[3], 0.45)
					var b: Vector2 = quad[1].lerp(quad[2], 0.45)
					if (b - a).cross(p - a) > 0.0:
						rec = recs[1]
				if campaign.CATALOG[rec][2].is_empty():
					return {"what": "none", "label": ""}
				return {"what": "item", "rec": rec, "label": "Order %s  ($%d,000)" % [_item_name(rec), campaign.CATALOG[rec][1]]}
	return {"what": "none", "label": ""}


func _item_name(rec: int) -> String:
	var e: Array = campaign.CATALOG[rec]
	if e[2].size() == 1 and e[2].values()[0] == 1:
		return e[0]
	var parts := []
	for k in e[2]:
		parts.append("%d %s" % [e[2][k], campaign.WEAPON_NAMES[k]])
	return "%s: %s" % [e[0].capitalize(), " + ".join(parts)]


func _mask_hit(shape: int, p: Vector2) -> bool:
	var fr: Array = Art.frames("opt", shape)
	if fr.is_empty():
		return false
	var d: Dictionary = fr[0]
	var x: int = int(p.x) - d.origin.x
	var y: int = int(p.y) - d.origin.y
	if x < 0 or y < 0 or x >= d.w or y >= d.h:
		return false
	return d.mask[y * d.w + x] != 0


func _stage_input(event: InputEvent) -> void:
	if _done or _turning:
		return
	if event is InputEventMouseMotion:
		var h := hit(_to_screen(event.position))
		if _note == "":
			_label.text = h.label
	elif event is InputEventMouseButton and event.pressed:
		if event.button_index == MOUSE_BUTTON_LEFT or event.button_index == MOUSE_BUTTON_RIGHT:
			press(hit(_to_screen(event.position)), event.button_index == MOUSE_BUTTON_RIGHT)
			accept_event()


## Acts on a hit (left click; `cancel` = right click).
func press(h: Dictionary, cancel := false) -> void:
	_note = ""
	match h.what:
		"exit":
			_close()
		"turn":
			_turn_ledger()
		"forward":
			_page += 1
			_refresh()
		"back":
			_page -= 1
			_refresh()
		"receipt":
			campaign.catalog_cancel(_order, h.rec)
			_refresh()
		"item":
			if cancel:
				campaign.catalog_cancel(_order, h.rec)
			elif not campaign.catalog_buy(_order, h.rec):
				_note = "Not enough money."
				if _label != null:
					_label.text = _note
			_refresh()


func _unhandled_input(event: InputEvent) -> void:
	if _done:
		return
	if event.is_action_pressed("ui_cancel") or event.is_action_pressed("pause") or event.is_action_pressed("ui_accept"):
		_close()
	elif event.is_action_pressed("ui_right") or event.is_action_pressed("ui_left"):
		var fwd := event.is_action_pressed("ui_right")
		if kind == "ledger":
			_turn_ledger()
		elif kind == "catalog":
			_page = clampi(_page + (1 if fwd else -1), 0, SPREADS.size() - 1)
			_refresh()
	else:
		return
	get_viewport().set_input_as_handled()


func _turn_ledger() -> void:
	if _turning:
		return
	_turning = true
	# Shape 41: the right page lifts (3), stands up (2) and falls left (1, 0).
	for f in ([3, 2, 1, 0] if _page == 0 else [0, 1, 2, 3]):
		_flip = f
		_refresh()
		await get_tree().create_timer(0.07).timeout
	_flip = -1
	_page = 1 - _page
	_refresh()
	_turning = false


func _close() -> void:
	if _done:
		return
	_done = true
	if kind == "catalog" and not _order.is_empty():
		campaign.catalog_close(_order)
	print("OFFICE %s closed" % kind)
	closed.emit()
