shader_type spatial;
render_mode unshaded, blend_add, cull_disabled;

uniform vec4 base_color : source_color = vec4(0.0, 0.8, 1.0, 0.5);
uniform float scanline_speed : hint_range(0.0, 10.0) = 2.0;
uniform float scanline_density : hint_range(1.0, 100.0) = 40.0;
uniform float glitch_intensity : hint_range(0.0, 1.0) = 0.05;

void vertex() {
	// Slight jitter glitch based on time
	float glitch = sin(TIME * 50.0 + VERTEX.y * 10.0) * glitch_intensity;
	if (mod(TIME, 3.0) < 0.2) {
		VERTEX.x += glitch;
	}
}

void fragment() {
	float scanline = sin(SCREEN_UV.y * scanline_density - TIME * scanline_speed);
	scanline = (scanline + 1.0) * 0.5; // normalize to 0-1
	
	// Edge glow (Fresnel-ish but unshaded)
	float rim = 1.0 - dot(normalize(VIEW), NORMAL);
	rim = smoothstep(0.4, 1.0, rim);
	
	vec4 col = base_color;
	col.a *= (0.5 + 0.5 * scanline) + rim;
	
	ALBEDO = col.rgb * (1.0 + rim * 2.0);
	ALPHA = col.a;
}
