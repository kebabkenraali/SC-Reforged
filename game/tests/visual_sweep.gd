## Visible sweep: opens every base screen and plays every original conversation
## in a real window, saving a screenshot of each screen and of sampled dialogues.
## Run (NOT --headless) with --demo so lines auto-advance:
##   Godot --path game --script res://tests/visual_sweep.gd -- --demo --dir=...
## Add --tactical to sweep GAMEFLO2.IFF / OPTIONS2.IFF / CONV2.PAK instead.
extends SceneTree

var OUT := "user://visual_sweep"

var failures := 0
var screens_seen := 0
var conversations_seen := 0
var blank_screens := 0
var blank_conversations := 0


func _initialize() -> void:
	await process_frame
	var sc = root.get_node("SCData")
	if not sc.is_mounted():
		sc.auto_mount()
	var Art = load("res://scripts/core/art.gd")
	var Campaign = load("res://scripts/game/campaign.gd")
	var BaseScreen = load("res://scripts/ui/base_screen.gd")
	var ConversationPlayer = load("res://scripts/ui/conversation_player.gd")
	var Pak = load("res://scripts/formats/pak_archive.gd")
	var tactical: bool = OS.get_cmdline_user_args().has("--tactical")
	if tactical:
		OUT = "user://tactical_visual_sweep"
		Art.set_active("tactical")
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(OUT))
	var gf = Art.gameflow()

	Campaign.save_path = "user://visual_sweep_campaign.json"
	var camp = Campaign.new()
	camp.tactical = tactical
	var base = BaseScreen.new()
	base.campaign = camp
	root.add_child(base)
	await process_frame

	# --- every room / screen -------------------------------------------------
	var ids: Array = gf.screens.keys()
	ids.sort()
	for id in ids:
		base._build_screen(int(id))
		await process_frame
		await RenderingServer.frame_post_draw
		var ok := _shot("screen_%02d" % int(id))
		screens_seen += 1
		if not ok:
			blank_screens += 1
	print("VISUAL screens=%d blank=%d" % [screens_seen, blank_screens])

	# --- every conversation --------------------------------------------------
	var conv_path: String = "GAMEFLOW/CONV2.PAK" if tactical else "GAMEFLOW/CONV.PAK"
	var conv_buf: PackedByteArray = sc.read(conv_path)
	var entries: Array = Pak.entries(conv_buf)
	var flags: Array = Pak.flags(conv_buf)
	for n in entries.size():
		if flags[n] == 0xFF:
			continue
		var p = ConversationPlayer.new()
		p.campaign = camp
		p.conv_index = n
		root.add_child(p)
		await p.play()
		conversations_seen += 1
		if conversations_seen % 20 == 0:
			print("VISUAL progress conversations=%d" % conversations_seen)
		if n % 10 == 0:
			await RenderingServer.frame_post_draw
			if not _shot("conv_%03d" % n):
				blank_conversations += 1
		p.queue_free()
	print("VISUAL conversations=%d blank_samples=%d" % [conversations_seen, blank_conversations])

	base.queue_free()
	failures = blank_screens
	print("visual_sweep failures=%d" % failures)
	quit(failures)


func _shot(name: String) -> bool:
	var img: Image = root.get_texture().get_image()
	if img == null or img.is_empty():
		return false
	var path := ProjectSettings.globalize_path(OUT + "/" + name + ".png")
	return img.save_png(path) == OK
