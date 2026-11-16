"""Add the original on-screen text to a recorded cut-scene timeline.

With digital speech off, OPTTEST.EXE shows each line as text (MIDGAMES.IFF
FORM DATA / SPOK) and paces the scenes for reading. This runs a cut-scene in
that mode, notes when each line is drawn (text routine 3f36b) and which frames
are on screen, then aligns those frames with the speech-mode timeline
(midN.json) and inserts [t, "subtitle", text] ops ("" clears).

usage: subtitles.py N timeline.json
"""
import difflib, hashlib, json, os, re, struct, sys
sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from emu import *
from trace_mid import STUBS, CALL_MID1, AFTER_MID1, DS, shape_index

DRAW, SDRAW, COPY, TEXT = 0x40570, 0x407be, 0x3fbb0, 0x3f36b


def clean(s):
    s = ''.join(c if 32 <= ord(c) < 127 else ' ' for c in s)
    s = re.sub(r'&\w\S*', '', s)          # unresolved name codes
    # Names (player, wingman) are not set up in the emulator: their slots hold
    # leftovers such as "id3\" or "=T =u = O U?g ... F". Leave them out.
    s = re.sub(r"'?\s*=T =u.*?F\s*'?", '', s)
    s = s.replace('id3' + chr(92), '')
    s = re.sub(r'\s+', ' ', s).strip()
    s = re.sub(r'\s+([,.!?])', r'\1', s)
    s = re.sub(r',([.!?])', r'\1', s)
    s = re.sub(r',+', ',', s)
    return '' if s in ('.', ',', "'") else s


def tidy_caption(text):
    return chr(10).join(x for x in (clean(l) for l in text.split(chr(10))) if x)


def is_title(text):
    """All-caps title cards (ORIGIN PRESENTS ...) are drawn as graphics already."""
    return text.upper() == text and any(c.isalpha() for c in text)


def scenes_of(ops):
    """[(time, signature)] per display copy; the signature is the set of
    shapes drawn (frame numbers and positions differ between the two modes)."""
    out, cur = [], set()
    for o in ops:
        if o[1] in ('draw', 'sdraw') and 'FONT' not in str(o[3]):
            cur.add((o[3], o[4]))
        elif o[1] == 'copy':
            out.append((o[0], hashlib.md5(repr(sorted(cur)).encode()).hexdigest()[:12]))
            cur = set()
    # collapse repeats: one entry per scene, with its start time
    seq = []
    for t, sig in out:
        if not seq or seq[-1][1] != sig:
            seq.append((t, sig))
    return seq


def run_text_mode(number, max_ticks):
    shapes = shape_index()
    e = Emu(log=lambda s: None)
    protect_lzw_refill(e)
    L = e.load_seg
    lin = lambda fo: L * 16 + fo - 0x5c00
    seg, off = STUBS[number]
    e.wr(0, lin(CALL_MID1), bytes([0x9a]) + struct.pack('<HH', off, L + seg))
    ops, lines = [], []
    now = lambda: int(e.time_us() / 1000)

    def args(n):
        ss, sp = e.r(UC_X86_REG_SS), e.r(UC_X86_REG_SP)
        return [e.u16(ss, sp + 4 + 2 * k) for k in range(n)]

    def ref(sg, of):
        size = struct.unpack('<I', e.rd(sg, of, 4))[0]
        return shapes.get(hashlib.md5(e.rd(sg, of, min(256, max(8, size)))).hexdigest(), ('?', -1))

    def on_draw(uc, a, s, _):
        x = args(6)
        r = ref(x[4], x[3])
        ops.append([now(), 'draw', '', r[0], r[1], x[5], x[1], x[2]])

    def on_copy(uc, a, s, _):
        ops.append([now(), 'copy'])

    def on_text(uc, a, s, _):
        obj, p = args(2)
        lines.append((now(), obj, clean(e.cstr(DS, p, 300))))

    def on_return(uc, a, s, _):
        e.stop_reason = 'done'
        uc.emu_stop()
    for f, h in ((DRAW, on_draw), (SDRAW, on_draw), (COPY, on_copy), (TEXT, on_text)):
        e.uc.hook_add(UC_HOOK_CODE, h, begin=lin(f), end=lin(f))
    e.uc.hook_add(UC_HOOK_CODE, on_return, begin=lin(AFTER_MID1), end=lin(AFTER_MID1))
    e.run(max_ticks)
    return ops, lines


def captions(lines, gap=250):
    """Text draws repeat every frame: group into (start, end, text) captions."""
    out = []
    by_time = {}
    for t, obj, s in lines:
        by_time.setdefault(t, []).append(s)
    cur, start, last = None, 0, 0
    for t in sorted(by_time):
        text = '\n'.join(x for x in by_time[t] if x)
        if text != cur or t - last > gap:
            if cur:
                out.append((start, last, cur))
            cur, start = text, t
        last = t
    if cur:
        out.append((start, last, cur))
    return [c for c in out if c[2]]


def retidy(tl, path):
    """Re-clean the subtitles already in a timeline (no emulator run)."""
    out, last = [], None
    for o in tl['ops']:
        if o[1] == 'subtitle' and o[2]:
            o[2] = tidy_caption(o[2])
            if not o[2] or o[2] == last:
                continue
            last = o[2]
        out.append(o)
    tl['ops'] = out
    json.dump(tl, open(path, 'w'), separators=(',', ':'))
    print('subtitles', sum(1 for o in out if o[1] == 'subtitle' and o[2]))


def main():
    number = int(sys.argv[1])
    path = sys.argv[2]
    tl = json.load(open(path))
    if len(sys.argv) > 3 and sys.argv[3] == '--tidy':
        retidy(tl, path)
        return
    ops = [o for o in tl['ops'] if o[1] != 'subtitle']
    text_ops, lines = run_text_mode(number, 60000)
    caps = captions(lines)
    a = scenes_of(text_ops)            # text mode
    b = scenes_of(ops)                 # speech mode
    end_a, end_b = text_ops[-1][0], ops[-1][0]
    sm = difflib.SequenceMatcher(None, [x for _, x in a], [x for _, x in b], autojunk=False)
    pairs = []                         # (text-mode start, speech-mode start) of matched scenes
    for i, j, n in sm.get_matching_blocks():
        for k in range(n):
            pairs.append((a[i + k][0], b[j + k][0]))
    pairs.append((end_a, end_b))
    voices = [o[0] for o in ops if o[1] == 'voice']

    def segment(t):
        for k in range(len(pairs) - 1):
            if pairs[k][0] <= t < pairs[k + 1][0]:
                return k
        return None

    subs = []
    by_seg = {}
    for c in caps:
        by_seg.setdefault(segment(c[0]), []).append(c)
    for k, group in sorted(by_seg.items(), key=lambda x: -1 if x[0] is None else x[0]):
        if k is None:
            continue
        (t0, u0), (t1, u1) = pairs[k], pairs[k + 1]
        scale = (u1 - u0) / max(1, t1 - t0)
        inside = [v for v in voices if u0 <= v < u1]
        for n, (start, end, text) in enumerate(group):
            s0 = inside[n] if len(inside) == len(group) else int(u0 + (start - t0) * scale)
            nxt = group[n + 1][0] if n + 1 < len(group) else end
            s1 = inside[n + 1] if len(inside) == len(group) and n + 1 < len(inside) else int(u0 + (min(end, nxt) - t0) * scale)
            subs.append([s0, 'subtitle', text])
            subs.append([max(s1, s0 + 1200), 'subtitle', ''])
    # Snap each caption to a speech line starting close by (not used yet), and
    # end it when the next one starts.
    starts = [x for x in subs if x[2]]
    used = set()
    for c in starts:
        near = [v for v in voices if abs(v - c[0]) <= 700 and v not in used]
        if near:
            v = min(near, key=lambda v: abs(v - c[0]))
            used.add(v)
            c[0] = v
    starts.sort(key=lambda c: c[0])
    for c in starts:
        c[2] = tidy_caption(c[2])
    tidy = []
    for c in starts:
        if not c[2]:
            continue
        if is_title(c[2]) or (tidy and tidy[-1][2] == c[2]):
            continue
        tidy.append(c)
    starts = tidy
    subs = []
    for n, c in enumerate(starts):
        subs.append(c)
        end = starts[n + 1][0] if n + 1 < len(starts) else c[0] + 4000
        subs.append([max(end - 1, c[0] + 800), 'subtitle', ''])
    merged = sorted(ops + subs, key=lambda o: o[0])
    tl['ops'] = merged
    json.dump(tl, open(path, 'w'), separators=(',', ':'))
    print('MID%d: %d captions, %d/%d scenes aligned' % (number, len(caps), len(pairs) - 1, len(a)))
    for s in subs[::2]:
        print('  %6d %s' % (s[0], s[2].replace('\n', ' / ')))


if __name__ == '__main__':
    main()
