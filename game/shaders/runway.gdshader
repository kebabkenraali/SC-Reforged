// Procedural runway for RealSpace RNWY objects (the original game draws them
// from extents only): asphalt, edge lines, centre-line dashes, threshold bars.
// UV.x runs across the runway, UV.y along it; `length_m` / `width_m` in metres.
shader_type spatial;

uniform float length_m = 700.0;
uniform float width_m = 22.0;

float hash(vec2 p) {
	return fract(sin(dot(p, vec2(127.1, 311.7))) * 43758.5453);
}

void fragment() {
	vec2 m = UV * vec2(width_m, length_m);          // metres across / along
	float grain = hash(floor(m * 10.0)) * 0.02;
	vec3 col = vec3(0.055, 0.055, 0.06) + grain;
	float paint = 0.0;
	// Edge lines
	paint += step(m.x, 0.9) + step(width_m - 0.9, m.x);
	// Centre-line dashes: 30 m painted, 20 m gap
	float centre = step(abs(m.x - width_m * 0.5), 0.45);
	paint += centre * step(mod(m.y, 50.0), 30.0) * step(60.0, m.y) * step(m.y, length_m - 60.0);
	// Threshold bars at both ends
	float ends = step(m.y, 40.0) + step(length_m - 40.0, m.y);
	float bars = step(0.5, fract(m.x / 3.0)) * step(2.5, m.x) * step(m.x, width_m - 2.5);
	paint += ends * step(8.0, min(m.y, length_m - m.y)) * bars;
	col = mix(col, vec3(0.85), clamp(paint, 0.0, 1.0));
	ALBEDO = col;
	ROUGHNESS = mix(0.85, 0.6, clamp(paint, 0.0, 1.0));
}
