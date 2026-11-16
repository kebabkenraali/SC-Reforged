## Mission event chain: what happens before, during and after one mission.
## Reads everything at run time from the user's own installation (no
## original content in the project) and writes a Markdown report:
##   1. campaign: the GAMEFLOW stages that select the mission (effect 0c n),
##      their effects in order and every conversation they play, line by line
##      with the speaker, the VOCLIST voice file (F:<voc>.VOC) and the text;
##   2. the mission: route (nav_plan), scenes, parts (who starts dormant, which
##      script blocks they own) and every PROG block decoded with the radio
##      line an `ab n` triggers for each owner (INTEL/<cast>.IFF MSGS).
##
## Run: Godot --headless --path game --script res://tools/mission_chain.gd -- [MISN-1A] [out.md]
## Default output: tmp/<mission>_chain.md (contains original game text: keep it local).
extends SceneTree

# campaign.gd / art.gd use the SCData autoload by name: load them at run time
# (a preload compiles before the autoloads exist in --script mode).
var Campaign
var Art
const CONDITIONS := [0x09, 0x0a, 0x14, 0x15, 0x16, 0x1c, 0x20, 0x23, 0x25]   # = campaign.gd
const Conv = preload("res://scripts/formats/sc_conversation.gd")
const Shape = preload("res://scripts/formats/sc_shape.gd")
const Pak = preload("res://scripts/formats/pak_archive.gd")

const EFFECTS := {
	0x00: "conversation", 0x01: "base screen", 0x02: "story cut-scene MID", 0x06: "set flag",
	0x07: "clear flag", 0x08: "establishing shot", 0x09: "IF flag clear", 0x0a: "IF flag set",
	0x0c: "select mission", 0x0d: "next stage =", 0x0f: "go to next stage", 0x10: "save",
	0x11: "load", 0x12: "transport map", 0x13: "kill board", 0x14: "IF answered yes",
	0x15: "IF answered no", 0x16: "FLY selected mission", 0x17: "catalog", 0x19: "ledger",
	0x1c: "IF (1c)", 0x1e: "ELSE", 0x1f: "ENDIF", 0x20: "IF mission succeeded", 0x21: "ALL of next",
	0x23: "IF (23)", 0x25: "IF (25)"}

var sc
var out := PackedStringArray()


func _initialize() -> void:
	await process_frame
	sc = root.get_node("SCData")
	if not sc.is_mounted():
		sc.auto_mount()
	Campaign = load("res://scripts/game/campaign.gd")
	Art = load("res://scripts/core/art.gd")
	var args: PackedStringArray = OS.get_cmdline_user_args()
	var tag: String = (args[0] if args.size() > 0 else "MISN-1A").to_upper().trim_suffix(".IFF")
	var out_path: String = args[1] if args.size() > 1 else \
			ProjectSettings.globalize_path("res://..") + "/tmp/%s_chain.md" % tag
	var file := "MISSIONS/%s.IFF" % tag
	var m = sc.mission(file)
	if m == null:
		printerr("mission not found: ", file)
		quit(1)
		return
	out.append("# %s – tapahtumaketju" % tag)
	out.append("")
	out.append("Generoitu `tools/mission_chain.gd`:llä pelin omasta datasta. Sisältää alkuperäistä tekstiä: älä jaa.")
	_campaign(file)
	_mission(m)
	var f := FileAccess.open(out_path, FileAccess.WRITE)
	f.store_string("\n".join(out) + "\n")
	f.close()
	print("written: ", out_path)
	quit(0)


# --- 1. campaign -------------------------------------------------------------

func _campaign(file: String) -> void:
	var files: Array = Campaign.mission_files()
	var idx: int = files.find(file)
	out.append("\n## 1. Kampanja (GAMEFLOW)\n")
	out.append("Kampanjan tehtävänumero: **%d** (`0c %d`)." % [idx, idx])
	if idx < 0:
		return
	var g = Art.gameflow()
	var convs := []
	for si in g.stages.size():
		var st: Dictionary = g.stages[si]
		if not _selects(st, idx):
			continue
		out.append("\n### Vaihe %d (stage id %d)\n" % [si, st.id])
		out.append("Saapumisefektit:")
		_effects(st.effects, convs, "")
		for scr in st.scenes:
			for sp in st.scenes[scr]:
				if sp.effects.is_empty():
					continue
				var req := ""
				if not sp.requires.is_empty():
					req = " (vaatii " + ", ".join(sp.requires.map(func(r): return "lippu %d=%d" % [r[1], r[0]])) + ")"
				out.append("\nRuutu %d, sprite %d%s:" % [scr, sp.id, req])
				_effects(sp.effects, convs, "")
	out.append("\n### Keskustelut\n")
	var entries: Array = Pak.entries(sc.read("GAMEFLOW/CONV.PAK"))
	for n in convs:
		_conversation(entries, n)
	# Cross-check: every conversation whose voice files carry the mission's prefix.
	var prefix: String = file.get_file().get_basename().substr(5)   # "1A"
	var other := []
	for n in entries.size():
		if n in convs:
			continue
		for s in Conv.parse(Shape.unpack(entries[n])):
			if s.has("voc") and String(s.voc).to_upper().begins_with(prefix):
				other.append(n)
				break
	if not other.is_empty():
		out.append("\nMuut keskustelut, joiden äänitiedostot alkavat `%s`: %s" % [prefix, ", ".join(other.map(func(x): return str(x)))])


func _selects(st: Dictionary, idx: int) -> bool:
	for e in st.effects:
		if e[0] == 0x0c and e[1] == idx:
			return true
	for scr in st.scenes:
		for sp in st.scenes[scr]:
			for e in sp.effects:
				if e[0] == 0x0c and e[1] == idx:
					return true
	return false


func _effects(effects: Array, convs: Array, indent: String) -> void:
	var depth := 0
	for e in effects:
		var op: int = e[0]
		if op in [0x1e, 0x1f]:
			depth = maxi(depth - 1, 0)
		var name: String = EFFECTS.get(op, "op %02x" % op)
		out.append("%s- %s`%02x %d` %s" % [indent, "  ".repeat(depth), op, e[1], name + ("" if op in [0x0f, 0x10, 0x11, 0x16, 0x1e, 0x1f] else " %d" % e[1])])
		if op in CONDITIONS or op == 0x1e:
			depth += 1
		if op == 0x00 and not e[1] in convs:
			convs.append(e[1])


func _conversation(entries: Array, n: int) -> void:
	out.append("\n#### Keskustelu %d\n" % n)
	if n < 0 or n >= entries.size():
		out.append("(ei löydy)")
		return
	out.append("| # | puhuja | ääni (VOCLIST) | teksti |")
	out.append("|---|---|---|---|")
	var speaker := ""
	var k := 0
	for s in Conv.parse(Shape.unpack(entries[n])):
		match s.op:
			0x02, 0x03:
				speaker = s.name
			0x0a:
				speaker = "(kertoja)"
			0x0b:
				out.append("| | | | **KYSYMYS kyllä/ei** – 'ei' hyppää kohtaan %d |" % s.target)
				continue
			0x0c:
				out.append("| | | | (hyppy kohtaan %d: ohittaa 'ei'-haaran) |" % s.target)
				continue
			0x0e:
				out.append("| | | | (lentobriefing-merkki) |")
				continue
			0x0f:
				out.append("| | | | **siipimiehen valinta ($W)** |")
				continue
		if s.has("text"):
			k += 1
			var voc: String = String(s.voc).to_upper()
			var has: bool = voc != "" and sc.read("F:%s.VOC" % voc).size() > 0
			out.append("| %d | %s | %s | %s |" % [k, speaker, (voc + ".VOC" if has else (voc + " (puuttuu)" if voc != "" else "–")),
				String(s.text).replace("|", "/")])


# --- 2. mission --------------------------------------------------------------

func _mission(m) -> void:
	out.append("\n## 2. Tehtävä %s\n" % m.file.get_file())
	out.append("- Nimi: %s" % m.name)
	out.append("- Maasto: %s" % m.area)
	out.append("- Pelaajan PART id: %d" % m.player_id)
	out.append("\n### Tehtävätekstit (MSGS)\n")
	for i in m.messages.size():
		out.append("%d. `%d` %s" % [i + 1, i, m.messages[i]])
	out.append("\n### Reitti (pelaajan route-blokki, nav_plan)\n")
	var k := 1
	for wp in m.nav_plan():
		out.append("%d. %s – %s" % [k, wp.label if wp.label != "" else "(nimetön)", _v(wp.pos)])
		k += 1
	out.append("\n### Alueet (AREA)\n")
	for i in m.areas.size():
		var a: Dictionary = m.areas[i]
		out.append("- %d `%s` %s r=%.0f m" % [i, a.name, _v(a.pos), float(a.radius)])
	var dormant: Array = m.dormant_part_indices()
	var roles := _roles(m)
	out.append("\n### Osat (PART)\n")
	out.append("| id | malli | puoli | cast | alussa | start | AI | tuhottu | reitti |")
	out.append("|---|---|---|---|---|---|---|---|---|")
	for i in m.parts.size():
		var p: Dictionary = m.parts[i]
		var cast: String = m.cast[p.id] if p.id >= 0 and p.id < m.cast.size() else ""
		out.append("| %d | %s | %d | %s | %s | %s | %s | %s | %s |" % [p.id, p.model, p.side, cast,
			"lepää (aktivoidaan 90)" if i in dormant else "mukana",
			_b(p.slots[0]), _b(p.slots[1]), _b(p.slots[2]), _b(p.slots[3])])
	out.append("\n### Kohtaukset (SCNE)\n")
	for i in m.scenes.size():
		var s: Dictionary = m.scenes[i]
		var an: String = m.areas[s.area].name if s.area >= 0 and s.area < m.areas.size() else "?"
		out.append("- kohtaus %d: alue `%s`, sisääntulo-blokit %s, osat %s" % [i, an,
			s.on_enter, s.parts.map(func(pi): return m.parts[pi].id if pi < m.parts.size() else pi)])
	out.append("\n### Skriptiblokit (PROG)\n")
	out.append("Tilakoneblokit ajetaan uudelleen joka skriptitikillä (0.5 s). `ab n` = radioviesti n blokin omistajalta.")
	for b in m.blocks.size():
		_block(m, b, roles.get(b, []))


func _roles(m) -> Dictionary:
	var roles := {}
	var kind := ["start", "AI", "tuhottu", "reitti"]
	for p in m.parts:
		for k in 4:
			var b: int = p.slots[k]
			if b >= 0 and b < m.blocks.size():
				roles[b] = roles.get(b, []) + [{"what": "%s: %s id=%d" % [kind[k], p.model, p.id], "id": p.id}]
	for i in m.scenes.size():
		for b in m.scenes[i].on_enter:
			if b >= 0 and b < m.blocks.size():
				var an: String = m.areas[m.scenes[i].area].name if m.scenes[i].area >= 0 and m.scenes[i].area < m.areas.size() else "?"
				roles[b] = roles.get(b, []) + [{"what": "kohtaus %d '%s' sisääntulo" % [i, an], "id": -1}]
	return roles


func _block(m, b: int, owners: Array) -> void:
	var code: Array = m.blocks[b]
	if code.is_empty():
		return
	var who: String = "; ".join(owners.map(func(o): return o.what)) if not owners.is_empty() else "tehtävänlaajuinen (ajetaan joka tikki)"
	out.append("\n#### Blokki %d – %s\n" % [b, who])
	out.append("```")
	for i in code.size():
		var op: int = code[i][0]
		var arg: int = code[i][1]
		out.append("%3d: %02x %02x  %s" % [i, op, arg, _op(m, op, arg, owners)])
	out.append("```")


func _op(m, op: int, arg: int, owners: Array) -> String:
	match op:
		0x01: return "-- tikin loppu (yield)"
		0x08: return "label %c:" % arg
		0x0f: return "TEHTÄVÄ PÄÄTTYY: %s" % ("onnistui" if arg == 1 else "epäonnistui")
		0x10: return "push %d" % arg
		0x11: return "push var %d" % arg
		0x50, 0x14: return "var %d = pop" % arg
		0x55: return "var %d += 1" % arg
		0x56: return "var %d -= 1" % arg
		0x23: return "var %d += pop" % arg
		0x40: return "push(pop >= %d)" % arg
		0x41: return "push(pop < %d)" % arg
		0x45: return "push lippu %d" % arg
		0x52: return "aseta lippu %d" % arg
		0x53: return "tyhjennä lippu %d" % arg
		0x92: return "push elossa? %s" % _part(m, arg)
		0x4e: return "goto %c" % arg
		0x4f: return "goto (pop)"
		0x48, 0x4b: return "jos tosi -> %c" % arg
		0x49, 0x4a: return "jos epätosi -> %c" % arg
		0x46: return "jos toiminto kesken -> %c" % arg
		0x90: return "AKTIVOI %s" % _part(m, arg)
		0x91: return "poista %s" % _part(m, arg)
		0xa0: return "odota %d s" % arg
		0xa1: return "nouse ilmaan"
		0xa2: return "laskeudu SPOT %d %s" % [arg, _spot(m, arg)]
		0xa5, 0xa6: return "lennä SPOT %d %s" % [arg, _spot(m, arg)]
		0xa7: return "HYÖKKÄÄ %s" % _part(m, arg)
		0xa8: return "saattaa %s" % _part(m, arg)
		0xaa: return "seuraa %s" % _part(m, arg)
		0x95: return "push etäisyys (NM, vaaka) -> %s" % _part(m, arg)
		0x97: return "push etäisyys (NM, 3D) -> %s" % _part(m, arg)
		0x93, 0x98: return "kysely %02x %s" % [op, _part(m, arg)]
		0x21, 0x24, 0x25, 0x2e, 0x2f: return "parametri %02x %d" % [op, arg]
		0xab: return "RADIO " + _radio(m, arg, owners)
	return ""


func _radio(m, n: int, owners: Array) -> String:
	var lines := []
	for o in owners:
		if o.id >= 0 and o.id < m.cast.size():
			var r: Dictionary = sc.radio(m.cast[o.id])
			if r.msgs.has(n):
				lines.append("%s (%s #%d): \"%s\"" % [r.speaker, m.cast[o.id], n, r.msgs[n]])
				continue
		if n < m.messages.size():
			lines.append("teksti MSGS[%d]: \"%s\"" % [n, m.messages[n]])
		else:
			lines.append("#%d (ei tekstiä)" % n)
	if lines.is_empty():
		lines.append("teksti MSGS[%d]: \"%s\"" % [n, m.messages[n]] if n < m.messages.size() else "#%d" % n)
	return " | ".join(lines)


func _part(m, id: int) -> String:
	var i: int = m.part_index(id)
	if i < 0:
		return "id %d" % id
	var cast: String = m.cast[id] if id >= 0 and id < m.cast.size() else ""
	return "%s id=%d%s" % [m.parts[i].model, id, (" (" + cast + ")") if cast != "" else ""]


func _spot(m, n: int) -> String:
	return _v(m.spots[n]) if n >= 0 and n < m.spots.size() else ""


func _b(b: int) -> String:
	return str(b) if b >= 0 else "–"


func _v(p: Vector3) -> String:
	return "(%.1f, %.1f km, alt %.0f m)" % [p.x / 1000.0, -p.z / 1000.0, p.y]
