// Sparse additive far-side rays for the reference aura.
//
// The alpha-mixed haze owns the continuous mass. This material adds only
// narrow analytic high-energy streaks on the far-side shell, preventing a
// visible cup or shoulder wings at arbitrary camera yaw.

shader_type spatial;
render_mode unshaded, blend_add, depth_draw_never, cull_disabled;

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

const float FRAME_COUNT = 11.0;
const float TAU_VALUE = 6.28318530718;

varying vec3 local_position;

void vertex() {
	local_position = VERTEX;
}

float wrapped_distance(float first, float second) {
	return abs(fract(first - second + 0.5) - 0.5);
}

float ghost_ray_field(
		float angular_uv, float height, float motion, float seed_hash) {
	float low_wave = 0.5 + 0.5 * sin(
		(angular_uv * 13.0 + height * 0.16 - motion * 0.19) * TAU_VALUE
		+ seed_hash * 3.1
	);
	float crossing_wave = 0.5 + 0.5 * sin(
		(angular_uv * 17.0 - height * 0.21 + motion * 0.11) * TAU_VALUE
		- seed_hash * 5.7
	);
	float broad_envelope = max(
		pow(low_wave, 3.8), pow(crossing_wave, 4.5) * 0.82
	);
	float bands = smoothstep(0.45, 0.92, broad_envelope);
	float core = smoothstep(0.78, 0.99, broad_envelope);
	float ray_index = floor(fract(angular_uv) * 17.0);
	float tip_oscillation = sin(
		motion * tip_oscillation_cycles * TAU_VALUE
		+ ray_index * tip_phase_step
	) * tip_oscillation_amplitude;
	float ceiling = 0.75
		+ sin((angular_uv * 4.0 + motion * 0.12) * TAU_VALUE) * 0.10
		+ sin((angular_uv * 9.0 - motion * 0.08) * TAU_VALUE) * 0.035
		+ tip_oscillation * (0.35 + bands * 0.65);
	float dissolved_tip = 1.0 - smoothstep(ceiling - 0.41, ceiling + 0.15, height);
	float root_floor = 0.06 + broad_envelope * 0.12;
	float root = smoothstep(root_floor, root_floor + 0.22, height);
	float upper_thinning = mix(1.0, 0.12, smoothstep(0.25, 0.80, height));
	return clamp(
		(0.025 + broad_envelope * 0.13 + bands * 0.37 + core * 0.22)
		* dissolved_tip * root * upper_thinning,
		0.0,
		1.0
	);
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
	float flow = ghost_ray_field(angular_uv, UV.y, motion, seed_hash);
	flow = pow(flow, 0.92);
	flow *= 1.0 - smoothstep(0.91, 1.0, UV.y);
	flow *= vertical_reveal(UV.y);
	// The source carries its energy below the waist. Tips remain present for
	// silhouette and oscillation, but lose most of their opacity near head
	// height instead of becoming equally bright flame petals.
	flow *= 1.0 - smoothstep(0.42, 0.92, UV.y) * 0.48;
	float signed_facing = dot(normalize(NORMAL), normalize(VIEW));
	float far_hemisphere = smoothstep(-0.10, 0.08, signed_facing);
	flow *= far_hemisphere;
	flow *= 0.02 + 0.98 * smoothstep(0.025, 0.22, abs(signed_facing));
	float onset_visibility = root_ignition * lifecycle_visibility;
	float alpha = flow * shell_opacity * plume_energy * onset_visibility;
	if (alpha < 0.0008) {
		discard;
	}
	float warm_weight = smoothstep(
		0.05, 0.40, aura_color.r - max(aura_color.g, aura_color.b)
	);
	vec3 element_bias = mix(
		vec3(0.40, 0.82, 1.18), vec3(0.76, 0.62, 0.54), warm_weight
	);
	vec3 tint = aura_color.rgb * element_bias;
	ALBEDO = tint * 0.60;
	EMISSION = tint * flow * emission_energy * plume_energy * onset_visibility;
	ALPHA = clamp(alpha, 0.0, 0.26);
}
