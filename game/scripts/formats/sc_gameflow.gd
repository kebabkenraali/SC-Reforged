## Campaign data from GAMEFLOW/*.IFF.
##
## GAMEFLOW.IFF  FORM GAME / FORM MISS (campaign stage): INFO id, EFCT (effects
##               run on entry, pairs op/arg), FORM SCEN (INFO scene id) with
##               FORM SPRT (INFO sprite id, EFCT, REQU = pairs value/flag).
## OPTIONS.IFF   FORM OPTS / FORM SCEN: INFO id, TUNE, FORM BACK (PALT, SHAP
##               layers), FORM FORE (PALT, FORM SPRT: SHAP id/b1/b2, LABL, RECT
##               x1,y1,x2,y2, INFO, SEQU frame list). SHAP = sprite id (matches the
##               gameflow sprite), shape index in OPTSHPS (0xFF = hotspot only), u8.
##               Frame 0 of the shape is the base picture, SEQU frames overlay it.
## CONVDATA.IFF  BCKS/BACK (INFO name, DATA n * {u8 archive, u8 shape, u8 palette,
##               i16 y}), FACE / FIGR / PFIG (name[8] + u8), FCPL / FGPL palettes.
extends RefCounted

const Iff = preload("res://scripts/formats/iff.gd")

var stages := []        # [{ id, effects: [[op,arg]], scenes: { scene_id: [sprite] } }]
## Ledger transactions (FORM STAT / FORM CHNG, read by gameflow effect 22 n,
## decoded from OPTTEST.EXE): id -> { cash: [op, k$], over: [op, k$],
## weap: [[op, weapon, count]], pilt: [[op, pilot, field, value]] }.
## op 0 = add, 1 = subtract, 2 = set. Money is in thousands of dollars.
var changes := {}
## Mission names in campaign order (FORM MLST / DATA): matches misn2op INFO.
var mission_list := []
var screens := {}       # scene_id -> { tune, back_pals, back_shapes, fore_pal, sprites: [] }
var backs := {}         # conversation background name -> [{ archive, shape, palette, y }]
var faces := {}         # name -> CONVSHPS index
var figures := {}       # name -> CONVSHPS index
var figure_pals := {}   # name -> CONVPALS index
var face_palette := -1
var figure_palette := -1


static func load_from(gameflow: PackedByteArray, options: PackedByteArray, convdata: PackedByteArray):
	var g = load("res://scripts/formats/sc_gameflow.gd").new()
	g._parse_gameflow(gameflow)
	g._parse_options(options)
	g._parse_convdata(convdata)
	return g


static func _pairs(buf: PackedByteArray, node) -> Array:
	var out := []
	if node == null:
		return out
	for k in range(0, node.size - 1, 2):
		out.append([buf[node.off + k], buf[node.off + k + 1]])
	return out


func _parse_gameflow(buf: PackedByteArray) -> void:
	var nodes = Iff.parse(buf)
	_parse_economy(buf, nodes)
	var root = Iff.find(nodes, ["FORM:GAME"])
	if root == null:
		return
	for m in Iff.find_all(root.children, "FORM:MISS"):
		var info = Iff.find(m.children, ["INFO"])
		var stage := {"id": buf[info.off] if info else stages.size(),
			"effects": _pairs(buf, Iff.find(m.children, ["EFCT"])), "scenes": {}}
		for sc in Iff.find_all(m.children, "FORM:SCEN"):
			var sinfo = Iff.find(sc.children, ["INFO"])
			var sprites := []
			for sp in Iff.find_all(sc.children, "FORM:SPRT"):
				var spi = Iff.find(sp.children, ["INFO"])
				sprites.append({"id": buf[spi.off] if spi else -1,
					"effects": _pairs(buf, Iff.find(sp.children, ["EFCT"])),
					"requires": _pairs(buf, Iff.find(sp.children, ["REQU"]))})
			stage.scenes[buf[sinfo.off]] = sprites
		stages.append(stage)


func _parse_economy(buf: PackedByteArray, nodes: Array) -> void:
	var stat = Iff.find(nodes, ["FORM:STAT"])
	if stat != null:
		for ch in Iff.find_all(stat.children, "FORM:CHNG"):
			var info = Iff.find(ch.children, ["INFO"])
			if info == null:
				continue
			var c := {"weap": [], "pilt": []}
			for key in ["CASH", "OVER"]:
				var n = Iff.find(ch.children, [key])
				if n != null and n.size >= 5:
					c[key.to_lower()] = [buf[n.off], buf.decode_s32(n.off + 1)]
			var w = Iff.find(ch.children, ["WEAP"])
			if w != null:
				for k in range(0, w.size - 3, 4):
					c.weap.append([buf[w.off + k], buf[w.off + k + 1], buf.decode_u16(w.off + k + 2)])
			var pl = Iff.find(ch.children, ["PILT"])
			if pl != null:
				for k in range(0, pl.size - 4, 5):
					c.pilt.append([buf[pl.off + k], buf[pl.off + k + 1], buf[pl.off + k + 2], buf.decode_u16(pl.off + k + 3)])
			changes[buf[info.off]] = c
	var ml = Iff.find(nodes, ["FORM:MLST", "DATA"])
	if ml != null:
		var cur := ""
		for k in ml.size:
			var b: int = buf[ml.off + k]
			if b == 0:
				if cur != "":
					mission_list.append(cur.to_upper())
				cur = ""
			else:
				cur += char(b)


func _parse_options(buf: PackedByteArray) -> void:
	var root = Iff.find(Iff.parse(buf), ["FORM:OPTS"])
	if root == null:
		return
	for sc in Iff.find_all(root.children, "FORM:SCEN"):
		var info = Iff.find(sc.children, ["INFO"])
		var tune = Iff.find(sc.children, ["TUNE"])
		var s := {"tune": buf[tune.off] if tune else -1, "back_pals": [], "back_shapes": [],
			"fore_pal": -1, "sprites": []}
		var back = Iff.find(sc.children, ["FORM:BACK"])
		if back != null:
			for c in back.children:
				if c.id == "PALT":
					s.back_pals.append(buf.decode_u16(c.off))
				elif c.id == "SHAP":
					s.back_shapes.append(buf.decode_u16(c.off))
		var fore = Iff.find(sc.children, ["FORM:FORE"])
		if fore != null:
			for c in fore.children:
				if c.id == "PALT":
					s.fore_pal = buf.decode_u16(c.off)
				elif c.id == "FORM:SPRT":
					var sp := {"id": -1, "shape": -1, "label": "", "rect": Rect2i(), "sequence": []}
					for k in c.children:
						match k.id:
							"SHAP":
								sp.id = buf[k.off]
								sp.shape = buf[k.off + 1] if k.size >= 2 and buf[k.off + 1] != 0xFF else -1
							"LABL":
								sp.label = Iff.cstr(buf, k.off, k.size)
							"RECT":
								var x1 := buf.decode_s16(k.off)
								var y1 := buf.decode_s16(k.off + 2)
								sp.rect = Rect2i(x1, y1, buf.decode_s16(k.off + 4) - x1, buf.decode_s16(k.off + 6) - y1)
							"SEQU":
								for q in k.size / 2:
									sp.sequence.append(buf.decode_u16(k.off + q * 2))
					s.sprites.append(sp)
		screens[buf[info.off]] = s


func _parse_convdata(buf: PackedByteArray) -> void:
	var root := Iff.parse(buf)
	var bcks = Iff.find(root, ["FORM:BCKS"])
	if bcks != null:
		for b in Iff.find_all(bcks.children, "FORM:BACK"):
			var info = Iff.find(b.children, ["INFO"])
			var data = Iff.find(b.children, ["DATA"])
			if info == null or data == null:
				continue
			var layers := []
			for k in data.size / 5:
				var o: int = data.off + k * 5
				layers.append({"archive": buf[o], "shape": buf[o + 1], "palette": buf[o + 2],
					"y": buf.decode_s16(o + 3)})
			backs[Iff.cstr(buf, info.off, 8).to_lower()] = layers
	for pair in [["FORM:FACE", faces], ["FORM:FIGR", figures], ["FORM:PFIG", figure_pals]]:
		var form = Iff.find(root, [pair[0]])
		if form != null:
			for d in Iff.find_all(form.children, "DATA"):
				if d.size >= 9:
					pair[1][Iff.cstr(buf, d.off, 8).to_lower()] = buf[d.off + 8]
	var fcpl = Iff.find(root, ["FORM:FCPL"])
	if fcpl != null and not fcpl.children.is_empty():
		face_palette = buf[fcpl.children[0].off + 8]
	var fgpl = Iff.find(root, ["FORM:FGPL"])
	if fgpl != null and not fgpl.children.is_empty():
		figure_palette = buf[fgpl.children[0].off + 8]


## Index of the gameflow stage with a given id.
func stage_index(id: int) -> int:
	for i in stages.size():
		if stages[i].id == id:
			return i
	return -1
