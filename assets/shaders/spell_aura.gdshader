// spell_aura.gdshader
// Ground-plane aura shader for spell-casting VFX.
//
// Applied to a flat PlaneMesh laid at the caster's feet.
// Uses polar-coordinate noise sampling for organic, swirling edge distortion
// and a bright-center radial gradient for the glow falloff.
//
// Driven by a single `lifetime_progress` uniform (0→1) from GDScript:
//   0.0 = just spawned (tiny, bright center flash)
//   0.5 = ring fully expanded
//   1.0 = fully faded out
// playback_time is the effect-local clock for noise and freezes with it.

shader_type spatial;
render_mode unshaded, blend_add, depth_draw_never, cull_disabled;

// ---------------------------------------------------------------------------
// Uniforms
// ---------------------------------------------------------------------------

uniform vec4 aura_color : source_color = vec4(0.2, 0.6, 1.0, 1.0);
uniform sampler2D noise_tex : repeat_enable, filter_linear;
uniform float lifetime_progress : hint_range(0.0, 1.0) = 0.0;
uniform float playback_time = 0.0;
uniform float intensity : hint_range(0.0, 12.0) = 6.0;
uniform float ring_width : hint_range(0.01, 0.3) = 0.12;
uniform float edge_distortion : hint_range(0.0, 0.15) = 0.07;
uniform float scroll_speed : hint_range(0.0, 2.0) = 0.4;

// ---------------------------------------------------------------------------
// Fragment
// ---------------------------------------------------------------------------

void fragment() {
	// --- Polar coordinates ---
	vec2 centered = UV - vec2(0.5);
	float dist = length(centered);
	float angle = atan(centered.y, centered.x); // -PI .. PI

	// --- Scrolling noise in polar space ---
	// Wrapping the angle / TAU gives a seamless horizontal scroll around the ring.
	vec2 noise_uv = vec2(
		angle / (2.0 * 3.14159265) + playback_time * scroll_speed,
		dist * 2.5
	);
	float noise_val = texture(noise_tex, noise_uv).r;
	// Also sample at a different scale for layered detail.
	vec2 noise_uv2 = vec2(
		-angle / (2.0 * 3.14159265) + playback_time * scroll_speed * 0.6,
		dist * 4.0 + 0.37
	);
	float noise_val2 = texture(noise_tex, noise_uv2).r;
	float combined_noise = mix(noise_val, noise_val2, 0.45);

	// --- Distort the effective distance with noise ---
	float distorted_dist = dist + (combined_noise - 0.5) * edge_distortion;

	// --- Ring mask that expands outward over lifetime ---
	// ring_center goes from nearly 0 (flash) to 0.42 (full size).
	float ring_center = mix(0.04, 0.42, lifetime_progress);
	float inner = smoothstep(ring_center - ring_width * 0.5, ring_center, distorted_dist);
	float outer = 1.0 - smoothstep(ring_center, ring_center + ring_width, distorted_dist);
	float ring_mask = inner * outer;

	// Boost the ring edges slightly with the noise for an irregular, fiery look.
	ring_mask *= (0.75 + 0.5 * combined_noise);

	// --- Soft center glow (disappears as ring expands) ---
	float center_glow = (1.0 - smoothstep(0.0, 0.28, distorted_dist));
	center_glow *= (1.0 - smoothstep(0.0, 0.45, lifetime_progress));

	// --- Fade-out at end of life ---
	float fade = 1.0 - smoothstep(0.65, 1.0, lifetime_progress);

	float alpha = clamp((ring_mask + center_glow * 0.7) * fade, 0.0, 1.0);

	// --- Colour gradient: hot white core → element colour → dark edge ---
	// dist 0→0.15: white (blow-out core)
	// dist 0.15→0.38: element colour
	// dist 0.38+: element colour at lower brightness
	vec3 core_color = vec3(1.0, 1.0, 1.0);
	vec3 mid_color = aura_color.rgb;
	vec3 edge_color = aura_color.rgb * 0.55;

	vec3 color = mix(core_color, mid_color, smoothstep(0.0, 0.22, dist));
	color = mix(color, edge_color, smoothstep(0.28, 0.45, dist));

	// Boost brightness with noise variation for the flame-like hot spots.
	float brightness = intensity * (0.7 + 0.6 * combined_noise);
	// Extra punch right at lifetime_progress=0 for the initial flash.
	brightness *= (1.0 + 1.8 * (1.0 - smoothstep(0.0, 0.18, lifetime_progress)));

	ALBEDO = color;
	EMISSION = color * brightness;
	ALPHA = alpha;
}
