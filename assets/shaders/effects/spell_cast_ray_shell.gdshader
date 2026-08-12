// spell_cast_ray_shell.gdshader
// A flared shell of light for the generic spell-cast aura.
//
// The rays are striations *on* this shell, not separate objects. That is what
// the reference frame actually shows: a filled cup of light whose individual
// rays are legible inside it, with the pointed ends living in a ragged top
// edge rather than in a fan of free-standing spikes.
//
// The mesh is a unit cylinder. This shader reshapes it into a truncated cone
// from `base_radius`, `rim_radius`, and `height`, so the silhouette is a
// uniform, not baked geometry. UV.x runs around the shell, UV.y from its seat
// (0) to its rim (1).
//
// Every stripe owns its own width, brightness, top height, and eruption delay,
// all derived by hash from its index and the effect's seed. That gives a
// staggered, ragged eruption out of one draw call, and keeps every frame a
// pure function of normalized time.
//
// Drawn double-sided and additively: the far wall shows through the near one,
// and where they overlap the interior builds toward white. That overlap is the
// whole reason the cup reads as filled rather than as an outline.

shader_type spatial;
render_mode unshaded, blend_add, depth_draw_never, cull_disabled;

// ---------------------------------------------------------------------------
// Uniforms
// ---------------------------------------------------------------------------

uniform vec4 aura_color : source_color = vec4(0.6, 0.9, 0.9, 1.0);
uniform float burst_progress : hint_range(0.0, 1.0) = 0.0;
uniform float shell_seed = 0.0;

uniform float base_radius = 0.55;
uniform float rim_radius = 1.45;
uniform float height = 3.6;
uniform float open_start : hint_range(0.0, 1.0) = 0.42;

uniform float stripe_count = 26.0;
uniform float stripe_width_min : hint_range(0.0, 1.0) = 0.18;
uniform float stripe_width_max : hint_range(0.0, 1.0) = 0.62;
uniform float stripe_alpha : hint_range(0.0, 1.0) = 0.36;
uniform float wall_glow_alpha : hint_range(0.0, 1.0) = 0.10;

uniform float tooth_min : hint_range(0.0, 1.0) = 0.55;
uniform float tooth_max : hint_range(0.0, 1.0) = 1.0;
uniform float tooth_soft : hint_range(0.01, 1.0) = 0.22;

uniform float edge_gain : hint_range(0.0, 6.0) = 1.6;
uniform float edge_power : hint_range(0.1, 8.0) = 2.5;

uniform float base_white_mix : hint_range(0.0, 1.0) = 0.88;
uniform float body_white_mix : hint_range(0.0, 1.0) = 0.34;
uniform float rim_deepen : hint_range(0.0, 2.0) = 0.85;
uniform float body_gradient_end : hint_range(0.0, 1.0) = 0.35;
uniform float rim_gradient_start : hint_range(0.0, 1.0) = 0.45;
uniform float emission_energy : hint_range(0.0, 8.0) = 2.3;
uniform float seat_glow_height : hint_range(0.01, 1.0) = 0.18;

uniform float eruption_start : hint_range(0.0, 1.0) = 0.03;
uniform float eruption_span : hint_range(0.01, 1.0) = 0.16;
uniform float stagger_span : hint_range(0.0, 1.0) = 0.16;
uniform float hold_end : hint_range(0.01, 1.0) = 0.44;
uniform float decay_end : hint_range(0.01, 1.0) = 0.88;
uniform float overshoot_amount : hint_range(0.0, 1.0) = 0.16;
uniform float decay_stretch : hint_range(0.0, 1.0) = 0.14;

varying float v_height_scale;

// ---------------------------------------------------------------------------
// Shared helpers
// ---------------------------------------------------------------------------

float hash1(float n) {
	return fract(sin(n * 127.1 + shell_seed * 13.7) * 43758.5453);
}

// Eased-out growth plus an overshoot that peaks mid-window and is exactly zero
// at both ends, so the shell snaps past its size and settles on it without
// drifting.
float rise(float local) {
	float grow = 1.0 - pow(1.0 - local, 3.0);
	return grow + overshoot_amount * sin(PI * local) * (1.0 - local);
}

float fade_at(float progress) {
	return 1.0 - smoothstep(hold_end, decay_end, progress);
}

// ---------------------------------------------------------------------------
// Vertex
// ---------------------------------------------------------------------------

void vertex() {
	// The authored mesh is a unit cylinder; the cone lives in these uniforms.
	vec3 dir = normalize(vec3(VERTEX.x, 0.0, VERTEX.z));
	float along = UV.y;

	float fade = fade_at(burst_progress);
	// One overall opening drives the flare. Per-stripe timing is a fragment
	// concern, because a stripe's ragged top is a mask, not geometry.
	float open = clamp(
			rise(clamp((burst_progress - eruption_start)
					/ max(eruption_span + stagger_span, 0.0001), 0.0, 1.0)),
			0.0, 1.2);
	v_height_scale = 1.0 + decay_stretch * (1.0 - fade);

	float radius = mix(base_radius, rim_radius, along) * mix(open_start, 1.0, open);
	VERTEX = vec3(
			dir.x * radius,
			along * height * v_height_scale,
			dir.z * radius);
	NORMAL = dir;
}

// ---------------------------------------------------------------------------
// Fragment
// ---------------------------------------------------------------------------

void fragment() {
	float around = UV.x;
	float along = clamp(UV.y, 0.0, 1.0);

	float stripe = floor(around * stripe_count);
	float within = fract(around * stripe_count);
	float width_roll = hash1(stripe);
	float tooth_roll = hash1(stripe + 31.0);
	float delay_roll = hash1(stripe + 67.0);
	float bright_roll = hash1(stripe + 101.0);

	// A hard-edged band, deliberately not a smooth falloff: under additive
	// blending a soft edge is a glow, and a glow is the opposite of a ray.
	float across = abs(within - 0.5) * 2.0;
	float band_width = mix(stripe_width_min, stripe_width_max, width_roll);
	float band = 1.0 - step(band_width, across);
	// A dimmer wash between the bands keeps the wall reading as a wall rather
	// than as a picket fence with holes in it.
	float wash = 1.0 - across;

	// Each stripe erupts on its own delay and stops at its own height, which is
	// what makes the rim ragged and the eruption a wave rather than a curtain.
	float local = clamp(
			(burst_progress - eruption_start - delay_roll * stagger_span)
					/ max(eruption_span, 0.0001),
			0.0, 1.0);
	float top = mix(tooth_min, tooth_max, tooth_roll) * clamp(rise(local), 0.0, 1.2);
	float tooth = 1.0 - smoothstep(max(top - tooth_soft, 0.0), top, along);

	// Brighter where the wall turns edge-on to the camera. On a shell that is
	// its silhouette, and it is most of what makes the cup read as a volume.
	float facing = 1.0 - abs(dot(normalize(NORMAL), normalize(VIEW)));
	float edge = 1.0 + edge_gain * pow(facing, edge_power);
	// Extra weight where the shell meets the ground.
	float seat = 1.0 + (1.0 - smoothstep(0.0, seat_glow_height, along));

	vec3 hot_color = mix(aura_color.rgb, vec3(1.0), base_white_mix);
	vec3 body_color = mix(aura_color.rgb, vec3(1.0), body_white_mix);
	vec3 rim_color = aura_color.rgb * rim_deepen;

	vec3 color = mix(hot_color, body_color, smoothstep(0.0, body_gradient_end, along));
	color = mix(color, rim_color, smoothstep(rim_gradient_start, 1.0, along));

	float energy = fade_at(burst_progress)
			* min(local * 6.0, 1.0)
			* mix(0.7, 1.0, bright_roll);
	float alpha = (band * stripe_alpha + wash * wall_glow_alpha)
			* tooth
			* edge
			* seat
			* energy;

	ALBEDO = color;
	EMISSION = color * emission_energy * edge * seat;
	ALPHA = clamp(alpha, 0.0, 1.0);
}
