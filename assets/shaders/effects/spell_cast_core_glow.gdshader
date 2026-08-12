// Soft upward-tapered body of the generic spell-cast aura.
//
// A bottom-anchored camera-facing quad carries a procedural teardrop mask. Two
// deterministic sine bands break the gradient into mist without using TIME or
// changing a shared texture.

shader_type spatial;
render_mode unshaded, blend_add, depth_draw_never, cull_disabled;

uniform vec4 aura_color : source_color = vec4(0.15, 0.75, 1.0, 1.0);
uniform float burst_progress : hint_range(0.0, 1.0) = 0.0;
uniform float seed_value = 0.0;
uniform float quad_height = 2.85;
uniform float peak_alpha : hint_range(0.0, 1.0) = 0.30;
uniform float white_mix : hint_range(0.0, 1.0) = 0.18;
uniform float emission_energy : hint_range(0.0, 8.0) = 1.45;
uniform float noise_scale = 8.0;
uniform float turbulence : hint_range(0.0, 1.0) = 0.22;
uniform float eruption_start : hint_range(0.0, 1.0) = 0.03;
uniform float eruption_end : hint_range(0.001, 1.0) = 0.30;
uniform float hold_end : hint_range(0.001, 1.0) = 0.50;
uniform float decay_end : hint_range(0.001, 1.0) = 0.90;

varying float v_life;

vec3 saturated_tint(vec3 color) {
	float luma = dot(color, vec3(0.299, 0.587, 0.114));
	return clamp(mix(vec3(luma), color, 2.35), vec3(0.0), vec3(1.0));
}

void vertex() {
	float grow = smoothstep(eruption_start, eruption_end, burst_progress);
	grow = 1.0 - pow(1.0 - grow, 3.0);
	float fade = 1.0 - smoothstep(hold_end, decay_end, burst_progress);
	v_life = grow * fade;

	// Grow from the seat rather than scaling around the quad's centre.
	VERTEX.y = (VERTEX.y + quad_height * 0.5) * grow - quad_height * 0.5;
	VERTEX.x *= mix(0.22, 1.0, grow);
	vec4 billboard_origin = MODEL_MATRIX[3];
	billboard_origin.xyz -= INV_VIEW_MATRIX[2].xyz * 0.10;
	MODELVIEW_MATRIX = VIEW_MATRIX * mat4(
		INV_VIEW_MATRIX[0],
		INV_VIEW_MATRIX[1],
		INV_VIEW_MATRIX[2],
		billboard_origin
	);
	MODELVIEW_NORMAL_MATRIX = mat3(MODELVIEW_MATRIX);
}

void fragment() {
	float y = 1.0 - UV.y;
	float x = UV.x * 2.0 - 1.0;
	float taper = mix(0.92, 0.20, smoothstep(0.08, 0.98, y));
	float side = abs(x) / max(taper, 0.001);
	float silhouette = 1.0 - smoothstep(0.20, 1.08, side);
	float vertical = smoothstep(0.0, 0.07, y) * (1.0 - smoothstep(0.72, 1.0, y));
	float seed_phase = seed_value * 0.113;
	float flow = 0.5 + 0.5 * sin(
		y * noise_scale
		+ sin(x * 5.2 + seed_phase) * 1.25
		- burst_progress * 8.0
	);
	float cross_flow = 0.5 + 0.5 * sin(
		x * noise_scale * 0.74 - y * 4.8 + seed_phase * 1.7
	);
	float breakup = mix(1.0, 0.58 + 0.42 * flow * cross_flow, turbulence);
	float lower_core = 1.0 - smoothstep(0.0, 0.72, length(vec2(x * 0.72, (y - 0.23) * 1.35)));
	float mask = clamp(silhouette * vertical * breakup + lower_core * 0.30, 0.0, 1.0);
	float alpha = mask * peak_alpha * v_life;
	if (alpha < 0.002) {
		discard;
	}

	vec3 tint = saturated_tint(aura_color.rgb);
	vec3 color = mix(tint, vec3(1.0), white_mix * lower_core);
	ALBEDO = color;
	EMISSION = color * emission_energy * mask;
	ALPHA = alpha;
}
