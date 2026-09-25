// Low, continuous alpha-mixed body field for the reference aura.
//
// The far side supplies the broad blue fan. The camera-side half is omitted;
// the footprint owns the low foreground closure. This keeps the character
// visually inside the aura without exposing the carrier as a transparent cup.
// Motion is explicit normalized seek; no TIME or camera-facing transform exists.

shader_type spatial;
render_mode unshaded, blend_add, depth_draw_never, cull_disabled;

uniform sampler2D plume_atlas : source_color, filter_linear, repeat_disable;
uniform vec2 atlas_pixel_size = vec2(2816.0, 256.0);
uniform vec4 aura_color : source_color = vec4(0.05, 0.42, 0.75, 1.0);
uniform float seed_value = 0.0;
uniform float uv_phase = 0.0;
uniform float shell_opacity = 0.46;
uniform float emission_energy = 0.24;
uniform float state_crossfade = 0.0;
uniform float atlas_state_position = 0.0;
uniform float plume_energy = 1.0;
uniform float root_ignition = 0.0;
uniform float reveal_front = 0.0;
uniform float reveal_softness = 0.08;
uniform float lifecycle_visibility = 1.0;
uniform float spin_turns = 0.10;

const float FRAME_COUNT = 11.0;
const float TAU_VALUE = 6.28318530718;

varying vec3 local_position;

void vertex() {
	local_position = VERTEX;
}

vec4 sample_frame(float frame_index, vec2 local_uv) {
	float cell_width = atlas_pixel_size.x / FRAME_COUNT;
	float pixel_x = frame_index * cell_width + 0.5 + fract(local_uv.x) * (cell_width - 1.0);
	float pixel_y = 0.5 + clamp(local_uv.y, 0.0, 1.0) * (atlas_pixel_size.y - 1.0);
	return texture(plume_atlas, vec2(pixel_x, pixel_y) / atlas_pixel_size);
}

vec4 sample_state(vec2 local_uv) {
	float position = clamp(atlas_state_position, 0.0, FRAME_COUNT - 1.0);
	float current = floor(position);
	float following = min(current + 1.0, FRAME_COUNT - 1.0);
	float transition = fract(position) * state_crossfade;
	return mix(sample_frame(current, local_uv), sample_frame(following, local_uv), transition);
}

float vertical_reveal(float height) {
	if (height >= reveal_front) {
		return 0.0;
	}
	float feather_start = max(reveal_front - reveal_softness, 0.0);
	return 1.0 - smoothstep(feather_start, max(reveal_front, 0.0001), height);
}

float wrapped_distance(float first, float second) {
	return abs(fract(first - second + 0.5) - 0.5);
}

float spectral_noise(float angular_uv, float height, float motion, float seed_hash) {
	float low = sin((angular_uv * 3.0 + motion * 0.071) * TAU_VALUE + seed_hash * 4.7);
	float middle = sin((angular_uv * 7.0 - height * 1.8) * TAU_VALUE - motion * 2.1);
	float high = sin((angular_uv * 13.0 + height * 2.6) * TAU_VALUE + seed_hash * 9.1);
	return clamp(0.50 + low * 0.10 + middle * 0.22 + high * 0.13, 0.0, 1.0);
}

float fog_haze_field(
		float angular_uv, float height, float motion, float seed_hash) {
	float flow = spectral_noise(
		angular_uv + height * 0.018, height, motion, seed_hash
	);
	float ceiling = 0.73
		+ sin((angular_uv * 5.0 + motion * 0.09) * TAU_VALUE) * 0.025
		+ sin((angular_uv * 11.0 - motion * 0.13 + seed_hash) * TAU_VALUE) * 0.060;
	float soft_cap = 1.0 - smoothstep(ceiling - 0.43, ceiling + 0.17, height);
	float root_floor = 0.045 + flow * 0.10;
	float root = smoothstep(root_floor, root_floor + 0.22, height);
	float upper_thinning = mix(1.0, 0.025, smoothstep(0.12, 0.72, height));
	float continuous_mass = soft_cap * root * mix(0.78, 1.22, flow) * upper_thinning;
	float root_fog = (1.0 - smoothstep(0.035, 0.48, height))
		* (0.12 + smoothstep(0.32, 0.86, flow) * 0.75);
	return clamp(continuous_mass + root_fog, 0.0, 1.0);
}

void fragment() {
	float seed_hash = fract(sin(seed_value * 12.9898) * 43758.5453);
	float motion = clamp(atlas_state_position / (FRAME_COUNT - 1.0), 0.0, 1.0);
	float phase = uv_phase + motion * spin_turns + (seed_hash - 0.5) * 0.025;
	float angular_uv = atan(local_position.z, local_position.x) / TAU_VALUE;
	angular_uv = angular_uv < 0.0 ? angular_uv + 1.0 : angular_uv;
	vec2 uv = vec2(angular_uv + phase, UV.y);
	float measured_haze = sample_state(uv).r;
	float root_detail = sample_state(uv).b;
	float root_variation = spectral_noise(
		angular_uv + phase + 0.19, UV.y * 0.7, motion + 0.31, seed_hash
	);
	float root_floor = 0.045 + root_variation * 0.12;
	float vertical = smoothstep(root_floor, root_floor + 0.25, UV.y)
		* (1.0 - smoothstep(0.78, 1.0, UV.y));
	float analytic_haze = fog_haze_field(
		angular_uv + phase, UV.y, motion, seed_hash
	);
	float measured_weight = 0.07;
	float analytic_weight = 1.42;
	float root_weight = 0.07;
	float haze = clamp(
		analytic_haze * analytic_weight + measured_haze * measured_weight, 0.0, 1.0
	) * vertical;
	haze = clamp(haze + root_detail * root_weight * vertical, 0.0, 1.0);
	haze *= vertical_reveal(UV.y);
	float signed_facing = dot(normalize(NORMAL), normalize(VIEW));
	float far_hemisphere = smoothstep(-0.10, 0.08, signed_facing);
	haze *= far_hemisphere;
	// A profiled shell is only a sampling carrier. Extinguishing its grazing
	// edge prevents the mesh from announcing itself as a dome or cup.
	haze *= 0.02 + 0.98 * smoothstep(0.025, 0.24, abs(signed_facing));
	float onset_visibility = root_ignition * lifecycle_visibility;
	float alpha = haze * shell_opacity * plume_energy * onset_visibility;
	if (alpha < 0.0008) {
		discard;
	}
	vec3 tint = aura_color.rgb;
	float warm_weight = smoothstep(0.05, 0.40, tint.r - max(tint.g, tint.b));
	vec3 deep_bias = mix(
		vec3(0.10, 0.34, 0.60), vec3(0.55, 0.20, 0.12), warm_weight
	);
	vec3 body_bias = mix(
		vec3(0.44, 0.84, 1.10), vec3(0.86, 0.34, 0.18), warm_weight
	);
	vec3 deep_blue = tint * deep_bias;
	vec3 body_blue = tint * body_bias;
	vec3 color = mix(deep_blue, body_blue, clamp(haze * 0.72, 0.0, 1.0));
	ALBEDO = color;
	EMISSION = body_blue * haze * emission_energy * plume_energy * onset_visibility;
	ALPHA = clamp(alpha, 0.0, 0.42);
}
