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
uniform vec4 flake_color : source_color = vec4(0.90, 0.96, 1.0, 0.62);


float hash_value(float value) {
	return fract(sin(value * 127.1 + vfx_seed * 17.17) * 43758.5453);
}


float wrap_span(float value, float span) {
	return mod(value + span * 0.5, span) - span * 0.5;
}


void process() {
	float index = float(INDEX);
	float base_x = (hash_value(index + 1.0) - 0.5) * footprint_width;
	float base_z = (hash_value(index + 41.0) - 0.5) * footprint_width;
	float phase = hash_value(index + 83.0);
	float down_speed = mix(min_down_speed, max_down_speed, hash_value(index + 127.0));
	float scale = mix(min_scale, max_scale, hash_value(index + 173.0));
	vec2 gust = normalize(gust_direction);
	float lateral_distance = playback_time * lateral_speed * gust_enabled;
	float x = wrap_span(base_x + gust.x * lateral_distance, footprint_width);
	float z = wrap_span(base_z + gust.y * lateral_distance, footprint_width);
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