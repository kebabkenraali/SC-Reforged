with open('C:/AI_Projektit/strike commander/game/scripts/game/flight_scene.gd', 'r', encoding='utf-8') as f:
    content = f.read()

old = 'for r in [Rect2(-half, -half, 2 * half, half - inner), Rect2(-half, inner, 2 * half, half - inner),]\n\t\t\tRect2(-half, -inner, half - inner, 2 * inner), Rect2(inner, -inner, half - inner, 2 * inner)]:'

new = 'for r in [Rect2(-half, -half, 2 * half, half - inner), Rect2(-half, inner, 2 * half, half - inner),\n\t\t\tRect2(-half, -inner, half - inner, 2 * inner), Rect2(inner, -inner, half - inner, 2 * inner)]:'

if old in content:
    content = content.replace(old, new)
    with open('C:/AI_Projektit/strike commander/game/scripts/game/flight_scene.gd', 'w', encoding='utf-8') as f:
        f.write(content)
    print('Fixed extra bracket')
else:
    print('Old code not found')
    idx = content.find('for r in [Rect2(-half, -half, 2 * half, half - inner), Rect2(-half, inner, 2 * half, half - inner),')
    if idx >= 0:
        print('Found at:', idx)
        print(repr(content[idx:idx+200]))