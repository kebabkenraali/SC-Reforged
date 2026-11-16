## Lists the game files that mention cockpit data and tries to open a
## cockpit PAK with the existing readers (virtual cockpit feasibility probe).
extends SceneTree

func _initialize() -> void:
	await process_frame
	var sc = root.get_node("SCData")
	if not sc.is_mounted():
		sc.auto_mount()
	var hits := []
	for layer in ["", "COCKPITS/", "COCKPIT/"]:
		for n in sc.list(layer):
			if n.contains("COCK") or n.contains("CKPT"):
				hits.append(n)
	print("COCKPIT FILES: ", hits)
	var Pak = load("res://scripts/formats/pak_archive.gd")
	for n in hits.slice(0, 4):
		var buf: PackedByteArray = sc.read(n)
		print(n, " size=", buf.size(), " head=", buf.slice(0, 12).get_string_from_ascii() if buf.size() > 12 else "")
		var entries: Array = Pak.entries(buf)
		print("  pak entries: ", entries.size())
		var i := 0
		for e in entries:
			if i > 5:
				break
			print("   entry ", i, " size=", e.size(), " head=", e.slice(0, 8).get_string_from_ascii())
			i += 1
	quit(0)
