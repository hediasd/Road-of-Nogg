shader_type particles;
render_mode disable_force, disable_velocity;

uniform float playback_time = 0.0;
uniform float total_duration = 2.2;
uniform float footprint_width = 9.0;
uniform float particle_count = 136.0;
uniform float storm_height = 4.1;
uniform float lateral_speed = 2.65;
uniform float min_down_speed = 1.25;
uniform float max_down_speed = 2.55;
uniform float min_scale = 0.055;
uniform float max_scale = 0.13;
uniform vec2 gust_direction = vec2(0.97, 0.24);
uniform float gust_band_period = 0.44;
uniform float gust_band_width = 0.22;
uniform float gust_min_density = 0.42;
uniform float snow_tiny_weight = 0.52;
uniform float snow_small_weight = 0.30;
uniform float snow_medium_weight = 0.14;
uniform float pulse_interval = 0.44;
uniform float pulse_window_fraction = 0.16;
uniform float squall_start_fraction = 0.22;
uniform float energy_half_life_fraction = 0.035;
uniform float settle_start_fraction = 0.82;
uniform float settle_half_life_fraction = 0.055;
uniform float temporal_sample_rate = 15.0;
uniform float position_quantum = 0.0625;
uniform float heading_steps = 8.0;
uniform float golden_angle = 2.39996323;
uniform float golden_angle_jitter_fraction = 0.16;
uniform float intensity_scale = 1.0;
uniform float gust_enabled = 1.0;
uniform float pulse_enabled = 1.0;
uniform float vfx_seed = 1.0;
uniform float diamond_shape = 1.0;
uniform vec4 flake_color : source_color = vec4(0.86, 0.95, 1.0, 0.82);

const float SQRT1_2 = 0.70710678;
const float TAU_VALUE = 6.28318531;
const float LN_2 = 0.69314718;


float hash_value(float value) {
	return fract(sin(value * 127.1 + vfx_seed * 17.17) * 43758.5453);
}


float wrap_span(float value, float span) {
	return mod(value + span * 0.5, span) - span * 0.5;
}


float quantize(float value, float quantum) {
	return round(value / max(quantum, 0.0001)) * quantum;
}


void process() {
	float index = float(INDEX);
	float stepped_time = floor(playback_time * temporal_sample_rate) / temporal_sample_rate;

	// Golden-angle placement progressively fills the field as particle_count
	// changes. The small seeded jitter breaks a visible sunflower spiral without
	// returning to unrelated hash-random clumps.
	float seed_phase = hash_value(5.0) * TAU_VALUE;
	float angle_jitter = (hash_value(index + 211.0) - 0.5) * 2.0;
	float sample_angle = (
		seed_phase
		+ index * golden_angle
		+ angle_jitter * golden_angle * golden_angle_jitter_fraction
	);
	float shape_scale = mix(1.0, SQRT1_2, diamond_shape);
	float square_width = footprint_width * shape_scale;
	float square_boundary = (square_width * 0.5) / max(
		max(abs(cos(sample_angle)), abs(sin(sample_angle))), 0.001
	);
	float radial_fraction = sqrt((index + 0.5) / max(particle_count, 1.0));
	float radial_distance = radial_fraction * square_boundary;
	float sx = cos(sample_angle) * radial_distance;
	float sz = sin(sample_angle) * radial_distance;

	float phase = hash_value(index + 83.0);
	float down_speed = mix(min_down_speed, max_down_speed, hash_value(index + 127.0));
	float scale = mix(min_scale, max_scale, hash_value(index + 173.0));
	// snow_strip.png is packed smallest-to-largest into four equal frames.
	// Select a static frame with cumulative weights; the largest frame receives
	// only the remainder and is therefore rare by construction.
	float variant_roll = hash_value(index + 263.0);
	float small_limit = snow_tiny_weight + snow_small_weight;
	float medium_limit = small_limit + snow_medium_weight;
	float variant = variant_roll < snow_tiny_weight
		? 0.0
		: (variant_roll < small_limit ? 1.0 : (variant_roll < medium_limit ? 2.0 : 3.0));

	vec2 authored_gust = normalize(gust_direction);
	float heading_step = TAU_VALUE / max(heading_steps, 1.0);
	float gust_angle = round(atan(authored_gust.y, authored_gust.x) / heading_step) * heading_step;
	vec2 gust = vec2(cos(gust_angle), sin(gust_angle));
	vec2 gust_rotated = vec2(gust.x + gust.y, gust.y - gust.x) * SQRT1_2;
	vec2 gust_square = mix(gust, gust_rotated, diamond_shape);
	float lateral_distance = stepped_time * lateral_speed * gust_enabled;
	sx = wrap_span(sx + gust_square.x * lateral_distance, square_width);
	sz = wrap_span(sz + gust_square.y * lateral_distance, square_width);

	float x = mix(sx, (sx - sz) * SQRT1_2, diamond_shape);
	float z = mix(sz, (sx + sz) * SQRT1_2, diamond_shape);
	float cycle = fract(phase + stepped_time * down_speed / storm_height);
	float y = mix(storm_height, 0.04, cycle);
	x = quantize(x, position_quantum);
	y = quantize(y, position_quantum);
	z = quantize(z, position_quantum);

	float band_coordinate = fract(
		(dot(vec2(x, z), gust) / footprint_width)
		- stepped_time / max(gust_band_period, 0.001)
	);
	float band_distance = abs(band_coordinate - 0.5) * 2.0;
	float band = 1.0 - smoothstep(0.0, gust_band_width, band_distance);
	float gust_density = mix(1.0, mix(gust_min_density, 1.0, band), gust_enabled);

	float pulse_phase = fract(stepped_time / max(pulse_interval, 0.001));
	float pulse = 1.0 - smoothstep(0.0, pulse_window_fraction, pulse_phase);
	float pulse_density = mix(1.0, 1.30, pulse * pulse_enabled);
	float normalized_time = clamp(playback_time / max(total_duration, 0.001), 0.0, 1.0);
	float squall_elapsed = max(normalized_time - squall_start_fraction, 0.0);
	float onset = normalized_time <= squall_start_fraction
		? 0.0
		: 1.0 - exp(-LN_2 * squall_elapsed / max(energy_half_life_fraction, 0.001));
	float settle_elapsed = max(normalized_time - settle_start_fraction, 0.0);
	float settle = exp(-LN_2 * settle_elapsed / max(settle_half_life_fraction, 0.001));

	TRANSFORM[0].xyz = vec3(scale, 0.0, 0.0);
	TRANSFORM[1].xyz = vec3(0.0, scale, 0.0);
	TRANSFORM[2].xyz = vec3(0.0, 0.0, scale);
	TRANSFORM[3].xyz = vec3(x, y, z);
	// BILLBOARD_PARTICLES maps INSTANCE_CUSTOM.z across the 4x1 atlas. Sampling
	// frame centres avoids boundary ambiguity at exactly 0.25/0.50/0.75.
	CUSTOM = vec4(0.0, 0.0, (variant + 0.5) / 4.0, 0.0);
	VELOCITY = vec3(gust.x * lateral_speed * gust_enabled, -down_speed, gust.y * lateral_speed * gust_enabled);
	COLOR = flake_color;
	COLOR.a *= clamp(onset * settle * gust_density * pulse_density * intensity_scale, 0.0, 1.0);
}
