with open('C:/AI_Projektit/strike commander/game/scripts/main.gd', 'r', encoding='utf-8') as f:
    content = f.read()

old = '''func _ready() -> void:
	# Keep screenshots, input and screen switching alive while the game is paused.
	process_mode = Node.PROCESS_MODE_ALWAYS
	for a in OS.get_cmdline_user_args():'''

new = '''func _ready() -> void:
	# Keep screenshots, input and screen switching alive while the game is paused.
	process_mode = Node.PROCESS_MODE_ALWAYS
	print("CMDLINE ARGS: %s" % OS.get_cmdline_user_args())
	for a in OS.get_cmdline_user_args():'''

if old in content:
    content = content.replace(old, new)
    with open('C:/AI_Projektit/strike commander/game/scripts/main.gd', 'w', encoding='utf-8') as f:
        f.write(content)
    print('Added debug print to main.gd')
else:
    print('Old code not found')
    idx = content.find('func _ready() -> void:')
    if idx >= 0:
        print('Found at:', idx)
        print(repr(content[idx:idx+200]))