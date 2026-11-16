with open('C:/AI_Projektit/strike commander/game/scripts/ui/base_screen.gd', 'r', encoding='utf-8') as f:
    content = f.read()

old = '''if (OS.get_cmdline_user_args().has("--demo") or is_auto) and not _auto_activated:
		print("BASE _process: checking auto-activate, hotspots=%d" % _hotspots.size())
		if not _auto_activated:
			_auto_activated = true
			print("BASE: PRIORITY LOOP START, hotspots=%d" % _hotspots.size())'''

new = '''if (OS.get_cmdline_user_args().has("--demo") or is_auto) and not _auto_activated:
		print("BASE _process: checking auto-activate, hotspots=%d" % _hotspots.size())
		print("BASE: AUTO-ACTIVATE BLOCK ENTERED, _auto_activated was=%s" % _auto_activated)
		if not _auto_activated:
			_auto_activated = true
			print("BASE: _auto_activated set to true, entering priority loop")
			print("BASE: PRIORITY LOOP START, hotspots=%d" % _hotspots.size())'''

if old in content:
    content = content.replace(old, new)
    with open('C:/AI_Projektit/strike commander/game/scripts/ui/base_screen.gd', 'w', encoding='utf-8') as f:
        f.write(content)
    print('Added entry debug')
else:
    print('Old code not found')
    idx = content.find('Auto-activate hotspot in demo/auto mode')
    if idx >= 0:
        print('Found at:', idx)
        print(repr(content[idx:idx+500]))