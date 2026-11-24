## Headless checks for the weapon-loading screen: the player must be able to
## change the configuration, pairs may split across single-slot wingtips,
## removals work, gun-only is valid, and the screen shows only original art.
extends SceneTree


func _initialize() -> void:
	await process_frame
	var sc = root.get_node("SCData")
	if not sc.is_mounted():
		sc.auto_mount()
	var LoadoutScreen = load("res://scripts/ui/loadout_screen.gd")
	var failures := 0
	var s = LoadoutScreen.new()
	root.add_child(s)
	await process_frame
	var inv := {"AMRAAM": 12, "SWINDERM": 12, "MK82": 12, "AGM-65D": 12}
	s.setup_for_mission(null, "OBJECTS/F-16DES.IFF", inv)
	if not s.get_loadout().is_empty():
		print("FAIL screen starts with a pre-filled loadout")
		failures += 1
	# Only the original background picture: no 3D model loaded from assets.
	var has_bg := false
	for c in s.get_children():
		if c is TextureRect and c.texture != null:
			has_bg = true
		if c is Node3D or c is SubViewportContainer:
			print("FAIL screen contains a 3D aircraft/viewport node: ", c.name)
			failures += 1
	if not has_bg:
		print("FAIL original weapon-screen background art was not composited")
		failures += 1
	# Adding must work from an empty configuration, including on wingtip
	# stations that hold a single missile each.
	s._try_add_weapon("AMRAAM", "air")
	if int(s.get_loadout().get("AMRAAM", 0)) != 2:
		print("FAIL first add did not load a pair")
		failures += 1
	for hp in s._hardpoints:
		if int(hp.used) > int(hp.max):
			print("FAIL station overfilled after add: ", hp)
			failures += 1
	# A second, different weapon must also fit (the configuration is editable).
	s._try_add_weapon("MK82", "bomb")
	if int(s.get_loadout().get("MK82", 0)) != 2:
		print("FAIL second add was rejected - configuration cannot be changed")
		failures += 1
	for hp in s._hardpoints:
		if int(hp.used) > int(hp.max):
			print("FAIL station overfilled after second add: ", hp)
			failures += 1
	# Removing the last of a type must leave no zero-count entry.
	s._try_remove_weapon("AMRAAM", "air")
	if s.get_loadout().has("AMRAAM"):
		print("FAIL remove left a zero-count entry")
		failures += 1
	var got := []
	s.fly_requested.connect(func(l): got.append(l))
	s._loadout.clear()
	s._on_fly_pressed()
	if got.size() != 1 or int(got[0].get("VULCAN", 0)) <= 0:
		print("FAIL gun-only flight was rejected")
		failures += 1
	print("loadout_test failures=", failures)
	quit(failures)
