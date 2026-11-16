shader_type sky;

uniform vec4 top_color : source_color = vec4(0.16, 0.38, 0.72, 1.0);
uniform vec4 horizon_color : source_color = vec4(0.74, 0.79, 0.86, 1.0);
uniform vec4 ground_color : source_color = vec4(0.30, 0.27, 0.22, 1.0);
uniform float sun_glow : hint_range(0.0, 128.0) = 12.0;
uniform float haze : hint_range(0.0, 1.0) = 0.25;

void sky() {
	float h = EYEDIR.y;
	vec3 col;
	if (h < 0.0) {
		col = mix(horizon_color.rgb, ground_color.rgb, clamp(-h * 7.0, 0.0, 1.0));
	} else {
		col = mix(horizon_color.rgb, top_color.rgb, pow(clamp(h, 0.0, 1.0), 0.55));
	}
	// Sun glow and disc from the scene directional light.
	float sd = dot(EYEDIR, LIGHT0_DIRECTION);
	if (LIGHT0_ENABLED) {
		col += LIGHT0_COLOR.rgb * pow(max(sd, 0.0), sun_glow) * 0.45;
		if (sd > 0.99965) {
			col = vec3(1.0, 0.97, 0.90);
		}
	}
	COLOR = col;
}