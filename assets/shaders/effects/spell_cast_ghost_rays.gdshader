// Sparse additive far-side rays for the reference aura.
//
// The alpha-mixed haze owns the continuous mass. This material keeps only
// narrow high-confidence atlas features and discards the camera-side shell,
// preventing a visible cup or shoulder wings at arbitrary camera yaw.

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

const float FRAME_COUNT = 11.0;

void vertex() {
	float motion = clamp(atlas_state_position / (FRAME_COUNT - 1.0), 0.0, 1.0);
	float angle = (UV.x + uv_phase + motion * 0.16) * 6.28318530718;
	float tip_wave = (
		sin(angle * 5.0 + motion * 2.0 * 6.28318530718) * 0.72
		+ sin(angle * 8.0 - motion * 1.35 * 6.28318530718 + 1.4) * 0.28
	);
	VERTEX.y += tip_wave * 0.045 * pow(UV.y, 1.8);
}

vec4 sample_frame(float frame_index, vec2 local_uv) {
	float cell_width = atlas_pixel_size.x / FRAME_COUNT;
	float pixel_x = frame_index * cell_width + 0.5 + fract(local_uv.x) * (cell_width - 1.0);
	float pixel_y = 0.5 + clamp(local_uv.y, 0.0, 1.0) * (atlas_pixel_size.y - 1.0);
	return texture(plume_atlas, vec2(pixel_x, pixel_y) / atlas_pixel_size);
}

float vertical_reveal(float height) {
	if (height >= reveal_front) {
		return 0.0;
	}
	float feather_start = max(reveal_front - reveal_softness, 0.0);
	return 1.0 - smoothstep(feather_start, max(reveal_front, 0.0001), height);
}

void fragment() {
	if (FRONT_FACING) {
		discard;
	}
	float position = clamp(atlas_state_position, 0.0, FRAME_COUNT - 1.0);
	float current = floor(position);
	float following = min(current + 1.0, FRAME_COUNT - 1.0);
	float transition = fract(position) * state_crossfade;
	float seed_hash = fract(sin(seed_value * 12.9898) * 43758.5453);
	float motion = clamp(position / (FRAME_COUNT - 1.0), 0.0, 1.0);
	vec2 uv = vec2(UV.x + uv_phase + motion * 0.16 + (seed_hash - 0.5) * 0.025, UV.y);
	float flow = mix(sample_frame(current, uv).g, sample_frame(following, uv).g, transition);
	flow = pow(clamp(flow, 0.0, 1.0), 0.68);
	flow *= smoothstep(0.055, 0.18, UV.y) * (1.0 - smoothstep(0.91, 1.0, UV.y));
	flow *= vertical_reveal(UV.y);
	// The source carries its energy below the waist. Tips remain present for
	// silhouette and oscillation, but lose most of their opacity near head
	// height instead of becoming equally bright flame petals.
	flow *= 1.0 - smoothstep(0.42, 0.92, UV.y) * 0.78;
	float view_feather = 0.42 + 0.58 * smoothstep(
		0.04, 0.34, abs(dot(normalize(NORMAL), normalize(VIEW)))
	);
	flow *= view_feather;
	float onset_visibility = root_ignition * lifecycle_visibility;
	float alpha = flow * shell_opacity * plume_energy * onset_visibility;
	if (alpha < 0.0025) {
		discard;
	}
	vec3 tint = aura_color.rgb * vec3(0.32, 0.70, 1.10);
	ALBEDO = tint * 0.65;
	EMISSION = tint * flow * emission_energy * plume_energy * onset_visibility;
	ALPHA = clamp(alpha, 0.0, 0.45);
}
