"""Replay a recorded display list (reference for the Godot player)."""
import json, struct, sys, os
sys.path.insert(0, os.path.dirname(__file__))
from arc import arc, entries, unpack
from shp import frames, decode_frame
from PIL import Image
import sclib

d = json.load(open(sys.argv[1]))
times = [int(x) for x in sys.argv[2].split(',')]
prefix = sys.argv[3] if len(sys.argv) > 3 else 'tl'
cache = {}


def shape(name, idx):
    k = (name, idx)
    if k not in cache:
        blob = arc(name)
        if idx >= 0:
            e, f = sclib.pak(blob)[idx]
            blob = sclib.lzw(e[4:]) if f == 0x20 else e
        cache[k] = [decode_frame(f) + (struct.unpack_from('<hhhh', f, 0),) for f in frames(blob)]
    return cache[k]


bufs = {}
tables = {}
surf = {}
pal = bytearray(768)


def buf(seg):
    return bufs.setdefault(seg, bytearray(0x10000))


def at(s, x, y):
    seg, base, stride = surf[s]
    return buf(seg), (base + y * stride + x) & 0xffff


def put(s, x, y, c):
    b, i = at(s, x, y)
    b[i] = c


def snap(t):
    if 'screen' not in surf:
        return
    seg, base, stride = surf['screen']
    b = buf(seg)
    img = Image.frombytes('P', (320, 200), bytes(b[base:base + 64000]))
    img.putpalette(bytes(min(255, c * 4) for c in pal))
    img.convert('RGB').save('%s_%06d.png' % (prefix, t))


shot = 0
for op in d['ops']:
    while shot < len(times) and op[0] > times[shot]:
        snap(times[shot]); shot += 1
    kind = op[1]
    if kind == 'surface':
        surf[op[2]] = (op[3], op[4], op[5])
    elif kind == 'table':
        tables[op[2]] = op[3]
    elif kind == 'pal':
        pal[op[2] * 3:op[2] * 3 + len(op[3])] = bytes(op[3])
    elif kind == 'fill':
        x1, y1, x2, y2 = op[4]
        for y in range(y1, y2 + 1):
            for x in range(x1, x2 + 1):
                put(op[2], x, y, op[3])
    elif kind in ('draw', 'sdraw'):
        fr = shape(op[3], op[4])
        if op[5] >= len(fr):
            continue
        w, h, img, (fx2, fx1, fy1, fy2) = fr[op[5]]
        sx = op[8] / 256 if kind == 'sdraw' else 1
        sy = op[9] / 256 if kind == 'sdraw' else 1
        first, count, tid = (op[10], op[11], op[12]) if kind == 'sdraw' else (256, 0, -1)
        for (px, py), c in img.items():
            shade = first <= c < first + count
            dx, dy = px - fx1, py - fy1     # offset from the hotspot
            X0 = op[6] + int(dx * sx); Y0 = op[7] + int(dy * sy)
            for yy in range(max(1, int(sy + 0.999))):
                for xx in range(max(1, int(sx + 0.999))):
                    X, Y = X0 + xx, Y0 + yy
                    if 0 <= X < 320 and 0 <= Y < 200:
                        if shade:
                            b, i = at(op[2], X, Y)
                            b[i] = tables[tid][(c - first) * 256 + b[i]]
                        else:
                            put(op[2], X, Y, c)
    elif kind == 'copy':
        sx1, sy1, sx2, sy2 = op[4]; dx1, dy1, dx2, dy2 = op[5]
        w = min(sx2 - sx1, dx2 - dx1) + 1; h = min(sy2 - sy1, dy2 - dy1) + 1
        for y in range(h):
            sb, si = at(op[2], sx1, sy1 + y)
            db, di = at(op[3], dx1, dy1 + y)
            db[di:di + w] = sb[si:si + w]
while shot < len(times):
    snap(times[shot]); shot += 1
