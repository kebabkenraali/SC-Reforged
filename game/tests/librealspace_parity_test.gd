## Cross-check against libRealSpace (tools/librealspace, commit 529fdc3):
##  - cockpit instrument quad centres from SCJetVirtualCockpit::f16Layout()
##  - mission PROG opcodes from SCenums.h prog_op
##  - exit-code / success handling from SCMission + mission_vm.gd
extends SceneTree

const Mission = preload("res://scripts/formats/sc_mission.gd")
const Instruments = preload("res://scripts/game/cockpit_instruments.gd")

# libRealSpace SCenums.h::prog_op (numeric values from the source).
const LRS_OPS := {
	0x01: "EXIT_PROG", 0x02: "EXEC_SUB_PROG", 0x08: "SET_LABEL", 0x09: "SPOT_DATA",
	0x0f: "SET_EXIT_CODE", 0x10: "MOVE_VALUE_TO_WORK", 0x11: "MOVE_FLAG_TO_WORK",
	0x14: "SAVE_TO_GAMEFLOW", 0x21: "ADD_TO_FLAG", 0x23: "ADD_WORK_TO_FLAG",
	0x2e: "MUL_VALUE_WITH_WORK", 0x40: "CMP_WORK_VALUE", 0x41: "CMP_VALUE_WITH_WORK",
	0x45: "TEST_FLAG", 0x46: "GOTO_IF_IN_PROGRESS", 0x48: "BRANCH_IF_EQUAL",
	0x49: "BRANCH_IF_NOT_EQUAL", 0x4a: "BRANCH_IF_LESS", 0x4b: "BRANCH_IF_GREATER",
	0x4f: "EXECUTE_CALL", 0x50: "MOVE_WORK_TO_FLAG", 0x52: "SET_FLAG_TRUE",
	0x53: "SET_FLAG_FALSE", 0x55: "ADD_1_TO_FLAG", 0x56: "REMOVE_1_FROM_FLAG",
	0x80: "ENABLE_SCENE", 0x81: "DISABLE_SCENE", 0x90: "ACTIVATE_OBJ",
	0x91: "DEACTIVATE_OBJ", 0x92: "IF_TARGET_IN_AREA", 0x93: "IS_TARGET_ALIVE",
	0x94: "INSTANT_DESTROY", 0x95: "DIST_TO_TARGET", 0x97: "DIST_TO_SPOT",
	0x98: "IS_TARGET_ACTIVE", 0xa0: "WAIT_SECONDS", 0xa1: "TAKE_OFF",
	0xa2: "LAND", 0xa5: "FLY_TO_WP", 0xa6: "FLY_TO_AREA", 0xa7: "DESTROY_TARGET",
	0xa8: "DEFEND_TARGET", 0xa9: "DEFEND_AREA", 0xaa: "FOLLOW_ALLY",
	0xab: "SET_MESSAGE", 0xb6: "SHOW_ON_NAV_MAP", 0xb7: "HIDE_FROM_NAV_MAP",
	0xb8: "JOIN_PLAYER_TEAM", 0xb9: "LEAVE_PLAYER_TEAM", 0xbf: "PACIFY",
	0xd0: "SELECT_FLAG_208",
}


func _initialize() -> void:
	await process_frame
	var sc = root.get_node("SCData")
	if not sc.is_mounted():
		sc.auto_mount()
	var failures := 0

	# 1) Instrument quad centres match libRealSpace f16Layout() corners.
	var expected := {
		"raws": Vector3(6.15, -1.915, -1.625),
		"alti": Vector3(5.90, -3.535, 0.460),
		"speed": Vector3(5.90, -3.535, -0.460),
		"mfd_l": Vector3(6.15, -3.450, 2.075),
		"mfd_r": Vector3(6.15, -3.450, -2.075),
		"comm": Vector3(6.10, -1.025, 0.0),
	}
	for key in expected:
		if not Instruments.LAYOUT.has(key):
			print("FAIL missing instrument ", key)
			failures += 1
		elif Instruments.LAYOUT[key].distance_to(expected[key]) > 0.02:
			print("FAIL instrument ", key, " = ", Instruments.LAYOUT[key], " expected ", expected[key])
			failures += 1

	# 2) Mission PROG opcodes from the original missions are ones libRealSpace
	#    implements (we decode the same 2-byte instruction stream).
	var seen := {}
	for mname in ["MISSIONS/MISN-1A.IFF", "MISSIONS/MISN-1B.IFF", "MISSIONS/MISN-3A.IFF",
			"MISSIONS/MISN-10A.IFF", "MISSIONS/MISN-15A.IFF"]:
		if not sc.has(mname):
			continue
		var m = Mission.load_from(sc.read(mname), mname)
		for block in m.blocks:
			for ins in block:
				seen[int(ins[0])] = true
	var unknown: Array = []
	for op in seen:
		if op == 0:
			continue
		if not LRS_OPS.has(op):
			unknown.append(op)
	unknown.sort()
	if not unknown.is_empty():
		print("PROG_INFO opcodes not in libRealSpace enum: ", unknown)
	# Require the core scripted-event opcodes to appear somewhere in the set.
	for must in [0x0f, 0x55, 0x90, 0xa5, 0xa7, 0xab]:
		if not seen.has(must):
			print("FAIL opcode not found in mission scripts: ", must)
			failures += 1

	# 3) Our VM handles libRealSpace's OP_SET_EXIT_CODE (0x0f) for success/failure.
	var vm_src := FileAccess.open("res://scripts/game/mission_vm.gd", FileAccess.READ).get_as_text()
	if not vm_src.contains("0x0f:"):
		print("FAIL mission_vm does not handle OP_SET_EXIT_CODE")
		failures += 1

	print("librealspace_parity_test failures=", failures)
	quit(failures)
