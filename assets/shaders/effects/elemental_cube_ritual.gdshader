shader_type spatial;
render_mode unshaded, cull_disabled, depth_draw_opaque;

uniform vec4 direct_color : source_color = vec4(1.0);
uniform vec4 mid_color : source_color = vec4(0.5);
uniform vec4 shadow_color : source_color = vec4(0.1);
uniform vec3 light_direction_world = vec3(0.55, 1.0, -0.18);
uniform float shadow_stop = -0.18;
uniform float mid_stop = 0.32;
uniform float direct_stop = 0.82;
uniform float edge_polish = 0.075;

void fragment() {
	vec3 normal_view = normalize(NORMAL);
	vec3 light_view = normalize((VIEW_MATRIX * vec4(normalize(light_direction_world), 0.0)).xyz);
	float illumination = dot(normal_view, light_view);
	float shadow_to_mid = smoothstep(shadow_stop, mid_stop, illumination);
	float mid_to_direct = smoothstep(mid_stop, direct_stop, illumination);
	vec3 shaded = mix(shadow_color.rgb, mid_color.rgb, shadow_to_mid);
	shaded = mix(shaded, direct_color.rgb, mid_to_direct);
	float fresnel = pow(1.0 - clamp(dot(normal_view, normalize(VIEW)), 0.0, 1.0), 5.0);
	ALBEDO = mix(shaded, direct_color.rgb, fresnel * edge_polish);
}
