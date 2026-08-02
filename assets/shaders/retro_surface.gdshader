shader_type spatial;

uniform vec4 color_a : source_color = vec4(1.0);
uniform vec4 color_b : source_color = vec4(1.0);
uniform bool split_color = false;
uniform vec2 split_bounds_min = vec2(-0.5, 0.0);
uniform vec2 split_bounds_size = vec2(1.0, 1.0);
instance uniform vec3 split_model_origin = vec3(0.0);
instance uniform vec3 split_model_basis_x = vec3(1.0, 0.0, 0.0);
instance uniform vec3 split_model_basis_y = vec3(0.0, 1.0, 0.0);
instance uniform vec3 split_model_basis_z = vec3(0.0, 0.0, 1.0);
uniform bool use_albedo_texture = false;
uniform sampler2D albedo_texture : source_color, filter_nearest;
uniform bool vertex_snap_enabled = true;
uniform float vertex_snap_strength : hint_range(0.0, 1.0) = 1.0;
uniform bool affine_mapping_enabled = true;
uniform vec2 snap_resolution = vec2(320.0, 240.0);
uniform float emission_strength = 0.0;
// Darkens ALBEDO/EMISSION in place, toward the same TEXT_DIM-style treatment
// the command menu already uses for a spent row. Defaults to 0.0 so every
// material is pixel-identical until something opts in.
uniform float dim_amount : hint_range(0.0, 1.0) = 0.0;

// Surface finish, promoted from what used to be hardcoded in fragment() so a
// material can opt into a different finish (the model base's metallic plinth,
// for one) without every other material in the scene changing appearance.
// Defaults are exactly the old hardcoded values.
uniform float surface_roughness : hint_range(0.0, 1.0) = 1.0;
uniform float surface_metallic : hint_range(0.0, 1.0) = 0.0;
uniform float surface_specular : hint_range(0.0, 1.0) = 0.25;
// Cheap fresnel edge glow, not physically based — a raised specular response
// alone reads as flat at this vertex-snapped, affine-mapped resolution, and a
// full PBR metal would fight the deliberately low-fidelity look elsewhere in
// the scene. Off by default; nothing opts in without also setting rim_amount.
uniform float rim_amount : hint_range(0.0, 1.0) = 0.0;
uniform vec4 rim_color : source_color = vec4(1.0);

// Screen-door transparency: a Bayer threshold on FRAGCOORD with discard,
// rather than blended alpha. Keeps depth writes, needs no transparency
// sorting, and is what the hardware this scene imitates actually did.
//
// Anchored to FRAGCOORD, never to UV: a screen-space grid reads as a stable
// pixel dither the model moves behind, while a UV-space one swims across the
// surface as it turns and looks like a texture bug.
//
// DITHER_MATRIX_SIZE is 4 (a 4x4 Bayer cell) rather than 2, so the pattern
// survives the retro pipeline's downsample to 320x240 and the CRT upscale as
// a visible weave instead of a flat haze.
uniform float dither_amount : hint_range(0.0, 1.0) = 0.0;

const int DITHER_MATRIX_SIZE = 4;
const float DITHER_THRESHOLDS[16] = float[16](
	 0.0 / 16.0,  8.0 / 16.0,  2.0 / 16.0, 10.0 / 16.0,
	12.0 / 16.0,  4.0 / 16.0, 14.0 / 16.0,  6.0 / 16.0,
	 3.0 / 16.0, 11.0 / 16.0,  1.0 / 16.0,  9.0 / 16.0,
	15.0 / 16.0,  7.0 / 16.0, 13.0 / 16.0,  5.0 / 16.0
);

varying vec2 split_model_xy;
varying vec2 affine_uv_times_w;
varying float affine_clip_w;

void vertex() {
	vec3 split_model_position = (
		split_model_origin +
		split_model_basis_x * VERTEX.x +
		split_model_basis_y * VERTEX.y +
		split_model_basis_z * VERTEX.z
	);
	split_model_xy = split_model_position.xy;
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
	if (dither_amount > 0.0) {
		ivec2 cell = ivec2(FRAGCOORD.xy) % DITHER_MATRIX_SIZE;
		if (dither_amount > DITHER_THRESHOLDS[cell.y * DITHER_MATRIX_SIZE + cell.x]) {
			discard;
		}
	}
	vec2 sample_uv = UV;
	if (affine_mapping_enabled && abs(affine_clip_w) > 0.00001) {
		sample_uv = affine_uv_times_w / affine_clip_w;
	}
	vec4 texel = vec4(1.0);
	if (use_albedo_texture) {
		texel = texture(albedo_texture, sample_uv);
	}
	vec4 tint = color_a;
	vec2 split_uv = (
		split_model_xy - split_bounds_min
	) / max(split_bounds_size, vec2(0.0001));
	if (split_color && split_uv.y - split_uv.x >= 0.0) {
		tint = color_b;
	}
	ALBEDO = tint.rgb * texel.rgb * (1.0 - dim_amount * 0.55);
	ROUGHNESS = surface_roughness;
	METALLIC = surface_metallic;
	SPECULAR = surface_specular;
	EMISSION = ALBEDO * emission_strength;
	if (rim_amount > 0.0) {
		float fresnel = pow(1.0 - clamp(dot(normalize(NORMAL), normalize(VIEW)), 0.0, 1.0), 4.0);
		EMISSION += rim_color.rgb * fresnel * rim_amount;
	}
}
