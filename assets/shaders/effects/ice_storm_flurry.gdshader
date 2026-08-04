shader_type particles;
render_mode disable_force, disable_velocity;

uniform float playback_time = 0.0;
uniform float total_duration = 4.5;
uniform float footprint_width = 5.0;
uniform float storm_height = 3.8;
uniform float lateral_speed = 2.4;
uniform float min_down_speed = 1.1;
uniform float max_down_speed = 2.2;
uniform float min_scale = 0.04;
uniform float max_scale = 0.11;
uniform vec2 gust_direction = vec2(0.97, 0.24);
uniform float gust_band_period = 0.45;
uniform float gust_band_width = 0.30;
uniform float pulse_interval = 0.45;
uniform float pulse_window_fraction = 0.18;
uniform float onset_fraction = 0.08;
uniform float intensity_scale = 1.0;
uniform float gust_enabled = 1.0;
uniform float pulse_enabled = 1.0;
uniform float vfx_seed = 1.0;
uniform float diamond_shape = 1.0;
uniform vec4 flake_color : source_color = vec4(0.90, 0.96, 1.0, 0.62);

const float SQRT1_2 = 0.70710678;


float hash_value(float value) {
	return fract(sin(value * 127.1 + vfx_seed * 17.17) * 43758.5453);
}


float wrap_span(float value, float span) {
	return mod(value + span * 0.5, span) - span * 0.5;
}


void process() {
	float index = float(INDEX);
	// The gameplay footprint is a Manhattan diamond (|x| + |z| <= radius), not a
	// square. Particles are sampled uniformly in a square rotated -45 degrees
	// from world space, then rotated back +45 degrees at the end: a square
	// rotated 45 degrees is exactly that diamond, so every sampled particle
	// lands inside it with none rejected. Drift and wrap happen before the final
	// rotation so wrapping stays axis-aligned in the pre-rotation frame; gust
	// is rotated -45 degrees to compensate, so the visible drift direction still
	// matches the authored world-space direction. diamond_shape = 0.0 collapses
	// all of this back to the original axis-aligned square field unchanged.
	float shape_scale = mix(1.0, SQRT1_2, diamond_shape);
	float square_width = footprint_width * shape_scale;
	float sx = (hash_value(index + 1.0) - 0.5) * square_width;
	float sz = (hash_value(index + 41.0) - 0.5) * square_width;
	float phase = hash_value(index + 83.0);
	float down_speed = mix(min_down_speed, max_down_speed, hash_value(index + 127.0));
	float scale = mix(min_scale, max_scale, hash_value(index + 173.0));

	vec2 gust = normalize(gust_direction);
	vec2 gust_rotated = vec2(gust.x + gust.y, gust.y - gust.x) * SQRT1_2;
	vec2 gust_square = mix(gust, gust_rotated, diamond_shape);
	float lateral_distance = playback_time * lateral_speed * gust_enabled;
	sx = wrap_span(sx + gust_square.x * lateral_distance, square_width);
	sz = wrap_span(sz + gust_square.y * lateral_distance, square_width);

	float x = mix(sx, (sx - sz) * SQRT1_2, diamond_shape);
	float z = mix(sz, (sx + sz) * SQRT1_2, diamond_shape);

	float cycle = fract(phase + playback_time * down_speed / storm_height);
	float y = mix(storm_height, 0.04, cycle);

	float band_coordinate = fract(
		(dot(vec2(x, z), gust) / footprint_width)
		- playback_time / max(gust_band_period, 0.001)
	);
	float band_distance = abs(band_coordinate - 0.5) * 2.0;
	float band = 1.0 - smoothstep(0.0, gust_band_width, band_distance);
	float gust_density = mix(1.0, mix(0.28, 1.0, band), gust_enabled);

	float pulse_phase = fract(playback_time / max(pulse_interval, 0.001));
	float pulse = 1.0 - smoothstep(0.0, pulse_window_fraction, pulse_phase);
	float pulse_density = mix(1.0, 1.42, pulse * pulse_enabled);
	float normalized_time = clamp(playback_time / max(total_duration, 0.001), 0.0, 1.0);
	float onset = smoothstep(0.0, onset_fraction, normalized_time);
	float settle = 1.0 - smoothstep(0.84, 0.95, normalized_time);

	TRANSFORM[0].xyz = vec3(scale, 0.0, 0.0);
	TRANSFORM[1].xyz = vec3(0.0, scale, 0.0);
	TRANSFORM[2].xyz = vec3(0.0, 0.0, scale);
	TRANSFORM[3].xyz = vec3(x, y, z);
	VELOCITY = vec3(
		gust.x * lateral_speed * gust_enabled,
		-down_speed,
		gust.y * lateral_speed * gust_enabled
	);
	COLOR = flake_color;
	COLOR.a *= clamp(onset * settle * gust_density * pulse_density * intensity_scale, 0.0, 1.0);
}