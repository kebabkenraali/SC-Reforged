with open('C:/AI_Projektit/strike commander/game/scripts/game/flight_scene.gd', 'r', encoding='utf-8') as f:
    content = f.read()

old = '''func _ready() -> void:
	var t0 := Time.get_ticks_msec()'''

new = '''func _ready() -> void:
	print("FLIGHTSCENE _ready: autopilot=%s" % autopilot)
	var t0 := Time.get_ticks_msec()'''

if old in content:
    content = content.replace(old, new)
    with open('C:/AI_Projektit/strike commander/game/scripts/game/flight_scene.gd', 'w', encoding='utf-8') as f:
        f.write(content)
    print('Added debug print to flight_scene.gd _ready')
else:
    print('Old code not found')
    idx = content.find('func _ready() -> void:')
    if idx >= 0:
        print('Found at:', idx)
        print(repr(content[idx:idx+200]))