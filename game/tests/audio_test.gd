## Sound effect decoding and the audio settings UI.
## Run: Godot --headless --path game --script res://tests/audio_test.gd
extends SceneTree

var failures := 0


func _initialize() -> void:
	await process_frame
	var sc = root.get_node("SCData")
	var sfx = root.get_node("Sfx")
	if not sc.is_mounted():
		sc.auto_mount()

	var count: int = sc.sfx_count()
	_check("DSOUNDFX holds 32 sounds", count == 32, str(count))
	var decoded := 0
	for i in count:
		var s = sc.sfx(i)
		if s != null and s.get_length() > 0.2:
			decoded += 1
	_check("31 non-empty sounds decode", decoded == 31, str(decoded))
	var eng = sc.sfx(23, true)
	_check("engine loop is ~4.9 s at 11.1 kHz", eng != null and absf(eng.get_length() - 4.9) < 0.2 and eng.mix_rate == 11111,
		"%.2f s %d Hz" % [eng.get_length(), eng.mix_rate] if eng else "null")
	_check("engine loop loops", eng.loop_mode == AudioStreamWAV.LOOP_FORWARD)
	for role in sfx.ROLES:
		_check("role %s has a stream" % role, sfx.stream(role) != null)
	_check("warning tone", sfx.tone("warning").get_length() > 0.5)
	var gun = sfx.synth("gun", true)
	_check("synthesised gun loops, ~0.5 s", gun.loop_mode == AudioStreamWAV.LOOP_FORWARD and absf(gun.get_length() - 0.5) < 0.02,
		"%.2f s" % gun.get_length())
	_check("F-16 gets the 20 mm preset", sfx.gun_preset(sc.model("OBJECTS/F-16DES.IFF")) == "20mm")
	_check("A-10 gets the 30 mm preset", sfx.gun_preset(sc.model("OBJECTS/A-10.IFF")) == "30mm")
	var g20 = sfx.gun(true, "20mm")
	var g30 = sfx.gun(true, "30mm")
	_check("both gun presets loop", g20.loop_mode == AudioStreamWAV.LOOP_FORWARD and g30.loop_mode == AudioStreamWAV.LOOP_FORWARD)
	_check("synthesised hit is short", sfx.synth("hit", false).get_length() < 0.3)
	_check("gun defaults to the synthesised sound", sfx.ROLES.gun[0] == -1, str(sfx.ROLES.gun[0]))

	var menu = load("res://scripts/ui/settings_menu.gd").new()
	root.add_child(menu)
	await process_frame
	var tabs: TabContainer = menu.find_children("*", "TabContainer", true, false)[0]
	var names := []
	for c in tabs.get_children():
		names.append(c.name)
	_check("settings has an Audio tab", "Audio" in names, str(names))
	menu.queue_free()

	print("audio_test failures=%d" % failures)
	quit(failures)


func _check(name: String, ok: bool, detail := "") -> void:
	print("%s %s %s" % ["PASS" if ok else "FAIL", name, detail])
	if not ok:
		failures += 1
