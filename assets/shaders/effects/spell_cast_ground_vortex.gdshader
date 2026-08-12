// Irregular ink-dark whirlpool beneath the generic spell-cast aura.
//
// The plane is world-horizontal: the battle camera supplies the apparent
// ellipse. Alpha mixing creates the navy/black anchor additive blending cannot;
// sparse element-tinted rims and spiral brush marks remain emissive accents.

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

float ring_mask(float radius, float target, float width) {
	return 1.0 - smoothstep(width * 0.45, width, abs(radius - target));
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
	float spin = burst_progress * 1.35;
	float wobble = (
		sin(angle * 3.0 + seed_phase + spin) * 0.030
		+ sin(angle * 7.0 - seed_phase * 0.7 - spin * 0.55) * 0.017
	);
	float radius = length(p) + wobble;
	float boundary = 1.0 - smoothstep(0.82, 1.02, radius);

	float brush_noise = 0.5 + 0.5 * sin(
		angle * 5.0 - radius * 18.0 + seed_phase * 1.9 + spin * 1.4
	);
	float angular_break = smoothstep(0.20, 0.72, brush_noise);
	float inner = 1.0 - smoothstep(0.12, 0.70, radius);
	float middle_ring = ring_mask(radius, 0.58 + wobble * 0.7, 0.10);
	float outer_ring = ring_mask(radius, 0.82 - wobble * 0.5, 0.085);
	float spiral = ring_mask(
		radius,
		0.34 + fract((angle + spin + seed_phase) / 6.2831853) * 0.48,
		0.055
	) * angular_break;

	float appear = smoothstep(0.0, max(charge_end, 0.001), burst_progress);
	float fade = 1.0 - smoothstep(hold_end, decay_end, burst_progress);
	float life = appear * fade;
	float dark_field = 1.0 - smoothstep(0.28, 0.90, radius);
	float dark_alpha = boundary * (
		max(inner, dark_field * 0.78) * inner_dark_alpha
		+ middle_ring * ring_alpha * 0.72
		+ spiral * ring_alpha * 0.62
	);

	float rim = boundary * angular_break * max(outer_ring, spiral * 0.60);
	float alpha = clamp((dark_alpha + rim * rim_alpha) * life, 0.0, 0.82);
	if (alpha < 0.003) {
		discard;
	}

	vec3 tint = saturated_tint(aura_color.rgb);
	vec3 ink = vec3(0.004, 0.012, 0.022);
	vec3 deep_tint = mix(ink, tint * 0.16, 0.36);
	vec3 color = mix(deep_tint, tint, rim * 0.68);
	ALBEDO = color;
	EMISSION = tint * rim * rim_emission_energy * life;
	ALPHA = alpha;
}
