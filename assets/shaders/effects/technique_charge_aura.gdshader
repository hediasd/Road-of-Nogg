// Owned wall-and-ground shader for the polygonal technique-charge aura.
//
// `aura_mask` is sampled only for opacity. The shader owns the yellow grade so
// low-alpha RGB cannot introduce dark or coloured filtering fringes. AURA-1 is
// deliberately static; AURA-2 will add deterministic playback-time motion.

shader_type spatial;
render_mode unshaded, blend_mix, depth_draw_never, cull_back;

uniform sampler2D aura_mask : source_color, filter_nearest, repeat_disable;
uniform vec4 aura_color : source_color = vec4(1.0, 0.941, 0.541, 1.0);
uniform int layer_kind = 0;
uniform float opacity = 0.65;
uniform float emission_energy = 0.35;
uniform float lifecycle_visibility = 1.0;

uniform float ground_inner_radius = 0.36;
uniform float ground_outer_radius = 0.49;
uniform float ground_edge_softness = 0.025;
uniform float ground_fill_alpha = 0.16;

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
		vec2 centred = UV * 2.0 - 1.0;
		float radius = length(centred) * 0.5;
		float inner_edge = smoothstep(
			ground_inner_radius - ground_edge_softness,
			ground_inner_radius + ground_edge_softness,
			radius
		);
		float outer_edge = 1.0 - smoothstep(
			ground_outer_radius - ground_edge_softness,
			ground_outer_radius + ground_edge_softness,
			radius
		);
		float rim = inner_edge * outer_edge;
		float fill = (
			1.0 - smoothstep(0.0, ground_outer_radius, radius)
		) * ground_fill_alpha;
		float grain = mix(
			0.72,
			1.0,
			texture(aura_mask, vec2(UV.x, 0.86 + UV.y * 0.08)).a
		);
		mask_alpha = max(rim, fill) * grain;
	}

	ALBEDO = aura_color.rgb;
	EMISSION = aura_color.rgb * emission_energy;
	ALPHA = mask_alpha * opacity * lifecycle_visibility;
}
