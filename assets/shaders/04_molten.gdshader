shader_type spatial;

uniform vec4 rock_color : source_color = vec4(0.1, 0.1, 0.1, 1.0);
uniform vec4 lava_color : source_color = vec4(1.0, 0.3, 0.0, 1.0);

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
	vec2 uv = UV * 5.0 + vec2(0.0, TIME * 0.2);
	float n = noise(uv);
	
	float threshold = 0.5;
	if (n > threshold) {
		ALBEDO = lava_color.rgb;
		EMISSION = lava_color.rgb * 4.0;
	} else {
		ALBEDO = rock_color.rgb;
		ROUGHNESS = 1.0;
		METALLIC = 0.0;
	}
}
