// Owned wall-and-ground shader for the polygonal technique-charge aura.
//
// `aura_mask` is sampled only for opacity. The shader owns the yellow grade so
// low-alpha RGB cannot introduce dark or coloured filtering fringes. AURA-1 is
// deliberately static; AURA-2 will add deterministic playback-time motion.

shader_type spatial;
render_mode unshaded, blend_mix, depth_draw_never, cull_disabled;

uniform sampler2D aura_mask : source_color, filter_nearest, repeat_disable;
uniform vec4 aura_color : source_color = vec4(1.0, 0.941, 0.541, 1.0);
uniform int layer_kind = 0;
uniform float opacity = 0.65;
uniform float emission_energy = 0.35;
uniform float lifecycle_visibility = 1.0;

uniform float ground_spill_inner = 0.18;
uniform float ground_spill_outer = 0.50;
uniform float ground_spill_alpha = 0.42;

// AURA-2 motion. `playback_time` is the effect's own normalized timeline,
// pushed by the playback; the shader never reads TIME. That is what makes a
// normalized seek land on exactly the image the same seek produced before, and
// what makes pause and speed scaling free rather than special cases.
uniform float playback_time = 0.0;
uniform float playback_seed = 0.0;
uniform float noise_scale_coarse = 3.0;
uniform float noise_scale_fine = 11.0;
uniform float noise_rise_speed = 0.55;
uniform float flicker_amount = 0.16;
uniform float displacement_u = 0.055;
uniform float wall_bottom_strength = 0.38;

float hash21(vec2 p) {
	vec2 h = fract(p * vec2(123.34, 456.21));
	h += dot(h, h + 45.32);
	return fract(h.x * h.y);
}

float value_noise(vec2 p) {
	vec2 cell = floor(p);
	vec2 f = fract(p);
	f = f * f * (3.0 - 2.0 * f);
	float a = hash21(cell);
	float b = hash21(cell + vec2(1.0, 0.0));
	float c = hash21(cell + vec2(0.0, 1.0));
	float d = hash21(cell + vec2(1.0, 1.0));
	return mix(mix(a, b, f.x), mix(c, d, f.x), f.y);
}

// Charge noise, sampled in the wall's own UV. It scrolls downward in sample
// space so the pattern reads as rising, and the seed only ever offsets the
// sample point, so two seeds are two draws of the same authored material
// rather than two different materials.
float charge_noise(vec2 uv) {
	vec2 drift = vec2(0.0, playback_time * noise_rise_speed);
	// The seed is added *after* scaling, never before. Scaling it first
	// multiplies the offset by the noise scale and pushes the hash's fract()
	// into float32 quantisation, where every seed collapses to the same
	// pattern — which is exactly what the seed-variation check caught.
	float coarse = value_noise(
		uv * noise_scale_coarse - drift + vec2(playback_seed, 0.0)
	);
	float fine = value_noise(
		uv * noise_scale_fine - drift * 1.7 + vec2(0.0, playback_seed)
	);
	return mix(coarse, fine, 0.35);
}

void vertex() {
	// Bottom-anchored height flutter. The displacement scales by the square of
	// the height fraction, so base vertices are pinned to the ground exactly —
	// "its base never lifts" is a property of the curve, not of a small number
	// that could be tuned upward by accident. The amplitude stays small on
	// purpose: a large one grows flame tongues, and this charges rather than
	// burns.
	if (layer_kind == 0) {
		float rise = UV.y * UV.y;
		float lift = value_noise(
			vec2(UV.x * noise_scale_coarse, playback_time * 1.6)
				+ vec2(playback_seed, playback_seed)
		) - 0.5;
		VERTEX.y += lift * 2.0 * displacement_u * rise;
	}
}

void fragment() {
	float mask_alpha = 0.0;
	if (layer_kind == 0) {
		// The authored mask reserves transparent headroom. Remap its active
		// range over the full mesh so the prism reaches character height while
		// retaining a faint, broadly level top edge.
		float sample_v = mix(0.34, 1.0, UV.y);
		float vertical_density = mix(wall_bottom_strength, 1.0, UV.y);
		float base = texture(aura_mask, vec2(UV.x, sample_v)).a * vertical_density;

		// Noise modulates the authored density rather than replacing it, so the
		// mask still owns the silhouette and the noise only breaks it up. The
		// floor matters: allowed to reach zero, the wall drops out between
		// noise cells and reads as television static instead of charge.
		mask_alpha = base * mix(0.55, 1.15, charge_noise(UV));
	} else {
		// A radial spill centred on the source, not a rim. Radii are in plane
		// UV: the 1.86u plane puts its edge midpoint at 0.50 and the 0.74u wall
		// line at 0.398, so the spill still carries roughly a quarter of its
		// peak where the wall meets the ground and reaches zero before the
		// square plane's corners can show as geometry.
		vec2 centred = UV * 2.0 - 1.0;
		float radius = length(centred) * 0.5;
		float spill = 1.0 - smoothstep(
			ground_spill_inner,
			ground_spill_outer,
			radius
		);

		// Grain is sampled planar, across the plane's own UV. Driving the mask's
		// v axis from radius instead — to mirror the way the wall's gradient
		// climbs — turns every row of the mask into a concentric ring and the
		// spill reads as ripples. The shared identity comes from sampling the
		// same mask, not from matching its axes. An angular u would seam at
		// +/-PI under repeat_disable, so it is not used either.
		float grain = mix(0.80, 1.0, texture(aura_mask, UV).a);
		mask_alpha = spill * ground_spill_alpha * grain;
	}

	// Brightness flutter is one value for the whole effect at a given instant,
	// not a per-fragment sample, so the aura pulses as a single body. Sampled
	// per fragment it would boil, which is the failure mode the reference never
	// shows. Both layers read the same flutter so the wall and its ground spill
	// stay locked to each other.
	float flutter = 1.0 + (
		value_noise(vec2(playback_time * 3.1 + playback_seed, 0.37)) - 0.5
	) * 2.0 * flicker_amount;

	ALBEDO = aura_color.rgb;
	EMISSION = aura_color.rgb * emission_energy;
	ALPHA = clamp(mask_alpha * opacity * lifecycle_visibility * flutter, 0.0, 1.0);
}
