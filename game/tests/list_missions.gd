extends Node

func _ready():
	print("=== MISSION LIST TEST ===")
	
	var sc = get_node("/root/SCData")
	if sc == null:
		print("ERROR: SCData not loaded")
		get_tree().quit(1)
	
	print("SCData found!")
	var err = sc.mount("C:/Gog games/Strike Commander")
	print("Mount result: ", err)
	
	var missions = sc.missions()
	print("Missions loaded: ", missions.size())
	for m in missions.slice(0, 10):
		print("  ", m.file, " - ", m.name, " (", m.area, ")")
	
	get_tree().quit(0)
