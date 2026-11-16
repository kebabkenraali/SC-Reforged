with open('C:/AI_Projektit/strike commander/game/scripts/ui/base_screen.gd', 'r', encoding='utf-8') as f:
    content = f.read()

old = '''func _process(dt: float) -> void:
	_anim_t += dt
	var step := int(_anim_t * 8.0)
	for h in _hotspots:
		if h.overlay != null:
			h.overlay.texture = h.frames[step % h.frames.size()]

	# Auto-activate first available hotspot in demo/auto mode
	if (OS.get_cmdline_user_args().has("--demo") or OS.get_cmdline_user_args().has("--auto")) and not _auto_activated:'''

new = '''func _process(dt: float) -> void:
	print("BASE _process called, hotspots=%d" % _hotspots.size())
	_anim_t += dt
	var step := int(_anim_t * 8.0)
	for h in _hotspots:
		if h.overlay != null:
			h.overlay.texture = h.frames[step % h.frames.size()]

	# Auto-activate first available hotspot in demo/auto mode
	if (OS.get_cmdline_user_args().has("--demo") or OS.get_cmdline_user_args().has("--auto")) and not _auto_activated:
		print("BASE _process: checking auto-activate, hotspots=%d, auto_activated=%s" % [_hotspots.size(), _auto_activated])'''

if old in content:
    content = content.replace(old, new)
    with open('C:/AI_Projektit/strike commander/game/scripts/ui/base_screen.gd', 'w', encoding='utf-8') as f:
        f.write(content)
    print('Added debug print')
else:
    print('Old code not found')