extends Node

func _ready():
	var sc = get_node("/root/SCData")
	print("SCData: ", sc != null)
	if sc:
		var missions = sc.missions()
		print("Missions: ", missions.size())
		for m in missions.slice(0, 5):
			print("  ", m.file)
	get_tree().quit(0)
