with open('C:/AI_Projektit/strike commander/game/scripts/ui/base_screen.gd', 'r', encoding='utf-8') as f:
    content = f.read()

old = '''elif _hotspots.size() > 0:
			# Fallback: first available
			for h in _hotspots:
				if h.gf and campaign.available(h.gf):
					print("BASE: auto-activating fallback hotspot %s" % h.label)
					_activate(_hotspots.find(h))
					break

# --- input'''

new = '''elif _hotspots.size() > 0:
			# Fallback: first available non-visited hotspot
			for h in _hotspots:
				if h.gf and campaign.available(h.gf):
					var visited := _visited_hotspots.get(campaign.screen, [])
					if h.label in visited:
						continue
					print("BASE: auto-activating fallback hotspot %s" % h.label)
					if not _visited_hotspots.has(campaign.screen):
						_visited_hotspots[campaign.screen] = []
					_visited_hotspots[campaign.screen].append(h.label)
					_activate(_hotspots.find(h))
					break

# --- input'''

if old in content:
    content = content.replace(old, new)
    with open('C:/AI_Projektit/strike commander/game/scripts/ui/base_screen.gd', 'w', encoding='utf-8') as f:
        f.write(content)
    print('Updated fallback logic')
else:
    print('Old code not found')
    idx = content.find('elif _hotspots.size() > 0:')
    if idx >= 0:
        print('Found at:', idx)
        print(repr(content[idx:idx+300]))