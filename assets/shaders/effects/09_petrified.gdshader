shader_type spatial;

uniform vec4 stone_color : source_color = vec4(0.4, 0.4, 0.4, 1.0);

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
	ALBEDO = stone_color.rgb;
	ROUGHNESS = 1.0;
	METALLIC = 0.0;
	
	// Bump map calculation from noise
	float n = noise(UV * 50.0);
	NORMAL_MAP = vec3(0.5, 0.5, 1.0) + vec3(n - 0.5, n - 0.5, 0.0) * 0.2;
}
