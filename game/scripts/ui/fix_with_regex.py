with open('C:/AI_Projektit/strike commander/game/scripts/ui/base_screen.gd', 'r', encoding='utf-8') as f:
    content = f.read()

# Find the _process function and replace the auto-activate block
import re

# Pattern to match the current _process function with auto-activate logic
pattern = r'(func _process\(dt: float\) -> void:.*?# Auto-activate first available hotspot in demo/auto mode\s*\n\s*if \(OS\.get_cmdline_user_args\(\)\.has\("--demo"\) or OS\.get_cmdline_user_args\(\)\.has\("--auto"\)\) and not _auto_activated:.*?break\s*\n)'

new_func = '''func _process(dt: float) -> void:
	_anim_t += dt
	var step := int(_anim_t * 8.0)
	for h in _hotspots:
		if h.overlay != null:
			h.overlay.texture = h.frames[step % h.frames.size()]

	# Auto-activate first available hotspot in demo/auto mode
	# Check for --auto or --auto=... in raw cmdline args
	var is_auto := false
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--auto"):
			is_auto = true
			break
	if (OS.get_cmdline_user_args().has("--demo") or is_auto) and not _auto_activated:
		print("BASE _process: checking auto-activate, hotspots=%d, auto_activated=%s" % [_hotspots.size(), _auto_activated])
		if not _auto_activated:
			_auto_activated = true
			for h in _hotspots:
				if h.gf and campaign.available(h.gf):
					print("BASE: auto-activating hotspot %s" % h.label)
					_activate(_hotspots.find(h))
					break'''

# Use regex to replace
new_content = re.sub(pattern, new_func, content, flags=re.DOTALL)

if new_content != content:
    with open('C:/AI_Projektit/strike commander/game/scripts/ui/base_screen.gd', 'w', encoding='utf-8') as f:
        f.write(new_content)
    print('Updated with regex')
else:
    print('Pattern not matched')
    # Show what we have
    idx = content.find('func _process(dt: float) -> void:')
    if idx >= 0:
        print(repr(content[idx:idx+600]))