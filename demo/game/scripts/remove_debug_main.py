with open('C:/AI_Projektit/strike commander/game/scripts/main.gd', 'r', encoding='utf-8') as f:
    content = f.read()

# Remove debug prints
content = content.replace('print("CMDLINE ARGS: %s" % OS.get_cmdline_user_args())', '')

with open('C:/AI_Projektit/strike commander/game/scripts/main.gd', 'w', encoding='utf-8') as f:
    f.write(content)
print('Removed main.gd debug prints')