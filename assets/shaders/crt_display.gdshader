shader_type canvas_item;

uniform sampler2D screen_texture : hint_screen_texture, filter_nearest;
uniform float scanline_strength : hint_range(0.0, 0.5) = 0.12;
uniform float mask_strength : hint_range(0.0, 0.25) = 0.04;
uniform float vignette_strength : hint_range(0.0, 0.5) = 0.16;
uniform float flicker_strength : hint_range(0.0, 0.1) = 0.012;

void fragment() {
	vec4 source = textureLod(screen_texture, SCREEN_UV, 0.0);
	float scanline = 1.0 - scanline_strength * (
		0.5 + 0.5 * sin(FRAGCOORD.y * 3.14159265)
	);

	float channel = mod(floor(FRAGCOORD.x), 3.0);
	vec3 phosphor_mask = vec3(1.0 - mask_strength);
	if (channel < 1.0) {
		phosphor_mask.r = 1.0;
	} else if (channel < 2.0) {
		phosphor_mask.g = 1.0;
	} else {
		phosphor_mask.b = 1.0;
	}

	vec2 centered_uv = UV * 2.0 - 1.0;
	float edge = smoothstep(0.35, 1.35, dot(centered_uv, centered_uv));
	float vignette = 1.0 - vignette_strength * edge;
	float flicker = 1.0 - flicker_strength * (
		0.5 + 0.5 * sin(TIME * 47.0)
	);

	COLOR = vec4(
		source.rgb * scanline * phosphor_mask * vignette * flicker,
		source.a
	);
}