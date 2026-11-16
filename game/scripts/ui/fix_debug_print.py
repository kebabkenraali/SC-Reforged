with open('C:/AI_Projektit/strike commander/game/scripts/ui/base_screen.gd', 'r', encoding='utf-8') as f:
    content = f.read()

old = '''\tif OS.is_debug_build():
\t\tprint("BASE screen=%d stage=%d hotspots=%s" % [id, campaign.stage,
\t\t\t_hotspots.map(func(x): return "%s%s" % [x.label, "*" if x.node else ""]))'''

new = '''\tif OS.is_debug_build():
\t\tprint("BASE screen=%d stage=%d hotspots=%s" % [id, campaign.stage, _hotspots.map(func(x): return "%s%s" % [x.label, "*" if x.node else ""])])'''

if old in content:
    content = content.replace(old, new)
    with open('C:/AI_Projektit/strike commander/game/scripts/ui/base_screen.gd', 'w', encoding='utf-8') as f:
        f.write(content)
    print('Fixed debug print statement')
else:
    print('Old code not found')