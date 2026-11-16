## Dumps the mission PARTS (model, side, leader) for a few missions.
extends SceneTree

func _initialize() -> void:
	await process_frame
	var sc = root.get_node("SCData")
	if not sc.is_mounted():
		sc.auto_mount()
	for mf in ["MISSIONS/MISN-1A.IFF", "MISSIONS/MISN-10A.IFF"]:
		var m = sc.mission(mf)
		var start = m.player_part()
		print("== ", mf, " start side=", start.side, " player=", start.model)
		for i in m.parts.size():
			var p: Dictionary = m.parts[i]
			var team := 1 if p.side == start.side else 2
			print("  part %d %s side=%d team=%d leader=%d pos=%s" % [i, p.model, p.side, team, p.leader, p.pos.round()])
	quit(0)
