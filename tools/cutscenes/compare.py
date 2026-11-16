"""Compares the Godot player with the original, frame by frame.

usage: compare.py name N|eN outdir [count]
Picks `count` moments spread over the timeline, renders them with the Godot
player (tests/vm_render.gd) and with the emulator (reference.py) and prints the
share of differing pixels. A side-by-side sheet goes to outdir/sheet.png.
"""
import json, os, subprocess, sys
from PIL import Image, ImageChops

ROOT = os.path.dirname(os.path.dirname(os.path.dirname(os.path.abspath(__file__))))
GODOT = os.path.join(ROOT, 'tools', 'godot', 'Godot_v4.7.2-stable_win64.exe')

name, arg, out = sys.argv[1], sys.argv[2], os.path.abspath(sys.argv[3])
count = int(sys.argv[4]) if len(sys.argv) > 4 else 8
os.makedirs(out, exist_ok=True)
ops = json.load(open(os.path.join(ROOT, 'game', 'data', 'cutscenes', name + '.json')))['ops']
# the original returns right after its last frame (subtitle clears may come later)
end = max(o[0] for o in ops if o[1] != 'subtitle') - 200
copies = [o[0] for o in ops if o[1] == 'copy']
times = []
for k in range(1, count + 1):
    target = end * k / (count + 1)
    # sample just before a display update so both sides show a finished frame
    after = [c for c in copies if c >= target]
    times.append(int(after[0]) - 1 if after else int(target))
ts = ','.join(str(t) for t in times)
subprocess.run([sys.executable, os.path.join(os.path.dirname(__file__), 'reference.py'), arg, ts, out], check=True)
subprocess.run([GODOT, '--headless', '--path', os.path.join(ROOT, 'game'), '--script', 'res://tests/vm_render.gd', '--', name, ts, out],
               check=True, capture_output=True)
sheet = Image.new('RGB', (640, 200 * len(times)))
worst = 0.0
for i, t in enumerate(times):
    a = Image.open(os.path.join(out, 'ref_%06d.png' % t)).convert('RGB')
    b = Image.open(os.path.join(out, 'vm_%06d.png' % t)).convert('RGB')
    diff = ImageChops.difference(a, b).convert('L').point(lambda v: 255 if v > 24 else 0)
    share = sum(diff.histogram()[255:]) / (320 * 200)
    worst = max(worst, share)
    sheet.paste(a, (0, 200 * i)); sheet.paste(b, (320, 200 * i))
    print('%s t=%6d ms  differing pixels %5.1f %%' % (name, t, share * 100))
sheet.save(os.path.join(out, 'sheet.png'))
print('%s worst %.1f %%' % (name, worst * 100))
