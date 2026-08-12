// Ink-dark pool and soft emanating rings beneath the generic spell-cast aura.
//
// The plane is world-horizontal: the battle camera supplies the apparent
// ellipse. Alpha mixing creates the navy/black anchor additive blending cannot.
// Three independently expanding annuli supply the cyan wavefronts seen from
// above; continuous low-frequency distortion keeps them organic without
// terminating them as pointed spiral fragments.

shader_type spatial;
render_mode unshaded, blend_mix, depth_draw_never, cull_disabled;

uniform vec4 aura_color : source_color = vec4(0.15, 0.75, 1.0, 1.0);
uniform float burst_progress : hint_range(0.0, 1.0) = 0.0;
uniform float seed_value = 0.0;
uniform float outer_radius = 1.16;
uniform float inner_dark_alpha : hint_range(0.0, 1.0) = 0.62;
uniform float ring_alpha : hint_range(0.0, 1.0) = 0.38;
uniform float rim_alpha : hint_range(0.0, 1.0) = 0.52;
uniform float rim_emission_energy : hint_range(0.0, 8.0) = 1.55;
uniform float charge_end : hint_range(0.001, 1.0) = 0.08;
uniform float hold_end : hint_range(0.001, 1.0) = 0.50;
uniform float decay_end : hint_range(0.001, 1.0) = 0.90;

varying vec2 v_local;

float soft_ring(float radius, float target, float width) {
	float distance_from_crest = abs(radius - target) / max(width, 0.001);
	float feather = 1.0 - smoothstep(0.0, 1.0, distance_from_crest);
	return feather * feather * (3.0 - 2.0 * feather);
}

vec3 saturated_tint(vec3 color) {
	float luma = dot(color, vec3(0.299, 0.587, 0.114));
	return clamp(mix(vec3(luma), color, 2.35), vec3(0.0), vec3(1.0));
}

void vertex() {
	v_local = VERTEX.xz;
}

void fragment() {
	vec2 p = v_local / max(outer_radius, 0.001);
	float angle = atan(p.y, p.x);
	float seed_phase = seed_value * 0.071;
	float drift = burst_progress * 0.42;
	float base_radius = length(p);
	float boundary_wobble = (
		sin(angle * 2.0 + seed_phase + drift) * 0.018
		+ sin(angle * 5.0 - seed_phase * 0.7 - drift * 0.55) * 0.008
	);
	float radius = base_radius + boundary_wobble;
	float boundary = 1.0 - smoothstep(0.82, 1.02, radius);

	float inner = 1.0 - smoothstep(0.12, 0.70, radius);
	float travel = smoothstep(0.0, 0.34, burst_progress);

	float wave_radius_1 = base_radius
		+ sin(angle * 2.0 + seed_phase + drift) * 0.024
		+ sin(angle * 4.0 - seed_phase * 0.6) * 0.010;
	float wave_radius_2 = base_radius
		+ sin(angle * 3.0 - seed_phase * 0.8 - drift * 0.7) * 0.030
		+ sin(angle * 6.0 + seed_phase * 0.5) * 0.009;
	float wave_radius_3 = base_radius
		+ sin(angle * 2.0 + seed_phase * 1.2 + drift * 0.5) * 0.036
		+ sin(angle * 5.0 - seed_phase * 0.4) * 0.012;

	float wave_1 = soft_ring(wave_radius_1, mix(0.20, 0.48, travel), 0.140);
	float wave_2 = soft_ring(wave_radius_2, mix(0.34, 0.70, travel), 0.130);
	float wave_3 = soft_ring(wave_radius_3, mix(0.50, 0.91, travel), 0.120);
	float wave_1_appear = smoothstep(0.00, 0.12, burst_progress);
	float wave_2_appear = smoothstep(0.04, 0.20, burst_progress);
	float wave_3_appear = smoothstep(0.08, 0.28, burst_progress);

	// Never drive the circumference to zero: the reference is a cloudy ring,
	// not a collection of tapered brush fragments lying on the ground.
	float variation_1 = 0.65 + 0.35 * (0.5 + 0.5 * sin(angle * 3.0 + seed_phase));
	float variation_2 = 0.68 + 0.32 * (0.5 + 0.5 * sin(angle * 4.0 - seed_phase * 0.7));
	float variation_3 = 0.62 + 0.38 * (0.5 + 0.5 * sin(angle * 3.0 + seed_phase * 1.3));
	float waves = clamp(
		wave_1 * wave_1_appear * variation_1 * 0.50
		+ wave_2 * wave_2_appear * variation_2 * 0.72
		+ wave_3 * wave_3_appear * variation_3,
		0.0,
		1.0
	) * boundary;
	float wave_crest = smoothstep(0.28, 0.90, waves);

	float appear = smoothstep(0.0, max(charge_end, 0.001), burst_progress);
	float fade = 1.0 - smoothstep(hold_end, decay_end, burst_progress);
	float life = appear * fade;
	float dark_field = 1.0 - smoothstep(0.28, 0.90, radius);
	float dark_alpha = boundary * max(inner, dark_field * 0.78) * inner_dark_alpha;

	float wave_alpha = waves * ring_alpha + wave_crest * rim_alpha * 0.55;
	float alpha = clamp((dark_alpha + wave_alpha) * life, 0.0, 0.82);
	if (alpha < 0.003) {
		discard;
	}

	vec3 tint = saturated_tint(aura_color.rgb);
	vec3 ink = vec3(0.004, 0.012, 0.022);
	vec3 deep_tint = mix(ink, tint * 0.16, 0.36);
	vec3 color = mix(deep_tint, tint, clamp(waves * 0.58 + wave_crest * 0.32, 0.0, 0.78));
	ALBEDO = color;
	EMISSION = tint * (waves * 0.42 + wave_crest * 0.58) * rim_emission_energy * life;
	ALPHA = alpha;
}
