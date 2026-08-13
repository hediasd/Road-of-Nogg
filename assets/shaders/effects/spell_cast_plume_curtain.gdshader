// Two low-opacity world-space shells share this project-owned flow atlas.
//
// The mesh has outward-facing winding; cull_front removes the near hemisphere
// for an external camera and leaves only the far curtain behind the character.
// No billboard matrix, camera-relative offset, particle, or TIME input exists.

shader_type spatial;
render_mode unshaded, blend_add, depth_draw_never, cull_front;

uniform sampler2D plume_atlas : source_color, filter_linear, repeat_disable;
uniform vec2 atlas_pixel_size = vec2(704.0, 64.0);
uniform vec4 aura_color : source_color = vec4(0.05, 0.42, 0.75, 1.0);
uniform float seed_value = 0.0;
uniform float uv_phase : hint_range(0.0, 1.0) = 0.0;
uniform float shell_opacity : hint_range(0.0, 1.0) = 0.24;
uniform float emission_energy : hint_range(0.0, 8.0) = 0.90;
uniform float state_crossfade : hint_range(0.0, 1.0) = 0.0;
uniform float atlas_state_position : hint_range(0.0, 10.0) = 0.0;
uniform float plume_energy : hint_range(0.0, 2.0) = 1.0;
uniform float effect_visibility : hint_range(0.0, 1.0) = 0.0;

const float FRAME_COUNT = 11.0;

vec4 sample_frame(float frame_index, vec2 local_uv) {
	float cell_width = atlas_pixel_size.x / FRAME_COUNT;
	float wrapped_u = fract(local_uv.x);
	// The inset samples the complete periodic cell including its duplicated
	// endpoints while preventing linear filtering from touching another state.
	float pixel_x = frame_index * cell_width + 0.5 + wrapped_u * (cell_width - 1.0);
	float pixel_y = 0.5 + clamp(local_uv.y, 0.0, 1.0) * (atlas_pixel_size.y - 1.0);
	return texture(plume_atlas, vec2(pixel_x, pixel_y) / atlas_pixel_size);
}

vec3 saturated_tint(vec3 color) {
	float luma = dot(color, vec3(0.299, 0.587, 0.114));
	return clamp(mix(vec3(luma), color, 2.0), vec3(0.0), vec3(1.0));
}

void fragment() {
	float frame_position = clamp(atlas_state_position, 0.0, FRAME_COUNT - 1.0);
	float current_frame = floor(frame_position);
	float next_frame = min(current_frame + 1.0, FRAME_COUNT - 1.0);
	float transition = fract(frame_position) * state_crossfade;
	float seed_hash = fract(sin(seed_value * 12.9898) * 43758.5453);
	float seeded_phase = fract(uv_phase + (seed_hash - 0.5) * 0.035);
	vec2 flow_uv = vec2(UV.x + seeded_phase, UV.y);
	float current_alpha = sample_frame(current_frame, flow_uv).a;
	float next_alpha = sample_frame(next_frame, flow_uv).a;
	float flow_alpha = pow(mix(current_alpha, next_alpha, transition), 1.25);
	// Suppress the geometric cone silhouette. The authored atlas, not the
	// grazing edge of a shell, must define every visible plume boundary.
	float view_feather = smoothstep(
		0.04,
		0.55,
		abs(dot(normalize(NORMAL), normalize(VIEW)))
	);
	flow_alpha *= view_feather;

	float alpha = flow_alpha * shell_opacity * plume_energy * effect_visibility;
	if (alpha < 0.0025) {
		discard;
	}

	vec3 tint = saturated_tint(aura_color.rgb) * 0.68;
	vec3 deep_blue = tint * vec3(0.28, 0.52, 0.78);
	vec3 color = mix(deep_blue, tint, clamp(flow_alpha * 0.82, 0.0, 1.0));
	ALBEDO = color;
	EMISSION = tint * flow_alpha * emission_energy * plume_energy * effect_visibility;
	ALPHA = clamp(alpha, 0.0, 0.62);
}
