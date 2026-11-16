with open('C:/AI_Projektit/strike commander/game/scripts/ui/base_screen.gd', 'r', encoding='utf-8') as f:
    content = f.read()

# Find the exact pattern with the dashes
import re
pattern = r'(elif _hotspots\.size\(\) > 0:\n\s*# Fallback: first available\n\s*for h in _hotspots:\n\s*if h\.gf and campaign\.available\(h\.gf\):\n\s*print\("BASE: auto-activating fallback hotspot %s" % h\.label\)\n\s*_activate\(_hotspots\.find\(h\)\)\n\s*break)# --- input'

new_text = '''elif _hotspots.size() > 0:
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

new_content = re.sub(pattern, new_text, content, flags=re.DOTALL)

if new_content != content:
    with open('C:/AI_Projektit/strike commander/game/scripts/ui/base_screen.gd', 'w', encoding='utf-8') as f:
        f.write(new_content)
    print('Updated fallback logic with regex')
else:
    print('Pattern not found')