with open('C:/AI_Projektit/strike commander/game/scripts/ui/base_screen.gd', 'r', encoding='utf-8') as f:
    content = f.read()

old = '_hotspots.map(func(x): return "%s%s" % [x.label, "*" if x.node else ""])])\n\n\nfunc _process(dt: float) -> void:'
new = '_hotspots.map(func(x): return "%s%s" % [x.label, "*" if x.node else ""]))\n\n\nfunc _process(dt: float) -> void:'

if old in content:
    content = content.replace(old, new)
    with open('C:/AI_Projektit/strike commander/game/scripts/ui/base_screen.gd', 'w', encoding='utf-8') as f:
        f.write(content)
    print('Fixed extra parenthesis')
else:
    print('Old code not found')