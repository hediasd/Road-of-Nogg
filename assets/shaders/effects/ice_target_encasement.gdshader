shader_type spatial;
render_mode blend_mix, depth_prepass_alpha, cull_disabled, diffuse_burley, specular_schlick_ggx;

uniform vec4 base_color : source_color = vec4(0.24, 0.80, 0.88, 1.0);
uniform vec4 shadow_color : source_color = vec4(0.08, 0.36, 0.44, 1.0);
uniform float opacity : hint_range(0.0, 1.0) = 0.62;
uniform float emission_strength : hint_range(0.0, 1.0) = 0.16;
uniform sampler2D facet_atlas : source_color, filter_nearest, repeat_disable;
uniform vec2 facet_tile = vec2(2.0, 1.0);
uniform vec2 facet_atlas_pixel_size = vec2(80.0, 64.0);
uniform vec2 facet_tile_pixel_size = vec2(16.0, 16.0);
uniform float facet_color_strength : hint_range(0.0, 1.0) = 0.82;

void fragment() {
	vec3 authored_light = normalize(vec3(0.35, 0.82, 0.45));
	float facing = clamp(dot(normalize(NORMAL), authored_light) * 0.5 + 0.5, 0.0, 1.0);
	float stepped_facing = floor(facing * 3.0 + 0.5) / 3.0;
	vec3 facet_color = mix(shadow_color.rgb, base_color.rgb, 0.38 + stepped_facing * 0.62);
	vec2 tile_pixel_origin = facet_tile * facet_tile_pixel_size;
	vec2 tile_uv = (
		tile_pixel_origin
		+ vec2(0.5)
		+ clamp(UV, vec2(0.0), vec2(1.0)) * (facet_tile_pixel_size - vec2(1.0))
	) / facet_atlas_pixel_size;
	vec4 painted_facet = texture(facet_atlas, tile_uv);
	facet_color = mix(
		facet_color,
		painted_facet.rgb,
		painted_facet.a * facet_color_strength);
	ALBEDO = facet_color;
	ROUGHNESS = 0.42;
	SPECULAR = 0.38;
	EMISSION = mix(base_color.rgb, facet_color, 0.45) * emission_strength;
	ALPHA = opacity;
}
