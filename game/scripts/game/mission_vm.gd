## Interpreter for Strike Commander mission scripts (PROG bytecode).
##
## A program is a block of 2-byte instructions. Programs are re-run from the top
## on every script tick; persistent state lives in mission variables, flags and
## each owner's current action, and AI programs keep their state machine in a
## variable that holds a label id (dispatched with 4f).
##
## Decoded from the original data (see docs/TIEDOSTOFORMAATIT.md):
##   10 k push k          11 n push var n       50 n pop -> var n
##   55 n var n += 1      56 n var n -= 1       23 n var n += pop
##   14 n var n = pop     40 k push(pop >= k)   41 k push(pop < k)
##   45 n push flag n
##   52 n set flag n      53 n clear flag n     92 id push(part id alive)
##   08 r label r         4e r goto r           4f 00 goto label popped
##   48 r / 4b r jump if pop true     49 r / 4a r jump if pop false
##   46 r jump if the owner's current action is not finished
##   01 00 end of this tick (yield)   0f n end mission (1 = success)
##   90 id activate part  91 id remove part     ab n radio message n
##   a0 k wait k s   a1 take off   a2 n land at SPOT n   a5/a6 n fly to SPOT n
##   a7 id attack    a8 id escort  aa id follow
## Every other opcode is skipped.
extends RefCounted

##   14 n var n = pop; the ops 21/24/25/2e/2f push a value first (see below)
const MAX_STEPS := 2000
const ACTIONS := [0xa0, 0xa1, 0xa2, 0xa5, 0xa6, 0xa7, 0xa8, 0xaa]
const PARAM_PUSHES := [0x21, 0x24, 0x25, 0x2e, 0x2f]


## Runs one program for one tick. `key` identifies the owner (part id >= 0,
## or a negative id for scene / global programs); `host` provides the world.
static func run(code: Array, key: int, host) -> void:
	if code.is_empty():
		return
	var labels := {}
	for i in code.size():
		if code[i][0] == 0x08:
			labels[code[i][1]] = i
	var stack: Array[int] = []
	var pc := 0
	var steps := 0
	while pc < code.size() and steps < MAX_STEPS:
		steps += 1
		var op: int = code[pc][0]
		var arg: int = code[pc][1]
		pc += 1
		match op:
			0x01:
				return
			0x08, 0x09:
				pass
			0x0f:
				host.vm_end(arg == 1)
			0x10:
				stack.push_back(arg)
			0x11:
				stack.push_back(host.vm_var(arg))
			0x50:
				host.vm_set_var(arg, _pop(stack))
			0x55:
				host.vm_set_var(arg, host.vm_var(arg) + 1)
			0x56:
				host.vm_set_var(arg, host.vm_var(arg) - 1)
			0x23:
				host.vm_set_var(arg, host.vm_var(arg) + _pop(stack))
			0x40:
				stack.push_back(1 if _pop(stack) >= arg else 0)
			0x41:
				stack.push_back(1 if _pop(stack) < arg else 0)
			0x45:
				stack.push_back(1 if host.vm_flag(arg) else 0)
			0x52:
				host.vm_set_flag(arg, true)
			0x53:
				host.vm_set_flag(arg, false)
			0x92:
				stack.push_back(1 if host.vm_alive(arg) else 0)
			0x4e:
				pc = labels.get(arg, code.size())
			0x4f:
				pc = labels.get(_pop(stack), code.size())
			0x48, 0x4b:
				if _pop(stack) != 0:
					pc = labels.get(arg, code.size())
			0x49, 0x4a:
				if _pop(stack) == 0:
					pc = labels.get(arg, code.size())
			0x46:
				if not host.vm_action_done(key):
					pc = labels.get(arg, code.size())
			0x90:
				host.vm_activate(arg)
			0x91:
				host.vm_remove(arg)
			0xab:
				host.vm_message(key, arg)
			0x14:
				# var n = pop (proven: "2e 19, 50 06" = var n = pushed param)
				host.vm_set_var(arg, _pop(stack))
			0x21, 0x24, 0x25, 0x2e, 0x2f:
				# Parameter pushes: enter a value consumed by a following 14/50.
				# De-coded from usage (prog_analyze.gd), e.g. every mission's
				# opening logic block pushes the mission parameter (2e 64 ->
				# var 1 = 100) and MISN-6A "2e 01, 50 06" sets a var from it.
				stack.push_back(host.vm_query_param(key, op, arg))
			0x93, 0x95, 0x97, 0x98:
				# Object queries: push object property onto stack
				# arg = part id to query
				stack.push_back(host.vm_query_object(key, op, arg))
			_:
				if op in ACTIONS:
					host.vm_action(key, op, arg)


static func _pop(stack: Array[int]) -> int:
	return stack.pop_back() if not stack.is_empty() else 0
