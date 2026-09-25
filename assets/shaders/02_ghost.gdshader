shader_type spatial;
render_mode depth_draw_always, blend_mix, cull_disabled;

uniform vec4 ghost_color : source_color = vec4(0.2, 0.9, 0.6, 0.7);

// Simple pseudo-random noise
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
	vec2 uv = UV + vec2(0.0, TIME * 0.5);
	float n = noise(uv * 10.0);
	
	float rim = 1.0 - dot(normalize(VIEW), NORMAL);
	rim = smoothstep(0.2, 0.8, rim);
	
	// Fade out near the bottom
	float fade = smoothstep(-0.2, 0.5, VERTEX.y);
	
	ALBEDO = ghost_color.rgb * (1.0 + rim);
	ALPHA = ghost_color.a * fade * (0.5 + 0.5 * n) * rim;
}
