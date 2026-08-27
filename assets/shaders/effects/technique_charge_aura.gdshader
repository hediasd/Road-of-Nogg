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

void fragment() {
	float mask_alpha = 0.0;
	if (layer_kind == 0) {
		// The authored mask reserves transparent headroom. Remap its active
		// range over the full mesh so the prism reaches character height while
		// retaining a faint, broadly level top edge.
		float sample_v = mix(0.34, 1.0, UV.y);
		float vertical_density = mix(0.38, 1.0, UV.y);
		mask_alpha = texture(aura_mask, vec2(UV.x, sample_v)).a * vertical_density;
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

	ALBEDO = aura_color.rgb;
	EMISSION = aura_color.rgb * emission_energy;
	ALPHA = mask_alpha * opacity * lifecycle_visibility;
}
