shader_type spatial;

uniform vec4 base_color : source_color = vec4(0.5, 0.5, 0.5, 1.0);
uniform vec4 edge_color : source_color = vec4(1.0, 0.5, 0.0, 1.0);

float hash(vec2 p) {
    return fract(sin(dot(p, vec2(12.9898, 78.233))) * 43758.5453);
}
float noise(vec2 p) {
    vec2 i = floor(p);
    vec2 f = fract(p);
    f = f * f * (3.0 - 2.0 * f);
    return mix(mix(hash(i), hash(i + vec2(1.0, 0.0)), f.x),
               mix(hash(i + vec2(0.0, 1.0)), hash(i + vec2(1.0, 1.0)), f.x), f.y);
}

void fragment() {
	float n = noise(UV * 20.0);
	float dissolve_time = mod(TIME, 4.0) / 4.0; // loops every 4s
	
	if (n < dissolve_time) {
		discard;
	}
	
	if (n < dissolve_time + 0.05) {
		ALBEDO = edge_color.rgb;
		EMISSION = edge_color.rgb * 2.0;
	} else {
		ALBEDO = base_color.rgb;
	}
}
