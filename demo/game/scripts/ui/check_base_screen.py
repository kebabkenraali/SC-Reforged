with open('C:/AI_Projektit/strike commander/game/scripts/ui/base_screen.gd', 'r', encoding='utf-8') as f:
    content = f.read()

# Check for syntax issues
lines = content.split('\n')
for i, line in enumerate(lines):
    stripped = line.strip()
    # Check for unmatched quotes
    if stripped.count('"') % 2 != 0:
        print(f'Line {i+1}: Unmatched quotes: {line}')
    if stripped.startswith('if ') and not (stripped.endswith(':') or stripped.endswith('\\\\')):
        if any(op in stripped for op in ['and', 'or', 'not', 'in', '==', '!=', '<', '>', '<=', '>=']):
            print(f'Line {i+1}: Possible missing colon: {line}')
    if stripped.startswith('elif ') and not stripped.endswith(':'):
        print(f'Line {i+1}: Missing colon on elif: {line}')
    if stripped.startswith('else:') and not stripped.endswith(':'):
        print(f'Line {i+1}: Missing colon on else: {line}')
    if stripped.startswith('for ') and not stripped.endswith(':'):
        print(f'Line {i+1}: Missing colon on for: {line}')
    if stripped.startswith('while ') and not stripped.endswith(':'):
        print(f'Line {i+1}: Missing colon on while: {line}')
    if stripped.startswith('match ') and not stripped.endswith(':'):
        print(f'Line {i+1}: Missing colon on match: {line}')
    if stripped.startswith('func ') and not (stripped.endswith(':') or '->' in stripped):
        print(f'Line {i+1}: Missing colon on func: {line}')
    if stripped.startswith('func ') and stripped.count('(') > stripped.count(')'):
        print(f'Line {i+1}: Unbalanced parens in func: {line}')
    if stripped.startswith('for ') and stripped.count('(') > stripped.count(')'):
        print(f'Line {i+1}: Unbalanced parens in for: {line}')
    if stripped.startswith('func ') and stripped.count('(') != stripped.count(')'):
        print(f'Line {i+1}: Unbalanced parens in func signature: {line}')
    # Check for unmatched parentheses in general
    if line.count('(') != line.count(')'):
        if 'func ' in line or 'if ' in line or 'elif ' in line or 'for ' in line or 'while ' in line:
            print(f'Line {i+1}: Unbalanced parens in statement: {line}')

print('Done checking base_screen.gd')