// Sparse additive far-side rays for the reference aura.
//
// The alpha-mixed haze owns the continuous mass. This material adds only
// narrow analytic high-energy streaks on the far-side shell, preventing a
// visible cup or shoulder wings at arbitrary camera yaw.

shader_type spatial;
render_mode unshaded, blend_add, depth_draw_never, cull_front;

uniform sampler2D plume_atlas : source_color, filter_linear, repeat_disable;
uniform vec2 atlas_pixel_size = vec2(2816.0, 256.0);
uniform vec4 aura_color : source_color = vec4(0.05, 0.42, 0.75, 1.0);
uniform float seed_value = 0.0;
uniform float uv_phase = 0.0;
uniform float shell_opacity = 0.28;
uniform float emission_energy = 0.92;
uniform float state_crossfade = 0.0;
uniform float atlas_state_position = 0.0;
uniform float plume_energy = 1.0;
uniform float root_ignition = 0.0;
uniform float reveal_front = 0.0;
uniform float reveal_softness = 0.08;
uniform float lifecycle_visibility = 1.0;
uniform float spin_turns = 0.18;
uniform float tip_oscillation_cycles = 1.15;
uniform float tip_oscillation_amplitude = 0.105;
uniform float tip_phase_step = 1.731;
uniform int prototype_variant = 0;

const float FRAME_COUNT = 11.0;
const float TAU_VALUE = 6.28318530718;

varying vec3 local_position;

void vertex() {
	local_position = VERTEX;
}

float wrapped_distance(float first, float second) {
	return abs(fract(first - second + 0.5) - 0.5);
}

float analytic_ray_field(float angular_uv, float height, float motion, float seed_hash) {
	float field = 0.0;
	// Twenty-four deterministic angular seeds produce roughly twelve visible
	// far-side streaks, matching the measured source fan without magnifying a
	// raster mask.
	// All shaping is evaluated per fragment, so a leaning edge stays continuous
	// across the profiled carrier's height bands.
	float accumulation = 0.0;
	for (int group = 0; group < 24; group++) {
		float group_value = float(group);
		float phase = group_value * tip_phase_step + seed_hash * TAU_VALUE;
		float direction = mod(group_value, 2.0) < 1.0 ? 1.0 : -1.0;
		float center = group_value / 24.0;
		float lean_motion = sin(phase * 0.71 + motion * TAU_VALUE * 0.72);
		float lean = direction * (0.015 + 0.009 * lean_motion);
		float bent_center = center + lean * pow(height, 1.35);
		float base_width = 0.0080 + mod(group_value, 4.0) * 0.0014;
		float width = base_width * (1.32 - 0.52 * height);
		float distance = wrapped_distance(angular_uv, bent_center);
		float lateral = exp(-0.5 * pow(distance / max(width, 0.001), 2.0));
		float resting_height = 0.67 + 0.055 * sin(phase * 0.83);
		float tip_motion = sin(
			motion * TAU_VALUE * tip_oscillation_cycles + phase
		);
		float spike_height = clamp(
			resting_height + tip_oscillation_amplitude * tip_motion, 0.47, 0.87
		);
		float local_distance = distance / max(width, 0.001);
		float local_height = spike_height - pow(clamp(local_distance, 0.0, 2.0), 1.25) * 0.14;
		float tip = 1.0 - smoothstep(local_height - 0.22, local_height, height);
		float root = smoothstep(0.045 + mod(group_value, 2.0) * 0.018, 0.17, height);
		float amplitude = 0.62 + 0.20 * sin(phase + motion * TAU_VALUE * 0.44 + 0.4);
		float ray = lateral * tip * root * amplitude;
		float soft_lateral = exp(-0.5 * pow(distance / max(width * 2.7, 0.001), 2.0));
		field = max(field, ray);
		accumulation += soft_lateral * tip * root * amplitude;
	}
	return clamp(field * 0.72 + accumulation * 0.040, 0.0, 1.0);
}

float prototype_ray_field(
		float angular_uv, float height, float motion, float seed_hash) {
	float low_wave = 0.5 + 0.5 * sin(
		(angular_uv * 7.0 + height * 0.12 - motion * 0.19) * TAU_VALUE
		+ seed_hash * 3.1
	);
	float crossing_wave = 0.5 + 0.5 * sin(
		(angular_uv * 11.0 - height * 0.18 + motion * 0.11) * TAU_VALUE
		- seed_hash * 5.7
	);
	float bands = smoothstep(0.45, 0.98, low_wave * 0.68 + crossing_wave * 0.32);
	float ceiling = 0.75
		+ sin((angular_uv * 4.0 + motion * 0.12) * TAU_VALUE) * 0.10
		+ sin((angular_uv * 9.0 - motion * 0.08) * TAU_VALUE) * 0.035;
	float dissolved_tip = 1.0 - smoothstep(ceiling - 0.41, ceiling + 0.15, height);
	float root = smoothstep(0.025, 0.14, height);
	return clamp((0.08 + bands * 0.34) * dissolved_tip * root, 0.0, 1.0);
}

float vertical_reveal(float height) {
	if (height >= reveal_front) {
		return 0.0;
	}
	float feather_start = max(reveal_front - reveal_softness, 0.0);
	return 1.0 - smoothstep(feather_start, max(reveal_front, 0.0001), height);
}

void fragment() {
	float position = clamp(atlas_state_position, 0.0, FRAME_COUNT - 1.0);
	float seed_hash = fract(sin(seed_value * 12.9898) * 43758.5453);
	float motion = clamp(position / (FRAME_COUNT - 1.0), 0.0, 1.0);
	// Reconstruct the angular coordinate from the carrier position instead of
	// interpolating UV.x across the triangles of a widening shell. Affine UV
	// interpolation on that flare shifts an atlas spike once per height band,
	// exposing the mesh rows as horizontal terraces.
	float angular_uv = atan(local_position.z, local_position.x) / TAU_VALUE;
	angular_uv = angular_uv < 0.0 ? angular_uv + 1.0 : angular_uv;
	angular_uv += uv_phase + motion * spin_turns + (seed_hash - 0.5) * 0.025;
	float flow = prototype_variant == 0
		? analytic_ray_field(angular_uv, UV.y, motion, seed_hash)
		: prototype_ray_field(angular_uv, UV.y, motion, seed_hash);
	flow = pow(flow, prototype_variant == 0 ? 0.78 : 0.92);
	flow *= smoothstep(0.055, 0.18, UV.y) * (1.0 - smoothstep(0.91, 1.0, UV.y));
	flow *= vertical_reveal(UV.y);
	// The source carries its energy below the waist. Tips remain present for
	// silhouette and oscillation, but lose most of their opacity near head
	// height instead of becoming equally bright flame petals.
	flow *= 1.0 - smoothstep(0.42, 0.92, UV.y)
		* (prototype_variant == 0 ? 0.78 : 0.48);
	float onset_visibility = root_ignition * lifecycle_visibility;
	float alpha = flow * shell_opacity * plume_energy * onset_visibility;
	if (alpha < (prototype_variant == 0 ? 0.0025 : 0.0008)) {
		discard;
	}
	float warm_weight = smoothstep(
		0.05, 0.40, aura_color.r - max(aura_color.g, aura_color.b)
	);
	vec3 element_bias = mix(
		vec3(0.32, 0.70, 1.10), vec3(0.70, 0.55, 0.50), warm_weight
	);
	vec3 tint = aura_color.rgb * element_bias;
	ALBEDO = tint * 0.60;
	EMISSION = tint * flow * emission_energy * plume_energy * onset_visibility;
	ALPHA = clamp(alpha, 0.0, 0.36);
}
