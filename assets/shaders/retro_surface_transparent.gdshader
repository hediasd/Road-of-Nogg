shader_type spatial;
render_mode blend_mix, depth_draw_opaque;

uniform vec4 color_a : source_color = vec4(1.0);
uniform vec4 color_b : source_color = vec4(1.0);
uniform bool split_color = false;
uniform bool use_albedo_texture = false;
uniform sampler2D albedo_texture : source_color, filter_nearest;
uniform bool vertex_snap_enabled = true;
uniform float vertex_snap_strength : hint_range(0.0, 1.0) = 1.0;
uniform bool affine_mapping_enabled = true;
uniform vec2 snap_resolution = vec2(320.0, 240.0);
uniform float emission_strength = 0.0;

varying vec3 local_position;
varying vec2 affine_uv_times_w;
varying float affine_clip_w;

void vertex() {
	local_position = VERTEX;
	vec4 clip_position = PROJECTION_MATRIX * MODELVIEW_MATRIX * vec4(VERTEX, 1.0);
	affine_uv_times_w = UV * clip_position.w;
	affine_clip_w = clip_position.w;
	if (vertex_snap_enabled) {
		vec2 half_resolution = max(snap_resolution * 0.5, vec2(1.0));
		vec2 original_ndc = clip_position.xy / clip_position.w;
		vec2 snapped_ndc = round(original_ndc * half_resolution) / half_resolution;
		vec2 adjusted_ndc = mix(original_ndc, snapped_ndc, vertex_snap_strength);
		clip_position.xy = adjusted_ndc * clip_position.w;
	}
	POSITION = clip_position;
}

void fragment() {
	vec2 sample_uv = UV;
	if (affine_mapping_enabled && abs(affine_clip_w) > 0.00001) {
		sample_uv = affine_uv_times_w / affine_clip_w;
	}
	vec4 texel = vec4(1.0);
	if (use_albedo_texture) {
		texel = texture(albedo_texture, sample_uv);
	}
	vec4 tint = color_a;
	if (split_color && local_position.y - local_position.x >= 0.0) {
		tint = color_b;
	}
	ALBEDO = tint.rgb * texel.rgb;
	ALPHA = tint.a * texel.a;
	ROUGHNESS = 1.0;
	METALLIC = 0.0;
	SPECULAR = 0.25;
	EMISSION = ALBEDO * emission_strength;
}
