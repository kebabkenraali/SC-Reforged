## Interpreter for Strike Commander mission scripts (PROG bytecode).
##
## Rebuilt 17.11.2026 from the original interpreter in STRIKE.EXE (opcode
## jump table of 209 entries, 0x00..0xd0; see docs/PROG_VM.md for the full
## opcode reference and the confidence of each entry). The earlier version
## guessed a stack machine from data usage; the original is an
## ACCUMULATOR machine with condition flags:
##
##   state per owner : ACC (accumulator), E (status of the last action:
##                     non-zero = still in progress), COND (bit 1 = less,
##                     2 = equal, 4 = greater), call stack of blocks
##   variables       : one mission-wide word array. "Flags" are the same
##                     variables holding 0 / 1 (52 n sets var n = 1).
##   instructions    : 2 bytes, op + arg; a following "09 x" pair is not an
##                     instruction but an extra argument of the previous one.
##
##   00/01      return from a called block; at top level: end of this tick
##   02 n/03    call PROG block n / block ACC as a subroutine (max depth 16)
##   04         stop (also unwinds the calls)
##   08 n       label n                    0f k  global result byte = k
##   10 k ACC=k  11 n ACC=var n  12 n swap ACC<->var n  13 ACC=E
##   14 n       mission register n = ACC (n < 8; read by the engine)
##   20 k/21 n  ACC += k / var n           22 n  var n += n (sic)
##   23 n       var n += ACC               24 k/25 n  ACC -= k / var n
##   26 n       var n -= n (sic)           27 n  var n = var n - ACC
##   28/29 or, 2a/2b and, 2c/2d xor, 2e/2f mul, 30/31 div (k / var n)
##   40 k       compare ACC with k         41 k  compare k with ACC
##   42 n/43 n  compare ACC with var n / var n with ACC   44 k  compare E, k
##   45 n       compare var n with 1 (a "flag is set" test)
##   46 r/47 r  jump to label r if E != 0 / E == 0
##   48 r =, 49 r !=, 4a r <, 4b r >, 4c r <=, 4d r >=, 4e r always,
##   4f         jump to label ACC.  Labels are searched FORWARD from the
##              current position only, up to the end of the block.
##   50 n var n = ACC   51 n var n = E   52 n var n = 1   53 n var n = 0
##   54 n var n ^= 1    55 n var n += 1  56 n var n -= 1
##   80 n/81 n/82 n  set / clear / test (equal flag) the state byte of
##              mission list entry n (probably an area or scene)
##   90 id activate part, 91 id remove part, 92 id equal flag = part alive,
##   93 id equal flag = part destroyed, 98 id equal flag = part present in
##   the world, 94 / 99 id engine calls (not decoded)
##   95 id ACC = 3D distance owner -> part in 1000 ft (max 255)
##   96 id ACC = (altitude ft - 2250) / 100 (max 255)
##   97 n  ACC = 3D distance owner -> SPOT n in 1000 ft (max 255)
##   a0 k  wait k seconds (E = 1 until the owner's timer ran out)
##   a1..bf actions of the owner (a1 take off, a2 land, a3/a4/a5/ac fly to,
##         a7 attack, a8 escort, a9, aa follow, ab radio, b1, b2, b3, b4,
##         b5, bf): E = the action's status. Without a live owner E = 0.
##         a6 is no action in the original (route data only).
##   b6/b7 id, b8/b9 id  set / clear object bits 0x10 / 0x20 of part id
##   be id  run the action prologue on part id (no action of its own)
##   c0 k   engine call;  d0 k  global byte = k
extends RefCounted

const MAX_STEPS := 4000
const MAX_DEPTH := 16
## Ops the original hands to the owner's action routine (0x56499).
const ACTIONS := [0xa1, 0xa2, 0xa3, 0xa4, 0xa5, 0xa7, 0xa8, 0xa9, 0xaa, 0xab, 0xac,
	0xb1, 0xb2, 0xb3, 0xb4, 0xb5, 0xbf]
const LESS := 1
const EQUAL := 2
const GREATER := 4


## Runs one tick of a program for one owner. `key` identifies the owner
## (part id >= 0, or a negative id for scene / mission-wide programs);
## `host` provides the world (see flight_scene.gd "host interface").
static func run(code: Array, key: int, host) -> void:
	if code.is_empty():
		return
	var st: Dictionary = host.vm_state(key) if host.has_method("vm_state") else {}
	if st.is_empty():
		st.merge({"acc": 0, "e": 0, "cond": 0})
	var frames := []              # call stack: [code, pc]
	var pc := 0
	var steps := 0
	while steps < MAX_STEPS:
		steps += 1
		if pc >= code.size():
			# Ran off the end: same as a return.
			if frames.is_empty():
				return
			var f: Array = frames.pop_back()
			code = f[0]
			pc = f[1]
			continue
		var op: int = code[pc][0]
		var arg: int = code[pc][1]
		pc += 1
		var extra := -1
		if pc < code.size() and code[pc][0] == 0x09:
			extra = code[pc][1]
			pc += 1
		match op:
			0x00, 0x01:
				if frames.is_empty():
					return
				var f: Array = frames.pop_back()
				code = f[0]
				pc = f[1]
			0x02, 0x03:
				var b: int = arg if op == 0x02 else int(st.acc)
				var sub: Array = host.vm_block(b) if host.has_method("vm_block") else []
				if frames.size() < MAX_DEPTH and not sub.is_empty():
					frames.append([code, pc])
					code = sub
					pc = 0
			0x04:
				return
			0x08:
				pass
			0x0f:
				# Original: sets a global byte only (not used by any mission).
				if host.has_method("vm_global"):
					host.vm_global(op, arg)
			0x10:
				st.acc = arg
			0x11:
				st.acc = host.vm_var(arg)
			0x12:
				var t: int = host.vm_var(arg)
				host.vm_set_var(arg, st.acc)
				st.acc = t
			0x13:
				st.acc = st.e
			0x14:
				if arg < 8 and host.has_method("vm_set_register"):
					host.vm_set_register(arg, st.acc)
			0x20: st.acc += arg
			0x21: st.acc += host.vm_var(arg)
			0x22: host.vm_set_var(arg, host.vm_var(arg) + arg)
			0x23: host.vm_set_var(arg, host.vm_var(arg) + st.acc)
			0x24: st.acc -= arg
			0x25: st.acc -= host.vm_var(arg)
			0x26: host.vm_set_var(arg, host.vm_var(arg) - arg)
			0x27: host.vm_set_var(arg, host.vm_var(arg) - st.acc)
			0x28: st.acc = int(st.acc) | arg
			0x29: st.acc = int(st.acc) | host.vm_var(arg)
			0x2a: st.acc = int(st.acc) & arg
			0x2b: st.acc = int(st.acc) & host.vm_var(arg)
			0x2c: st.acc = int(st.acc) ^ arg
			0x2d: st.acc = int(st.acc) ^ host.vm_var(arg)
			0x2e: st.acc = _i16(int(st.acc) * arg)
			0x2f: st.acc = _i16(int(st.acc) * host.vm_var(arg))
			0x30: st.acc = _div(st.acc, arg)
			0x31: st.acc = _div(st.acc, host.vm_var(arg))
			0x40: st.cond = _cmp(st.acc, arg)
			0x41: st.cond = _cmp(arg, st.acc)
			0x42: st.cond = _cmp(st.acc, host.vm_var(arg))
			0x43: st.cond = _cmp(host.vm_var(arg), st.acc)
			0x44: st.cond = _cmp(st.e, arg)
			0x45: st.cond = _cmp(host.vm_var(arg), 1)
			0x46, 0x47, 0x48, 0x49, 0x4a, 0x4b, 0x4c, 0x4d, 0x4e, 0x4f:
				var take := false
				match op:
					0x46: take = st.e != 0
					0x47: take = st.e == 0
					0x48: take = st.cond & EQUAL != 0
					0x49: take = st.cond & EQUAL == 0
					0x4a: take = st.cond & LESS != 0
					0x4b: take = st.cond & GREATER != 0
					0x4c: take = st.cond & (LESS | EQUAL) != 0
					0x4d: take = st.cond & (EQUAL | GREATER) != 0
					0x4e, 0x4f: take = true
				if take:
					var target: int = int(st.acc) if op == 0x4f else arg
					var at := _find_label(code, pc, target)
					if at >= 0:
						pc = at
			0x50: host.vm_set_var(arg, st.acc)
			0x51: host.vm_set_var(arg, st.e)
			0x52: host.vm_set_var(arg, 1)
			0x53: host.vm_set_var(arg, 0)
			0x54: host.vm_set_var(arg, host.vm_var(arg) ^ 1)
			0x55: host.vm_set_var(arg, host.vm_var(arg) + 1)
			0x56: host.vm_set_var(arg, host.vm_var(arg) - 1)
			0x80, 0x81:
				if host.has_method("vm_list_flag"):
					host.vm_list_flag(arg, op == 0x80)
			0x82:
				var on: bool = host.vm_list_flag_get(arg) if host.has_method("vm_list_flag_get") else false
				st.cond = (int(st.cond) & ~EQUAL) | (EQUAL if on else 0)
			0x90:
				host.vm_activate(arg)
			0x91:
				host.vm_remove(arg)
			0x92, 0x93, 0x98:
				var yes: bool = host.vm_part_state(op, arg)
				st.cond = (int(st.cond) & ~EQUAL) | (EQUAL if yes else 0)
			0x95, 0x96, 0x97:
				st.acc = host.vm_measure(key, op, arg)
			0x94, 0x99, 0xc0, 0xd0, 0xb6, 0xb7, 0xb8, 0xb9, 0xbe:
				if host.has_method("vm_global"):
					host.vm_global(op, arg)
			0xa0:
				st.e = 0 if host.vm_wait(key, arg) else 1
			_:
				if op in ACTIONS:
					if host.vm_owner_ready(key):
						if op == 0xab:
							host.vm_message(key, arg)
							st.e = 0
						else:
							host.vm_action(key, op, arg, extra)
							st.e = 0 if host.vm_action_done(key) else 1
					else:
						st.e = 0


## Forward search for "08 label" from `from` to the end of the block.
static func _find_label(code: Array, from: int, label: int) -> int:
	for i in range(from, code.size()):
		if code[i][0] == 0x00:
			break
		if code[i][0] == 0x08 and code[i][1] == label:
			return i + 1
	return -1


static func _cmp(a: int, b: int) -> int:
	if a < b:
		return LESS
	if a == b:
		return EQUAL
	return GREATER


static func _i16(v: int) -> int:
	v &= 0xffff
	return v - 0x10000 if v >= 0x8000 else v


static func _div(a: int, b: int) -> int:
	if b == 0:
		return a
	return int(a / b)
