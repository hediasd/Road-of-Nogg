shader_type spatial;
render_mode blend_mix, depth_draw_always, cull_back, diffuse_burley, specular_schlick_ggx;

uniform float roughness : hint_range(0.0, 1.0) = 0.1;
uniform float refraction : hint_range(0.0, 1.0) = 0.5;

void fragment() {
	ALBEDO = vec3(0.9, 0.9, 1.0);
	METALLIC = 0.5;
	ROUGHNESS = roughness;
	
	// Rainbow iridescence based on view angle
	float vdn = 1.0 - max(dot(normalize(VIEW), NORMAL), 0.0);
	vec3 iridescent = vec3(
		0.5 + 0.5 * cos(vdn * 10.0 + 0.0),
		0.5 + 0.5 * cos(vdn * 10.0 + 2.0),
		0.5 + 0.5 * cos(vdn * 10.0 + 4.0)
	);
	
	ALBEDO *= iridescent;
	ALPHA = 0.6;
}
