with open('C:/AI_Projektit/strike commander/game/scripts/ui/base_screen.gd', 'r', encoding='utf-8') as f:
    content = f.read()

old = '\t\t\t_hotspots.map(func(x): return "%s%s" % [x.label, "*" if x.node else ""]])'
new = '\t\t\t_hotspots.map(func(x): return "%s%s" % [x.label, "*" if x.node else ""]))'

if old in content:
    content = content.replace(old, new)
    with open('C:/AI_Projektit/strike commander/game/scripts/ui/base_screen.gd', 'w', encoding='utf-8') as f:
        f.write(content)
    print('Fixed extra parenthesis')
else:
    print('Old code not found')
    idx = content.find('_hotspots.map(func(x): return')
    if idx >= 0:
        print('Found at:', idx)
        print(repr(content[idx:idx+100]))