## Original Strike Commander disassembler: real-mode MZ executables to ASM
## listings with annotation. Not a decompiler; the goal is a source-like
## listing whose subsystems can be compared with the Godot port.
##
## Usage: python disasm.py <exe> <out_dir>
##  - Parses the MZ header (capstone 16-bit x86)
##  - Disassembles code between the loaded-image start and the image end,
##    per paragraph-aligned block; annotates:
##      * interrupt calls (int 21h/10h/16h/... with known DOS meanings)
##      * near/far calls and jumps -> labels and cross reference lists
##      * absolute string references (imm16 -> data range)
##  - Writes: <exe base>.asm (listing), _strings.txt (ASCIIZ dump),
##    _xrefs.txt (summary lists: ints, call targets, data refs)
import struct, sys, os, re


def parse_mz(data: bytes) -> dict:
	hdr = struct.unpack_from('<2sH14H', data, 0)
	cs, ip, ss, sp = hdr[9], hdr[10], hdr[12], hdr[13]
	hdrpages = struct.unpack_from('<H', data, 2)[0]
	hdrsize = (hdrpages & 0x1FF) if hdrpages != 0 else 512
	overflow = (hdrpages >> 9) if hdrpages >= 8 else 0
	start = ((cs + overflow) * 16 + ip)
	print("MZ: hdrpages=0x%x hdrsize=0x%x cs=0x%04x ip=0x%04x ss=0x%04x sp=0x%04x overlay=%d start=0x%x"
		% (hdrpages, hdrsize, cs, ip, ss, sp, hdr[3] if False else 0, start))
	return {"cs": cs, "ip": ip, "start": start}


def find_code_ranges(data: bytes, start: int):
	## STRIKE.EXE / OPTTEST.EXE: overlay executables contain a stub plus
	## many one-past paragraphs of code. Look for runs of x86-like bytes.
	return start, len(data)


def annotate(ins, s, e, data):
	## annotate the meaning of certain instructions
	return ""


def disassemble(data: bytes, start: int, out_asm, out_xref):
	## linear sweep with label bookkeeping; the dead-space heuristic: skip
	## long zero-filled gaps.
	from capstone import Cs, CS_ARCH_X86, CS_MODE_16
	md = Cs(CS_ARCH_X86, CS_MODE_16)
	md.detail = True
	int_calls = {}
	call_targets = {}
	data_refs = {}
	jump_targets = {}
	out = []
	addr = start
	while addr < len(data) - 1:
		gap_start = addr
		while addr < len(data) and data[addr] == 0x90 and addr + 1 < len(data) and data[addr+1] in (0x90, 0x00):
			addr += 1
		if addr > gap_start:
			out.append("    ; gap (nop/zeros) %06X..%06X" % (gap_start, addr))
		md2 = Cs(CS_ARCH_X86, CS_MODE_16)
		chunk_end = min(addr + 0x1000, len(data))
		for ins in md2.disasm(data[addr:chunk_end], addr):
			line = "%06X  %-24s %s" % (ins.address, ins.mnemonic, ins.op_str)
			m = re.match(r'call\s+0x([0-9a-f]+)', ins.mnemonic + " " + ins.op_str)
			if ins.mnemonic == "int":
				n = int(ins.op_str, 16) if ins.op_str.startswith("0x") else int(ins.op_str)
				int_calls[n] = int_calls.get(n, 0) + 1
				line += "   ; " + INT_NAMES.get(n, "")
			elif ins.mnemonic in ("call", "jmp"):
				mm = re.match(r'^(near|far|short)?\s*0x([0-9a-f]+)', ins.op_str)
				if mm:
					t = int(mm.group(2), 16)
					if ins.mnemonic == "jmp":
						jump_targets.setdefault(t, 0)
						jump_targets[t] += 1
						line = "%06X  %-24s %s L_%06X" % (ins.address, ins.mnemonic, mm.group(2), t)
					else:
						call_targets.setdefault(t, 0)
						call_targets[t] += 1
			elif ins.mnemonic.startswith("j"):
				mm = re.match(r'^\s*0x([0-9a-f]+)', ins.op_str)
				if mm:
					t = int(mm.group(1), 16)
					jump_targets[t] = jump_targets.get(t, 0) + 1
					line = "%06X  %-24s %s L_%06X" % (ins.address, ins.mnemonic, ins.op_str, t)
			elif "word ptr 0x" in ins.op_str or "byte ptr 0x" in ins.op_str:
				pass
			out.append(line)
			addr = ins.address + ins.size
			if addr >= chunk_end:
				break
		addr = chunk_end
	return out, int_calls, call_targets, jump_targets


INT_NAMES = {
	0x10: "video BIOS", 0x13: "disk BIOS", 0x14: "serial", 0x15: "misc/sys",
	0x16: "keyboard BIOS", 0x1a: "timer BIOS", 0x21: "DOS services",
	0x29: "fast console out", 0x2e: "command execute", 0x33: "mouse driver",
	0x2f: "multiplex (lightbox etc.)", 0x67: "EMS (DPMI/EMS)", 0x8: "timer IRQ",
	0x9: "keyboard IRQ", 0xc: "serial IRQ", 0x70: "RTC IRQ", 0x71: "??",
}


def dump_strings(data, out_path):
	for m in re.finditer(rb'[!-~ ]{6,}\x00', data):
		s = m.group()[:-1].decode('latin1').strip()
		if len(s) >= 6:
			out_path and open(out_path, 'a', encoding='latin1', errors='ignore').write("%06X: %s\n" % (m.start(), s))


if __name__ == "__main__":
	exe, outdir = sys.argv[1], sys.argv[2]
	os.makedirs(outdir, exist_ok=True)
	data = open(exe, 'rb').read()
	mz = parse_mz(data)
	start = mz["start"]
	if start >= len(data):
		print("MZ start beyond file; assuming flat from header size...")
		start = 0
	base = os.path.basename(exe)
	rsp = "%s/%s_strings.txt" % (outdir, base)
	if os.path.exists(rsp):
		os.remove(rsp)
	dump_strings(data, rsp)
	asm_lines, ints, calls, jumps = disassemble(data, start, None, None)
	open("%s/%s.asm" % (outdir, base), 'w', encoding='latin1', errors='ignore').write("\n".join(asm_lines))
	x = "%s/%s_xrefs.txt" % (outdir, base)
	with open(x, 'w', encoding='latin1') as f:
		f.write("INT usage:\n")
		for k, v in sorted(ints.items()):
			f.write("  int %02X x%d  %s\n" % (k, v, INT_NAMES.get(k, "?")))
		f.write("\nCall targets (top 40):\n")
		for k, v in sorted(calls.items(), key=lambda i: -i[1])[:40]:
			f.write("  L_%06X x%d\n" % (k, v))
		f.write("\nJournal targets (top 40):\n")
		for k, v in sorted(jumps.items(), key=lambda i: -i[1])[:40]:
			f.write("  L_%06X x%d\n" % (k, v))
		print("wrote", rsp, "and asm + xref")
