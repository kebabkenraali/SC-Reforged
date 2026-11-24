shader_type spatial;
render_mode unshaded, blend_mix, depth_draw_never, cull_disabled, fog_disabled, shadows_disabled;

uniform sampler2D noise_tex : source_color, filter_linear_mipmap, repeat_enable;
uniform float coverage : hint_range(0.0, 1.0) = 0.42;
uniform float alpha : hint_range(0.0, 1.0) = 0.5;
uniform float scale = 0.00006;
uniform float drift = 4.0;
uniform float fade_start = 55000.0;
uniform float fade_end = 70000.0;

varying vec3 v_world_pos;

void vertex() {
	// VERTEX in the fragment stage is view-space: using it makes the cloud
	// texture slide when the head (or mouse look) turns. Bake world position.
	v_world_pos = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
}

void fragment() {
	vec2 wp = v_world_pos.xz * scale + vec2(TIME * drift * 0.001, TIME * drift * 0.0004);
	float n = texture(noise_tex, wp).r;
	n = max(n, texture(noise_tex, wp * 2.7 - vec2(TIME * drift * 0.0007, 0.0)).r * 0.75);
	float a = smoothstep(coverage, coverage + 0.25, n) * alpha;
	a *= 1.0 - smoothstep(fade_start, fade_end, length(v_world_pos.xz));
	ALBEDO = vec3(1.05, 1.04, 1.02);
	ALPHA = clamp(a, 0.0, 1.0);
}