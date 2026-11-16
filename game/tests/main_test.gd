## Minimal test to check if autoloads work via main.tscn
extends SceneTree

func _init() -> void:
	print("=== MAIN SCENE TEST ===")
	print("Main scene exists: ", file_exists("res://scenes/main.tscn"))
	quit(0)

func file_exists(path: String) -> bool:
	var dir = DirAccess.open("res://")
	return dir.file_exists(path)
