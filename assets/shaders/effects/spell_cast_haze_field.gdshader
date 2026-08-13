// Low, continuous alpha-mixed body field for the reference aura.
//
// The far side supplies the broad blue fan. The camera-side half is omitted;
// the footprint owns the low foreground closure. This keeps the character
// visually inside the aura without exposing the carrier as a transparent cup.
// Motion is explicit normalized seek; no TIME or camera-facing transform exists.

shader_type spatial;
render_mode unshaded, blend_mix, depth_draw_never, cull_disabled;

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

float analytic_haze_field(float angular_uv, float height, float motion, float seed_hash) {
	float strongest = 0.0;
	float accumulation = 0.0;
	// Broad overlapping columns join into the source's smoky body. Their low
	// contrast and soft tips keep this layer connective rather than petal-like.
	for (int group = 0; group < 24; group++) {
		float group_value = float(group);
		float phase = group_value * 1.371 + motion * 5.2 + seed_hash * 0.38;
		float direction = mod(group_value, 2.0) < 1.0 ? 1.0 : -1.0;
		float center = group_value / 24.0
			+ motion * (0.010 + mod(group_value, 3.0) * 0.002);
		float lean = direction * (0.010 + 0.008 * sin(phase));
		float bent_center = center + lean * pow(height, 1.25);
		float width = (0.022 + mod(group_value, 4.0) * 0.0032)
			* (1.18 - 0.30 * height);
		float distance = wrapped_distance(angular_uv, bent_center);
		float lateral = exp(-0.5 * pow(distance / max(width, 0.001), 2.0));
		float column_height = clamp(0.58 + 0.17 * sin(phase * 0.79), 0.42, 0.79);
		float local_distance = distance / max(width, 0.001);
		float local_height = column_height - pow(clamp(local_distance, 0.0, 2.0), 1.35) * 0.10;
		float tip = 1.0 - smoothstep(local_height - 0.27, local_height, height);
		float root = smoothstep(0.025, 0.13, height);
		float amplitude = 0.42 + 0.16 * sin(phase + 0.7);
		float column = lateral * tip * root * amplitude;
		strongest = max(strongest, column);
		accumulation += column;
	}
	float root_fog = (1.0 - smoothstep(0.10, 0.34, height)) * 0.30;
	return clamp(strongest * 0.58 + accumulation * 0.052 + root_fog, 0.0, 1.0);
}

void fragment() {
	float seed_hash = fract(sin(seed_value * 12.9898) * 43758.5453);
	float motion = clamp(atlas_state_position / (FRAME_COUNT - 1.0), 0.0, 1.0);
	float phase = uv_phase + motion * 0.10 + (seed_hash - 0.5) * 0.025;
	float angular_uv = atan(local_position.z, local_position.x) / TAU_VALUE;
	angular_uv = angular_uv < 0.0 ? angular_uv + 1.0 : angular_uv;
	vec2 uv = vec2(angular_uv + phase, UV.y);
	float measured_haze = sample_state(uv).r;
	float root_detail = sample_state(uv).b;
	float vertical = smoothstep(0.055, 0.26, UV.y) * (1.0 - smoothstep(0.78, 1.0, UV.y));
	float analytic_haze = analytic_haze_field(
		angular_uv + phase, UV.y, motion, seed_hash
	);
	float haze = clamp(analytic_haze * 1.05 + measured_haze * 0.20, 0.0, 1.0) * vertical;
	haze = clamp(haze + root_detail * 0.16, 0.0, 1.0);
	haze *= vertical_reveal(UV.y);
	float facing = dot(normalize(NORMAL), normalize(VIEW));
	float far_hemisphere = smoothstep(-0.12, 0.06, facing);
	haze *= far_hemisphere;
	// A profiled shell is only a sampling carrier. Extinguishing its grazing
	// edge prevents the mesh from announcing itself as a dome or cup.
	haze *= 0.38 + 0.62 * smoothstep(0.015, 0.34, abs(facing));
	float onset_visibility = root_ignition * lifecycle_visibility;
	float alpha = haze * shell_opacity * plume_energy * onset_visibility;
	if (alpha < 0.0025) {
		discard;
	}
	vec3 tint = aura_color.rgb;
	float warm_weight = smoothstep(0.05, 0.40, tint.r - max(tint.g, tint.b));
	vec3 deep_bias = mix(
		vec3(0.06, 0.22, 0.55), vec3(0.55, 0.20, 0.12), warm_weight
	);
	vec3 body_bias = mix(
		vec3(0.16, 0.55, 0.95), vec3(0.80, 0.28, 0.14), warm_weight
	);
	vec3 deep_blue = tint * deep_bias;
	vec3 body_blue = tint * body_bias;
	vec3 color = mix(deep_blue, body_blue, clamp(haze * 0.72, 0.0, 1.0));
	ALBEDO = color;
	EMISSION = body_blue * haze * emission_energy * plume_energy * onset_visibility;
	ALPHA = clamp(alpha, 0.0, 0.34);
}
