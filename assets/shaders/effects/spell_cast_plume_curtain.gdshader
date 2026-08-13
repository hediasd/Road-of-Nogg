// Two world-space shells share this project-owned upward-tongue atlas.
//
// Both hemispheres render. The camera-side half is deliberately attenuated,
// rather than removed, so the caster reads inside the aura without becoming a
// cyan silhouette. Angular spin and vertical ghost-tip oscillation use the
// explicit normalized source-state position. No billboard matrix,
// camera-relative offset, particle, or TIME input exists.

shader_type spatial;
render_mode unshaded, blend_add, depth_draw_never, cull_disabled;

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
const float SPIN_REVOLUTIONS = 0.72;
const float OSCILLATION_CYCLES = 2.35;

void vertex() {
	float motion = clamp(atlas_state_position / (FRAME_COUNT - 1.0), 0.0, 1.0);
	float role = smoothstep(0.10, 0.18, uv_phase);
	float angular_phase = (
		(UV.x + uv_phase + motion * SPIN_REVOLUTIONS) * 6.28318530718
	);
	float primary = sin(angular_phase * 4.0 + motion * OSCILLATION_CYCLES * 6.28318530718);
	float secondary = sin(angular_phase * 7.0 - motion * 1.65 * 6.28318530718 + 1.7);
	float irregular_wave = primary * 0.72 + secondary * 0.28;
	float oscillation_height = mix(0.10, 0.24, role);
	VERTEX.y += irregular_wave * oscillation_height * pow(UV.y, 1.55);
}

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
	float motion = clamp(frame_position / (FRAME_COUNT - 1.0), 0.0, 1.0);
	vec2 flow_uv = vec2(
		UV.x + seeded_phase + motion * SPIN_REVOLUTIONS,
		UV.y
	);
	float current_alpha = sample_frame(current_frame, flow_uv).a;
	float next_alpha = sample_frame(next_frame, flow_uv).a;
	float flow_alpha = pow(mix(current_alpha, next_alpha, transition), 1.25);
	// Retain the grazing-angle field around the caster's silhouette. The old
	// zero-at-the-edge mask erased the side tongues and left only a timid patch
	// behind the head; the atlas still defines the actual plume boundaries.
	float view_feather = 0.58 + 0.42 * smoothstep(
		0.04,
		0.55,
		abs(dot(normalize(NORMAL), normalize(VIEW)))
	);
	flow_alpha *= view_feather;
	float shell_role = smoothstep(0.10, 0.18, uv_phase);
	// The looser outer crown uses its far hemisphere only. Rendering its near
	// half exposes the flared mesh as two bright curved panels. The tighter
	// inner crown keeps a soft camera-side wash above the root so the caster is
	// visibly enclosed without a flat skirt at ground level.
	if (FRONT_FACING) {
		if (shell_role > 0.5) {
			discard;
		}
		float front_height_envelope = smoothstep(0.12, 0.38, UV.y);
		float front_body_mask = smoothstep(
			0.38,
			0.86,
			dot(normalize(NORMAL), normalize(VIEW))
		);
		flow_alpha *= 0.28 * front_height_envelope * front_body_mask;
	}
	flow_alpha = min(flow_alpha * 1.32, 1.0);

	float alpha = flow_alpha * shell_opacity * plume_energy * effect_visibility;
	if (alpha < 0.0025) {
		discard;
	}

	vec3 tint = saturated_tint(aura_color.rgb) * 0.86;
	vec3 deep_blue = tint * vec3(0.28, 0.52, 0.78);
	vec3 color = mix(deep_blue, tint, clamp(flow_alpha * 0.82, 0.0, 1.0));
	ALBEDO = color;
	EMISSION = tint * flow_alpha * emission_energy * plume_energy * effect_visibility;
	ALPHA = clamp(alpha, 0.0, 0.88);
}
