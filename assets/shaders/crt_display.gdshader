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
uniform float mask_strength : hint_range(0.0, 1.0) = 0.1;
uniform float mask_size : hint_range(1.0, 6.0) = 1.0;
// Darkens every other mask row, turning the vertical phosphor stripe into a
// two-dimensional dot grid. Zero leaves the stripe exactly as it was.
uniform float mask_dot_strength : hint_range(0.0, 1.0) = 0.0;
uniform float vignette_strength : hint_range(0.0, 0.6) = 0.2;
uniform float flicker_strength : hint_range(0.0, 0.1) = 0.02;
uniform float color_bleed : hint_range(0.0, 4.0) = 0.8;
uniform float noise_strength : hint_range(0.0, 0.2) = 0.03;
uniform float glow_strength : hint_range(0.0, 0.5) = 0.1;

// Maps the frame onto a three-stop ink ramp -- shadow, mid, paper -- driven by
// luminance. Applied after the tone controls and BEFORE the posterize, so
// `color_levels` bands the ramp rather than the original colour, and the dither
// then breaks those bands up. Zero strength is a no-op.
//
// A non-zero strength also REORDERS the pass: see the `ink_first` branch in
// fragment(). Inking a frame the mask has already multiplied down would push
// the whole image into the shadow stop -- the paper stop is only reachable if
// the ink ramp reads the image before the grid darkens it. So when duotone is
// on, the mask, scanline, vignette, and flicker are held back and applied last,
// which is also the physical order the look imitates: ink the panel, then print
// it through the grid.
uniform float duotone_strength : hint_range(0.0, 1.0) = 0.0;
uniform vec3 duotone_shadow : source_color = vec3(0.05, 0.03, 0.02);
uniform vec3 duotone_mid : source_color = vec3(0.85, 0.20, 0.12);
uniform vec3 duotone_paper : source_color = vec3(1.0, 0.94, 0.87);

float random_value(vec2 position) {
	return fract(sin(dot(position, vec2(12.9898, 78.233))) * 43758.5453);
}

void fragment() {
	vec2 texel_size = 1.0 / vec2(textureSize(screen_texture, 0));
	vec4 center = textureLod(screen_texture, SCREEN_UV, 0.0);
	vec3 color = center.rgb;

	bool ink_first = duotone_strength > 0.0;
	vec3 held_modulation = vec3(1.0);
	float held_noise = 0.0;

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

		vec3 phosphor_mask;
		if (ink_first) {
			// Ink dots, not phosphors. An RGB triad would put back exactly the
			// colour the ink ramp just took out -- a paper-white pixel comes
			// out red in an R column, green in a G column -- so the grid
			// darkens every channel equally, on a two-column period. Averaging
			// the triad instead would not work: its mean is the same at every
			// x, so the stripe would vanish entirely.
			float stripe = mod(floor(FRAGCOORD.x / max(mask_size, 1.0)), 2.0);
			phosphor_mask = vec3(1.0 - mask_strength * stripe);
		} else {
			float channel = mod(floor(FRAGCOORD.x / max(mask_size, 1.0)), 3.0);
			phosphor_mask = vec3(1.0 - mask_strength);
			if (channel < 1.0) {
				phosphor_mask.r = 1.0;
			} else if (channel < 2.0) {
				phosphor_mask.g = 1.0;
			} else {
				phosphor_mask.b = 1.0;
			}
		}
		float dot_row = mod(floor(FRAGCOORD.y / max(mask_size, 1.0)), 2.0);
		phosphor_mask *= 1.0 - mask_dot_strength * dot_row;

		vec2 centered_uv = UV * 2.0 - 1.0;
		float edge = smoothstep(0.35, 1.35, dot(centered_uv, centered_uv));
		float vignette = 1.0 - vignette_strength * edge;
		float flicker = 1.0 - flicker_strength * (
			0.5 + 0.5 * sin(TIME * 47.0)
		);
		float noise = (
			random_value(floor(FRAGCOORD.xy) + floor(TIME * 60.0)) - 0.5
		) * noise_strength;
		vec3 modulation = vec3(scanline) * phosphor_mask * vignette * flicker;
		if (ink_first) {
			held_modulation = modulation;
			held_noise = noise;
		} else {
			color = color * modulation + noise;
		}
	}

	float luminance = dot(color, vec3(0.299, 0.587, 0.114));
	color = mix(vec3(luminance), color, saturation);
	color = (color - 0.5) * contrast + 0.5;
	color *= brightness;

	if (duotone_strength > 0.0) {
		float ink = clamp(dot(color, vec3(0.299, 0.587, 0.114)), 0.0, 1.0);
		vec3 inked = ink < 0.5
			? mix(duotone_shadow, duotone_mid, ink * 2.0)
			: mix(duotone_mid, duotone_paper, (ink - 0.5) * 2.0);
		color = mix(color, inked, duotone_strength);
	}

	float dither = (
		random_value(floor(FRAGCOORD.xy)) - 0.5
	) * dither_strength;
	float levels = floor(color_levels + 0.5);
	if (levels >= 2.0) {
		color = floor(clamp(color + dither, 0.0, 1.0) * (levels - 1.0) + 0.5) / (levels - 1.0);
	} else {
		color += dither;
	}

	if (ink_first) {
		color = color * held_modulation + held_noise;
	}

	COLOR = vec4(clamp(color, 0.0, 1.0), center.a);
}