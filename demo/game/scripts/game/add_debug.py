with open('C:/AI_Projektit/strike commander/game/scripts/game/flight_scene.gd', 'r', encoding='utf-8') as f:
    content = f.read()

old = '''# Combat autopilot (original --autopilot flag)
	if autopilot:'''

new = '''# Combat autopilot (original --autopilot flag)
	if autopilot:
		print("AUTOPILOT ACTIVE: on_ground=%s speed=%.1f" % [player.on_ground, player.speed()])'''

if old in content:
    content = content.replace(old, new)
    with open('C:/AI_Projektit/strike commander/game/scripts/game/flight_scene.gd', 'w', encoding='utf-8') as f:
        f.write(content)
    print('Added debug print')
else:
    print('Old code not found')
    # Find the actual text
    idx = content.find('Combat autopilot')
    if idx >= 0:
        print('Found at:', idx)
        print(repr(content[idx:idx+100]))