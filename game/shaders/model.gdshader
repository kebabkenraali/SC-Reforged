// RealSpace object surfaces: transparent texels show the triangle's own
// palette colour (as in the original renderer) instead of cutting holes.
//
// enhanced (settings: Smooth textures on): the original skin with a painted-
// metal finish and a subtle, model-space panel and wear detail, so the large
// flat-coloured surfaces (wings, fins) are no longer plain plastic. Off shows
// the original pixels with the plain lighting, exactly as before.
shader_type spatial;
render_mode cull_disabled;

uniform bool textured = false;
uniform bool pixelated = false;
uniform bool enhanced = false;
uniform sampler2D albedo_tex : source_color, filter_linear_mipmap_anisotropic, repeat_disable;
uniform sampler2D albedo_tex_px : source_color, filter_nearest, repeat_disable;

varying vec3 obj_pos;
varying vec3 obj_nrm;

void vertex() {
	obj_pos = VERTEX;
	obj_nrm = NORMAL;
}

float hash(vec3 p) {
	p = fract(p * 0.3183099 + 0.1);
	p *= 17.0;
	return fract(p.x * p.y * p.z * (p.x + p.y + p.z));
}

float noise(vec3 x) {
	vec3 i = floor(x);
	vec3 f = fract(x);
	f = f * f * (3.0 - 2.0 * f);
	return mix(mix(mix(hash(i), hash(i + vec3(1, 0, 0)), f.x),
				mix(hash(i + vec3(0, 1, 0)), hash(i + vec3(1, 1, 0)), f.x), f.y),
			mix(mix(hash(i + vec3(0, 0, 1)), hash(i + vec3(1, 0, 1)), f.x),
				mix(hash(i + vec3(0, 1, 1)), hash(i + vec3(1, 1, 1)), f.x), f.y), f.z);
}

// Thin lines on a 1.6 m grid in the two axes that lie in the surface: a hint
// of panel seams. Fades with distance (fwidth) so it never shimmers.
float panel_lines(vec3 p, vec3 n) {
	vec3 g = abs(fract(p / 1.6 + 0.5) - 0.5) * 1.6;
	vec3 w = fwidth(p) * 1.2 + 0.012;
	vec3 l = 1.0 - smoothstep(vec3(0.0), w, g);
	vec3 an = abs(normalize(n));
	// ignore the axis along the normal (lines would smear across the face)
	l *= 1.0 - smoothstep(0.55, 0.85, an);
	float fade = 1.0 - smoothstep(0.08, 0.35, length(fwidth(p)));
	return max(max(l.x, l.y), l.z) * fade;
}

void fragment() {
	vec3 base = COLOR.rgb;
	if (textured) {
		vec4 t = pixelated ? texture(albedo_tex_px, UV) : texture(albedo_tex, UV);
		base = mix(base, t.rgb, t.a);
	}
	if (enhanced) {
		// Large-scale paint variation and grime (a few percent only).
		float n1 = noise(obj_pos * 0.45);
		float n2 = noise(obj_pos * 2.3);
		float wear = n1 * 0.65 + n2 * 0.35;
		base *= mix(0.9, 1.04, wear);
		// Panel seams.
		base *= 1.0 - 0.11 * panel_lines(obj_pos, obj_nrm);
		ALBEDO = base;
		ROUGHNESS = mix(0.32, 0.6, wear);   // satin paint, rougher where worn
		METALLIC = 0.05;
		SPECULAR = 0.55;
		CLEARCOAT = 0.25;
		CLEARCOAT_ROUGHNESS = 0.35;
	} else {
		ALBEDO = base;
		ROUGHNESS = 0.5;
		METALLIC = 0.15;
	}
}
