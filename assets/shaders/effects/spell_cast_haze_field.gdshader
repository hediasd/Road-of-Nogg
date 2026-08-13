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
uniform float effect_visibility = 0.0;

const float FRAME_COUNT = 11.0;

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

void fragment() {
	if (FRONT_FACING) {
		discard;
	}
	float seed_hash = fract(sin(seed_value * 12.9898) * 43758.5453);
	float motion = clamp(atlas_state_position / (FRAME_COUNT - 1.0), 0.0, 1.0);
	float phase = uv_phase + motion * 0.10 + (seed_hash - 0.5) * 0.025;
	vec2 uv = vec2(UV.x + phase, UV.y);
	float measured_haze = sample_state(uv).r;
	float root_detail = sample_state(uv).b;
	float vertical = smoothstep(0.055, 0.26, UV.y) * (1.0 - smoothstep(0.78, 1.0, UV.y));
	float haze = pow(clamp(measured_haze, 0.0, 1.0), 0.88) * vertical;
	haze = clamp(haze + root_detail * 0.16, 0.0, 1.0);
	float facing = dot(normalize(NORMAL), normalize(VIEW));
	// A profiled shell is only a sampling carrier. Extinguishing its grazing
	// edge prevents the mesh from announcing itself as a dome or cup.
	haze *= 0.12 + 0.88 * smoothstep(0.015, 0.34, abs(facing));
	float alpha = haze * shell_opacity * plume_energy * effect_visibility;
	if (alpha < 0.0025) {
		discard;
	}
	vec3 tint = aura_color.rgb;
	vec3 deep_blue = tint * vec3(0.10, 0.34, 0.60);
	vec3 body_blue = tint * vec3(0.34, 0.72, 1.00);
	vec3 color = mix(deep_blue, body_blue, clamp(haze * 0.72, 0.0, 1.0));
	ALBEDO = color;
	EMISSION = body_blue * haze * emission_energy * plume_energy * effect_visibility;
	ALPHA = clamp(alpha, 0.0, 0.42);
}
