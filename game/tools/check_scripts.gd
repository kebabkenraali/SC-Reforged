## Loads every .gd script in the project and reports which ones fail to compile.
extends SceneTree

func _init() -> void:
	var dirs := ["res://scripts/core", "res://scripts/game", "res://scripts/ui", "res://scripts/formats", "res://scripts/audio"]
	var ok := 0
	var fail := 0
	for d in dirs:
		var dir := DirAccess.open(d)
		if dir == null:
			print("SKIP (missing dir): ", d)
			continue
		for f in dir.get_files():
			if not f.ends_with(".gd"):
				continue
			var path: String = d + "/" + f
			print("LOADING ", path)
			var s = load(path)
			if s == null:
				print("FAIL ", path)
				fail += 1
			else:
				print("OK ", path)
				ok += 1
	print("RESULT ok=%d fail=%d" % [ok, fail])
	quit()