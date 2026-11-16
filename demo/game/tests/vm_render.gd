## Renders a recorded timeline at given times (for comparing with the emulator).
## Run: Godot --headless --path game --script res://tests/vm_render.gd -- name ms1,ms2 outdir
extends SceneTree


func _initialize() -> void:
	await process_frame
	var sc = root.get_node("SCData")
	if not sc.is_mounted():
		sc.auto_mount()
	var a := OS.get_cmdline_user_args()
	var name: String = a[0]
	var times := []
	for t in a[1].split(","):
		times.append(int(t))
	var out: String = a[2]
	var VM = load("res://scripts/ui/cutscene_vm.gd")
	var v = VM.new()
	root.add_child(v)
	var f := FileAccess.open("res://data/cutscenes/%s.json" % name, FileAccess.READ)
	var ops: Array = JSON.parse_string(f.get_as_text()).ops
	var k := 0
	for op in ops:
		while k < times.size() and float(op[0]) > times[k]:
			_save(v, "%s/vm_%06d.png" % [out, times[k]])
			k += 1
		v._run(op)
	while k < times.size():
		_save(v, "%s/vm_%06d.png" % [out, times[k]])
		k += 1
	quit()


func _save(v, path: String) -> void:
	var src: Image = v._buffers.get(v._screen_key)
	var img := Image.create(320, 200, false, Image.FORMAT_RGB8)
	if src:
		for y in 200:
			for x in 320:
				var i := int(round(src.get_pixel(x, y).r * 255.0))
				img.set_pixel(x, y, v._palette.get_pixel(i, 0))
	img.save_png(path)
