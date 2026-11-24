## Cutscene audio: recorded story timelines carry a "music" op; establishing
## shots and the fallback player must start the midgame score as well, so no
## cutscene is silent after the opening intro.
extends SceneTree


func _initialize() -> void:
	await process_frame
	var failures := 0
	var sc = root.get_node("SCData")
	if not sc.is_mounted():
		sc.auto_mount()
	var Music = root.get_node("Music")
	var VM = load("res://scripts/ui/cutscene_vm.gd")

	# Every recorded story cut-scene has its own music op.
	for n in [1, 2, 3, 5, 12, 14, 15, 16, 17, 20]:
		var f := FileAccess.open("res://data/cutscenes/mid%d.json" % n, FileAccess.READ)
		if f == null:
			continue
		var data = JSON.parse_string(f.get_as_text())
		f.close()
		if not (data is Dictionary):
			continue
		var has_music := false
		for op in data.get("ops", []):
			if op[1] == "music":
				has_music = true
				break
		if not has_music:
			print("FAIL mid", n, " has no music op")
			failures += 1

	# Establishing shot has no recorded music op, but VM.play() must start the
	# score anyway.
	Music.stop()
	var v = VM.new()
	v.file = "est0"
	root.add_child(v)
	v.play()
	for i in range(4):
		await process_frame
	if Music.current.is_empty():
		print("FAIL est0 cutscene left music silent")
		failures += 1
	elif not Music.current.begins_with("MIDGAMES/AMUSIC.PAK"):
		print("FAIL est0 started wrong music: ", Music.current)
		failures += 1
	v.free()
	Music.stop()

	print("cutscene_audio_test failures=", failures)
	quit(failures)
