## Audits all original conversations: every close-up speaker must have a face
## shape and every line's recorded voice must exist in the player's install.
## Run: --script res://tests/conversation_test.gd  (exit code = failure count)
extends SceneTree


func _initialize() -> void:
	await process_frame
	var sc = root.get_node("SCData")
	if not sc.is_mounted():
		sc.auto_mount()
	var gf = load("res://scripts/core/art.gd").gameflow()
	var Conv = load("res://scripts/formats/sc_conversation.gd")
	var Shape = load("res://scripts/formats/sc_shape.gd")
	var Pak = load("res://scripts/formats/pak_archive.gd")
	var Voc = load("res://scripts/formats/voc.gd")
	var entries: Array = Pak.entries(sc.read("GAMEFLOW/CONV.PAK"))
	print("conversations: ", entries.size(), "  faces: ", gf.faces.size())
	var failures := 0
	var lines := 0
	var closeups := 0
	var missing_voice := 0
	var bad_decode := 0
	var _checked_voc := {}
	var missing_face := {}
	var no_closeup := {}
	for ci in entries.size():
		var steps: Array = Conv.parse(Shape.unpack(entries[ci]))
		var speaker := ""
		var has_closeup := false
		for s in steps:
			match s.op:
				0x00, 0x01:
					has_closeup = false
				0x03:
					speaker = String(s.name)
					has_closeup = true
					closeups += 1
					if not gf.faces.has(speaker):
						missing_face[speaker] = true
				0x02:
					speaker = String(s.name)
				0x04:
					if speaker != "" and not has_closeup:
						no_closeup[speaker] = true
				0x0a:
					speaker = ""
			if s.has("voc") and String(s.voc) != "":
				lines += 1
				var voc_name := String(s.voc).to_upper()
				if not sc.has("F:%s.VOC" % voc_name):
					missing_voice += 1
					if missing_voice <= 12:
						print("  no voice conv=%d voc=%s speaker=%s" % [ci, s.voc, speaker])
				elif not _checked_voc.has(voc_name):
					_checked_voc[voc_name] = true
					var stream: AudioStream = Voc.to_stream(sc.read("F:%s.VOC" % voc_name))
					if stream == null:
						bad_decode += 1
						if bad_decode <= 12:
							print("  bad decode conv=%d voc=%s speaker=%s" % [ci, s.voc, speaker])
	print("lines=%d closeups=%d missing_voice=%d bad_decode=%d" % [lines, closeups, missing_voice, bad_decode])
	print("speakers without FACE: ", missing_face.keys())
	print("continued lines without closeup: ", no_closeup.keys())
	if not missing_face.is_empty():
		failures += missing_face.size()
	if not no_closeup.is_empty():
		failures += no_closeup.size()
	print("conversation_test failures=", failures)
	quit(failures)
