// RealSpace object surfaces: transparent texels show the triangle's own
// palette colour (as in the original renderer) instead of cutting holes.
shader_type spatial;
render_mode cull_disabled;

uniform bool textured = false;
uniform bool pixelated = false;
uniform sampler2D albedo_tex : source_color, filter_linear_mipmap_anisotropic, repeat_disable;
uniform sampler2D albedo_tex_px : source_color, filter_nearest, repeat_disable;

void fragment() {
	vec3 base = COLOR.rgb;
	if (textured) {
		vec4 t = pixelated ? texture(albedo_tex_px, UV) : texture(albedo_tex, UV);
		base = mix(base, t.rgb, t.a);
	}
	ALBEDO = base;
	ROUGHNESS = 0.5;
	METALLIC = 0.15;
}
