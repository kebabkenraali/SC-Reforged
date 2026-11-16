with open('C:/AI_Projektit/strike commander/game/scripts/ui/conversation_player.gd', 'r', encoding='utf-8') as f:
    content = f.read()

old = '''_talking = stream != null and not _mouth_frames.is_empty()
	var t := 0.0
	while t < duration and not _advance and not _skip:'''

new = '''_talking = stream != null and not _mouth_frames.is_empty()
	# Auto-advance in demo/headless mode (--demo or --auto)
	var auto_advance := OS.get_cmdline_user_args().has("--demo") or OS.get_cmdline_user_args().has("--auto")
	var t := 0.0
	while t < duration and not _advance and not _skip and not auto_advance:'''

if old in content:
    content = content.replace(old, new)
    with open('C:/AI_Projektit/strike commander/game/scripts/ui/conversation_player.gd', 'w', encoding='utf-8') as f:
        f.write(content)
    print('Added auto-advance for demo mode')
else:
    print('Old code not found')
    idx = content.find('_talking = stream != null')
    if idx >= 0:
        print('Found at:', idx)
        print(repr(content[idx:idx+200]))