"""Ground-truth screens for checking the cut-scene player.

Runs a cut-scene (N = MIDn, eN = establishing shot) in the emulator exactly as
trace_mid.py does and saves what the original program has on its display
(the FFFF:0010 screen, through the current VGA palette) at the given times.

usage: reference.py N ms1,ms2,... outdir
"""
import os, struct, sys, zlib
sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from emu import *
from trace_mid import STUBS, CALL_MID1, AFTER_MID1, DS


def png(path, rgb, w=320, h=200):
    raw = b''.join(b'\0' + rgb[y * w * 3:(y + 1) * w * 3] for y in range(h))
    def ch(t, d): return struct.pack('>I', len(d)) + t + d + struct.pack('>I', zlib.crc32(t + d) & 0xffffffff)
    open(path, 'wb').write(b'\x89PNG\r\n\x1a\n' + ch(b'IHDR', struct.pack('>IIBBBBB', w, h, 8, 2, 0, 0, 0))
                           + ch(b'IDAT', zlib.compress(raw)) + ch(b'IEND', b''))


def main():
    arg, times, out = sys.argv[1], [int(t) for t in sys.argv[2].split(',')], sys.argv[3]
    os.makedirs(out, exist_ok=True)
    shot = arg.startswith('e')
    trans = arg.startswith('t')
    number = int(arg.lstrip('et'))
    e = Emu(log=lambda s: None)
    protect_lzw_refill(e)
    L = e.load_seg
    lin = lambda fo: L * 16 + fo - 0x5c00
    if shot or trans:
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
                e.w(UC_X86_REG_CS, L + 0x4b1e); e.w(UC_X86_REG_IP, 0x57)
        e.uc.hook_add(UC_HOOK_CODE, call_shot, begin=lin(CALL_MID1), end=lin(CALL_MID1))
    else:
        seg, off = STUBS[number]
        e.wr(0, lin(CALL_MID1), bytes([0x9a]) + struct.pack('<HH', off, L + seg))

    def stop(uc, a, s, _):
        e.stop_reason = 'done'
        uc.emu_stop()
    e.uc.hook_add(UC_HOOK_CODE, stop, begin=lin(AFTER_MID1), end=lin(AFTER_MID1))
    # speech stubs as in trace_mid (play / init / stop / update return at once)
    def retf(uc, a, s, _):
        ss, sp = e.r(UC_X86_REG_SS), e.r(UC_X86_REG_SP)
        ip, cs = e.u16(ss, sp), e.u16(ss, sp + 2)
        e.w(UC_X86_REG_SP, sp + 4); e.w(UC_X86_REG_CS, cs); e.w(UC_X86_REG_IP, ip)
    for f in (0x14277, 0x14587, 0x14db4, 0x143ce):
        e.uc.hook_add(UC_HOOK_CODE, retf, begin=lin(f), end=lin(f))
    pending = sorted(times)

    def snap(em):
        if em.ticks < 20 and not (shot or trans):
            em.wr(DS, 0x4031, struct.pack('<H', 1))
        t = em.time_us() / 1000
        while pending and t >= pending[0]:
            vram = bytes(em.uc.mem_read(0x100000, 64000))
            pal = bytes(min(255, c * 255 // 63) for c in em.palette)
            png(os.path.join(out, 'ref_%06d.png' % pending[0]), b''.join(pal[p * 3:p * 3 + 3] for p in vram))
            pending.pop(0)
        return not pending
    e.run(60000, snap)


if __name__ == '__main__':
    main()
