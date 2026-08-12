// World-space radial light ribbons for the generic spell-cast aura.
//
// Each MultiMesh instance is a thin crossed ribbon with authored world
// position, height, width, and outward lean. The shader only feathers and
// animates its two faces; it never reads or rotates toward the camera.

shader_type spatial;
render_mode unshaded, blend_add, depth_draw_never, cull_disabled;

uniform vec4 aura_color : source_color = vec4(0.15, 0.75, 1.0, 1.0);
uniform sampler2D ray_tex : filter_linear;
uniform float burst_progress : hint_range(0.0, 1.0) = 0.0;
uniform float seed_value = 0.0;
uniform float peak_alpha : hint_range(0.0, 1.0) = 0.18;
uniform float white_mix : hint_range(0.0, 1.0) = 0.0;
uniform float emission_energy : hint_range(0.0, 8.0) = 1.1;
uniform float flicker_cycles = 2.6;
uniform float eruption_start : hint_range(0.0, 1.0) = 0.03;
uniform float eruption_end : hint_range(0.001, 1.0) = 0.30;
uniform float stagger_span : hint_range(0.0, 1.0) = 0.14;
uniform float hold_end : hint_range(0.001, 1.0) = 0.50;
uniform float decay_end : hint_range(0.001, 1.0) = 0.90;

varying float v_energy;
varying float v_pulse;

vec3 saturated_tint(vec3 color) {
	float luma = dot(color, vec3(0.299, 0.587, 0.114));
	return clamp(mix(vec3(luma), color, 2.35), vec3(0.0), vec3(1.0));
}

void vertex() {
	float local = clamp(
		(burst_progress - eruption_start - INSTANCE_CUSTOM.x * stagger_span)
			/ max(eruption_end - eruption_start, 0.001),
		0.0,
		1.0
	);
	float grow = 1.0 - pow(1.0 - local, 3.0);
	float fade = 1.0 - smoothstep(hold_end, decay_end, burst_progress);
	v_energy = min(local * 5.0, 1.0) * fade * INSTANCE_CUSTOM.y;
	v_pulse = 0.72 + 0.28 * sin(
		burst_progress * 6.2831853 * (flicker_cycles + INSTANCE_CUSTOM.z)
		+ INSTANCE_CUSTOM.z * 6.2831853
		+ seed_value * 0.071
	);
	VERTEX.y = (VERTEX.y + 0.5) * grow - 0.5;
	VERTEX.x *= mix(0.30, 1.0, grow);
}

void fragment() {
	float y = 1.0 - UV.y;
	float sampled = texture(ray_tex, vec2(y, UV.x)).a;
	float core = smoothstep(0.46, 0.86, sampled);
	float tip_fade = 1.0 - smoothstep(0.58, 1.0, y);
	float mask = sampled * tip_fade * v_pulse;
	float alpha = mask * peak_alpha * v_energy;
	if (alpha < 0.0015) {
		discard;
	}

	vec3 tint = saturated_tint(aura_color.rgb);
	vec3 color = mix(tint, vec3(1.0), white_mix + core * 0.03);
	ALBEDO = color;
	EMISSION = color * emission_energy * mask;
	ALPHA = alpha;
}
