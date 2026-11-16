with open('C:/AI_Projektit/strike commander/game/scripts/ui/base_screen.gd', 'r', encoding='utf-8') as f:
    content = f.read()

old = '''func _process(dt: float) -> void:
	_anim_t += dt
	var step := int(_anim_t * 8.0)
	for h in _hotspots:
		if h.overlay != null:
			h.overlay.texture = h.frames[step % h.frames.size()]


# --- input -------------------------------------------------------------------------'''

new = '''func _process(dt: float) -> void:
	_anim_t += dt
	var step := int(_anim_t * 8.0)
	for h in _hotspots:
		if h.overlay != null:
			h.overlay.texture = h.frames[step % h.frames.size()]

	# Auto-activate first available hotspot in demo/auto mode
	if (OS.get_cmdline_user_args().has("--demo") or OS.get_cmdline_user_args().has("--auto")) and not _auto_activated:
		_auto_activated = true
		for h in _hotspots:
			if h.gf and campaign.available(h.gf):
				print("BASE: auto-activating hotspot %s" % h.label)
				_activate(_hotspots.find(h))
				break


# --- input -------------------------------------------------------------------------'''

if old in content:
    content = content.replace(old, new)
    with open('C:/AI_Projektit/strike commander/game/scripts/ui/base_screen.gd', 'w', encoding='utf-8') as f:
        f.write(content)
    print('Added auto-activate logic')
else:
    print('Old code not found')
    # Try with different newline handling
    import re
    matches = list(re.finditer(r'func _process\(dt: float\) -> void:', content))
    if matches:
        idx = matches[0].start()
        print('Found at:', idx)
        print(repr(content[idx:idx+400]))