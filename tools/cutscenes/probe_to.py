"""Probe TOPTTST1.EXE in the emulator: does it draw to VGA during start-up?

Run with SC_EXE=TOPTTST1.EXE and SC_GAME_DIR set. Reports the code addresses
that write to the VGA plane and the first files it opens, so the cut-scene
trace hooks can be rebased without guessing.
"""
import os, struct, sys, collections
sys.path.insert(0, os.path.dirname(__file__))
from emu import *

writes = collections.Counter()
opens = []


def on_write(uc, access, address, size, value, _):
    if 0xA0000 <= address < 0xC0000:
        writes[uc.reg_read(UC_X86_REG_EIP)] += 1


def on_code(uc, addr, size, _):
    pass


def main():
    e = Emu(log=lambda s: print('EMU:', s) if ('rror' in s or 'unhandled' in s) else None)
    e.uc.hook_add(UC_HOOK_MEM_WRITE, on_write, begin=0xA0000, end=0xBFFFF)
    # Track the first DOS opens by hooking INT 21h through the existing BIOS trap.
    print('EXE', EXE)
    try:
        e.run(int(sys.argv[1]) if len(sys.argv) > 1 else 4000)
    except Exception as ex:
        print('CRASH', ex, 'EIP=%04x:%04x' % (e.r(UC_X86_REG_CS), e.r(UC_X86_REG_IP)))
        cs, ip = e.r(UC_X86_REG_CS), e.r(UC_X86_REG_IP)
        try:
            print('bytes', e.rd(cs, ip, 32).hex())
        except Exception as ex2:
            print('dump failed', ex2)
    if e.stop_reason == 'cpu':
        cs, ip = e.r(UC_X86_REG_CS), e.r(UC_X86_REG_IP)
        try:
            print('bytes at crash', e.rd(cs, ip, 32).hex())
        except Exception as ex2:
            print('dump failed', ex2)
    print('ticks', e.ticks, 'vga writes', sum(writes.values()))
    print('top write sites', [(hex(k), v) for k, v in writes.most_common(12)])
    print('palette nonzero', sum(1 for v in e.palette if v))


if __name__ == '__main__':
    main()
