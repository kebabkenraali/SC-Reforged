## Original music: XMIDI parsing and AdLib instrument rendering.
## Run: Godot --headless --path game --script res://tests/music_test.gd
extends SceneTree

var failures := 0


func _initialize() -> void:
	await process_frame
	var sc = root.get_node("SCData")
	if not sc.is_mounted():
		sc.auto_mount()
	var Xmidi = load("res://scripts/formats/xmidi.gd")
	var Fm = load("res://scripts/audio/fm_synth.gd")
	var Pak = load("res://scripts/formats/pak_archive.gd")
	var bank: Dictionary = Fm.load_bank(sc.read("SOUND/STRIKE.AD"))
	_check("timbre bank", bank.size() > 150, str(bank.size()))
	for f in ["SOUND/GAMEFLOW.ADL", "SOUND/COMBAT.ADL", "MIDGAMES/AMUSIC.PAK"]:
		var entries: Array = Pak.entries(sc.read(f))
		var seqs := 0
		var notes := 0
		var missing := {}
		for e in entries:
			for s in Xmidi.sequences(e):
				seqs += 1
				for ev in s.events:
					if (ev[1] & 0xF0) == 0x90:
						notes += 1
				for tb in s.timbres:
					var k: int = (tb[1] << 8) | tb[0]
					if not bank.has(k) and tb[1] != 127:
						missing[k] = true
		_check("%s: %d entries, %d sequences, %d notes" % [f, entries.size(), seqs, notes], seqs > 0 and notes > 100)
		_check("%s timbres in the bank" % f, missing.size() <= 3, str(missing.keys().slice(0, 5)))
	var t0 := Time.get_ticks_msec()
	var silent := 0
	var count := 0
	for k in bank.keys().slice(0, 40):
		var w: AudioStreamWAV = Fm.render(bank[k])
		count += 1
		var peak := 0
		for i in range(0, w.data.size() - 1, 64):
			peak = maxi(peak, absi(w.data.decode_s16(i)))
		if peak < 200:
			silent += 1
	var ms := Time.get_ticks_msec() - t0
	_check("rendered %d instruments in %d ms" % [count, ms], ms < count * 400, "")
	_check("instruments are audible", silent <= 4, "%d silent" % silent)
	print("music_test failures=%d" % failures)
	quit(failures)


func _check(name: String, ok: bool, detail := "") -> void:
	print("%s %s %s" % ["PASS" if ok else "FAIL", name, detail])
	if not ok:
		failures += 1
