shader_type spatial;
render_mode unshaded, blend_add, depth_draw_never, depth_test_disabled,
		cull_disabled, skip_vertex_transform, fog_disabled, shadows_disabled;

// Cross-filter sparkle aura, owned by CrossFilterSparkleEffect.
//
// One MultiMesh quad per slot. Slots are grouped: slot 0 of a group is a
// leader, the rest are followers that pop in after it along the body's edge.
// Every value is a pure function of INSTANCE_ID, seed and playback_time, so
// the effect seeks exactly in either direction. playback_time arrives already
// floored to the profile's frame rate; that floor is what makes each sparkle
// hold between ticks like a drawing shot on twos. Do not read TIME here.
//
// The star is drawn in the camera's plane: the quad is laid out in view space
// and the rays are at a fixed angle in that plane, so every sparkle shares one
// screen angle, the way a cross-screen filter marks every light the same.
//
// Every number comes from CrossFilterSparkleProfile through a uniform.

uniform float playback_time = 0.0;
uniform float total_duration = 2.6;
uniform float settle_seconds = 0.5;
uniform int seed = 0;

uniform int group_count = 30;
uniform int chain_slots = 4;
uniform int lane_count = 2;
uniform float idle_active_chance = 0.7;
uniform float chain_chance = 0.3;
uniform float entrance_spread = 0.35;
uniform float entrance_peak_gain = 0.6;
uniform float entrance_decay = 0.5;
uniform float life_min = 0.55;
uniform float life_max = 1.4;
uniform float rise_min = 0.05;
uniform float rise_max = 0.12;
uniform float fall_exponent = 1.3;
uniform float birth_jitter = 0.2;
uniform float chain_step_min = 0.0833;
uniform float chain_step_max = 0.1833;
uniform float period_min = 2.15;
uniform float period_max = 3.0;
uniform float peak_min = 0.16;
uniform float peak_skew = 2.2;
uniform float chain_peak_min = 0.7;
uniform float chain_peak_max = 1.15;
uniform float flicker_depth = 0.2;
uniform float flicker_rate_min = 9.0;
uniform float flicker_rate_max = 18.0;

uniform float edge_scale = 1.0;
uniform float edge_spread = 0.11;
uniform float edge_outward_bias = 0.05;
uniform float drift_up_min = 0.03;
uniform float drift_up_max = 0.12;
uniform float drift_side = 0.03;
uniform float chain_gap_fraction = 0.8;

uniform float ray_angle_degrees = 45.0;
uniform float ray_length = 0.18;
uniform float ray_min_fraction = 0.15;
uniform float ray_length_exponent = 1.25;
uniform float ray_gain = 0.95;
uniform float ray_exponent = 1.6;
uniform float ray_taper = 1.7;
uniform float ray_width = 0.004;
uniform float ray_min_pixels = 0.55;
uniform float ray_root_widen = 0.9;
uniform float core_base = 0.28;
uniform float core_gain = 0.95;
uniform float core_sigma = 0.013;
uniform float core_sigma_min = 0.65;
uniform float core_sigma_gain = 0.55;
uniform float core_min_pixels = 1.1;
uniform float halo_gain = 0.3;
uniform float halo_sigma_scale = 3.4;
uniform float quad_half = 0.24;

uniform float ramp_e0 = 0.0;
uniform float ramp_e1 = 0.12;
uniform float ramp_e2 = 0.30;
uniform float ramp_e3 = 0.55;
uniform float ramp_e4 = 0.80;
uniform float ramp_e5 = 1.00;
uniform float ramp_e6 = 1.45;
uniform float ramp_e7 = 2.00;
uniform vec4 ramp_c0 : source_color = vec4(0.0, 0.0, 0.0, 1.0);
uniform vec4 ramp_c1 : source_color = vec4(0.0, 0.0, 0.0, 1.0);
uniform vec4 ramp_c2 : source_color = vec4(0.0, 0.0, 0.0, 1.0);
uniform vec4 ramp_c3 : source_color = vec4(0.0, 0.0, 0.0, 1.0);
uniform vec4 ramp_c4 : source_color = vec4(0.0, 0.0, 0.0, 1.0);
uniform vec4 ramp_c5 : source_color = vec4(0.0, 0.0, 0.0, 1.0);
uniform vec4 ramp_c6 : source_color = vec4(0.0, 0.0, 0.0, 1.0);
uniform vec4 ramp_c7 : source_color = vec4(0.0, 0.0, 0.0, 1.0);

uniform int body_count = 1;
uniform vec3 body_centers[8];
// x: horizontal half-extent, y: vertical half-extent, world units.
uniform vec2 body_halves[8];

uniform bool layer_visible = true;

varying float v_intensity;
varying vec2 v_local;

uint hash_u(uint x) {
	x ^= x >> 16u;
	x *= 0x7feb352du;
	x ^= x >> 15u;
	x *= 0x846ca68bu;
	x ^= x >> 16u;
	return x;
}

// Uniform 0..1 from a seed, a group, a cycle and a channel.
float h01(uint s, uint g, uint c, uint channel) {
	uint h = hash_u(s ^ hash_u(g + 0x9e3779b9u * hash_u(c ^ hash_u(channel))));
	return float(h >> 8u) / 16777216.0;
}

void vertex() {
	float intensity = 0.0;
	vec3 world = vec3(0.0);
	int perGroup = chain_slots * lane_count;
	int group = INSTANCE_ID / perGroup;
	int laneSlot = INSTANCE_ID - group * perGroup;
	int lane = laneSlot / chain_slots;
	int member = laneSlot - lane * chain_slots;
	uint s = uint(seed);
	uint g = uint(group);
	float t = playback_time;
	float period = mix(period_min, period_max, h01(s, g, 0u, 1u));
	float start0 = entrance_spread * h01(s, g, 0u, 2u);

	if (layer_visible && group < group_count && t >= start0) {
		// Cycles alternate between lanes. lane_count periods hold jitter + a
		// full chain + the longest life, so a lane's sparkle is gone before its
		// lane comes round again and only its most recent cycle counts.
		float cycleNow = floor((t - start0) / period);
		float cycle = cycleNow - mod(cycleNow - float(lane), float(lane_count));
		uint cu = uint(max(cycle, 0.0));
		float cycleStart = start0 + cycle * period;
		float activeChance = cycle < 0.5 ? 1.0 : idle_active_chance;
		bool chained = h01(s, g, cu, 4u) < chain_chance;
		int followers = chained ?
				1 + int(floor(h01(s, g, cu, 5u) * float(chain_slots - 1) * 0.9999)) : 0;
		if (cycle >= 0.0 && h01(s, g, cu, 3u) < activeChance && member <= followers) {
			uint mu = uint(member);
			float born = cycleStart + birth_jitter * h01(s, g, cu, 6u);
			for (int k = 1; k < 8; k++) {
				if (k > member) {
					break;
				}
				born += mix(chain_step_min, chain_step_max, h01(s, g, cu, 10u + uint(k)));
			}
			float life = mix(life_min, life_max, h01(s, g, cu, 20u + mu));
			float age = t - born;
			if (age >= 0.0 && age < life && born <= total_duration - settle_seconds) {
				float entrance = 1.0 + entrance_peak_gain * exp(-cycleStart / entrance_decay);
				float leaderPeak = (peak_min + (1.0 - peak_min)
						* pow(h01(s, g, cu, 7u), peak_skew)) * entrance;
				float peak = leaderPeak;
				if (member > 0) {
					peak *= mix(chain_peak_min, chain_peak_max, h01(s, g, cu, 30u + mu));
				}
				peak = min(peak, 1.0);
				float rise = mix(rise_min, rise_max, h01(s, g, cu, 40u + mu));
				float flickerRate = mix(flicker_rate_min, flicker_rate_max, h01(s, g, cu, 50u + mu));
				float flickerPhase = 6.2831853 * h01(s, g, cu, 60u + mu);
				float flicker = 1.0 + flicker_depth * sin(age * flickerRate + flickerPhase);
				float settle = clamp((total_duration - t) / max(settle_seconds, 0.001), 0.0, 1.0);
				intensity = peak * min(1.0, age / rise)
						* pow(1.0 - age / life, fall_exponent) * flicker * settle;

				// Placement: an ellipse round the body's outline, in the
				// camera's plane. The vertical half-extent is the body's
				// projected screen height, not its world height.
				int body = clamp(group % max(body_count, 1), 0, 7);
				vec3 right = normalize(INV_VIEW_MATRIX[0].xyz);
				vec3 up = normalize(INV_VIEW_MATRIX[1].xyz);
				float upY = clamp(abs(up.y), 0.0, 1.0);
				vec2 bodyHalf = body_halves[body];
				float hw = bodyHalf.x * edge_scale;
				float hh = (bodyHalf.y * upY + bodyHalf.x * sqrt(1.0 - upY * upY)) * edge_scale;
				float theta = 6.2831853 * h01(s, g, cu, 8u);
				vec2 dir = vec2(cos(theta), sin(theta));
				vec2 p = dir * vec2(hw, hh);
				vec2 n = normalize(vec2(dir.x / max(hw, 0.001), dir.y / max(hh, 0.001)));
				float spread = h01(s, g, cu, 9u) + h01(s, g, cu, 70u) + h01(s, g, cu, 71u) - 1.5;
				p += n * (edge_outward_bias + edge_spread * spread * 1.15);
				if (member > 0) {
					vec2 tangent = vec2(-n.y, n.x);
					float side = h01(s, g, cu, 72u) < 0.5 ? -1.0 : 1.0;
					float gap = chain_gap_fraction * ray_length * (0.55 + 0.4 * leaderPeak);
					p += tangent * gap * float(member) * side;
				}
				p.y += mix(drift_up_min, drift_up_max, h01(s, g, cu, 80u + mu)) * age;
				p.x += drift_side * (2.0 * h01(s, g, cu, 90u + mu) - 1.0) * age;
				world = body_centers[body] + right * p.x + up * p.y;
			}
		}
	}

	v_intensity = intensity;
	if (intensity < 0.02) {
		VERTEX = vec3(0.0);
		v_local = vec2(0.0);
	} else {
		vec3 viewCentre = (VIEW_MATRIX * vec4(world, 1.0)).xyz;
		vec2 corner = VERTEX.xy * 2.0 * quad_half;
		VERTEX = viewCentre + vec3(corner, 0.0);
		v_local = corner;
	}
}

vec3 ramp(float e) {
	float stops[8] = float[8](ramp_e0, ramp_e1, ramp_e2, ramp_e3, ramp_e4, ramp_e5, ramp_e6, ramp_e7);
	vec3 colors[8] = vec3[8](ramp_c0.rgb, ramp_c1.rgb, ramp_c2.rgb, ramp_c3.rgb,
			ramp_c4.rgb, ramp_c5.rgb, ramp_c6.rgb, ramp_c7.rgb);
	if (e <= stops[0]) {
		return colors[0];
	}
	for (int k = 0; k < 7; k++) {
		if (e <= stops[k + 1]) {
			float f = (e - stops[k]) / max(stops[k + 1] - stops[k], 0.0001);
			return mix(colors[k], colors[k + 1], f);
		}
	}
	return colors[7];
}

void fragment() {
	float i = clamp(v_intensity, 0.0, 1.2);
	vec2 q = v_local;
	// World units per screen pixel, so widths never fall below the raster.
	float px = max(length(dFdx(q)), length(dFdy(q)));
	float a = radians(ray_angle_degrees);
	float u = q.x * cos(a) + q.y * sin(a);
	float v = -q.x * sin(a) + q.y * cos(a);
	float r2 = dot(q, q);

	float cs = max(core_sigma * (core_sigma_min + core_sigma_gain * i), core_min_pixels * px);
	float hs = max(core_sigma * halo_sigma_scale, cs * 1.5);
	float e = (core_base + core_gain * i) * exp(-r2 / (2.0 * cs * cs))
			+ halo_gain * i * exp(-r2 / (2.0 * hs * hs));

	float len = ray_length * (ray_min_fraction + (1.0 - ray_min_fraction) * pow(i, ray_length_exponent));
	float rayEnergy = ray_gain * pow(i, ray_exponent);
	float w0 = max(ray_width, ray_min_pixels * px);
	float t1 = 1.0 - abs(u) / len;
	float t2 = 1.0 - abs(v) / len;
	if (t1 > 0.0) {
		float w = w0 * (1.0 + ray_root_widen * t1);
		e += rayEnergy * exp(-v * v / (2.0 * w * w)) * pow(t1, ray_taper);
	}
	if (t2 > 0.0) {
		float w = w0 * (1.0 + ray_root_widen * t2);
		e += rayEnergy * exp(-u * u / (2.0 * w * w)) * pow(t2, ray_taper);
	}

	ALBEDO = ramp(e);
	ALPHA = 1.0;
}
