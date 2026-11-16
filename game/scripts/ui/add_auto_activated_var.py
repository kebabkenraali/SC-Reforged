with open('C:/AI_Projektit/strike commander/game/scripts/ui/base_screen.gd', 'r', encoding='utf-8') as f:
    content = f.read()

old = '''var _hotspots: Array = []        # [{ gf: gameflow sprite, rect: Rect2i, label, frames, node }]
var _focus := -1
var _anim_t := 0.0
var _smooth := false'''

new = '''var _hotspots: Array = []        # [{ gf: gameflow sprite, rect: Rect2i, label, frames, node }]
var _focus := -1
var _anim_t := 0.0
var _auto_activated := false
var _smooth := false'''

if old in content:
    content = content.replace(old, new)
    with open('C:/AI_Projektit/strike commander/game/scripts/ui/base_screen.gd', 'w', encoding='utf-8') as f:
        f.write(content)
    print('Added _auto_activated variable')
else:
    print('Old code not found')