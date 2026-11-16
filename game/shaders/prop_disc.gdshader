// Spinning propeller (enhanced look): the original PROP board is a square
// noise texture drawn opaque. Shown here as a round, see-through blur disc
// with a faint tip ring; the texture only adds a little streak variation.
shader_type spatial;
render_mode unshaded, cull_disabled, blend_mix, depth_draw_never, shadows_disabled;

uniform sampler2D prop_tex : source_color, filter_linear_mipmap, repeat_disable;

void fragment() {
	vec2 c = UV * 2.0 - 1.0;
	float r = length(c);
	float disc = 1.0 - smoothstep(0.86, 0.98, r);
	float ring = smoothstep(0.78, 0.86, r) * (1.0 - smoothstep(0.88, 0.96, r));
	float tone = dot(texture(prop_tex, UV).rgb, vec3(0.333));
	ALBEDO = vec3(0.10) + vec3(0.18) * tone;
	ALPHA = disc * (0.10 + 0.08 * (1.0 - r)) + ring * 0.10;
}
