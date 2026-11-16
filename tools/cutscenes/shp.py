from sclib import *
import zlib, sys


def pngrgb(path, w, h, px):
    raw = b''.join(b'\0' + bytes(px[y * w * 3:(y + 1) * w * 3]) for y in range(h))
    def ch(t, d): return struct.pack('>I', len(d)) + t + d + struct.pack('>I', zlib.crc32(t + d) & 0xffffffff)
    open(path, 'wb').write(b'\x89PNG\r\n\x1a\n' + ch(b'IHDR', struct.pack('>IIBBBBB', w, h, 8, 2, 0, 0, 0)) + ch(b'IDAT', zlib.compress(raw)) + ch(b'IEND', b''))


def unpack(e):
    """PAK entry -> raw bytes (0x20 entries are u32 size + LZW)."""
    return e


def frames(shp):
    """Shape file: u32 total size, u32 frame offsets... Returns list of frame byte slices."""
    first = struct.unpack_from('<I', shp, 4)[0]
    offs = [struct.unpack_from('<I', shp, i)[0] for i in range(4, first, 4)]
    offs.append(len(shp))
    return [shp[offs[i]:offs[i + 1]] for i in range(len(offs) - 1)]


def decode_frame(f):
    """Wing Commander style RLE shape: i16 x2, x1, y1, y2 then line records."""
    x2, x1, y1, y2 = struct.unpack_from('<hhhh', f, 0)
    w = x1 + x2 + 1
    h = y1 + y2 + 1
    img = {}
    i = 8
    while i + 2 <= len(f):
        key = struct.unpack_from('<H', f, i)[0]
        i += 2
        if key == 0:
            break
        dx, dy = struct.unpack_from('<hh', f, i)
        i += 4
        count = key >> 1
        x = dx + x1
        y = dy + y1
        if key & 1:
            end = x + count
            while x < end:
                b = f[i]; i += 1
                n = b >> 1
                if b & 1:
                    c = f[i]; i += 1
                    for k in range(n): img[(x + k, y)] = c
                else:
                    for k in range(n): img[(x + k, y)] = f[i + k]
                    i += n
                x += n
        else:
            for k in range(count): img[(x + k, y)] = f[i + k]
            i += count
    return w, h, img


def render(path, w, h, img, pal):
    px = bytearray(w * h * 3)
    for (x, y), c in img.items():
        if 0 <= x < w and 0 <= y < h:
            o = (y * w + x) * 3
            px[o:o + 3] = bytes(min(255, pal[c * 3 + k] * 4) for k in range(3))
    pngrgb(path, w, h, px)
