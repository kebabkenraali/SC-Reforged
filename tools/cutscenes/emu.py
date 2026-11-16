"""Tiny DOS + VGA emulator (unicorn) for running OPTTEST.EXE far enough to trace cut-scenes."""
import ctypes, os, struct, sys, time, zlib
sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from unicorn import *
from unicorn.x86_const import *

GAME = os.environ.get('SC_GAME_DIR', r'C:\Gog games\Strike Commander')
EXE = os.path.join(GAME, 'OPTTEST.EXE')

# ---------------------------------------------------------------- ISO files
import sclib
ISO_FILES = {k.strip('/').upper(): k for k in sclib.files}


def host_file(path):
    p = path.replace('/', '\\').upper()
    if len(p) > 1 and p[1] == ':':
        p = p[2:]
    parts = [x for x in p.split('\\') if x not in ('', '.')]
    out = []
    for x in parts:
        if x == '..':
            if out: out.pop()
        else:
            out.append(x)
    name = '\\'.join(out)
    local = os.path.join(GAME, *out)
    for cand in (local, os.path.join(GAME, out[-1]) if out else local):
        if os.path.isfile(cand):
            return ('disk', cand)
    if out and out[-1] in ISO_FILES:
        return ('iso', ISO_FILES[out[-1]])
    if name.replace('\\', '/') in ISO_FILES:
        return ('iso', ISO_FILES[name.replace('\\', '/')])
    return None


CONFIG = b'=liltre.tre' + bytes([13, 10]) + b'=bigtre.tre' + bytes([13, 10]) + b'=voclist.tre' + bytes([13, 10, 13, 10])


class OpenFile:
    def __init__(self, kind, ref):
        self.kind, self.ref, self.pos = kind, ref, 0
        if kind == 'disk' and ref.upper().endswith('SC.CFG'):
            kind = self.kind = 'mem'; self.data = CONFIG; self.size = len(CONFIG)
        if kind == 'mem':
            pass
        elif kind == 'disk':
            self.f = open(ref, 'rb'); self.size = os.path.getsize(ref)
        else:
            _, self.lba, self.size = sclib.files[ref]

    def read(self, n):
        n = max(0, min(n, self.size - self.pos))
        if self.kind == 'mem':
            b = self.data[self.pos:self.pos + n]
        elif self.kind == 'disk':
            self.f.seek(self.pos); b = self.f.read(n)
        else:
            first = self.pos // 2048; last = (self.pos + n + 2047) // 2048
            blob = sclib.sec(self.lba + first, max(0, last - first)) if n else b''
            off = self.pos - first * 2048
            b = blob[off:off + n]
        self.pos += len(b)
        return b


class Emu:
    PSP = 0x0800
    ENV = 0x0700
    BIOS = 0x0060
    # JEMM memory model (as far as OPTTEST relies on it): 24 physical EMS pages
    # sit contiguously at A000-FFFF. Pages 20-23 (F000) are always mapped and are
    # the "small" frame; in "big" mode ('SM') pages 0-19 also cover A000-EFFF,
    # hiding VGA memory.
    BIG = 0xA000
    NBIG = 20

    def __init__(self, args=' Fugitive sc.cfg', log=print):
        self.log = log
        self.uc = uc = Uc(UC_ARCH_X86, UC_MODE_16)
        uc.mem_map(0, self.BIG * 16)
        uc.mem_map(0x100000, 0x400000 - 0x100000)
        self.conv = ctypes.create_string_buffer(self.NBIG * 0x4000)       # 6000-AFFF incl. VGA
        self.small_buf = [ctypes.create_string_buffer(0x4000) for _ in range(4)]
        self.big_map = [None] * self.NBIG
        self.small_map = [None] * 4
        self.big_map2 = [None] * 4
        for i in range(self.NBIG):
            uc.mem_map_ptr(self.BIG * 16 + i * 0x4000, 0x4000, UC_PROT_ALL, ctypes.addressof(self.conv) + i * 0x4000)
        for i in range(4):
            uc.mem_map_ptr(0xF0000 + i * 0x4000, 0x4000, UC_PROT_ALL, ctypes.addressof(self.small_buf[i]))
        self.ems_linear = 0x400000
        self.files = {}
        self.next_handle = 5
        self.dta = (self.PSP, 0x80)
        self.palette = bytearray(768)
        self.pal_w = 0; self.pal_r = 0
        self.ticks = 0
        self.pit_div = 0x10000
        self.retrace = 0
        self.mcb = {}          # seg -> paras
        self.mem_top = 0x9F00
        self.ems = {}          # handle -> [pages bytearray]
        self.ems_frame = 0xE000
        self.next_ems = 1
        self.hooks = {}        # linear addr -> python callback
        self.int_hooks = {}
        self.insn = 0
        self.stop_reason = None
        self.video_mode = 3
        self.keys = []
        self.slot_ptr = {}
        self.remaps = 0
        self.jemm_mode = 0
        # IVT -> BIOS stubs (iret) that we trap with a code hook
        for n in range(256):
            uc.mem_write(n * 4, struct.pack('<HH', n * 4, self.BIOS))
            uc.mem_write(self.BIOS * 16 + n * 4, b'\xcf\x90\x90\x90')
        uc.mem_write(0x400 + 0x10, struct.pack('<H', 0x0021))      # equipment
        uc.mem_write(0x400 + 0x13, struct.pack('<H', 640))
        uc.mem_write(0x400 + 0x49, b'\x03')
        uc.mem_write(0x463, struct.pack("<H", 0x3d4))
        uc.hook_add(UC_HOOK_CODE, lambda *a: self._bios(*a), begin=self.BIOS * 16, end=self.BIOS * 16 + 0x3ff)
        uc.hook_add(UC_HOOK_INTR, self._intr)
        uc.hook_add(UC_HOOK_INSN, self._in, None, 1, 0, UC_X86_INS_IN)
        uc.hook_add(UC_HOOK_INSN, self._out, None, 1, 0, UC_X86_INS_OUT)
        uc.hook_add(UC_HOOK_MEM_UNMAPPED, self._unmapped)
        self._load(args)

    # ------------------------------------------------------------ loading
    def _load(self, args):
        d = open(EXE, 'rb').read()
        cblp, cp, crlc, cparhdr, minalloc, maxalloc, ss, sp, _, ip, cs, lfarlc = struct.unpack_from('<12H', d, 2)
        size = (cp - 1) * 512 + (cblp or 512)
        img = d[cparhdr * 16:size]
        self._ovl_init(d)
        L = self.PSP + 0x10
        self.load_seg = L
        self.image = img
        self.uc.mem_write(L * 16, img)
        for i in range(crlc):
            off, seg = struct.unpack_from('<HH', d, lfarlc + i * 4)
            a = (L + seg) * 16 + off
            v = struct.unpack('<H', self.uc.mem_read(a, 2))[0]
            self.uc.mem_write(a, struct.pack('<H', (v + L) & 0xffff))
        env = b'COMSPEC=C:\\COMMAND.COM\0PATH=C:\\\0\0\x01\0C:\\OPTTEST.EXE\0'
        self.uc.mem_write(self.ENV * 16, env)
        psp = bytearray(256)
        psp[0:2] = b'\xcd\x20'
        struct.pack_into('<H', psp, 2, self.mem_top)
        struct.pack_into('<H', psp, 0x2c, self.ENV)
        tail = args.encode()
        psp[0x80] = len(tail); psp[0x81:0x81 + len(tail)] = tail; psp[0x81 + len(tail)] = 13
        self.uc.mem_write(self.PSP * 16, bytes(psp))
        self.mcb[self.PSP] = self.mem_top - self.PSP
        uc = self.uc
        uc.reg_write(UC_X86_REG_CS, L + cs); uc.reg_write(UC_X86_REG_IP, ip)
        uc.reg_write(UC_X86_REG_SS, L + ss); uc.reg_write(UC_X86_REG_SP, sp)
        uc.reg_write(UC_X86_REG_DS, self.PSP); uc.reg_write(UC_X86_REG_ES, self.PSP)
        self.log('loaded image at %04x, entry %04x:%04x' % (L, L + cs, ip))

    # ------------------------------------------------------------ helpers
    def r(self, reg): return self.uc.reg_read(reg)
    def w(self, reg, v): self.uc.reg_write(reg, v & 0xffff)
    def rd(self, seg, off, n): return bytes(self.uc.mem_read((seg * 16 + off) & 0xfffff, n))
    def wr(self, seg, off, b): self.uc.mem_write((seg * 16 + off) & 0xfffff, bytes(b))
    def u16(self, seg, off): return struct.unpack('<H', self.rd(seg, off, 2))[0]

    def cstr(self, seg, off, n=128):
        return self.rd(seg, off, n).split(b'\0')[0].decode('latin1')

    def set_cf(self, on):
        # Flags pushed by the INT we are servicing sit at SS:SP+4
        ss, sp = self.r(UC_X86_REG_SS), self.r(UC_X86_REG_SP)
        f = self.u16(ss, sp + 4)
        f = (f | 1) if on else (f & ~1)
        self.wr(ss, sp + 4, struct.pack('<H', f))

    def set_zf(self, on):
        ss, sp = self.r(UC_X86_REG_SS), self.r(UC_X86_REG_SP)
        f = self.u16(ss, sp + 4)
        f = (f | 0x40) if on else (f & ~0x40)
        self.wr(ss, sp + 4, struct.pack('<H', f))

    def push(self, v):
        sp = (self.r(UC_X86_REG_SP) - 2) & 0xffff
        self.w(UC_X86_REG_SP, sp)
        self.wr(self.r(UC_X86_REG_SS), sp, struct.pack('<H', v & 0xffff))

    def raise_int(self, n):
        cs, ip = self.r(UC_X86_REG_CS), self.r(UC_X86_REG_IP)
        fl = self.r(UC_X86_REG_EFLAGS)
        self.push(fl); self.push(cs); self.push(ip)
        self.w(UC_X86_REG_EFLAGS, fl & ~0x300)
        off, seg = struct.unpack('<HH', self.uc.mem_read(n * 4, 4))
        self.w(UC_X86_REG_CS, seg); self.w(UC_X86_REG_IP, off)

    # ------------------------------------------------------------ traps
    def _intr(self, uc, intno, _):
        self.raise_int(intno)

    def _unmapped(self, uc, access, addr, size, value, _):
        self.log('unmapped access %x' % addr)
        return False

    def _bios(self, uc, addr, size, _):
        n = (addr - self.BIOS * 16) // 4
        if (addr - self.BIOS * 16) % 4:
            return
        try:
            h = getattr(self, 'int_%02x' % n, None)
            if h:
                h()
            elif n not in (0x08, 0x1c, 0x09, 0x0b, 0x0f, 0x0d):
                self.log('unhandled int %02x ax=%04x' % (n, self.r(UC_X86_REG_AX)))
        except Exception as e:
            import traceback; traceback.print_exc()
            self.stop_reason = 'python error'
            uc.emu_stop()

    # ------------------------------------------------------------ ports
    def _in(self, uc, port, size, _):
        if port == 0x3da:
            self.retrace ^= 1
            return 0x09 if self.retrace else 0x00
        if port == 0x3c9:
            v = self.palette[self.pal_r % 768]; self.pal_r += 1; return v
        if port == 0x21 or port == 0xa1:
            return 0
        if port == 0x60:
            return 0
        if port == 0x64:
            return 0x14
        if port == 0x201:
            return 0xff  # no joystick
        return 0xff

    def _out(self, uc, port, size, value, _):
        if port == 0x3c8:
            self.pal_w = (value & 0xff) * 3
        elif port == 0x3c7:
            self.pal_r = (value & 0xff) * 3
        elif port == 0x3c9:
            self.palette[self.pal_w % 768] = value & 0x3f; self.pal_w += 1
        elif port == 0x43:
            self.pit_mode = value
            self.pit_bytes = []
        elif port == 0x40:
            self.pit_bytes = getattr(self, 'pit_bytes', []) + [value & 0xff]
            if len(self.pit_bytes) == 2:
                self.pit_div = (self.pit_bytes[0] | self.pit_bytes[1] << 8) or 0x10000
                self.log('PIT divisor %d (%.1f Hz)' % (self.pit_div, 1193182 / self.pit_div))
                self.pit_bytes = []

    # ------------------------------------------------------------ BIOS
    def int_10(self):
        ah = self.r(UC_X86_REG_AH)
        if ah == 0x0e:
            self.tty = getattr(self, 'tty', '') + chr(self.r(UC_X86_REG_AL))
            if self.tty.endswith(chr(10)):
                self.log('TTY: ' + self.tty.rstrip()); self.tty = ''
        elif ah == 0x00:
            self.video_mode = self.r(UC_X86_REG_AL) & 0x7f
            self.log('video mode %02x' % self.video_mode)
        elif ah == 0x0f:
            self.w(UC_X86_REG_AX, (80 << 8) | self.video_mode); self.w(UC_X86_REG_BX, 0)
        elif ah == 0x10 and self.r(UC_X86_REG_AL) == 0x12:
            bx, cx = self.r(UC_X86_REG_BX), self.r(UC_X86_REG_CX)
            es, dx = self.r(UC_X86_REG_ES), self.r(UC_X86_REG_DX)
            data = self.rd(es, dx, cx * 3)
            self.palette[bx * 3:bx * 3 + cx * 3] = data
        elif ah == 0x1a:
            self.w(UC_X86_REG_AX, 0x001a); self.w(UC_X86_REG_BX, 0x0008)
        elif ah == 0x12:
            self.w(UC_X86_REG_BX, 0x0003)

    def int_11(self):
        self.w(UC_X86_REG_AX, 0x0021)

    def int_12(self):
        self.w(UC_X86_REG_AX, 640)

    def int_15(self):
        ax, bx = self.r(UC_X86_REG_AX), self.r(UC_X86_REG_BX)
        if ax == 0x1209:   # Origin JEMM services
            name = struct.pack('>H', bx).decode('latin1')
            if name == 'AC':
                self.w(UC_X86_REG_AX, 0); self.w(UC_X86_REG_BX, 0x1209)
            elif name == 'VE':
                self.w(UC_X86_REG_AX, 0x436)
            elif name in ('sm', 'SM'):
                self.w(UC_X86_REG_BX, self.jemm_mode); self.set_mode(0 if name == 'sm' else 1)
            elif name == 'FF':
                self.w(UC_X86_REG_AX, 0); self.w(UC_X86_REG_ES, 0x0040); self.w(UC_X86_REG_DI, 0xF0); self.wr(0x40, 0xF0, b'')
            elif name == 'FH':
                h = self.r(UC_X86_REG_DX)
                self.w(UC_X86_REG_AX, 0); self.uc.reg_write(UC_X86_REG_EDX, self.ems[h]['linear'])
            else:
                cs, ip = self.u16(self.r(UC_X86_REG_SS), self.r(UC_X86_REG_SP) + 2), self.u16(self.r(UC_X86_REG_SS), self.r(UC_X86_REG_SP))
                self.log('JEMM %s cx=%04x dx=%04x es:di=%04x:%04x edx=%08x from %04x:%04x' % (name, self.r(UC_X86_REG_CX), self.r(UC_X86_REG_DX), self.r(UC_X86_REG_ES), self.r(UC_X86_REG_DI), self.uc.reg_read(UC_X86_REG_EDX), cs, ip))
            return
        ah = ax >> 8
        if ah == 0xc0:      # system configuration: report an RTC (feature bit 0x20)
            self.wr(0x0050, 0x40, struct.pack('<HBBBB', 8, 0xfc, 0x01, 0x00, 0x70) + bytes(4))
            self.w(UC_X86_REG_ES, 0x0050); self.w(UC_X86_REG_BX, 0x40); self.w(UC_X86_REG_AX, ax & 0xff)
            self.set_cf(False)
        elif ah == 0x83:    # event wait: set bit 7 of es:bx after cx:dx microseconds
            al = ax & 0xff
            if al == 1:
                self.rtc_event = None
            else:
                us = (self.r(UC_X86_REG_CX) << 16) | self.r(UC_X86_REG_DX)
                self.rtc_event = (self.time_us() + us, self.r(UC_X86_REG_ES), self.r(UC_X86_REG_BX))
            self.set_cf(False)
        elif ah == 0x86:    # blocking wait
            self.set_cf(False)
        else:
            self.set_cf(True); self.w(UC_X86_REG_AX, 0x8600)

    def int_16(self):
        ah = self.r(UC_X86_REG_AH) & 0xef
        if ah == 1:
            if self.keys:
                self.w(UC_X86_REG_AX, self.keys[0]); self.set_zf(False)
            else:
                self.set_zf(True)
        elif ah == 0:
            self.w(UC_X86_REG_AX, self.keys.pop(0) if self.keys else 0x011b)
        elif ah == 2:
            self.w(UC_X86_REG_AX, 0)

    def int_1a(self):
        ah = self.r(UC_X86_REG_AH)
        if ah == 0:
            t = int(self.ticks * 0x10000 / self.pit_div) if self.pit_div else self.ticks
            self.w(UC_X86_REG_CX, t >> 16); self.w(UC_X86_REG_DX, t); self.w(UC_X86_REG_AX, 0)
        else:
            self.set_cf(True)

    def int_2f(self):
        ax = self.r(UC_X86_REG_AX)
        if ax == 0x1500:      # MSCDEX: one CD drive, D:
            self.w(UC_X86_REG_BX, 1); self.w(UC_X86_REG_CX, 3)
        else:
            self.w(UC_X86_REG_AX, ax & 0xff00 if ax == 0x4300 else ax)

    def int_33(self):
        # A mouse that scripts can move and click: self.mouse = [x, y, buttons]
        # in 320 x 200 screen pixels.
        ax = self.r(UC_X86_REG_AX)
        m = getattr(self, 'mouse', None)
        if m is None:
            m = self.mouse = [160, 100, 0]
            self.mouse_presses = 0
            self.mouse_last = (160, 100)
        if ax == 0:
            self.w(UC_X86_REG_AX, 0xffff); self.w(UC_X86_REG_BX, 2)
        elif ax == 3:
            self.w(UC_X86_REG_BX, m[2]); self.w(UC_X86_REG_CX, m[0] * 2); self.w(UC_X86_REG_DX, m[1])
        elif ax == 4:
            m[0] = self.r(UC_X86_REG_CX) // 2; m[1] = self.r(UC_X86_REG_DX)
        elif ax == 5:
            self.w(UC_X86_REG_AX, m[2]); self.w(UC_X86_REG_BX, self.mouse_presses)
            self.w(UC_X86_REG_CX, m[0] * 2); self.w(UC_X86_REG_DX, m[1])
            self.mouse_presses = 0
        elif ax == 6:
            self.w(UC_X86_REG_AX, m[2]); self.w(UC_X86_REG_BX, 0)
        elif ax == 0x0b:
            lx, ly = self.mouse_last
            self.w(UC_X86_REG_CX, (m[0] - lx) * 2); self.w(UC_X86_REG_DX, m[1] - ly)
            self.mouse_last = (m[0], m[1])

    def click(self, x, y, button=1):
        """Moves the mouse and presses the button (release with release())."""
        self.int_33_init()
        self.mouse[0], self.mouse[1], self.mouse[2] = x, y, button
        self.mouse_presses += 1

    def release(self):
        self.int_33_init()
        self.mouse[2] = 0

    def int_33_init(self):
        if getattr(self, 'mouse', None) is None:
            self.mouse = [160, 100, 0]
            self.mouse_presses = 0
            self.mouse_last = (160, 100)

    # ------------------------------------------------------------ overlays (JEMM int 3Fh)
    OVL_AREAS = [(0xC000, 0xE000), (0xF000, 0x10000)]

    def _ovl_init(self, exe):
        self.ovl_base = None
        i = exe.find(b'FBOV')
        self.ovl_base = i + 16
        self.ovl_data = exe
        self.ovl_loaded = {}     # stub seg -> (load seg, paras)
        self.ovl_lru = []

    def _ovl_free_space(self, paras):
        while True:
            used = sorted((v[0], v[0] + v[1]) for v in self.ovl_loaded.values())
            for lo, hi in self.OVL_AREAS:
                at = lo
                for a, b in used:
                    if b <= at or a >= hi: continue
                    if a - at >= paras: return at
                    at = max(at, b)
                if hi - at >= paras: return at
            victim = self.ovl_lru.pop(0)
            self._ovl_unload(victim)

    def _ovl_unload(self, stub):
        seg, paras = self.ovl_loaded.pop(stub)
        n = self.u16(stub, 0x0c)
        for k in range(n):
            off = self.u16(stub, 0x20 + 5 * k + 1)
            self.wr(stub, 0x20 + 5 * k, bytes([0xcd, 0x3f]) + struct.pack('<HB', off, 0))
        self.uc.ctl_remove_cache(stub * 16, stub * 16 + 0x20 + 5 * n)
        self.log('overlay %04x evicted' % (stub - self.load_seg))

    def _ovl_load(self, stub):
        fo = struct.unpack('<I', self.rd(stub, 4, 4))[0]
        size, rsize, n = struct.unpack('<HHH', self.rd(stub, 8, 6))
        code = bytearray(self.ovl_data[self.ovl_base + fo:self.ovl_base + fo + size])
        rel = self.ovl_data[self.ovl_base + fo + size:self.ovl_base + fo + size + rsize]
        for k in range(rsize // 2):
            o = struct.unpack_from('<H', rel, 2 * k)[0]
            v = struct.unpack_from('<H', code, o)[0]
            struct.pack_into('<H', code, o, (v + self.load_seg) & 0xffff)
        paras = (size + 15) // 16 + 1
        seg = self._ovl_free_space(paras)
        self.wr(seg, 0, code)
        for k in range(n):
            off = self.u16(stub, 0x20 + 5 * k + 2)
            self.wr(stub, 0x20 + 5 * k, bytes([0xea]) + struct.pack('<HH', off, seg))
        self.ovl_loaded[stub] = (seg, paras)
        self.uc.ctl_remove_cache(stub * 16, stub * 16 + 0x20 + 5 * n)
        self.uc.ctl_remove_cache(seg * 16, seg * 16 + paras * 16)
        self.ovl_lru.append(stub)
        self.ovl_names = getattr(self, 'ovl_names', {})
        self.ovl_names[seg] = stub - self.load_seg
        return seg

    def int_3f(self):
        ss, sp = self.r(UC_X86_REG_SS), self.r(UC_X86_REG_SP)
        ip, cs = self.u16(ss, sp), self.u16(ss, sp + 2)
        if cs not in self.ovl_loaded:
            self._ovl_load(cs)
        else:
            self.ovl_lru.remove(cs); self.ovl_lru.append(cs)
        # re-run the (now patched) stub entry
        self.wr(ss, sp, struct.pack('<H', ip - 2))

    # ------------------------------------------------------------ EMS
    # Each handle is one host buffer mapped linearly (JEMM 'FH' exposes it); the
    # page frame windows alias 16 KB pieces of it.
    def _ptr(self, m, fallback):
        return fallback if m is None else ctypes.addressof(self.ems[m[0]]['buf']) + m[1] * 0x4000

    def _remap(self, base, ptr):
        cur = self.slot_ptr.get(base)
        if cur == ptr:
            return
        self.slot_ptr[base] = ptr
        self.remaps += 1
        self.uc.mem_unmap(base, 0x4000)
        self.uc.mem_map_ptr(base, 0x4000, UC_PROT_ALL, ptr)
        self.uc.ctl_remove_cache(base, base + 0x4000)

    def _show_big(self, i):
        conv = ctypes.addressof(self.conv) + i * 0x4000
        # 'sm' (mode 0) only uncovers VGA memory (A000-AFFF, pages 0-3)
        # 'sm' (mode 0) uncovers VGA memory (A000-AFFF, pages 0-3)
        ptr = self._ptr(self.big_map[i], conv) if (self.jemm_mode or i >= 4) else conv
        self._remap(self.BIG * 16 + i * 0x4000, ptr)

    def set_mode(self, big):
        if big != self.jemm_mode:
            self.jemm_mode = big
            for i in range(4):
                self._show_big(i)
            for i in range(4):
                self._show_frame(i)

    def _show_frame(self, i):
        pass

    def _map_phys(self, n, m):
        # Physical pages 0-19: A000-EFFF window, 20-23: the F000 frame (shared by both modes).
        if n < self.NBIG:
            self.big_map[n] = m; self._show_big(n)
        elif n < self.NBIG + 4:
            n -= self.NBIG
            self.small_map[n] = m
            self._remap(0xF0000 + n * 0x4000, self._ptr(m, ctypes.addressof(self.small_buf[n])))
        else:
            self.log('EMS map to phys %d ignored' % n)

    def int_67(self):
        ah = self.r(UC_X86_REG_AH)
        ok = lambda: self.w(UC_X86_REG_AX, self.r(UC_X86_REG_AX) & 0xff)
        if ah == 0x40:
            ok()
        elif ah == 0x41:
            ok(); self.w(UC_X86_REG_BX, self.BIG if self.jemm_mode else 0xF000)
        elif ah == 0x42:
            used = sum(v['pages'] for v in self.ems.values())
            ok(); self.w(UC_X86_REG_BX, 2048 - used); self.w(UC_X86_REG_DX, 2048)
        elif ah == 0x43:
            n = self.r(UC_X86_REG_BX); h = self.next_ems; self.next_ems += 1
            size = max(1, n) * 0x4000
            buf = ctypes.create_string_buffer(size)
            lin = self.ems_linear; self.ems_linear += (size + 0xfffff) & ~0xfffff
            self.uc.mem_map_ptr(lin, size, UC_PROT_ALL, ctypes.addressof(buf))
            self.ems[h] = {'buf': buf, 'pages': n, 'linear': lin}
            self.log('EMS alloc %d pages -> handle %d at %x' % (n, h, lin))
            ok(); self.w(UC_X86_REG_DX, h)
        elif ah == 0x44:
            al = self.r(UC_X86_REG_AL); bx = self.r(UC_X86_REG_BX); h = self.r(UC_X86_REG_DX)
            self._map_phys(al, None if bx == 0xffff else (h, bx))
            ok()
        elif ah == 0x45:
            h = self.r(UC_X86_REG_DX)
            for i, m in enumerate(self.big_map):
                if m and m[0] == h: self.big_map[i] = None
            for i, m in enumerate(self.small_map):
                if m and m[0] == h: self.small_map[i] = None
            e = self.ems.pop(h, None)
            if e: self.uc.mem_unmap(e['linear'], len(e['buf']))
            ok()
        elif ah == 0x46:
            self.w(UC_X86_REG_AX, 0x0040)
        elif ah == 0x4b:
            ok(); self.w(UC_X86_REG_BX, len(self.ems))
        elif ah == 0x4c:
            ok(); self.w(UC_X86_REG_BX, self.ems.get(self.r(UC_X86_REG_DX), {'pages': 0})['pages'])
        elif ah == 0x50:   # map multiple
            al = self.r(UC_X86_REG_AL); h = self.r(UC_X86_REG_DX); cx = self.r(UC_X86_REG_CX)
            ds, si = self.r(UC_X86_REG_DS), self.r(UC_X86_REG_SI)
            for k in range(cx):
                lp, phys = struct.unpack('<HH', self.rd(ds, si + 4 * k, 4))
                if al == 2:
                    self.log('EMS 5002 lp=%x phys=%x' % (lp, phys)); continue
                if al == 1:
                    phys = (phys - self.BIG) // 0x400
                self._map_phys(phys, None if lp == 0xffff else (h, lp))
            ok()
        elif ah == 0x47:
            self.saved_map = (list(self.big_map), list(self.small_map)); ok()
        elif ah == 0x48:
            for i, m in enumerate(self.saved_map[0] + self.saved_map[1]): self._map_phys(i, m)
            ok()
        elif ah == 0x4e:
            if self.r(UC_X86_REG_AL) == 3: self.w(UC_X86_REG_AX, 16)
            else: ok()
        elif ah == 0xde:    # no VCPI
            self.w(UC_X86_REG_AX, 0x8400)
        else:
            self.log('EMS fn %02x unhandled' % ah)
            self.w(UC_X86_REG_AX, 0x8400)

    # ------------------------------------------------------------ DOS
    def alloc(self, paras):
        segs = sorted(self.mcb.items())
        start = self.PSP
        cand = None
        prev_end = None
        for s, n in segs:
            if prev_end is not None and s - prev_end >= paras + 1:
                cand = prev_end + 1; break
            prev_end = s + n
        if cand is None:
            cand = prev_end + 1
        if paras == 0 or cand + paras > self.mem_top:
            free = self.mem_top - prev_end - 1
            return None, max(0, free)
        self.mcb[cand] = paras
        return cand, 0

    def int_21(self):
        uc = self.uc
        ah = self.r(UC_X86_REG_AH); al = self.r(UC_X86_REG_AL)
        ds, dx = self.r(UC_X86_REG_DS), self.r(UC_X86_REG_DX)
        self.set_cf(False)
        fail = lambda code: (self.set_cf(True), self.w(UC_X86_REG_AX, code))
        if ah == 0x30:
            self.w(UC_X86_REG_AX, 0x0005); self.w(UC_X86_REG_BX, 0); self.w(UC_X86_REG_CX, 0)
        elif ah == 0x35:
            off, seg = struct.unpack('<HH', uc.mem_read(al * 4, 4))
            self.w(UC_X86_REG_ES, seg); self.w(UC_X86_REG_BX, off)
        elif ah == 0x25:
            uc.mem_write(al * 4, struct.pack('<HH', dx, ds))
            self.log('set vector %02x -> %04x:%04x' % (al, ds, dx))
        elif ah == 0x4a:
            es, bx = self.r(UC_X86_REG_ES), self.r(UC_X86_REG_BX)
            limit = self.mem_top
            for s in self.mcb:
                if s > es: limit = min(limit, s - 1)
            if es + bx > limit:
                fail(8); self.w(UC_X86_REG_BX, limit - es)
            else:
                self.mcb[es] = bx
        elif ah == 0x48:
            seg, free = self.alloc(self.r(UC_X86_REG_BX))
            if seg is None:
                fail(8); self.w(UC_X86_REG_BX, free)
            else:
                self.w(UC_X86_REG_AX, seg)
        elif ah == 0x49:
            self.mcb.pop(self.r(UC_X86_REG_ES), None)
        elif ah == 0x3d or ah == 0x6c:
            name = self.cstr(ds, dx) if ah == 0x3d else self.cstr(ds, self.r(UC_X86_REG_SI))
            hf = host_file(name)
            self.log('open %r -> %s' % (name, hf and hf[1]))
            if hf is None:
                fail(2)
            else:
                h = self.next_handle; self.next_handle += 1
                self.files[h] = OpenFile(*hf)
                self.w(UC_X86_REG_AX, h)
                if ah == 0x6c: self.w(UC_X86_REG_CX, 1)
        elif ah == 0x3c:
            name = self.cstr(ds, dx); self.log('create %r (ignored)' % name)
            h = self.next_handle; self.next_handle += 1
            self.files[h] = None; self.w(UC_X86_REG_AX, h)
        elif ah == 0x3e:
            self.files.pop(self.r(UC_X86_REG_BX), None)
        elif ah == 0x3f:
            h = self.r(UC_X86_REG_BX); n = self.r(UC_X86_REG_CX)
            f = self.files.get(h)
            if f is None:
                self.w(UC_X86_REG_AX, 0)
            else:
                b = f.read(n); self.wr(ds, dx, b); self.w(UC_X86_REG_AX, len(b))
        elif ah == 0x40:
            h = self.r(UC_X86_REG_BX); n = self.r(UC_X86_REG_CX)
            if h in (1, 2):
                self.log('STDOUT: %r' % self.rd(ds, dx, n))
            self.w(UC_X86_REG_AX, n)
        elif ah == 0x42:
            h = self.r(UC_X86_REG_BX); f = self.files.get(h)
            off = (self.r(UC_X86_REG_CX) << 16) | dx
            if off & 0x80000000: off -= 1 << 32
            if f is None:
                self.w(UC_X86_REG_AX, 0); self.w(UC_X86_REG_DX, 0)
            else:
                f.pos = [0, f.pos, f.size][al] + off
                self.w(UC_X86_REG_AX, f.pos & 0xffff); self.w(UC_X86_REG_DX, f.pos >> 16)
        elif ah == 0x44:
            if al == 0:
                h = self.r(UC_X86_REG_BX)
                self.w(UC_X86_REG_DX, 0x80d3 if h < 5 else 0x0002)
            elif al == 8:
                self.w(UC_X86_REG_AX, 1)
            else:
                self.w(UC_X86_REG_AX, 0)
        elif ah == 0x1a:
            self.dta = (ds, dx)
        elif ah == 0x2f:
            self.w(UC_X86_REG_ES, self.dta[0]); self.w(UC_X86_REG_BX, self.dta[1])
        elif ah == 0x4e:
            name = self.cstr(ds, dx); hf = host_file(name)
            self.log('findfirst %r -> %s' % (name, hf and hf[1]))
            if hf is None: fail(18)
            else:
                f = OpenFile(*hf)
                rec = bytearray(43); rec[21] = 0x20
                struct.pack_into('<I', rec, 26, f.size)
                nm = os.path.basename(hf[1].replace('/', '\\')).upper().encode()[:12]
                rec[30:30 + len(nm)] = nm
                self.wr(self.dta[0], self.dta[1], rec)
        elif ah == 0x4f:
            fail(18)
        elif ah == 0x19:
            self.w(UC_X86_REG_AX, (ah << 8) | 2)
        elif ah == 0x0e:
            self.w(UC_X86_REG_AX, (ah << 8) | 26)
        elif ah == 0x47:
            self.wr(ds, self.r(UC_X86_REG_SI), b'\0')
        elif ah == 0x3b:
            self.log('chdir %r' % self.cstr(ds, dx))
        elif ah == 0x2a:
            self.w(UC_X86_REG_CX, 1993); self.w(UC_X86_REG_DX, 0x0101); self.w(UC_X86_REG_AX, (ah << 8) | 5)
        elif ah == 0x2c:
            t = self.ticks
            self.w(UC_X86_REG_CX, 0x0c00 | (t // 1092 % 60)); self.w(UC_X86_REG_DX, (t // 18 % 60) << 8)
        elif ah == 0x33:
            self.w(UC_X86_REG_DX, 0)
        elif ah == 0x62 or ah == 0x51:
            self.w(UC_X86_REG_BX, self.PSP)
        elif ah == 0x0b:
            self.w(UC_X86_REG_AX, (ah << 8))
        elif ah in (0x06, 0x07, 0x08):
            self.set_zf(True); self.w(UC_X86_REG_AX, ah << 8)
        elif ah == 0x09:
            s = self.rd(ds, dx, 300).split(b'$')[0]; self.log('PRINT: %r' % s)
        elif ah == 0x4c or ah == 0x00:
            self.log('exit %d' % al); self.stop_reason = 'exit'; uc.emu_stop()
        elif ah == 0x58:
            self.w(UC_X86_REG_AX, 0)
        elif ah == 0x36:
            self.w(UC_X86_REG_AX, 64); self.w(UC_X86_REG_BX, 10000); self.w(UC_X86_REG_CX, 512); self.w(UC_X86_REG_DX, 20000)
        elif ah == 0x29:
            self.w(UC_X86_REG_AX, 0)
        elif ah == 0x43:
            name = self.cstr(ds, dx)
            if host_file(name) is None: fail(2)
            else: self.w(UC_X86_REG_CX, 0x20)
        elif ah == 0x41:
            pass
        else:
            self.log('DOS fn %02x unhandled (al=%02x)' % (ah, al))
            fail(1)

    # ------------------------------------------------------------ running
    def time_us(self):
        return self.ticks * self.pit_div * 1_000_000 // 1193182

    def tick_insns(self):
        hz = 1193182 / self.pit_div
        return max(2000, int(6_000_000 / hz))   # ~6 MIPS machine

    def run(self, max_ticks=10_000, until=None):
        uc = self.uc
        while self.stop_reason is None and self.ticks < max_ticks:
            cs, ip = self.r(UC_X86_REG_CS), self.r(UC_X86_REG_IP)
            try:
                uc.emu_start(cs * 16 + ip, 0xFFFFFFFF, count=self.tick_insns())
            except UcError as e:
                cs, ip = self.r(UC_X86_REG_CS), self.r(UC_X86_REG_IP)
                self.log('CPU error %s at %04x:%04x' % (e, cs, ip))
                self.stop_reason = 'cpu'
                break
            self.ticks += 1
            ev = getattr(self, 'rtc_event', None)
            if ev and self.time_us() >= ev[0]:
                b = self.rd(ev[1], ev[2], 1)[0]
                self.wr(ev[1], ev[2], bytes([b | 0x80]))
                self.rtc_event = None
            self.last_pc = (self.r(UC_X86_REG_CS), self.r(UC_X86_REG_IP))
            if self.r(UC_X86_REG_EFLAGS) & 0x200:
                self.raise_int(8)
            if until and until(self):
                break

    def screenshot(self, path):
        if getattr(self, 'shot_from_window', False):
            # the A000 surface as seen in 'SM' mode (EMS pages 0-3)
            vram = b''.join(ctypes.string_at(self._ptr(self.big_map[i], ctypes.addressof(self.conv) + i * 0x4000), 0x4000) for i in range(4))[:64000]
        else:
            vram = ctypes.string_at(ctypes.addressof(self.conv) + 0xA0000 - self.BIG * 16, 64000)
        pal = bytes(min(255, c * 4 + c // 16) for c in self.palette)
        raw = b''.join(b'\0' + b''.join(pal[p * 3:p * 3 + 3] for p in vram[y * 320:(y + 1) * 320]) for y in range(200))
        def ch(t, d): return struct.pack('>I', len(d)) + t + d + struct.pack('>I', zlib.crc32(t + d) & 0xffffffff)
        open(path, 'wb').write(b'\x89PNG\r\n\x1a\n' + ch(b'IHDR', struct.pack('>IIBBBBB', 320, 200, 8, 2, 0, 0, 0)) + ch(b'IDAT', zlib.compress(raw)) + ch(b'IEND', b''))


if __name__ == '__main__':
    e = Emu()
    t0 = time.time()
    shots = int(sys.argv[2]) if len(sys.argv) > 2 else 50
    maxt = int(sys.argv[1]) if len(sys.argv) > 1 else 2000
    def every(em):
        if em.ticks % shots == 0:
            em.screenshot('shot_%05d.png' % em.ticks)
        return False
    e.run(maxt, every)
    cs, ip = e.r(UC_X86_REG_CS), e.r(UC_X86_REG_IP)
    print('stopped', e.stop_reason, 'ticks', e.ticks, 'at %04x:%04x' % (cs, ip), '%.1fs' % (time.time() - t0))


def surface_png(e, ptr, path):
    """Dump an OPTTEST surface struct (seg, row table, x1, y1, x2, y2) as PNG."""
    ds = 0x5435
    seg, rows, x1, y1, x2, y2 = struct.unpack('<6H', e.rd(ds, ptr, 12))
    w, h = x2 - x1 + 1, y2 - y1 + 1
    if not (0 < w <= 320 and 0 < h <= 200):
        return None
    pal = bytes(min(255, c * 4 + c // 16) for c in e.palette)
    lines = []
    for y in range(h):
        off = e.u16(ds, rows + 2 * (y1 + y)) + x1
        px = e.rd(seg, off, w)
        lines.append(b'\0' + b''.join(pal[p * 3:p * 3 + 3] for p in px))
    def ch(t, d): return struct.pack('>I', len(d)) + t + d + struct.pack('>I', zlib.crc32(t + d) & 0xffffffff)
    open(path, 'wb').write(b'\x89PNG\r\n\x1a\n' + ch(b'IHDR', struct.pack('>IIBBBBB', w, h, 8, 2, 0, 0, 0)) + ch(b'IDAT', zlib.compress(b''.join(lines))) + ch(b'IEND', b''))
    return (seg, w, h)


def protect_lzw_refill(e):
    """The LZW decoder keeps its output mapped in EMS pages 20-23 while its input
    refill maps the file buffer there; keep the decoder's mapping (and the
    program's own page table) intact across the refill."""
    lin = lambda fo: e.load_seg * 16 + fo - 0x5c00
    DS, TABLE = 0x5435, 0x69d6
    saved = []

    def enter(uc, addr, size, _):
        saved.append((list(e.small_map), e.rd(DS, TABLE + 20 * 4, 16)))

    def leave(uc, addr, size, _):
        if saved:
            m, t = saved.pop()
            for i, x in enumerate(m):
                e._map_phys(20 + i, x)
            e.wr(DS, TABLE + 20 * 4, t)
    e.uc.hook_add(UC_HOOK_CODE, enter, begin=lin(0x494e9), end=lin(0x494e9))
    e.uc.hook_add(UC_HOOK_CODE, leave, begin=lin(0x49583), end=lin(0x49583))
