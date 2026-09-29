shader_type spatial;

uniform vec4 albedo : source_color = vec4(1.0, 0.4, 0.2, 1.0);
uniform vec4 outline_color : source_color = vec4(0.0, 0.0, 0.0, 1.0);
uniform float outline_width : hint_range(0.0, 0.1) = 0.02;

void vertex() {
	// Standard vertex
}

void fragment() {
	ALBEDO = albedo.rgb;
}

void light() {
	float NdotL = dot(NORMAL, LIGHT);
	float diff = step(0.0, NdotL); // Binary light
	DIFFUSE_LIGHT += clamp(diff, 0.0, 1.0) * ALBEDO * LIGHT_COLOR;
}
