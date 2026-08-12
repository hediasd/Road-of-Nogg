// Feathered vertical and diagonal shafts behind the generic spell-cast aura.
//
// Twenty compile-time slots allow a seeded active subset. Each shaft receives
// independent angle, length, width, brightness, drift, and pulse, preventing
// the fan from rotating or flickering as one rigid sunburst.

shader_type spatial;
render_mode unshaded, blend_add, depth_draw_never, cull_disabled;

uniform vec4 aura_color : source_color = vec4(0.15, 0.75, 1.0, 1.0);
uniform float burst_progress : hint_range(0.0, 1.0) = 0.0;
uniform float seed_value = 0.0;
uniform float quad_width = 3.55;
uniform float quad_height = 3.65;
uniform float ray_count = 17.0;
uniform float angle_span = 2.20;
uniform float length_min = 0.46;
uniform float length_max = 1.0;
uniform float width_min = 0.010;
uniform float width_max = 0.070;
uniform float peak_alpha : hint_range(0.0, 1.0) = 0.19;
uniform float white_mix : hint_range(0.0, 1.0) = 0.10;
uniform float emission_energy : hint_range(0.0, 8.0) = 1.30;
uniform float flicker_cycles = 2.6;
uniform float eruption_start : hint_range(0.0, 1.0) = 0.03;
uniform float eruption_end : hint_range(0.001, 1.0) = 0.30;
uniform float hold_end : hint_range(0.001, 1.0) = 0.50;
uniform float decay_end : hint_range(0.001, 1.0) = 0.90;

varying float v_life;

vec3 saturated_tint(vec3 color) {
	float luma = dot(color, vec3(0.299, 0.587, 0.114));
	return clamp(mix(vec3(luma), color, 2.35), vec3(0.0), vec3(1.0));
}

float hash_value(float value) {
	return fract(sin(value * 127.1 + seed_value * 17.17) * 43758.5453);
}

void vertex() {
	float grow = smoothstep(eruption_start, eruption_end, burst_progress);
	grow = 1.0 - pow(1.0 - grow, 3.0);
	float fade = 1.0 - smoothstep(hold_end, decay_end, burst_progress);
	v_life = grow * fade;
	VERTEX.y = (VERTEX.y + quad_height * 0.5) * grow - quad_height * 0.5;
	VERTEX.x *= mix(0.18, 1.0, grow);
	vec4 billboard_origin = MODEL_MATRIX[3];
	billboard_origin.xyz -= INV_VIEW_MATRIX[2].xyz * 0.13;
	MODELVIEW_MATRIX = VIEW_MATRIX * mat4(
		INV_VIEW_MATRIX[0],
		INV_VIEW_MATRIX[1],
		INV_VIEW_MATRIX[2],
		billboard_origin
	);
	MODELVIEW_NORMAL_MATRIX = mat3(MODELVIEW_MATRIX);
}

void fragment() {
	vec2 p = vec2(
		(UV.x - 0.5) * quad_width / max(quad_height, 0.001),
		1.0 - UV.y
	);
	float rays = 0.0;
	float hot_rays = 0.0;

	for (int i = 0; i < 20; i++) {
		float index = float(i);
		float active = 1.0 - step(ray_count - 0.5, index);
		float slot = (index + 0.5) / max(ray_count, 1.0);
		float jitter = (hash_value(index + 11.0) - 0.5) * angle_span * 0.13;
		float drift = sin(
			burst_progress * 6.2831853 * (0.45 + hash_value(index + 17.0) * 0.35)
			+ hash_value(index + 23.0) * 6.2831853
		) * 0.018;
		float angle = mix(-angle_span * 0.5, angle_span * 0.5, slot) + jitter + drift;
		vec2 direction = vec2(sin(angle), cos(angle));
		float along = dot(p, direction);
		float side = abs(p.x * direction.y - p.y * direction.x);
		float length_value = mix(length_min, length_max, hash_value(index + 31.0));
		float base_width = mix(width_min, width_max, pow(hash_value(index + 43.0), 1.65));
		float along_norm = clamp(along / max(length_value, 0.001), 0.0, 1.0);
		float width_at = base_width * mix(0.16, 1.0, sqrt(along_norm));
		float feather = 1.0 - smoothstep(width_at * 0.24, width_at, side);
		float body = step(0.0, along) * (1.0 - smoothstep(0.72, 1.0, along_norm));
		float base_fade = smoothstep(0.0, 0.035, along);
		float pulse = 0.70 + 0.30 * sin(
			burst_progress * 6.2831853 * (flicker_cycles + hash_value(index + 59.0))
			+ hash_value(index + 67.0) * 6.2831853
		);
		float brightness = mix(0.16, 1.0, hash_value(index + 71.0));
		brightness *= mix(1.0, 0.62, smoothstep(width_min, width_max, base_width));
		float ray = active * feather * body * base_fade * pulse * brightness;
		rays = max(rays, ray);
		hot_rays = max(hot_rays, ray * step(base_width, width_min * 2.35));
	}

	float alpha = rays * peak_alpha * v_life;
	if (alpha < 0.0015) {
		discard;
	}
	vec3 tint = saturated_tint(aura_color.rgb);
	vec3 color = mix(tint, vec3(1.0), white_mix + hot_rays * 0.05);
	ALBEDO = color;
	EMISSION = color * emission_energy * rays;
	ALPHA = alpha;
}
