"""Regenerates the LOCAL-ONLY reverse-engineering material in alkuperainen_purku/
from the player's own Strike Commander installation (CD / GOG version).

    python tools/decompile/pura_tulkit.py "C:/Gog games/Strike Commander"

Everything written to alkuperainen_purku/ is derived from the original game
(disassembly of its programs, dumps of its data) and must never be committed
or distributed: the folder is in .gitignore (only its README is tracked).
This script itself contains no original code or data, only offsets that were
found while decoding (docs/PROG_VM.md, docs/GAMEFLOW_VM.md).

Requires: pip install capstone
"""
import os, struct, sys, collections, re
from capstone import Cs, CS_ARCH_X86, CS_MODE_16

ROOT = os.path.dirname(os.path.dirname(os.path.dirname(os.path.abspath(__file__))))
OUT = os.path.join(ROOT, "alkuperainen_purku")
MD = Cs(CS_ARCH_X86, CS_MODE_16)


def header(d):
    return struct.unpack_from("<H", d, 8)[0] * 16


def listing(d, start, end, labels, base=0, data_ranges=()):
    """Linear listing of [start, end) with labels {addr: name}."""
    out, a = [], start
    while a < end:
        skip = next((r for r in data_ranges if r[0] <= a < r[1]), None)
        if skip:
            out.append("%06x: <data %d bytes>" % (a, skip[1] - a))
            a = skip[1]
            continue
        got = False
        stop = min([end] + [r[0] for r in data_ranges if r[0] > a])
        for x in MD.disasm(d[a:stop], a):
            if x.address in labels:
                out.append("\n%s:" % labels[x.address])
            out.append("%06x [%04x]: %s %s" % (x.address, x.address - base, x.mnemonic, x.op_str))
            a = x.address + x.size
            got = True
        if not got:
            out.append("%06x: db %02x" % (a, d[a]))
            a += 1
    return "\n".join(out) + "\n"


def jump_table(d, table, base, n, first=0):
    vals = [struct.unpack_from("<H", d, table + 2 * k)[0] for k in range(n)]
    dflt = collections.Counter(vals).most_common(1)[0][0]
    names = collections.defaultdict(list)
    for k, v in enumerate(vals):
        names[base + v].append("op_%02x" % (first + k) if v != dflt else None)
    return {a: "/".join(x for x in l if x) or "op_DEFAULT" for a, l in names.items()}


def overlay_segments(d):
    hdr, ovl = header(d), None
    fbov = d.find(b"FBOV")
    ovl = fbov + 16
    segs = {}
    for o in range(hdr, fbov, 16):
        if d[o:o + 4] == b"\xcd\x3f\x00\x00":
            off = struct.unpack_from("<I", d, o + 4)[0]
            size = struct.unpack_from("<H", d, o + 8)[0]
            n = struct.unpack_from("<H", d, o + 0xc)[0]
            if size and ovl + off + size <= len(d):
                ents = {0x20 + 5 * k: struct.unpack_from("<H", d, o + 0x22 + 5 * k)[0] for k in range(n)}
                segs[(o - hdr) // 16] = (ovl + off, size, ents)
    return segs


def write(path, text):
    os.makedirs(os.path.dirname(path), exist_ok=True)
    open(path, "w", encoding="utf-8").write(text)
    print("wrote", os.path.relpath(path, ROOT))


def tactical_ops(game):
    """Disassemble the Tactical Operations add-on executable's overlays.

    TOPTTST1.EXE uses the same FBOV overlay layout as OPTTEST.EXE. The 30 new
    missions themselves live in TOBIGTRE.TRE on the CD (see
    docs/TACTICAL_OPS_TEST_PLAN.md); this function only handles the program.
    """
    path = os.path.join(game, "TOPTTST1.EXE")
    if not os.path.isfile(path):
        print("no TOPTTST1.EXE in", game)
        return
    d = open(path, "rb").read()
    segs = overlay_segments(d)
    out_dir = os.path.join(OUT, "TOPTTST1.EXE")
    for s, (b, size, ents) in sorted(segs.items()):
        lab = {b + off: "ENTRY_%04x:%02x" % (s, e) for e, off in ents.items() if off}
        write(os.path.join(out_dir, "ovl_%04x.asm" % s), listing(d, b, b + size, lab, b))
    strings = []
    for m in re.finditer(rb'[!-~ ]{6,}\x00', d):
        s = m.group()[:-1].decode('latin1').strip()
        if len(s) >= 6:
            strings.append("%06X: %s" % (m.start(), s))
    write(os.path.join(out_dir, "_strings.txt"), "\n".join(strings) + "\n")
    print("TOPTTST1.EXE: %d overlay segments, %d strings" % (len(segs), len(strings)))


def main():
    game = sys.argv[1] if len(sys.argv) > 1 else os.environ.get("SC_GAME_DIR", r"C:\Gog games\Strike Commander")
    strike = open(os.path.join(game, "STRIKE.EXE"), "rb").read()
    opt = open(os.path.join(game, "OPTTEST.EXE"), "rb").read()
    tactical_ops(game)

    # STRIKE.EXE: PROG interpreter (docs/PROG_VM.md)
    seg, table = 0x548A0, 0x55711
    labels = jump_table(strike, table, seg, 209)
    write(os.path.join(OUT, "STRIKE.EXE", "prog_vm.asm"),
          listing(strike, seg, 0x56F00, labels, seg, [(table, table + 2 * 209), (seg + 0x216E, seg + 0x216E + 2 * 31)]))
    act = {seg + v: "ACT_%02x" % (0xA1 + k) for k, v in enumerate(
        struct.unpack_from("<H", strike, seg + 0x216E + 2 * k)[0] for k in range(31))}
    write(os.path.join(OUT, "STRIKE.EXE", "actions.asm"), listing(strike, 0x56499, 0x56A0E, act, seg))

    # OPTTEST.EXE: GAMEFLOW interpreter and misn2op reader (docs/GAMEFLOW_VM.md)
    gtab, gbase = 0xBD47, 0xB730
    glabels = {gbase + struct.unpack_from("<H", opt, gtab + 2 * k)[0]: "EFFECT_%02x" % k for k in range(0x2B)}
    write(os.path.join(OUT, "OPTTEST.EXE", "gameflow_vm.asm"), listing(opt, 0xB916, gtab, glabels, gbase))
    segs = overlay_segments(opt)
    rows = ["seg   file_off  size   entries (stub offset -> code offset)"]
    for s, (b, size, ents) in sorted(segs.items()):
        rows.append("%04x  %#08x  %#06x  %s" % (s, b, size, " ".join("%02x:%04x" % kv for kv in sorted(ents.items()))))
    write(os.path.join(OUT, "OPTTEST.EXE", "overlay_segments.txt"), "\n".join(rows) + "\n")
    for s, entry, name in ((0x4B1E, None, "ovl_4b1e_gameflow_results"), (0x4B32, None, "ovl_4b32_ledger_killboard"),
                           (0x4B36, None, "ovl_4b36_loadout_catalog_ledger")):
        b, size, ents = segs[s]
        lab = {b + off: "ENTRY_%s:%02x" % ("%04x" % s, e) for e, off in ents.items() if off}
        write(os.path.join(OUT, "OPTTEST.EXE", name + ".asm"), listing(opt, b, b + size, lab, b))
    print("done: alkuperainen_purku/ (local only, never commit or share)")


if __name__ == "__main__":
    main()
