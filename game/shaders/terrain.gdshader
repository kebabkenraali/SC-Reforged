// Terrain: original type colours + original 64x64 transition tiles, with
// modern lighting, procedural micro detail and reflective water.
shader_type spatial;
render_mode cull_disabled;

uniform sampler2DArray tiles : source_color, filter_linear_mipmap_anisotropic, repeat_disable;
uniform sampler2D detail : filter_linear_mipmap, repeat_enable;
uniform float detail_scale = 0.012;
uniform bool pixel_tiles = false;
uniform sampler2DArray tiles_nearest : source_color, filter_nearest_mipmap, repeat_disable;

varying flat float tile;
varying vec3 world_pos;

void vertex() {
	tile = UV2.x;
	world_pos = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
}

void fragment() {
	vec3 base = COLOR.rgb;
	float water = COLOR.a;
	float n1 = texture(detail, world_pos.xz * detail_scale).r;
	float n2 = texture(detail, world_pos.xz * detail_scale * 7.3).r;
	base *= mix(0.82, 1.12, n1) * mix(0.92, 1.06, n2);
	if (tile < 254.5) {
		vec2 uv = clamp(UV, vec2(0.004), vec2(0.996));
		vec4 t = pixel_tiles ? texture(tiles_nearest, vec3(uv, tile)) : texture(tiles, vec3(uv, tile));
		base = mix(base, t.rgb * mix(0.9, 1.08, n2), t.a);
		water *= 1.0 - t.a;
	}
	ALBEDO = base;
	ROUGHNESS = mix(0.93, 0.06, water);
	METALLIC = 0.0;
	SPECULAR = mix(0.3, 0.6, water);
}
