## Demo build: the opening cut-scene, the first base and the first campaign
## mission (MISN-1A), then an end screen. On when the project contains
## res://demo.cfg (the packaged demo) or the game is started with --demo.
extends RefCounted

const LAST_MISSION := 0          # campaign mission index that ends the demo (MISN-1A)


static func enabled() -> bool:
	return FileAccess.file_exists("res://demo.cfg") or OS.get_cmdline_user_args().has("--demo")
