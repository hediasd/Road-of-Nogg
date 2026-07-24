shader_type spatial;
render_mode unshaded;

float hash(vec2 p) {
    return fract(sin(dot(p, vec2(12.9898, 78.233))) * 43758.5453);
}

void vertex() {
	// Writhe and boil
	float r = hash(VERTEX.xy * TIME) * 0.1;
	VERTEX += NORMAL * r;
}

void fragment() {
	ALBEDO = vec3(0.0);
}
