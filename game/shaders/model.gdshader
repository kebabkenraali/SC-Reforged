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
uniform int kind = 0;   // 0 paint, 1 canopy, 2 exhaust metal, 3 propeller (RealSpaceModel.surface_kind)
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
		if (kind == 1) {
			// Canopy: the original glass texels are mid greys (a dark-texel
			// test found none), so the whole canopy texture is glass - the
			// frames are thin. Darkened and blue-tinted so the sky reflection
			// reads as glass, smooth and strongly reflective.
			ALBEDO = base * vec3(0.55, 0.6, 0.7);
			ROUGHNESS = 0.08;
			METALLIC = 0.0;
			SPECULAR = 0.8;
			CLEARCOAT = 1.0;
			CLEARCOAT_ROUGHNESS = 0.04;
			RIM = 0.2;
			RIM_TINT = 0.6;
		} else if (kind == 2) {
			// Exhaust nozzle: bare, heat-darkened metal.
			ALBEDO = base * mix(0.85, 1.0, n2);
			ROUGHNESS = mix(0.3, 0.5, wear);
			METALLIC = 0.85;
		} else if (kind == 3) {
			ALBEDO = base;
			ROUGHNESS = 0.45;
			METALLIC = 0.6;
		} else {
			base *= mix(0.9, 1.04, wear);
			// Panels: each 1.6 m cell is a slightly different shade (separately
			// painted panels), with faint seams between them.
			float cell = hash(floor(obj_pos / 1.6) + 7.0);
			base *= mix(0.965, 1.03, cell);
			base *= 1.0 - 0.07 * panel_lines(obj_pos, obj_nrm);
			ALBEDO = base;
			// Satin military paint, rougher where worn. Kept matte enough that the
			// smoothed normals do not focus the sun into a white hot spot
			// (seen on the MiG-29 flank with roughness 0.32 + clearcoat 0.25).
			ROUGHNESS = mix(0.45, 0.7, wear) + (cell - 0.5) * 0.08;
			METALLIC = 0.05;
			SPECULAR = 0.45;
			CLEARCOAT = 0.1;
			CLEARCOAT_ROUGHNESS = 0.5;
		}
	} else {
		ALBEDO = base;
		ROUGHNESS = 0.5;
		METALLIC = 0.15;
	}
}
