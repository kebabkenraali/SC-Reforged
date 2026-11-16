with open('C:/AI_Projektit/strike commander/game/scripts/ui/conversation_player.gd', 'r', encoding='utf-8') as f:
    content = f.read()

old = '''func _ask(options: Array) -> int:
	for c in _choices.get_children():
		c.queue_free()
	var picked := [-1]
	for k in options.size():
		var b := Button.new()
		b.text = options[k]
		b.pressed.connect(func(): picked[0] = k)
		_choices.add_child(b)
	_choices.get_child(0).grab_focus()
	while picked[0] < 0 and not _skip:
		await get_tree().process_frame'''

new = '''func _ask(options: Array) -> int:
	for c in _choices.get_children():
		c.queue_free()
	var picked := [-1]
	for k in options.size():
		var b := Button.new()
		b.text = options[k]
		b.pressed.connect(func(): picked[0] = k)
		_choices.add_child(b)
	_choices.get_child(0).grab_focus()
	# Auto-answer in demo/headless mode: Yes (0) for yes/no, first wingman for wingman selection
	var auto_advance := OS.get_cmdline_user_args().has("--demo") or OS.get_cmdline_user_args().has("--auto")
	if auto_advance:
		picked[0] = 0
	while picked[0] < 0 and not _skip and not auto_advance:
		await get_tree().process_frame'''

if old in content:
    content = content.replace(old, new)
    with open('C:/AI_Projektit/strike commander/game/scripts/ui/conversation_player.gd', 'w', encoding='utf-8') as f:
        f.write(content)
    print('Added auto-advance for _ask')
else:
    print('Old code not found')
    idx = content.find('func _ask(options: Array) -> int:')
    if idx >= 0:
        print('Found at:', idx)
        print(repr(content[idx:idx+300]))