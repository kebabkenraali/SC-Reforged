## Every mission selection in GAMEFLOW.IFF / GAMEFLO2.IFF must resolve to the
## same file as the original: effect `0c n` / `03 n` indexes FORM MLST directly.
## The campaign list must therefore contain ALL MLST entries, including the
## alternates (5BB, 9AA, 6X, ...) and the add-on's empty slots.
extends SceneTree


var failures := 0


func _initialize() -> void:
	await process_frame
	var sc = root.get_node("SCData")
	if not sc.is_mounted():
		sc.auto_mount()
	var Art = load("res://scripts/core/art.gd")
	var GF = load("res://scripts/formats/sc_gameflow.gd")
	var Campaign = load("res://scripts/game/campaign.gd")

	for setname in ["base", "tactical"]:
		Art.set_active(setname)
		var gf = GF.load_from(
			sc.read("GAMEFLOW/GAMEFLOW.IFF" if setname == "base" else "GAMEFLOW/GAMEFLO2.IFF"),
			sc.read("GAMEFLOW/OPTIONS.IFF" if setname == "base" else "GAMEFLOW/OPTIONS2.IFF"),
			sc.read("GAMEFLOW/CONVDATA.IFF" if setname == "base" else "GAMEFLOW/CONVDAT2.IFF"))
		var files: Array = Campaign.mission_files()
		_check("%s list size matches MLST" % setname, files.size() == gf.mission_list.size(),
			"%d vs %d" % [files.size(), gf.mission_list.size()])

		# Collect every mission number the campaign can select, from stage
		# effects and from hotspot sprite effects.
		var used := {}
		for s in gf.stages:
			for e in s.effects:
				if e[0] == 0x0c or e[0] == 0x03:
					used[int(e[1])] = true
			for scene in s.scenes.values():
				for sp in scene:
					for e in sp.effects:
						if e[0] == 0x0c or e[0] == 0x03:
							used[int(e[1])] = true
		var nums: Array = used.keys()
		nums.sort()
		var checked := 0
		for n in nums:
			var expected: String = "MISSIONS/" + String(gf.mission_list[n]) + ".IFF"
			var got: String = String(files[n]) if n < files.size() else "<missing index>"
			var exists: bool = sc.has(expected)
			var want: String = expected if exists else ""
			if got != want:
				_check("%s 0c %d -> %s" % [setname, n, expected], false, "got %s" % got)
				continue
			if exists:
				var m = sc.mission(got)
				if m == null:
					_check("%s 0c %d parses" % [setname, n], false, got)
					continue
			checked += 1
		_check("%s all %d selected missions resolve" % [setname, nums.size()], checked == nums.size(),
			"%d/%d" % [checked, nums.size()])
		# Explicitly cover the indices that a filtered list would shift.
		if setname == "base":
			_check("base alternate 5BB keeps index 12", String(files[12]).ends_with("MISN-5BB.IFF"), str(files[12]))
			_check("base alternate 9AA keeps index 25", String(files[25]).ends_with("MISN-9AA.IFF"), str(files[25]))
			_check("base 10A keeps index 28", String(files[28]).ends_with("MISN-10A.IFF"), str(files[28]))
		else:
			_check("tactical empty slot 2 is preserved", files[2] == "", str(files[2]))
			_check("tactical last mission keeps index 36", String(files[36]).ends_with("MISN-H1.IFF"), str(files[36]))
	Art.set_active("base")
	print("mission_index_test failures=", failures)
	quit(failures)


func _check(label: String, ok: bool, info: String) -> void:
	if not ok:
		failures += 1
	print("%s %s %s" % ["PASS" if ok else "FAIL", label, info])
