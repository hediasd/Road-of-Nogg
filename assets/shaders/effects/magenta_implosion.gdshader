shader_type particles;
render_mode disable_force, disable_velocity;

// Inward spiral and radial discharge for the data-selected magenta implosion.
//
// Forked from fire_storm_vortex.gdshader, which was already most of this
// running backwards: a spiral whose angular rate rises over the travel,
// per-particle lifetime phase off INDEX, and onset_fraction. What changed is
// the sign and the mapping -- the fire column's radius is a function of height
// and rises, this one's is a function of the beat timeline and falls.
//
// Every value below is a pure function of INDEX and playback_time. Nothing
// integrates across frames, which is what lets MagentaReductionEffect report
// is_particle_seek_exact() == true and lets the debug harness scrub to an exact
// frame in either direction. Introducing any frame-accumulated term here
// silently breaks scrubbing -- add state to the GDScript timeline instead,
// never to this shader.
//
// Two layers share this shader and are selected by layer_mode, mirroring the
// fire storm's two-emitter/one-shader arrangement: the mote field cannot
// silently drift out of step with the discharge on the field radius or the beat
// boundaries, because both read the same uniforms.

uniform float playback_time = 0.0;
uniform float total_duration = 3.4;
// Half-extent of the footprint in world units: radius_tiles + 0.5.
uniform float footprint_radius_u = 3.5;
// The field is a CIRCLE, deliberately, not the Manhattan diamond the spell
// actually hits. See FIELD_CIRCLE_RADIUS_FRACTION in the profile -- this is a
// chosen look, with the ground wash left carrying the true footprint.
uniform float circle_radius_fraction = 0.88;
// 0 = mote field, 1 = discharge bolts, 2 = discharge sparks.
uniform float layer_mode = 0.0;

// --- Beat boundaries, as normalized fractions of the timeline ---------------
// gather 0 -> gather_end, spiral gather_end -> spiral_end,
// charge spiral_end -> charge_end, discharge charge_end -> 1.
uniform float gather_end_fraction = 0.18;
uniform float spiral_end_fraction = 0.44;
uniform float charge_end_fraction = 0.84;
uniform float onset_fraction = 0.06;

// --- Spiral -----------------------------------------------------------------
// Angular velocity ramps smoothly between two rates across an explicit window,
// and the swept angle is that ramp's exact integral, so the field has no
// discontinuity in speed anywhere on the timeline. See SWIRL_GATHER_RATE.
uniform float swirl_gather_rate = 0.9;
uniform float swirl_charge_rate = 5.2;
uniform float windup_start_fraction = 0.14;
uniform float windup_end_fraction = 0.58;
uniform float inward_accel_exponent = 2.2;
uniform float gather_drift_fraction = 0.07;
uniform float charge_radius_fraction = 0.42;
uniform float charge_compress_fraction = 0.26;

// --- Mote spawn band --------------------------------------------------------
uniform float band_inner_fraction = 0.85;
uniform float phase_spread = 0.20;

// --- Motes ------------------------------------------------------------------
uniform float mote_min_size = 0.05;
uniform float mote_max_size = 0.13;
uniform float mote_shrink = 0.72;
uniform float mote_height_min_fraction = 0.04;
uniform float mote_height_max_fraction = 0.25;
uniform float mote_sink_fraction = 0.35;
uniform float mote_dissipate_fraction = 0.35;
// Peak per-mote opacity. Separate from the colour uniforms because these layers
// blend additively: the charge beat stacks the entire field into a few tiles, a
// far smaller volume than even the fire column's, so the centre clips to white
// long before any single mote looks bright. This is the value to lower when the
// core saturates -- not the colours, which only control hue.
uniform float mote_alpha = 0.13;
// RGB only; alpha is ignored in favour of mote_alpha above.
uniform vec4 mote_outer_color : source_color = vec4(0.82, 0.14, 0.70, 1.0);
uniform vec4 mote_inner_color : source_color = vec4(1.0, 0.44, 0.95, 1.0);

// --- Twinkle ----------------------------------------------------------------
// A sharpened sine: raising a 0..1 sine to a power spends most of the cycle
// near zero and spikes briefly, which reads as a twinkle rather than the even
// throb a plain sine gives.
uniform float twinkle_rate_min = 3.5;
uniform float twinkle_rate_max = 9.0;
uniform float twinkle_sharpness = 4.0;
uniform float twinkle_depth = 0.75;
uniform float twinkle_size_depth = 0.35;
// A minority of motes are larger and brighter, so the field reads as brights
// among dots rather than as one uniform grade of speck.
uniform float bright_fraction = 0.22;
uniform float bright_size_scale = 1.9;
uniform float bright_alpha_scale = 1.7;

// --- Discharge --------------------------------------------------------------
uniform float discharge_width_fraction = 0.046;
uniform float discharge_width_min = 0.08;
uniform float discharge_length_fraction = 0.30;
uniform float discharge_lance_count = 14.0;
uniform float discharge_speed = 1.8;
uniform float discharge_angular_jitter = 0.16;
uniform float discharge_stagger_fraction = 0.12;
uniform float discharge_height_fraction = 0.17;
uniform float discharge_alpha = 0.52;
// Radians of outward curl over a lance's full travel. Non-zero makes each lance
// an arc rather than a spoke, so the release reads as the spiral unwinding.
uniform float discharge_curl = 0.55;
uniform float discharge_length_variance = 0.45;
uniform float discharge_alpha_variance = 0.40;
uniform float discharge_height_variance = 0.05;

// --- Bolt path --------------------------------------------------------------
// Each bolt is a chain of segment quads laid end to end. MAX_SEGMENTS bounds
// the accumulation loop at compile time; bolt_segments is the live count.
uniform float bolt_segments = 5.0;
uniform float bolt_jag = 0.55;
uniform float bolt_length_overshoot = 1.45;
uniform float bolt_color_bias = 0.45;
uniform float bolt_tip_width_fraction = 0.35;
uniform float bolt_strobe_rate = 26.0;
uniform float bolt_strobe_sharpness = 2.2;
uniform float bolt_strobe_depth = 0.45;
uniform float bolt_fork_count = 6.0;
uniform float bolt_fork_length_fraction = 0.45;
uniform float bolt_fork_width_fraction = 0.65;
uniform float bolt_fork_deviation = 0.8;

// --- Sparks -----------------------------------------------------------------
uniform float spark_scatter = 0.06;
uniform float spark_min_size = 0.09;
uniform float spark_max_size = 0.26;
uniform float spark_alpha = 0.5;
uniform float spark_spawn_window = 0.5;
uniform float spark_life_fraction = 0.55;
uniform float spark_height_min_fraction = 0.02;
uniform float spark_height_max_fraction = 0.22;
// Multiplies the authored sprite's own colours rather than replacing them.
// White leaves the strip exactly as drawn.
uniform vec4 spark_tint : source_color = vec4(1.0, 1.0, 1.0, 1.0);
// RGB only; alpha is ignored in favour of discharge_alpha above.
uniform vec4 discharge_core_color : source_color = vec4(1.0, 0.97, 0.84, 1.0);
uniform vec4 discharge_edge_color : source_color = vec4(1.0, 0.22, 0.86, 1.0);

// --- Isolation toggles and global scaling -----------------------------------
// These exist so a motion component can be switched off and looked at in the
// debug harness, not because the game ever sets them to zero.
uniform float spiral_enabled = 1.0;
uniform float windup_enabled = 1.0;
uniform float twinkle_enabled = 1.0;
uniform float intensity_scale = 1.0;
uniform float vfx_seed = 1.0;

const float TAU_C = 6.28318531;
// Compile-time bound on the segment-accumulation loop. bolt_segments may be
// anything up to this; the loop breaks early.
const int MAX_SEGMENTS = 8;


float hash_value(float value) {
	return fract(sin(value * 127.1 + vfx_seed * 17.17) * 43758.5453);
}


// Angular kink applied at the start of segment `seg` of bolt `bolt_id`. The
// curl term is divided across the segments so the bolt's *mean* path still
// curves the way the old smooth lance did, with the jag riding on top of it
// rather than replacing it.
float bolt_kink(float bolt_id, float seg) {
	float jag = (hash_value(bolt_id * 31.0 + seg * 7.0 + 601.0) - 0.5) * 2.0 * bolt_jag;
	return jag + discharge_curl / max(bolt_segments, 1.0);
}


// Start position of segment `seg` along a bolt, walking the chain from its
// origin and accumulating each kink. `out_angle` receives that segment's own
// direction.
//
// This is what keeps the bolt continuous: every particle recomputes the same
// prefix of the same path from INDEX alone, so segment N always begins exactly
// where segment N-1 ended, with no shared state between particles and nothing
// accumulated across frames.
vec3 bolt_segment_start(
		float bolt_id, float launch, float seg_length, float seg, out float out_angle) {
	float angle = launch;
	vec3 point = vec3(0.0);
	for (int i = 0; i < MAX_SEGMENTS; i++) {
		float step_index = float(i);
		angle += bolt_kink(bolt_id, step_index);
		if (step_index >= seg) {
			break;
		}
		point += vec3(cos(angle), 0.0, sin(angle)) * seg_length;
	}
	out_angle = angle;
	return point;
}


float bolt_launch_angle(float bolt_id) {
	float jitter = (hash_value(bolt_id + 211.0) - 0.5) * 2.0;
	return (bolt_id / max(discharge_lance_count, 1.0)) * TAU_C
			+ jitter * discharge_angular_jitter;
}


// The field's outer radius. A plain circle -- no angular term -- because this
// effect deliberately swirls on a circle rather than tracing the diamond the
// spell hits.
float field_limit() {
	return footprint_radius_u * circle_radius_fraction;
}


// Angle swept by `playback_time`, as the exact integral of an angular velocity
// that ramps smoothstep-wise from swirl_gather_rate to swirl_charge_rate across
// the wind-up window.
//
// Integrating rather than switching rates is the whole point. The previous
// version accumulated angle as a function of radius and then bolted a constant
// charge-beat spin on top, which left a step in angular velocity at the beat
// boundary -- the field visibly lurched. smoothstep's integral is elementary
// (p^3 - p^4/2), so the closed form below costs nothing and is C1-continuous
// everywhere: speed starts slow, rises smoothly, and arrives at the charge rate
// without a seam.
float swept_angle() {
	float peak_rate = mix(swirl_gather_rate, swirl_charge_rate, windup_enabled);
	float ramp_start = windup_start_fraction * total_duration;
	float ramp_end = windup_end_fraction * total_duration;
	float span = max(ramp_end - ramp_start, 0.001);
	float p = clamp((playback_time - ramp_start) / span, 0.0, 1.0);
	float ramp_integral = swirl_gather_rate * p
			+ (peak_rate - swirl_gather_rate) * (p * p * p - 0.5 * p * p * p * p);
	return swirl_gather_rate * min(playback_time, ramp_start)
			+ ramp_integral * span
			+ peak_rate * max(playback_time - ramp_end, 0.0);
}


void process() {
	float index = float(INDEX);
	float normalized_time = clamp(playback_time / max(total_duration, 0.001), 0.0, 1.0);

	float base_angle = hash_value(index + 1.0) * TAU_C;
	float band = mix(band_inner_fraction, 1.0, hash_value(index + 41.0));
	float stagger = hash_value(index + 83.0) * phase_spread;
	float size_rand = hash_value(index + 127.0);
	float height_rand = hash_value(index + 173.0);
	float jitter = (hash_value(index + 211.0) - 0.5) * 2.0;

	if (layer_mode < 0.5) {
		// ------------------------------------------------------------------
		// Mote field: boundary -> centre across the first three beats.
		// ------------------------------------------------------------------

		// Radius as a fraction of this mote's own spawn radius, chained across
		// the three inward beats. Each term is inert until its beat opens, so
		// the boundaries stay exactly where the profile puts them.
		float gather_lin = clamp(normalized_time / max(gather_end_fraction, 0.001), 0.0, 1.0);
		float spiral_lin = clamp(
				(normalized_time - gather_end_fraction)
				/ max(spiral_end_fraction - gather_end_fraction, 0.001), 0.0, 1.0);
		float charge_lin = clamp(
				(normalized_time - spiral_end_fraction)
				/ max(charge_end_fraction - spiral_end_fraction, 0.001), 0.0, 1.0);
		// Above 1.0 the mote leaves the boundary slowly and accelerates as it
		// closes. This is the inward-speed curve, kept separate from the
		// angular wind-up, which is purely a function of time.
		float spiral_eased = pow(spiral_lin, max(inward_accel_exponent, 0.001));

		float radius_fraction = mix(1.0, 1.0 - gather_drift_fraction, gather_lin);
		radius_fraction = mix(radius_fraction, charge_radius_fraction, spiral_eased);
		radius_fraction = mix(radius_fraction, charge_compress_fraction, charge_lin);

		float angle = base_angle + swept_angle() * spiral_enabled;
		float radius = field_limit() * band * radius_fraction;

		// Motes sink toward the core as they converge, which reads as being
		// pulled in rather than merely closing ranks.
		float height = mix(mote_height_min_fraction, mote_height_max_fraction, height_rand)
				* footprint_radius_u
				* mix(mote_sink_fraction, 1.0, radius_fraction);

		float converge = clamp(
				(1.0 - radius_fraction) / max(1.0 - charge_compress_fraction, 0.001), 0.0, 1.0);
		vec3 tint = mix(mote_outer_color.rgb, mote_inner_color.rgb, converge);

		// Twinkle: each mote pulses on its own rate and phase, so the field
		// glitters instead of sitting at one steady brightness.
		float twinkle_rate = mix(twinkle_rate_min, twinkle_rate_max, hash_value(index + 257.0));
		float twinkle_phase = hash_value(index + 293.0) * TAU_C;
		float spark = pow(
				0.5 + 0.5 * sin(playback_time * twinkle_rate + twinkle_phase),
				max(twinkle_sharpness, 0.001));
		float twinkle = mix(1.0, spark, twinkle_depth * twinkle_enabled);

		// A minority of motes are brights rather than dots.
		float is_bright = step(1.0 - bright_fraction, hash_value(index + 317.0));

		// Staggered appearance, so the gather beat delivers motes a few at a
		// time instead of switching the whole boundary on at once.
		float appear = smoothstep(0.0, onset_fraction, normalized_time - stagger);
		float dissipate = 1.0 - smoothstep(
				charge_end_fraction,
				mix(charge_end_fraction, 1.0, mote_dissipate_fraction),
				normalized_time);

		float scale = mix(mote_min_size, mote_max_size, size_rand)
				* mix(mote_shrink, 1.0, radius_fraction)
				* mix(1.0, bright_size_scale, is_bright)
				* mix(1.0, twinkle, twinkle_size_depth);
		TRANSFORM[0].xyz = vec3(scale, 0.0, 0.0);
		TRANSFORM[1].xyz = vec3(0.0, scale, 0.0);
		TRANSFORM[2].xyz = vec3(0.0, 0.0, scale);
		TRANSFORM[3].xyz = vec3(radius * cos(angle), height, radius * sin(angle));

		VELOCITY = vec3(0.0, 0.0, 0.0);
		COLOR = vec4(tint, mote_alpha * mix(1.0, bright_alpha_scale, is_bright));
		COLOR.a *= clamp(appear * dissipate * twinkle * intensity_scale, 0.0, 1.0);
	} else if (layer_mode < 1.5) {
		// ------------------------------------------------------------------
		// Discharge bolts: centre -> boundary across the final beat, as chains
		// of jagged segments, some of them forks off the others.
		// ------------------------------------------------------------------

		float segments = max(bolt_segments, 1.0);
		float bolt_id = floor(index / segments);
		float seg_index = mod(index, segments);
		float is_fork = step(discharge_lance_count, bolt_id);

		// Per-bolt variation. Identical spokes are what made the first version
		// read as a diagram.
		float length_scale = mix(
				1.0 - discharge_length_variance, 1.0, hash_value(bolt_id + 353.0));
		float alpha_scale = mix(
				1.0 - discharge_alpha_variance, 1.0, hash_value(bolt_id + 401.0));
		float height_offset = (hash_value(bolt_id + 439.0) - 0.5) * 2.0
				* discharge_height_variance * footprint_radius_u;

		// A fork hangs off a parent partway along, so it needs the parent's path
		// walked first: its origin is that branch point and it leaves at an
		// angle off the parent's local direction. `reveal_offset` is how many
		// parent segments must already have struck before the fork may start,
		// which is what stops a branch appearing ahead of the bolt it grows from.
		// Overshoot because a jagged path spends much of its arc length moving
		// sideways; without it the bolts reach only about half the field.
		float bolt_length = field_limit() * length_scale * bolt_length_overshoot;
		vec3 origin = vec3(0.0);
		float launch = bolt_launch_angle(bolt_id);
		float reveal_offset = 0.0;
		float width_scale = 1.0;

		if (is_fork > 0.5) {
			float fork_ordinal = bolt_id - discharge_lance_count;
			float parent_id = floor(
					hash_value(fork_ordinal + 503.0) * max(discharge_lance_count, 1.0));
			float branch_seg = 1.0 + floor(
					hash_value(fork_ordinal + 541.0) * max(segments - 2.0, 1.0));
			float parent_length = field_limit() * bolt_length_overshoot
					* mix(1.0 - discharge_length_variance, 1.0, hash_value(parent_id + 353.0));
			float parent_angle = 0.0;
			origin = bolt_segment_start(
					parent_id,
					bolt_launch_angle(parent_id),
					parent_length / segments,
					branch_seg,
					parent_angle);
			float side_sign = sign(hash_value(fork_ordinal + 577.0) - 0.5);
			launch = parent_angle + side_sign * bolt_fork_deviation;
			bolt_length *= bolt_fork_length_fraction;
			reveal_offset = branch_seg;
			width_scale = bolt_fork_width_fraction;
		}

		float lance_stagger = hash_value(bolt_id + 307.0) * discharge_stagger_fraction;
		float beat_lin = clamp(
				(normalized_time - charge_end_fraction)
				/ max(1.0 - charge_end_fraction, 0.001), 0.0, 1.0);
		float travel_lin = clamp(beat_lin - lance_stagger, 0.0, 1.0);
		float travel = clamp(travel_lin * discharge_speed, 0.0, 1.0);

		// The bolt strikes outward one segment at a time. Normalising by the
		// fork's own offset means every chain, parent or branch, completes
		// exactly at full travel rather than a fork being cut off.
		float reveal_total = segments + reveal_offset;
		float extend = clamp(
				travel * reveal_total - (reveal_offset + seg_index), 0.0, 1.0);

		float seg_length = bolt_length / segments;
		float seg_angle = 0.0;
		vec3 start = origin + bolt_segment_start(
				bolt_id, launch, seg_length, seg_index, seg_angle);

		vec3 forward = vec3(cos(seg_angle), 0.0, sin(seg_angle));
		// Note the handedness: cross(forward, side) must come out as +Y to match
		// the normal set on TRANSFORM[2]. The opposite sign makes the basis
		// left-handed, flips the quad's winding, and gets every segment
		// backface-culled when seen from above -- invisible, no error, every
		// other value correct.
		vec3 side = vec3(forward.z, 0.0, -forward.x);

		float chain_position = (reveal_offset + seg_index) / max(reveal_total, 1.0);
		float drawn_length = seg_length * extend;
		float lance_width = max(
				discharge_width_fraction * footprint_radius_u, discharge_width_min)
				* width_scale
				* mix(1.0, bolt_tip_width_fraction, chain_position);

		// The quad spans -0.5..0.5 in its own X, so it is centred on the segment
		// it represents rather than starting at it.
		vec3 centre = start + forward * drawn_length * 0.5;

		TRANSFORM[0].xyz = forward * drawn_length;
		TRANSFORM[1].xyz = side * lance_width;
		TRANSFORM[2].xyz = vec3(0.0, lance_width, 0.0);
		TRANSFORM[3].xyz = vec3(
				centre.x,
				discharge_height_fraction * footprint_radius_u + height_offset,
				centre.z);

		// Yellow-white at the core end of the chain, cooling to fuchsia at the
		// tip.
		// Biased so the yellow-white stays confined to the first segment or two:
		// a bolt's mass concentrates near the core where all the chains meet, so
		// an even gradient washes the whole release out to white.
		vec3 tint = mix(
				discharge_core_color.rgb,
				discharge_edge_color.rgb,
				pow(chain_position, max(bolt_color_bias, 0.001)));

		// Lightning strobes rather than fading evenly, which is most of what
		// separates it from a drawn ray.
		float strobe = mix(
				1.0,
				pow(0.5 + 0.5 * sin(playback_time * bolt_strobe_rate
						+ hash_value(bolt_id + 613.0) * TAU_C),
					max(bolt_strobe_sharpness, 0.001)),
				bolt_strobe_depth);

		float ignite = smoothstep(0.0, 0.25, extend);
		float fade = 1.0 - smoothstep(0.55, 1.0, travel);

		VELOCITY = vec3(0.0, 0.0, 0.0);
		COLOR = vec4(tint, discharge_alpha * alpha_scale);
		COLOR.a *= clamp(ignite * fade * strobe * intensity_scale, 0.0, 1.0);
	} else {
		// ------------------------------------------------------------------
		// Discharge sparks: star glints thrown across the field as the bolts
		// strike. Scattered rather than attached to a bolt, so they read as the
		// air lighting up rather than as debris.
		// ------------------------------------------------------------------

		// Sparks sit ON the bolt paths rather than scattered across the field:
		// each picks a parent bolt and a point along it, then is born at the
		// moment that bolt's tip passes. What is left behind is a trail of
		// glints marking where the lightning went.
		float segments = max(bolt_segments, 1.0);
		float parents = max(discharge_lance_count, 1.0);
		float bolt_id = floor(hash_value(index + 641.0) * parents);
		float seg_pick = floor(hash_value(index + 683.0) * segments);
		float along = hash_value(index + 727.0);

		float length_scale = mix(
				1.0 - discharge_length_variance, 1.0, hash_value(bolt_id + 353.0));
		float bolt_length = field_limit() * length_scale * bolt_length_overshoot;
		float seg_length = bolt_length / segments;

		float seg_angle = 0.0;
		vec3 seg_start = bolt_segment_start(
				bolt_id, bolt_launch_angle(bolt_id), seg_length, seg_pick, seg_angle);
		vec3 position = seg_start
				+ vec3(cos(seg_angle), 0.0, sin(seg_angle)) * seg_length * along;

		// Scattered slightly off the path, so the trail reads as thrown sparks
		// rather than as beads threaded on a wire.
		float scatter_angle = hash_value(index + 769.0) * TAU_C;
		float scatter_distance = hash_value(index + 811.0)
				* spark_scatter * footprint_radius_u;
		position += vec3(cos(scatter_angle), 0.0, sin(scatter_angle)) * scatter_distance;

		float height = mix(
				spark_height_min_fraction,
				spark_height_max_fraction,
				hash_value(index + 853.0)) * footprint_radius_u;

		// Birth timed off the same reveal the bolt uses, including that bolt's
		// own stagger, so a spark cannot appear before the lightning reaches it.
		float bolt_stagger = hash_value(bolt_id + 307.0) * discharge_stagger_fraction;
		float arrival = (seg_pick + along) / segments;
		float beat_span = max(1.0 - charge_end_fraction, 0.001);
		float birth = charge_end_fraction
				+ (arrival / max(discharge_speed, 0.001) + bolt_stagger) * beat_span;
		float age = (normalized_time - birth) / max(spark_life_fraction * beat_span, 0.001);

		float scale = mix(spark_min_size, spark_max_size, hash_value(index + 971.0))
				* footprint_radius_u;

		TRANSFORM[0].xyz = vec3(scale, 0.0, 0.0);
		TRANSFORM[1].xyz = vec3(0.0, scale, 0.0);
		TRANSFORM[2].xyz = vec3(0.0, 0.0, scale);
		TRANSFORM[3].xyz = vec3(position.x, height, position.z);

		// Frame selection. The draw material is BILLBOARD_PARTICLES with
		// `particles_anim_h_frames` set, and its generated shader picks the frame
		// from `INSTANCE_CUSTOM.z` — which is this. Driving it from `age`, itself
		// a function of playback_time, keeps the animation deterministic: it
		// scrubs and freezes with the rest of the effect. Driving it from TIME,
		// the obvious alternative, would keep sparks animating on a paused frame
		// and break both scrubbing and golden capture.
		CUSTOM = vec4(0.0, 0.0, clamp(age, 0.0, 1.0), 0.0);

		// The sprite is authored art with its own shading, so this multiplies
		// rather than replaces it; spark_tint is white by default and exists so a
		// later session can push the sparkles without repainting the strip.
		float rise = smoothstep(0.0, 0.06, age);
		float fall = 1.0 - smoothstep(0.78, 1.0, age);
		// Hard-gated at both ends: before birth, and once the strip has played
		// out. Without the upper gate a spark would hold its last frame forever.
		float alive = step(0.0, age) * (1.0 - step(1.0, age));

		VELOCITY = vec3(0.0, 0.0, 0.0);
		COLOR = vec4(spark_tint.rgb, spark_alpha);
		COLOR.a *= clamp(rise * fall * alive * intensity_scale, 0.0, 1.0);
	}
}
