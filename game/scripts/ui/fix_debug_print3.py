with open('C:/AI_Projektit/strike commander/game/scripts/ui/base_screen.gd', 'r', encoding='utf-8') as f:
    content = f.read()

old = '''	if OS.is_debug_build():
		print("BASE screen=%d stage=%d hotspots=%s" % [id, campaign.stage,
		_hotspots.map(func(x): return "%s%s" % [x.label, "*" if x.node else ""]))'''

new = '''	if OS.is_debug_build():
		print("BASE screen=%d stage=%d hotspots=%s" % [id, campaign.stage, _hotspots.map(func(x): return "%s%s" % [x.label, "*" if x.node else ""])])'''

if old in content:
    content = content.replace(old, new)
    with open('C:/AI_Projektit/strike commander/game/scripts/ui/base_screen.gd', 'w', encoding='utf-8') as f:
        f.write(content)
    print('Fixed debug print statement')
else:
    print('Old code not found')
    idx = content.find('if OS.is_debug_build():')
    if idx >= 0:
        print('Found at:', idx)
        print(repr(content[idx:idx+300]))