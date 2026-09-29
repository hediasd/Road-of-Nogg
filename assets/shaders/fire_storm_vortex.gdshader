shader_type particles;
render_mode disable_force, disable_velocity;

// Rising ember vortex for the data-selected fire-area storm.
//
// Every value below is a pure function of INDEX and playback_time. Nothing
// integrates across frames, which is what lets FireStormEffect report
// is_particle_seek_exact() == true and lets the debug harness scrub to an
// exact frame in either direction. Introducing any frame-accumulated term
// here silently breaks scrubbing -- add state to the GDScript timeline
// instead, never to this shader.

uniform float playback_time = 0.0;
uniform float total_duration = 2.4;
// Half-extent of the footprint in world units: radius_tiles + 0.5, matching
// the ground wash cylinder's own radius so the column and the wash agree.
uniform float footprint_radius_u = 1.5;
uniform float column_height = 3.4;
uniform float base_radius_fraction = 0.85;
uniform float crown_taper = 0.34;
uniform float swirl_base = 2.30;
uniform float swirl_crown = 0.95;
uniform float swirl_speed = 1.0;
uniform float min_rise_speed = 1.15;
uniform float max_rise_speed = 2.05;
uniform float min_scale = 0.045;
uniform float max_scale = 0.115;
uniform float ember_shrink = 0.35;
uniform float flicker_rate = 11.0;
uniform float flicker_depth = 0.28;
uniform float lean_offset = 0.16;
uniform float onset_fraction = 0.10;
uniform float intensity_scale = 1.0;
uniform float swirl_enabled = 1.0;
uniform float flicker_enabled = 1.0;
uniform float diamond_shape = 1.0;
uniform float vfx_seed = 1.0;
// Peak per-ember opacity. Separate from the colour uniforms because these
// layers blend additively: a column packs its particles into a far smaller
// volume than a storm field spreads them across, so dozens overlap per pixel
// and clip to white long before any single ember looks bright. This is the
// value to lower when the column saturates -- not the colours, which only
// control hue.
uniform float ember_alpha = 0.34;
// RGB only; alpha is ignored in favour of ember_alpha above.
uniform vec4 ember_hot_color : source_color = vec4(1.0, 0.94, 0.72, 1.0);
uniform vec4 ember_mid_color : source_color = vec4(1.0, 0.55, 0.16, 1.0);
uniform vec4 ember_cool_color : source_color = vec4(0.72, 0.16, 0.09, 1.0);

const float SQRT1_2 = 0.70710678;
const float TAU_C = 6.28318531;


float hash_value(float value) {
	return fract(sin(value * 127.1 + vfx_seed * 17.17) * 43758.5453);
}


void process() {
	float index = float(INDEX);
	float base_angle = hash_value(index + 1.0) * TAU_C;
	// sqrt() gives uniform density per unit AREA rather than per unit radius.
	// Without it embers bunch visibly along the column's axis and the outer
	// column reads as empty.
	float radius_norm = sqrt(hash_value(index + 41.0));
	float phase = hash_value(index + 83.0);
	float rise_speed = mix(min_rise_speed, max_rise_speed, hash_value(index + 127.0));
	float base_scale = mix(min_scale, max_scale, hash_value(index + 173.0));
	float flicker_phase = hash_value(index + 211.0) * TAU_C;

	// Vertical cycle: 0 at the floor, 1 at the crown, wrapping so the column
	// is continuously fed rather than emptying once.
	float height = fract(phase + playback_time * rise_speed / max(column_height, 0.001));
	float y = height * column_height;

	// Funnel: the radius narrows toward the crown.
	float taper = mix(1.0, crown_taper, smoothstep(0.0, 1.0, height));

	// Differential rotation -- the base winds faster than the crown, so the
	// spiral visibly twists instead of turning as a rigid body.
	float omega = mix(swirl_base, swirl_crown, height) * swirl_speed * swirl_enabled;
	float angle = base_angle + playback_time * omega;

	// Exact polar form of the Manhattan diamond |x| + |z| <= R that
	// ShapeCaster.getCircle actually casts: at angle 0 this is R (the
	// diamond's vertex), at 45 degrees it is R/sqrt(2) (the edge midpoint), so
	// the column breathes in and out as it rotates and traces the real
	// gameplay footprint. cross/line carriers get the inscribed circle.
	float diamond_limit = footprint_radius_u / max(abs(cos(angle)) + abs(sin(angle)), 0.001);
	float radius_max = mix(footprint_radius_u * SQRT1_2, diamond_limit, diamond_shape);
	float radius = min(radius_norm * footprint_radius_u * base_radius_fraction, radius_max) * taper;

	// A small quadratic lean; perfectly vertical reads as mechanical.
	float lean = lean_offset * height * height;
	vec3 position = vec3(radius * cos(angle) + lean, y, radius * sin(angle));

	// Cooling with height: hot core at the floor through orange to deep red at
	// the crown, so an ember that survives the climb has visibly burnt down.
	vec3 tint = mix(ember_hot_color.rgb, ember_mid_color.rgb, smoothstep(0.0, 0.45, height));
	tint = mix(tint, ember_cool_color.rgb, smoothstep(0.45, 1.0, height));

	float flicker = 1.0 - flicker_depth * flicker_enabled
		* (0.5 + 0.5 * sin(playback_time * flicker_rate + flicker_phase));
	float birth = smoothstep(0.0, 0.09, height);
	float death = 1.0 - smoothstep(0.52, 1.0, height);

	float normalized_time = clamp(playback_time / max(total_duration, 0.001), 0.0, 1.0);
	float onset = smoothstep(0.0, onset_fraction, normalized_time);
	float settle = 1.0 - smoothstep(0.80, 0.96, normalized_time);

	// Embers shrink as they rise, reading as burning out rather than simply
	// fading at a constant size.
	float scale = base_scale * mix(1.0, ember_shrink, height);
	TRANSFORM[0].xyz = vec3(scale, 0.0, 0.0);
	TRANSFORM[1].xyz = vec3(0.0, scale, 0.0);
	TRANSFORM[2].xyz = vec3(0.0, 0.0, scale);
	TRANSFORM[3].xyz = position;

	VELOCITY = vec3(-sin(angle) * radius * omega, rise_speed, cos(angle) * radius * omega);

	COLOR = vec4(tint, ember_alpha);
	COLOR.a *= clamp(birth * death * flicker * onset * settle * intensity_scale, 0.0, 1.0);
}
