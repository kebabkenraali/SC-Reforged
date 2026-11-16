## PROG bytecode analyzer: usage contexts of the still-open opcodes
## (14 21 25 2e parameter ops, 92-98 object ops) across every mission file.
## Run: Godot --headless --path game --script res://tools/prog_analyze.gd
##      [...after "--" : out_file, or pairs of "file blocknr" to dump]
## Stats mode: per-opcode counts, then one context line per occurrence:
##   mission | block index | role | ... [op arg] ... (as decoded hex words)
extends SceneTree

const OPS := [0x14, 0x21, 0x25, 0x2e, 0x92, 0x93, 0x95, 0x97, 0x98]

var counts := {}
var lines := {}


func _initialize() -> void:
	await process_frame
	var sc = root.get_node("SCData")
	if not sc.is_mounted():
		sc.auto_mount()
	var names: PackedStringArray = sc.list("MISSIONS/", ".IFF")
	var args: PackedStringArray = OS.get_cmdline_user_args()
	var out_path: String = args[0] if args.size() > 0 else \
			ProjectSettings.globalize_path("res://..") + "/tmp/prog_analysis.txt"
	var f := FileAccess.open(out_path, FileAccess.WRITE)
	if args.size() > 2:
		for i in range(1, args.size() - 1, 2):
			_dump(f, sc, names, args[i], int(args[i + 1]))
	else:
		_stats(f, sc, names)
	f.close()
	if args.size() > 2:
		print("written: ", out_path)
	else:
		for op in OPS:
			print("opcode %02X count=%d" % [op, counts.get(op, 0)])
		print("written: ", out_path)
	quit(0)


func _stats(f, sc, names: PackedStringArray) -> void:
	for n in names:
		var m = sc.mission(n)
		if m == null:
			continue
		var roles := _roles(m)
		for b in m.blocks.size():
			_scan(m, n, b, roles)
	f.store_line("missions=%d" % names.size())
	for op in OPS:
		f.store_line("opcode %02X count=%d" % [op, counts.get(op, 0)])
	for op in OPS:
		f.store_line("\n=== opcode %02X ===" % op)
		for l in lines.get(op, []):
			f.store_line(l)


## Map block index -> description of which slot references it.
func _roles(m) -> Dictionary:
	var roles := {}
	for p in m.parts:
		var kind := ["start", "ai", "destroyed", "route"]
		for k in 4:
			var b: int = p.slots[k]
			if b >= 0 and b < m.blocks.size():
				var d: String = "%s (%s:#%d id=%d)" % [kind[k], p.model, m.part_index(p.id), p.id]
				if not roles.has(b):
					roles[b] = d
				else:
					roles[b] += " | " + d
	for scn in m.scenes:
		if scn.area >= 0 and scn.area < m.areas.size():
			for b in scn.on_enter:
				if b >= 0 and b < m.blocks.size():
					var d: String = "scene '%s' enter" % m.areas[scn.area].name
					if not roles.has(b):
						roles[b] = d
					else:
						roles[b] += " | " + d
	return roles


func _scan(m, file_name: String, b: int, roles: Dictionary) -> void:
	var code: Array = m.blocks[b]
	if code.is_empty():
		return
	for i in code.size():
		var op: int = code[i][0]
		if not op in OPS:
			continue
		counts[op] = counts.get(op, 0) + 1
		var lo := maxi(i - 3, 0)
		var hi := mini(i + 4, code.size())
		var words := []
		for j in range(lo, hi):
			words.append((".." if (j == lo and lo > 0) or j == i else " ") +
				"%02x%02x" % [code[j][0], code[j][1]])
		words[i - lo] = words[i - lo].replace(" ", "")
		words[i - lo] = "*" + words[i - lo]
		lines[op] = lines.get(op, [])
		lines[op].append("%s blk=%-2d %-40s %s" %
			[file_name.get_file(), b, roles.get(b, "unused"), " ".join(words)])


## Full decode of one block: per-instruction hex, with labels marked and
## part/variable annotations where known.
func _dump(f, sc, names: PackedStringArray, want: String, b: int) -> void:
	for n in names:
		if not n.get_file().to_lower().begins_with(want.to_lower()):
			continue
		var m = sc.mission(n)
		if m == null or b >= m.blocks.size():
			continue
		f.store_line("\n=== %s block %d ===" % [n.get_file(), b])
		f.store_line("roles: %s" % _roles(m).get(b, "unused"))
		var labels := {}
		for i in m.blocks[b].size():
			if m.blocks[b][i][0] == 0x08:
				labels[m.blocks[b][i][1]] = i
		for i in m.blocks[b].size():
			var op: int = m.blocks[b][i][0]
			var arg: int = m.blocks[b][i][1]
			var note := ""
			if op == 0x08:
				note = "label %c:" % arg
			elif op == 0x10:
				note = "push %d" % arg
			elif op == 0x11:
				note = "push var %d" % arg
			elif op == 0x50:
				note = "var %d = pop" % arg
			elif op == 0xa7:
				note = "attack id %d (%s)" % [arg, _part(m, arg)]
			elif op == 0xa8 or op == 0xaa:
				note = "escort/follow id %d (%s)" % [arg, _part(m, arg)]
			elif op == 0x90:
				note = "activate id %d (%s)" % [arg, _part(m, arg)]
			elif op == 0x91:
				note = "remove id %d (%s)" % [arg, _part(m, arg)]
			elif op == 0x92:
				note = "push alive id %d (%s)" % [arg, _part(m, arg)]
			elif op == 0x93 or op == 0x95 or op == 0x97 or op == 0x98:
				note = "query id %d (%s)" % [arg, _part(m, arg)]
			elif op == 0xab and arg < m.messages.size():
				note = "msg '%s'" % m.messages[arg]
			f.store_line("%3d: %02x %02x   %s" % [i, op, arg, note])


func _part(m, id: int) -> String:
	var idx: int = m.part_index(id)
	if idx < 0:
		return "id %d" % id
	var p: Dictionary = m.parts[idx]
	return "%s id=%d" % [p.model, id]
