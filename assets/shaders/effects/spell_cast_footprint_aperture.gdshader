// Single evolving footprint boundary for the reference-locked cast aura.
//
// One horizontal plane produces the camera-pitched ellipse. The main rim and
// its two close early striations remain one boundary system; there are no
// independently travelling rings. The centre darkening uniform exists only for
// the required terrain A/B and defaults to transparent in battle playback.

shader_type spatial;
render_mode unshaded, blend_mix, depth_draw_never, cull_disabled;

uniform vec4 aura_color : source_color = vec4(0.05, 0.42, 0.75, 1.0);
uniform float burst_progress : hint_range(0.0, 1.0) = 0.0;
uniform float seed_value = 0.0;
uniform float outer_radius = 1.16;
uniform float aperture_radius_start = 0.43;
uniform float aperture_radius_trough = 0.39;
uniform float aperture_radius_end = 0.53;
uniform float rim_width = 0.105;
uniform float rim_alpha : hint_range(0.0, 1.0) = 0.34;
uniform float striation_alpha : hint_range(0.0, 1.0) = 0.22;
uniform float rim_emission_energy : hint_range(0.0, 8.0) = 0.82;
uniform float center_darkening : hint_range(0.0, 1.0) = 0.0;
uniform float charge_end : hint_range(0.001, 1.0) = 0.08;
uniform float decay_end : hint_range(0.001, 1.0) = 0.90;

varying vec2 v_local;

float soft_ring(float radius, float target, float width) {
	float distance_from_crest = abs(radius - target) / max(width, 0.001);
	float feather = 1.0 - smoothstep(0.0, 1.0, distance_from_crest);
	return feather * feather * (3.0 - 2.0 * feather);
}

vec3 saturated_tint(vec3 color) {
	float luma = dot(color, vec3(0.299, 0.587, 0.114));
	return clamp(mix(vec3(luma), color, 2.15), vec3(0.0), vec3(1.0));
}

void vertex() {
	v_local = VERTEX.xz;
}

void fragment() {
	vec2 p = v_local / max(outer_radius, 0.001);
	float angle = atan(p.y, p.x);
	float seed_phase = seed_value * 0.071;
	float state = clamp(
		(burst_progress - charge_end) / max(decay_end - charge_end, 0.001),
		0.0,
		1.0
	);
	float first_half = smoothstep(0.0, 0.56, state);
	float second_half = smoothstep(0.56, 1.0, state);
	float aperture_radius = mix(aperture_radius_start, aperture_radius_trough, first_half);
	aperture_radius = mix(aperture_radius, aperture_radius_end, second_half);

	float wobble = (
		sin(angle * 2.0 + seed_phase + state * 0.75) * 0.018
		+ sin(angle * 5.0 - seed_phase * 0.6 - state * 0.40) * 0.007
	);
	float radius = length(p) + wobble;
	float rim = soft_ring(radius, aperture_radius, rim_width);

	// These strokes remain inside the main boundary's feathered width. They
	// read as packed rim texture early and disappear as the opening simplifies.
	float striation_life = 1.0 - smoothstep(0.36, 0.76, state);
	float inner_striation = soft_ring(
		radius,
		aperture_radius - rim_width * 0.46,
		rim_width * 0.30
	);
	float outer_striation = soft_ring(
		radius,
		aperture_radius + rim_width * 0.52,
		rim_width * 0.27
	);
	float angular_cloud = 0.68 + 0.32 * (
		0.5 + 0.5 * sin(angle * 3.0 + seed_phase + state * 0.9)
	);
	float striations = max(inner_striation * 0.84, outer_striation * 0.62);
	striations *= striation_life * angular_cloud;

	float appear = smoothstep(0.0, max(charge_end, 0.001), burst_progress);
	float fade = 1.0 - smoothstep(0.72, decay_end, burst_progress);
	float life = appear * fade;
	float aperture_fill = 1.0 - smoothstep(
		aperture_radius - rim_width * 0.65,
		aperture_radius + rim_width * 0.28,
		radius
	);
	float mixed_alpha = (
		rim * rim_alpha
		+ striations * striation_alpha
		+ aperture_fill * center_darkening
	) * life;
	if (mixed_alpha < 0.0025) {
		discard;
	}

	vec3 tint = saturated_tint(aura_color.rgb);
	vec3 ink = vec3(0.004, 0.012, 0.022);
	float light_mask = clamp(rim + striations * 0.72, 0.0, 1.0);
	vec3 color = mix(ink, tint, light_mask * 0.82);
	ALBEDO = color;
	EMISSION = tint * light_mask * rim_emission_energy * life;
	ALPHA = clamp(mixed_alpha, 0.0, 0.78);
}
