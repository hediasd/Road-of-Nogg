shader_type spatial;

uniform vec4 base_color : source_color = vec4(0.0, 0.0, 0.0, 1.0);
uniform vec4 rain_color : source_color = vec4(0.0, 1.0, 0.2, 1.0);

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
	vec2 uv = SCREEN_UV * 20.0;
	// vertical scroll
	uv.y += TIME * 5.0 * (hash(vec2(floor(uv.x), 0.0)) + 0.5);
	
	float n = noise(uv);
	
	if (n > 0.8) {
		ALBEDO = rain_color.rgb;
		EMISSION = rain_color.rgb * 2.0;
	} else {
		ALBEDO = base_color.rgb;
	}
}
