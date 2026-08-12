// Soft world-space core of the generic spell-cast aura.
//
// Six radial cards share this material. No camera matrices are read or
// replaced: the volume stays planted around world up while camera yaw changes
// which cards are seen. Each card remains faint; their alpha-mixed overlap
// builds the central cyan body without becoming a screen-facing wall.

shader_type spatial;
render_mode unshaded, blend_mix, depth_draw_never, cull_disabled;

uniform vec4 aura_color : source_color = vec4(0.15, 0.75, 1.0, 1.0);
uniform sampler2D puff_tex : filter_linear;
uniform float burst_progress : hint_range(0.0, 1.0) = 0.0;
uniform float seed_value = 0.0;
uniform float peak_alpha : hint_range(0.0, 1.0) = 0.17;
uniform float white_mix : hint_range(0.0, 1.0) = 0.0;
uniform float emission_energy : hint_range(0.0, 8.0) = 0.9;
uniform float noise_scale = 8.0;
uniform float turbulence : hint_range(0.0, 1.0) = 0.38;
uniform float eruption_start : hint_range(0.0, 1.0) = 0.03;
uniform float eruption_end : hint_range(0.001, 1.0) = 0.30;
uniform float hold_end : hint_range(0.001, 1.0) = 0.50;
uniform float decay_end : hint_range(0.001, 1.0) = 0.90;

varying float v_life;
varying float v_phase;

vec3 saturated_tint(vec3 color) {
	float luma = dot(color, vec3(0.299, 0.587, 0.114));
	return clamp(mix(vec3(luma), color, 2.35), vec3(0.0), vec3(1.0));
}

void vertex() {
	float grow = smoothstep(eruption_start, eruption_end, burst_progress);
	grow = 1.0 - pow(1.0 - grow, 3.0);
	float fade = 1.0 - smoothstep(hold_end, decay_end, burst_progress);
	v_life = grow * fade * INSTANCE_CUSTOM.y;
	v_phase = INSTANCE_CUSTOM.x * 6.2831853 + seed_value * 0.113;

	// Unit cards are transformed to authored world dimensions by the MultiMesh.
	// This local edit keeps every card's bottom fixed at the vortex while it grows.
	VERTEX.y = (VERTEX.y + 0.5) * grow - 0.5;
	VERTEX.x *= mix(0.26, 1.0, grow);
}

void fragment() {
	float y = 1.0 - UV.y;
	float x = UV.x * 2.0 - 1.0;
	float sampled = texture(puff_tex, UV).a;
	float flow = 0.5 + 0.5 * sin(
		y * noise_scale + sin(x * 5.2 + v_phase) * 1.25 - burst_progress * 8.0
	);
	float cross_flow = 0.5 + 0.5 * sin(x * noise_scale * 0.74 - y * 4.8 + v_phase * 1.7);
	float breakup = mix(1.0, 0.72 + 0.28 * flow * cross_flow, turbulence);
	float lower_weight = mix(1.08, 0.60, smoothstep(0.10, 0.92, y));
	float mask = sampled * breakup * lower_weight;
	float alpha = mask * peak_alpha * v_life;
	if (alpha < 0.002) {
		discard;
	}

	vec3 tint = saturated_tint(aura_color.rgb);
	vec3 color = mix(tint, vec3(1.0), white_mix * sampled);
	ALBEDO = color;
	EMISSION = color * emission_energy * mask;
	ALPHA = alpha;
}
