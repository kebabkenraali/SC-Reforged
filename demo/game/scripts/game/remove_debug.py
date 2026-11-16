with open('C:/AI_Projektit/strike commander/game/scripts/game/flight_scene.gd', 'r', encoding='utf-8') as f:
    content = f.read()

# Remove debug prints
content = content.replace('print("AUTOPILOT ACTIVE: on_ground=%s speed=%.1f" % [player.on_ground, player.speed()])', '')
content = content.replace('print("FLIGHTSCENE _ready: autopilot=%s" % autopilot)', '')

with open('C:/AI_Projektit/strike commander/game/scripts/game/flight_scene.gd', 'w', encoding='utf-8') as f:
    f.write(content)
print('Removed flight_scene debug prints')