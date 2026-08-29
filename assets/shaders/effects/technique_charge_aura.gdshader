// Owned wall-and-ground shader for the polygonal technique-charge aura.
//
// `aura_mask` is sampled only for opacity. The shader owns the yellow grade so
// low-alpha RGB cannot introduce dark or coloured filtering fringes.
//
// Motion is a pure function of the playback clock this material is handed and a
// small per-cast seed; the shader never reads TIME. That is what makes a
// normalized seek land on exactly the image the same seek produced before, and
// what makes pause and speed scaling free rather than special cases.

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

// `playback_time` is the effect's own normalized timeline and
// `playback_seconds` the same clock in seconds, both pushed by the playback.
uniform float playback_time = 0.0;
uniform float playback_seconds = 0.0;
uniform float playback_seed = 0.0;
uniform float noise_scale_coarse = 3.0;
uniform float noise_scale_fine = 11.0;
uniform float noise_rise_speed = 0.55;
uniform float flicker_amount = 0.16;
uniform float displacement_u = 0.055;
uniform float wall_bottom_strength = 0.38;

// Ring stack. One entry per ring, indexed by the identity baked into COLOR.r
// when the mesh was built. Every one of these is pushed once at build time;
// nothing here changes per frame.
//
// They are deliberately safe when left unset: an unpushed array reads as zero,
// which the guards below resolve to a ring standing at its full built extension
// and not moving, rather than to a division by zero.
uniform float ring_base_radius[3];
uniform float ring_ceiling[3];
uniform float ring_launch[3];
uniform float ring_rise[3];
uniform float ring_period[3];
uniform float ring_decay[3];
uniform float ring_overshoot[3];
uniform float ring_breath_scale[3];
// Grade. RING_TIP_BRIGHT is a blend weight rather than a bool because uniform
// arrays in this shader are float only; 0 keeps the core's shipped base-faint
// curve, 1 switches a face to the flares' tip-bright one.
uniform float ring_opacity[3];
uniform float ring_tip_bright[3];

uniform float breath_min = 0.030;
uniform float breath_max = 0.075;
uniform float breath_face_mix = 0.45;
// Two unrelated rates so the idle has no readable loop or countable beat.
uniform float breath_rate_slow = 1.7;
uniform float breath_rate_fast = 4.3;
// How far the breath's height factor is amplified into brightness and into the
// top-edge flutter. Height alone is a couple of pixels at the battle camera's
// framing; brightness is legible at any size.
uniform float breath_bright_coupling = 1.6;
uniform float breath_flutter_coupling = 1.0;
uniform float ring_phase_a1 = 0.045;
uniform float ring_phase_a2 = 0.022;

// How strongly the ground's brightness tracks the core ring's own bounce
// (index 0), and the floor it will not fall under even mid-dip. A wall
// bouncing off a completely unlit floor stops reading as one source with its
// own ground contact.
uniform float ground_pulse_strength = 0.55;
uniform float ground_pulse_floor = 0.55;

const float RING_TAU = 6.283185307179586;

// How far this fragment's ring is currently extended, as a fraction of the
// geometry that was built. The fragment stage needs it to hold the charge noise
// still in world units while the ring grows.
varying float v_extension;
// This ring's breath factor at the instant this vertex was placed, carried to
// the fragment stage so alpha can swing with the same idle that moves height.
varying float v_breathFactor;

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

// Charge noise, sampled in the ring's own mesh space. It scrolls so the pattern
// reads as rising, and the seed only ever offsets the sample point, so two
// seeds are two draws of the same authored material rather than two different
// materials.
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

// Damped-spring entrance for one ring: a launch to peak, then an oscillation
// that crosses the resting height and decays away. The two halves meet at the
// peak by construction -- the cosine is 1 there -- so there is no join to hide.
float ring_bounce(int index, float seconds) {
	float t = seconds - ring_launch[index];
	if (t <= 0.0) {
		return 0.0;
	}
	float rise = max(ring_rise[index], 0.0001);
	if (t < rise) {
		float p = t / rise;
		return (1.0 + ring_overshoot[index]) * (1.0 - pow(1.0 - p, 3.0));
	}
	float tau = t - rise;
	return 1.0 + ring_overshoot[index]
		* exp(-ring_decay[index] * tau)
		* cos(RING_TAU / max(ring_period[index], 0.0001) * tau);
}

// The idle never stops, and it grows into its full amplitude on the same decay
// term that kills the core ring's bounce: it never competes with the entrance,
// and it arrives exactly where the aura would otherwise go still.
float breath_amplitude(float seconds) {
	float tau = max(seconds - ring_rise[0], 0.0);
	return breath_max - (breath_max - breath_min) * exp(-ring_decay[0] * tau);
}

// Two unrelated rates, so the idle has no readable loop and no countable beat.
// The per-face term is a three-lobed function of the face's own azimuth rather
// than an independent sample per face: neighbouring panels stay close, which is
// what holds the step at their shared corner inside what the mask's ragged top
// edge can absorb. The mask has no side margin, so nothing else hides it.
float ring_breath(int index, float seconds, float face_angle) {
	float amount = breath_amplitude(seconds) * ring_breath_scale[index];
	float slow = seconds * breath_rate_slow;
	float fast = seconds * breath_rate_fast;
	float shared =
		(value_noise(vec2(slow, 3.1 + playback_seed)) - 0.5) * 1.35
		+ (value_noise(vec2(fast, 8.7 + playback_seed)) - 0.5) * 0.65;
	float own =
		(value_noise(vec2(slow + sin(3.0 * face_angle + 0.6) * 0.9, 3.1 + playback_seed)) - 0.5) * 1.35
		+ (value_noise(vec2(fast + sin(3.0 * face_angle + 2.2) * 0.7, 8.7 + playback_seed)) - 0.5) * 0.65;
	return 1.0 + amount * mix(shared, own, breath_face_mix);
}

void vertex() {
	if (layer_kind != 0) {
		v_extension = 1.0;
		v_breathFactor = 1.0;
	} else {
		int ring = int(round(COLOR.r * 2.0));

		// Phase comes from the vertex's own position, not from its face.
		// Neighbouring faces are built with coincident corner vertices, so a
		// position-derived phase resolves to the same value on both sides of
		// every corner and the rim stays watertight however far the ring
		// spreads. It also has to be periodic in the angle: a lag that ramps
		// linearly with theta wraps at +/-PI and tears at exactly one corner.
		float theta = atan(VERTEX.z, VERTEX.x);
		float phase = ring_phase_a1 * sin(theta + playback_seed)
			+ ring_phase_a2 * sin(2.0 * theta + 1.7 * playback_seed + 1.1);

		// The breath is taken per face instead, from the face's own azimuth --
		// panels shimmering against each other, which its small amplitude can
		// afford where the bounce's amplitude could not.
		float face_angle = atan(NORMAL.z, NORMAL.x);
		float breath = ring_breath(ring, playback_seconds, face_angle);

		float factor = ring_bounce(ring, playback_seconds - phase) * breath;
		float extension = clamp(factor / max(ring_ceiling[ring], 0.0001), 0.0, 1.0);

		// Base and tip of a ring sit on the same radial line, so the base is
		// recoverable from the built vertex and the ring's own radius alone.
		// The mesh is built at the ceiling extension, which is what stops the
		// factor above from ever asking for geometry that does not exist.
		vec2 radial = normalize(vec2(VERTEX.x, VERTEX.z));
		vec3 anchored = vec3(radial.x, 0.0, radial.y) * ring_base_radius[ring];
		VERTEX = mix(anchored, VERTEX, extension);

		// Bottom-anchored flutter. UV.y is 1 at the base and 0 at the tip, so
		// the height fraction is its complement -- the shipped code squared
		// UV.y directly and called that the height fraction, which pinned the
		// tip and fluttered the foot, the exact opposite of what its own
		// comment claimed. Squaring the complement pins the base as a property
		// of the curve rather than of a small amplitude, and scaling by the
		// extension keeps the flutter at the leading edge as the ring grows.
		// The amplitude stays small on purpose: a large one grows flame
		// tongues, and this charges rather than burns.
		//
		// The flutter amount itself rides the breath, the same way alpha will
		// in the fragment stage: the silhouette gets choppier on a swell and
		// calms on an ebb instead of fluttering at one constant amount.
		float along = 1.0 - UV.y;
		float flutter_amount = displacement_u
			* (1.0 + breath_flutter_coupling * (breath - 1.0));
		float lift = value_noise(
			vec2(UV.x * noise_scale_coarse, playback_time * 1.6)
				+ vec2(playback_seed, playback_seed)
		) - 0.5;
		VERTEX.y += lift * 2.0 * flutter_amount * along * along * extension;

		v_extension = extension;
		v_breathFactor = breath;
	}
}

void fragment() {
	float mask_alpha = 0.0;
	float layer_opacity = opacity;
	float bright_coupling = 1.0;
	if (layer_kind == 0) {
		int ring = int(round(COLOR.r * 2.0));
		float along = 1.0 - UV.y;

		// The authored mask reserves transparent headroom. Remap its active
		// range over the full mesh so the prism reaches character height while
		// retaining a faint, broadly level top edge. The geometry itself
		// shortens as the ring retracts, so this remap holds the authored taper
		// at the leading edge at every extension.
		float sample_v = mix(0.34, 1.0, UV.y);

		// The core keeps its shipped base-faint curve, dim at the foot and
		// strong at the top. A flare inverts that: near-nothing where it meets
		// the floor, brightest through its leading third and tapering at the
		// very tip so that edge stays soft rather than a hard bright line --
		// stacking three rings' density at the foot would otherwise build
		// exactly the solid collar WALL_BOTTOM_STRENGTH exists to prevent.
		float base_faint = mix(wall_bottom_strength, 1.0, UV.y);
		float tip_bright = smoothstep(0.0, 0.38, along)
			* (1.0 - 0.85 * smoothstep(0.78, 1.0, along));
		float vertical_density = mix(base_faint, tip_bright, ring_tip_bright[ring]);
		float base = texture(aura_mask, vec2(UV.x, sample_v)).a * vertical_density;

		// Noise is sampled against the ring's world extent, not against its UV.
		// Sampled in UV it would squash and stretch with the ring, and since the
		// height is now never constant, the texture would look like the thing
		// that was breathing instead of the body.
		vec2 mesh_uv = vec2(UV.x, along * v_extension);

		// Noise modulates the authored density rather than replacing it, so the
		// mask still owns the silhouette and the noise only breaks it up. The
		// floor matters: allowed to reach zero, the wall drops out between
		// noise cells and reads as television static instead of charge.
		mask_alpha = base * mix(0.55, 1.15, charge_noise(mesh_uv));
		layer_opacity = ring_opacity[ring];
		// Alpha swings with the same breath that moves height, amplified by
		// BREATH_BRIGHT_COUPLING so the idle reads at the battle camera's
		// framing even though a few pixels of height motion would not.
		bright_coupling = 1.0 + breath_bright_coupling * (v_breathFactor - 1.0);
	} else {
		// A radial spill centred on the source, not a rim. Radii are in plane
		// UV: the plane's edge midpoint is 0.50, and it is sized against the
		// outer flare's built radius so that ring's own peak still lands inside
		// the spill rather than outside its own light (see GROUND_DIAMETER_U).
		// Reaches zero before the square plane's corners can show as geometry.
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

		// The ground answers the core ring's own bounce rather than sitting at
		// a flat brightness under it: it re-flares on every crest and dims on
		// every dip, floored so a deep dip never reads as the floor going dark.
		bright_coupling = max(
			1.0 + ground_pulse_strength * (ring_bounce(0, playback_seconds) - 1.0),
			ground_pulse_floor
		);
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
	ALPHA = clamp(
		mask_alpha * layer_opacity * bright_coupling * lifecycle_visibility * flutter,
		0.0,
		1.0
	);
}
