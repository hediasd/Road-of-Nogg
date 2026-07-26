shader_type canvas_item;

uniform sampler2D screen_texture : hint_screen_texture, filter_nearest;
uniform bool crt_enabled = false;

uniform float brightness : hint_range(0.5, 1.5) = 1.0;
uniform float contrast : hint_range(0.5, 1.5) = 1.0;
uniform float saturation : hint_range(0.0, 2.0) = 1.0;
uniform float color_levels : hint_range(0.0, 64.0) = 0.0;
uniform float dither_strength : hint_range(0.0, 0.15) = 0.0;

uniform float scanline_strength : hint_range(0.0, 0.5) = 0.22;
uniform float scanline_size : hint_range(0.5, 4.0) = 1.0;
uniform float mask_strength : hint_range(0.0, 0.3) = 0.1;
uniform float mask_size : hint_range(1.0, 6.0) = 1.0;
uniform float vignette_strength : hint_range(0.0, 0.6) = 0.2;
uniform float flicker_strength : hint_range(0.0, 0.1) = 0.02;
uniform float color_bleed : hint_range(0.0, 4.0) = 0.8;
uniform float noise_strength : hint_range(0.0, 0.2) = 0.03;
uniform float glow_strength : hint_range(0.0, 0.5) = 0.1;

float random_value(vec2 position) {
	return fract(sin(dot(position, vec2(12.9898, 78.233))) * 43758.5453);
}

void fragment() {
	vec2 texel_size = 1.0 / vec2(textureSize(screen_texture, 0));
	vec4 center = textureLod(screen_texture, SCREEN_UV, 0.0);
	vec3 color = center.rgb;

	if (crt_enabled) {
		vec2 bleed_offset = vec2(texel_size.x * color_bleed, 0.0);
		color = vec3(
			textureLod(screen_texture, SCREEN_UV + bleed_offset, 0.0).r,
			center.g,
			textureLod(screen_texture, SCREEN_UV - bleed_offset, 0.0).b
		);

		vec3 neighbor_color = (
			textureLod(screen_texture, SCREEN_UV + vec2(texel_size.x, 0.0), 0.0).rgb +
			textureLod(screen_texture, SCREEN_UV - vec2(texel_size.x, 0.0), 0.0).rgb +
			textureLod(screen_texture, SCREEN_UV + vec2(0.0, texel_size.y), 0.0).rgb +
			textureLod(screen_texture, SCREEN_UV - vec2(0.0, texel_size.y), 0.0).rgb
		) * 0.25;
		color += neighbor_color * glow_strength * 0.35;

		float line_phase = FRAGCOORD.y * 3.14159265 / max(scanline_size, 0.5);
		float scanline = 1.0 - scanline_strength * (
			0.5 + 0.5 * sin(line_phase)
		);

		float channel = mod(floor(FRAGCOORD.x / max(mask_size, 1.0)), 3.0);
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
		float noise = (
			random_value(floor(FRAGCOORD.xy) + floor(TIME * 60.0)) - 0.5
		) * noise_strength;
		color = color * scanline * phosphor_mask * vignette * flicker + noise;
	}

	float luminance = dot(color, vec3(0.299, 0.587, 0.114));
	color = mix(vec3(luminance), color, saturation);
	color = (color - 0.5) * contrast + 0.5;
	color *= brightness;

	float dither = (
		random_value(floor(FRAGCOORD.xy)) - 0.5
	) * dither_strength;
	float levels = floor(color_levels + 0.5);
	if (levels >= 2.0) {
		color = floor(clamp(color + dither, 0.0, 1.0) * (levels - 1.0) + 0.5) / (levels - 1.0);
	} else {
		color += dither;
	}

	COLOR = vec4(clamp(color, 0.0, 1.0), center.a);
}