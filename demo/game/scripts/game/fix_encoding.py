with open('C:/AI_Projektit/strike commander/game/scripts/game/flight_scene.gd', 'r', encoding='utf-8') as f:
    content = f.read()

# Replace all non-ASCII characters
content = content.replace('\u2014', '-')  # em dash
content = content.replace('\u2013', '-')  # en dash
content = content.replace('\u2026', '...')  # ellipsis
content = content.replace('\u2018', "'")  # left single quote
content = content.replace('\u2019', "'")  # right single quote
content = content.replace('\u201c', '"')  # left double quote
content = content.replace('\u201d', '"')  # right double quote
content = content.replace('\ufffd', '->')  # replacement character

with open('C:/AI_Projektit/strike commander/game/scripts/game/flight_scene.gd', 'w', encoding='utf-8') as f:
    f.write(content)

print('Replaced all special characters')