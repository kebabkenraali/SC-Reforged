with open('C:/AI_Projektit/strike commander/game/scripts/ui/base_screen.gd', 'r', encoding='utf-8') as f:
    content = f.read()

old = '''			for h in _hotspots:
				if not h.gf or not campaign.available(h.gf):
					continue'''

new = '''			for h in _hotspots:
				print("BASE: checking hotspot '%s', gf=%s, available=%s" % [h.label, h.gf, campaign.available(h.gf) if h.gf else 'no gf'])
				if not h.gf or not campaign.available(h.gf):
					continue'''

if old in content:
    content = content.replace(old, new)
    with open('C:/AI_Projektit/strike commander/game/scripts/ui/base_screen.gd', 'w', encoding='utf-8') as f:
        f.write(content)
    print('Added debug')
else:
    print('Old code not found')
    # Find all occurrences
    import re
    for m in re.finditer(r'for h in _hotspots:', content):
        idx = m.start()
        print(f'Found at {idx}: {repr(content[idx:idx+100])}')