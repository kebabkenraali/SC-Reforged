with open('C:/AI_Projektit/strike commander/game/scripts/ui/base_screen.gd', 'r', encoding='utf-8') as f:
    content = f.read()

old = '''	# Auto-activate first available hotspot in demo/auto mode
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

new = '''	# Auto-activate hotspot in demo/auto mode - smart selection to find mission
	# Check for --auto or --auto=... in raw cmdline args
	var is_auto := false
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--auto"):
			is_auto = true
			break
	if (OS.get_cmdline_user_args().has("--demo") or is_auto) and not _auto_activated:
		print("BASE _process: checking auto-activate, hotspots=%d" % _hotspots.size())
		if not _auto_activated:
			_auto_activated = true
			# Priority order: Transport > Fly Mission > Conversation > Other
			var priority_order := ["Transport", "Fly", "Talk", "Enter", "Look", "Return"]
			var best_hotspot := null
			var best_priority := priority_order.size()
			
			for h in _hotspots:
				if not h.gf or not campaign.available(h.gf):
					continue
				# Check if we've visited this screen via this hotspot before
				var label := h.label
				var priority := priority_order.size()
				for i in range(priority_order.size()):
					if label.contains(priority_order[i]):
						priority = i
						break
				if priority < best_priority:
					best_priority = priority
					best_hotspot = h
			
			if best_hotspot:
				print("BASE: auto-activating hotspot %s (priority %d)" % [best_hotspot.label, best_priority])
				_activate(_hotspots.find(best_hotspot))
			elif _hotspots.size() > 0:
				# Fallback: first available
				for h in _hotspots:
					if h.gf and campaign.available(h.gf):
						print("BASE: auto-activating fallback hotspot %s" % h.label)
						_activate(_hotspots.find(h))
						break'''

if old in content:
    content = content.replace(old, new)
    with open('C:/AI_Projektit/strike commander/game/scripts/ui/base_screen.gd', 'w', encoding='utf-8') as f:
        f.write(content)
    print('Updated with smart priority')
else:
    print('Old code not found')
    idx = content.find('Auto-activate hotspot in demo/auto mode')
    if idx >= 0:
        print('Found at:', idx)
        print(repr(content[idx:idx+800]))