with open('C:/AI_Projektit/strike commander/game/scripts/ui/base_screen.gd', 'r', encoding='utf-8') as f:
    content = f.read()

import re

# Pattern to match the debug print statement
pattern = r'(\tif OS\.is_debug_build\(\):\n\t\tprint\("BASE screen=%d stage=%d hotspots=%s" % \[id, campaign\.stage,\n\t\t\t_hotspots\.map\(func\(x\): return "%s%s" % \[x\.label, "\*" if x\.node else ""\]\)\))'

new = '''	if OS.is_debug_build():
		print("BASE screen=%d stage=%d hotspots=%s" % [id, campaign.stage, _hotspots.map(func(x): return "%s%s" % [x.label, "*" if x.node else ""])])'''

new_content = re.sub(pattern, new, content, flags=re.DOTALL)

if new_content != content:
    with open('C:/AI_Projektit/strike commander/game/scripts/ui/base_screen.gd', 'w', encoding='utf-8') as f:
        f.write(new_content)
    print('Fixed debug print statement')
else:
    print('Pattern not found')
    idx = content.find('if OS.is_debug_build():')
    if idx >= 0:
        print('Found at:', idx)
        print(repr(content[idx:idx+300]))