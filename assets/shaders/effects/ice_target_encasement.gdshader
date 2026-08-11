shader_type spatial;
render_mode cull_disabled, depth_draw_opaque, diffuse_burley, specular_schlick_ggx;

uniform vec4 base_color : source_color = vec4(0.45, 0.75, 0.95, 1.0);
uniform vec4 shadow_color : source_color = vec4(0.10, 0.24, 0.42, 1.0);
uniform float emission_strength : hint_range(0.0, 1.0) = 0.10;

void fragment() {
	vec3 authored_light = normalize(vec3(0.35, 0.82, 0.45));
	float facing = clamp(dot(normalize(NORMAL), authored_light) * 0.5 + 0.5, 0.0, 1.0);
	float stepped_facing = floor(facing * 3.0 + 0.5) / 3.0;
	vec3 facet_color = mix(shadow_color.rgb, base_color.rgb, 0.38 + stepped_facing * 0.62);
	ALBEDO = facet_color;
	ROUGHNESS = 0.24;
	SPECULAR = 0.72;
	EMISSION = base_color.rgb * emission_strength;
}
