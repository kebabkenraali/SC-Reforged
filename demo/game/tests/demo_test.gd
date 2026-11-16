## Demo mode: the campaign stops with the end screen after the first mission.
## Run: Godot --headless --path game --script res://tests/demo_test.gd -- --demo
extends SceneTree

var failures := 0


class FakeHost:
	var flights := []
	var ended := false

	func play_conversation(_n: int) -> void:
		pass

	func play_cutscene(_n: int) -> void:
		pass

	func play_story(_n: int) -> void:
		pass

	func play_transport(_n: int) -> void:
		pass

	func fly_mission(n: int) -> bool:
		flights.append(n)
		return true

	func end_demo() -> void:
		ended = true


func _initialize() -> void:
	await process_frame
	var sc = root.get_node("SCData")
	if not sc.is_mounted():
		sc.auto_mount()
	var Demo = load("res://scripts/core/demo.gd")
	_check("demo mode on (--demo)", Demo.enabled())
	var Campaign = load("res://scripts/game/campaign.gd")
	_check("demo uses its own save", Campaign.save_path == "user://demo_campaign.json", Campaign.save_path)
	Campaign.save_path = "user://demo_test.json"
	var c = Campaign.new()
	var host := FakeHost.new()
	c.host = host
	await c.start_new()
	var fly = null
	for sid in c.current_stage().scenes:
		for s in c.current_stage().scenes[sid]:
			for e in s.effects:
				if e[0] == 0x0c:
					fly = s
	_check("first mission hotspot found", fly != null)
	if fly != null:
		await c.activate(fly)
	_check("flies MISN-1A", host.flights == [0], str(host.flights))
	_check("end screen after the first mission", host.ended)
	_check("campaign stays on stage 0", c.stage == 0, str(c.stage))
	DirAccess.remove_absolute(ProjectSettings.globalize_path("user://demo_test.json"))
	print("demo_test failures=%d" % failures)
	quit(failures)


func _check(name: String, ok: bool, detail := "") -> void:
	print("%s %s %s" % ["PASS" if ok else "FAIL", name, detail])
	if not ok:
		failures += 1
