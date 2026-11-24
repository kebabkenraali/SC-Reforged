## Cloud regression: the cloud pattern must be sampled in WORLD space. Godot's
## `VERTEX` inside fragment() is view-space, which makes clouds slide along
## with head/mouse look — especially visible in VR.
extends SceneTree


func _initialize() -> void:
	var failures := 0
	var f := FileAccess.open("res://shaders/clouds.gdshader", FileAccess.READ)
	if f == null:
		print("FAIL clouds.gdshader not readable")
		quit(1)
		return
	var src: String = f.get_as_text()
	f.close()

	if not src.contains("varying vec3 v_world_pos;"):
		print("FAIL cloud shader has no world-position varying")
		failures += 1
	if not src.contains("v_world_pos = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;"):
		print("FAIL cloud vertex stage does not bake world position")
		failures += 1
	var parts := src.split("void fragment()")
	if parts.size() < 2:
		print("FAIL cloud shader has no fragment stage")
		failures += 1
	else:
		var frag: String = parts[1]
		if frag.contains("VERTEX"):
			print("FAIL cloud fragment still uses view-space VERTEX")
			failures += 1
		if not frag.contains("v_world_pos.xz"):
			print("FAIL cloud fragment does not sample world position")
			failures += 1

	print("shader_test failures=", failures)
	quit(failures)
