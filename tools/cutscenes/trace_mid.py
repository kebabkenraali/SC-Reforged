"""Run OPTTEST.EXE in the emulator and record a cut-scene as a display list.

Ops (t = milliseconds):
  [t, "draw", surf, archive, entry, frame, x, y]
  [t, "copy", src, dst, [sx1, sy1, sx2, sy2], [dx1, dy1, dx2, dy2]]
  [t, "fill", surf, color, [x1, y1, x2, y2]]
  [t, "pal", first, [r, g, b, ...]]          (6-bit VGA values)
Surfaces are named by their near pointer; "screen" is the display.
"""
import hashlib, json, os, struct, sys, time
sys.path.insert(0, os.path.dirname(__file__))
from emu import *
import sclib

DS = 0x5435
# Overlay stub segment of each cut-scene function (entry at stub:0020; MID1 at 0025)
STUBS = {1: (0x4b5c, 0x25), 2: (0x4b62, 0x20), 3: (0x4b65, 0x20), 5: (0x4b68, 0x20), 12: (0x4b6b, 0x20),
         14: (0x4b6e, 0x20), 15: (0x4b71, 0x20), 16: (0x4b74, 0x20), 17: (0x4b77, 0x20), 20: (0x4b7a, 0x20),
         33: (0x4b7d, 0x20), 34: (0x4b80, 0x20), 36: (0x4b83, 0x20)}
CALL_MID1, AFTER_MID1 = 0xc0ca, 0xc0cf
DRAW, COPY, FILL, SDRAW = 0x40570, 0x3fbb0, 0x3fb64, 0x407be


def shape_index():
    idx = {}
    for name, blob in sclib.B.items():
        up = name.upper()
        short = up.replace('..\\..\\DATA\\', '').replace('\\', '/')
        if up.endswith('.SHP'):
            n = struct.unpack_from('<I', blob, 0)[0]
            idx.setdefault(hashlib.md5(blob[:min(256, max(8, n))]).hexdigest(), (short, -1))
        elif up.endswith('.PAK'):
            try:
                entries = sclib.pak(blob)
            except Exception:
                continue
            for i, (e, f) in enumerate(entries):
                if len(e) < 8:
                    continue
                raw = e
                if f == 0x20:
                    try:
                        raw = sclib.lzw(e[4:])
                    except Exception:
                        continue
                n = struct.unpack_from('<I', raw, 0)[0] if len(raw) >= 4 else 0
                idx.setdefault(hashlib.md5(raw[:min(256, max(8, n))]).hexdigest(), (short, i))
    return idx


def main():
    # "N" = story cut-scene MIDn, "eN" = establishing shot N (gameflow effect 08)
    arg = sys.argv[1] if len(sys.argv) > 1 else '1'
    shot = arg.startswith('e')
    conv = arg.startswith('c')
    trans = arg.startswith('t')    # transport between bases (effect 12, 4b3b:002a)
    number = int(arg.lstrip('ect'))
    max_ticks = int(sys.argv[2]) if len(sys.argv) > 2 else 12000
    out_path = sys.argv[3] if len(sys.argv) > 3 else 'mid%d.json' % number
    t0 = time.time()
    shapes = shape_index()
    print('shape index', len(shapes), flush=True)
    e = Emu(log=lambda s: print(s) if ("rror" in s or "unhandled" in s) else None)
    protect_lzw_refill(e)
    L = e.load_seg
    # The start-up intro call plays our cut-scene instead; stop when it returns.
    if shot or conv or trans:
        # call the effect-08 (establishing shot, 4b1e:0057) or effect-00
        # (conversation, 4b1e:0043) handler with (gameflow object, n)
        def call_shot(uc, addr, size, _):
            ss, sp = e.r(UC_X86_REG_SS), e.r(UC_X86_REG_SP)
            cs, ip = e.r(UC_X86_REG_CS), e.r(UC_X86_REG_IP)
            for v in (number, e.r(UC_X86_REG_SI), cs, ip + 5):
                sp = (sp - 2) & 0xffff
                e.wr(ss, sp, struct.pack('<H', v))
            e.w(UC_X86_REG_SP, sp)
            if trans:
                e.w(UC_X86_REG_CS, L + 0x4b3b); e.w(UC_X86_REG_IP, 0x2a)
            else:
                e.w(UC_X86_REG_CS, L + 0x4b1e); e.w(UC_X86_REG_IP, 0x43 if conv else 0x57)
        e.uc.hook_add(UC_HOOK_CODE, call_shot, begin=L * 16 + CALL_MID1 - 0x5c00, end=L * 16 + CALL_MID1 - 0x5c00)
    else:
        seg, off = STUBS[number]
        e.wr(0, L * 16 + CALL_MID1 - 0x5c00, bytes([0x9a]) + struct.pack('<HH', off, L + seg))
    done = {'t': False}

    def on_return(uc, addr, size, _):
        done['t'] = True
        e.stop_reason = 'cut-scene finished'
        uc.emu_stop()
    e.uc.hook_add(UC_HOOK_CODE, on_return, begin=L * 16 + AFTER_MID1 - 0x5c00, end=L * 16 + AFTER_MID1 - 0x5c00)
    lin = lambda fo: L * 16 + fo - 0x5c00
    ops = []
    unknown = {}
    cache = {}
    state = {'pal': bytearray(768), 'active': False}

    def now():
        return int(e.time_us() / 1000)

    def flush_pal():
        cur = e.palette
        old = state['pal']
        if cur != old:
            lo = next(i for i in range(768) if cur[i] != old[i]) // 3
            hi = max(i for i in range(768) if cur[i] != old[i]) // 3
            ops.append([now(), 'pal', lo, list(cur[lo * 3:hi * 3 + 3])])
            state['pal'] = bytearray(cur)

    surfaces = {}

    def surf(p):
        name = 'screen' if p == e.u16(DS, 0x4668) else '%04x' % p
        seg, rows = struct.unpack('<HH', e.rd(DS, p, 4))
        r0, r1 = e.u16(DS, rows), e.u16(DS, rows + 2)
        d = {'seg': seg, 'base': r0, 'stride': (r1 - r0) & 0xffff, 'rect': rect(p)}
        if surfaces.get(name) != d:
            surfaces[name] = d
            ops.append([now(), 'surface', name, seg, r0, d['stride'], d['rect']])
        return name

    def rect(p):
        return list(struct.unpack('<4h', e.rd(DS, p + 4, 8)))

    def args(n):
        ss, sp = e.r(UC_X86_REG_SS), e.r(UC_X86_REG_SP)
        return [e.u16(ss, sp + 4 + 2 * k) for k in range(n)]

    def shape_ref(seg, off):
        size_ = struct.unpack('<I', e.rd(seg, off, 4))[0]
        h = hashlib.md5(e.rd(seg, off, min(256, max(8, size_)))).hexdigest()
        ref = shapes.get(h)
        if ref is None:
            # shapes embedded in other files (e.g. a font inside CREDITS.IFF)
            head = e.rd(seg, off, 64)
            for name, blob in sclib.B.items():
                j = blob.find(head)
                if j >= 0 and not name.upper().endswith('.PAK'):
                    ref = (name.upper().replace('..' + chr(92) + '..' + chr(92) + 'DATA' + chr(92), '').replace(chr(92), '/') + '@%d' % j, -1)
                    shapes[h] = ref
                    break
        if ref is None:
            if h not in unknown:
                open('unknown_%s.bin' % h[:8], 'wb').write(e.rd(seg, off, min(size_, 0x20000)))
            unknown[h] = unknown.get(h, 0) + 1
            ref = ('?' + h[:8], -1)
        return ref

    tables = {}

    def on_sdraw(uc, addr, size, _):
        a = args(12)
        s, x, y, off, seg, frame = a[:6]
        sx, sy, toff, tseg, first, count = a[6:12]
        sg = lambda v: v - 0x10000 if v & 0x8000 else v
        ref = shape_ref(seg, off)
        flush_pal()
        tid = -1
        if count:
            tab = e.rd(tseg, toff, count * 256)
            h = hashlib.md5(tab).hexdigest()
            if h not in tables:
                tables[h] = len(tables)
                ops.append([now(), 'table', tables[h], list(tab)])
            tid = tables[h]
        ops.append([now(), 'sdraw', surf(s), ref[0], ref[1], frame, sg(x), sg(y), sg(sx), sg(sy), first, count, tid])

    def on_draw(uc, addr, size, _):
        s, x, y, off, seg, frame = args(6)
        ref = shape_ref(seg, off)
        flush_pal()
        x = x - 0x10000 if x & 0x8000 else x
        y = y - 0x10000 if y & 0x8000 else y
        ops.append([now(), 'draw', surf(s), ref[0], ref[1], frame, x, y])

    def on_copy(uc, addr, size, _):
        src, dst = args(2)
        flush_pal()
        ops.append([now(), 'copy', surf(src), surf(dst), rect(src), rect(dst)])

    def on_fill(uc, addr, size, _):
        s, color = args(2)
        flush_pal()
        ops.append([now(), 'fill', surf(s), color & 0xff, rect(s)])

    e.uc.hook_add(UC_HOOK_CODE, on_draw, begin=lin(DRAW), end=lin(DRAW))
    e.uc.hook_add(UC_HOOK_CODE, on_copy, begin=lin(COPY), end=lin(COPY))
    e.uc.hook_add(UC_HOOK_CODE, on_fill, begin=lin(FILL), end=lin(FILL))
    e.uc.hook_add(UC_HOOK_CODE, on_sdraw, begin=lin(SDRAW), end=lin(SDRAW))

    def on_zdraw(uc, addr, size, _):
        # sprite drawn at a distance (4730e): uniform scale [bp+14] / 256;
        # unscaled calls continue into the plain draw and are logged there
        a = args(9)
        s_, x, y, off, seg, frame, k, scale, k2 = a
        if scale == 0x100 and k == (k2 & 0xff):
            return
        sg = lambda v: v - 0x10000 if v & 0x8000 else v
        ref = shape_ref(seg, off)
        flush_pal()
        ops.append([now(), 'sdraw', surf(s_), ref[0], ref[1], frame, sg(x), sg(y), scale, scale, 0, 0, -1])
    def on_glyph(uc, addr, size, _):
        # text: a font frame drawn in one colour (402f0)
        s_, x, y, off, seg, frame, color = args(7)
        sg = lambda v: v - 0x10000 if v & 0x8000 else v
        ref = shape_ref(seg, off)
        flush_pal()
        ops.append([now(), 'glyph', surf(s_), ref[0], ref[1], frame, sg(x), sg(y), color & 0xff])
    e.uc.hook_add(UC_HOOK_CODE, on_glyph, begin=lin(0x402f0), end=lin(0x402f0))
    def on_line(uc, addr, size, _):
        s_, x1, y1, x2, y2, color = args(6)
        sg = lambda v: v - 0x10000 if v & 0x8000 else v
        flush_pal()
        ops.append([now(), 'line', surf(s_), sg(x1), sg(y1), sg(x2), sg(y2), color & 0xff])

    def on_ellipse(uc, addr, size, _):
        s_, cx, cy, rx, ry, color = args(6)
        sg = lambda v: v - 0x10000 if v & 0x8000 else v
        flush_pal()
        ops.append([now(), 'ellipse', surf(s_), sg(cx), sg(cy), rx, ry, color & 0xff])
    e.uc.hook_add(UC_HOOK_CODE, on_line, begin=lin(0x3ff7e), end=lin(0x3ff7e))
    e.uc.hook_add(UC_HOOK_CODE, on_ellipse, begin=lin(0x3fc3c), end=lin(0x3fc3c))
    ZDRAW = 0x4730e
    e.uc.hook_add(UC_HOOK_CODE, on_zdraw, begin=lin(ZDRAW), end=lin(ZDRAW))
    # Speech: pretend digital sound is on, stub the speech object and log
    # which archive entry each line plays. Archive objects are named from the
    # path built just before they are opened.
    SPEECH = {0x14277: 'init', 0x14587: 'play', 0x14db4: 'stop', 0x143ce: 'update'}
    MKPATH, OPEN, OPEN_VOC, PAKLOAD = 0x199fc, 0x4b3a8, 0x4b378, 0x195da
    names, loads, last = {}, {}, {'path': None}

    def retf(uc):
        ss, sp = e.r(UC_X86_REG_SS), e.r(UC_X86_REG_SP)
        ip, cs = e.u16(ss, sp), e.u16(ss, sp + 2)
        e.w(UC_X86_REG_SP, sp + 4); e.w(UC_X86_REG_CS, cs); e.w(UC_X86_REG_IP, ip)

    def speech_hook(kind):
        def h(uc, addr, size, _):
            if kind == 'play':
                obj, ref = args(2)
                flush_pal()
                ops.append([now(), 'voice'] + list(loads.get(ref, ('?', -1))))
            retf(uc)
        return h

    def on_mkpath(uc, addr, size, _):
        a = args(7)
        parts = [e.cstr(a[k + 1], a[k]) for k in (1, 3, 5)]
        last['path'] = (parts[0].upper().split('DATA' + chr(92))[-1] + parts[1] + parts[2]).upper().replace(chr(92), '/')

    def on_open(uc, addr, size, _):
        names[args(1)[0]] = last['path']

    def on_pakload(uc, addr, size, _):
        obj, index, ref = args(3)
        loads[ref] = (names.get(obj, '?'), index)

    def on_say(uc, addr, size, _):
        # talking characters (MID36 and others): (actor, sample ref, channel)
        actor, ref, ch = args(3)
        name, idx = loads.get(ref, ('?', -1))
        if name.endswith('VOC.PAK'):
            flush_pal()
            ops.append([now(), 'voice', name, idx])
    SAY = 0x16e34
    e.uc.hook_add(UC_HOOK_CODE, on_say, begin=lin(SAY), end=lin(SAY))

    for off, kind in SPEECH.items():
        e.uc.hook_add(UC_HOOK_CODE, speech_hook(kind), begin=lin(off), end=lin(off))
    e.uc.hook_add(UC_HOOK_CODE, on_mkpath, begin=lin(MKPATH), end=lin(MKPATH))
    e.uc.hook_add(UC_HOOK_CODE, on_open, begin=lin(OPEN), end=lin(OPEN))
    e.uc.hook_add(UC_HOOK_CODE, on_open, begin=lin(OPEN_VOC), end=lin(OPEN_VOC))
    e.uc.hook_add(UC_HOOK_CODE, on_pakload, begin=lin(PAKLOAD), end=lin(PAKLOAD))

    # Subtitle pass (SUBS=1): with digital sound off the cut-scenes show their
    # lines as text instead; log them (set text 140a1, clear 13ff0).
    subs_only = os.environ.get('SUBS') == '1'

    def on_subtitle(uc, addr, size, _):
        obj, text = args(2)
        ops.append([now(), 'subtitle', e.cstr(DS, text, 300)])

    def on_subclear(uc, addr, size, _):
        ops.append([now(), 'subtitle', ''])

    # Music pass (MUSIC=device): turn a music device on and log what the
    # cut-scene plays: 140a1 play (player, sequence ref, index), 13ff0 stop.
    music_dev = int(os.environ.get('MUSIC', '0'))

    def on_music(uc, addr, size, _):
        obj, ref, index = args(3)
        name, entry = loads.get(ref, ('?', -1))
        ops.append([now(), 'music', name, entry, index])

    def on_music_stop(uc, addr, size, _):
        ops.append([now(), 'music_stop'])
    if music_dev:
        e.uc.hook_add(UC_HOOK_CODE, on_music, begin=lin(0x140a1), end=lin(0x140a1))
        e.uc.hook_add(UC_HOOK_CODE, on_music_stop, begin=lin(0x13ff0), end=lin(0x13ff0))

    def force_voice(em):
        if em.ticks < 20 and music_dev:
            em.wr(DS, 0x402e, bytes([music_dev]))
        if em.ticks < 20 and not subs_only:
            em.wr(DS, 0x4031, struct.pack('<H', 1))
        return False
    e.run(max_ticks, force_voice)
    flush_pal()
    if music_dev:
        ops[:] = [o for o in ops if o[1] in ('music', 'music_stop')]
    json.dump({'number': number, 'ops': ops}, open(out_path, 'w'), separators=(',', ':'))
    print('finished' if done['t'] else 'NOT finished', 'ops', len(ops), 'unknown shapes', len(unknown), 'ticks', e.ticks, '%.0fs' % (time.time() - t0))


if __name__ == '__main__':
    main()
