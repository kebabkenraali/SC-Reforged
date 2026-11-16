## Diagnostic: does ExternalModels find/load the .glb drop-ins for each aircraft?
extends SceneTree

const ExternalModels = preload("res://scripts/game/external_models.gd")

func _init() -> void:
	print("=== scanning res://models/ ===")
	var d := DirAccess.open("res://models/")
	if d == null:
		print("models dir NOT FOUND")
	else:
		var files := d.get_files()
		print("files in models/: ", files.size())
		var glbs := 0
		for f in files:
			if f.to_upper().ends_with(".GLB"):
				glbs += 1
		print("glb count: ", glbs)
	print("=== override_mesh per aircraft ===")
	var probes := ["OBJECTS/F-16DES.IFF", "OBJECTS/MIG29.IFF", "OBJECTS/MIG21.IFF", "OBJECTS/F14_TOMCAT.glb"]
	for p in probes:
		var m = ExternalModels.override_mesh(p)
		if m == null:
			print("  %s -> null (no glb match)" % p)
		else:
			print("  %s -> mesh ok, surfaces=%d size=%s" % [p, m.get_surface_count(), str(m.get_aabb().size)])
	quit()

