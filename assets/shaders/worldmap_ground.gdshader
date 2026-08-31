// Ground plane for the out-of-battle world map: a painted region texture laid flat,
// viewed from a fixed yaw at a steep pitch, with the far distance washing out into haze.
//
// Fog is computed HERE rather than by a WorldEnvironment. Godot 4 skips environment fog
// on unshaded materials, so routing it there yields either no fog or a lit ground, and it
// would couple the map's haze to whatever environment the battle scene wants. See
// docs/WORLDMAP_DESIGN.md.
//
// Pass order is fixed: sample -> cloud shadow multiply -> fog blend -> void substitution.
// The void is substituted rather than blended so an off-map fragment never carries a
// smeared edge texel, and it is placed after fog so a fogged region edge stays soft while
// an unfogged one reads as a hard plane edge -- which is what the reference does.

shader_type spatial;
render_mode unshaded, cull_disabled, depth_draw_opaque, shadows_disabled;

// The same texture is bound to all three samplers. Godot resolves filtering from the
// uniform hint at compile time, so a runtime-switchable filter needs one sampler per
// mode; there is no way to change a hint from GDScript. One extra binding of an already
// resident texture is cheaper than the alternatives, and the debug scene needs the
// comparison. `filter_mode` selects:
//   0 NEAREST      no mipmaps. Maximum sparkle. What the low-resolution reference does.
//   1 NEAREST_MIP  crisp when magnified, stable when minified. The default.
//   2 LINEAR_MIP   smooth. The comparison that shows what the clean version costs.
uniform sampler2D region_nearest : source_color, filter_nearest, repeat_disable;
uniform sampler2D region_nearest_mip : source_color, filter_nearest_mipmap_anisotropic, repeat_disable;
uniform sampler2D region_linear_mip : source_color, filter_linear_mipmap_anisotropic, repeat_disable;
uniform int filter_mode : hint_range(0, 2) = 1;

// Where the region sits on the plane, in world units. The plane is deliberately larger
// than the region so fog has somewhere to close before the art runs out; everything
// outside this rectangle is void.
uniform vec2 region_origin = vec2(0.0, 0.0);
uniform vec2 region_size = vec2(48.0, 64.0);

// Distance haze. In the reference this never completes on screen -- it is a wash, not a
// wall -- so `fog_end` sitting beyond the far edge of the frame is the normal case.
uniform float fog_start = 21.0;
uniform float fog_end = 116.0;
uniform float fog_curve : hint_range(0.2, 4.0) = 1.4;
uniform vec4 fog_color : source_color = vec4(0.812, 0.914, 0.961, 1.0);
uniform vec4 void_color : source_color = vec4(0.0, 0.0, 0.0, 1.0);

// Ground curvature: y = -k * d^2 in view space, so the world falls away with distance.
// Zero is flat and is the reference. Non-zero pulls the horizon nearer.
uniform float curvature_k : hint_range(0.0, 0.02) = 0.0;

// Cloud shadows. Off in the reference; present because the debug scene must be able to
// explore them and because they are the cheapest thing that makes a static map feel alive.
uniform float cloud_strength : hint_range(0.0, 0.6) = 0.0;
// World units per noise cell. This is bounded above by the REGION size, not by taste:
// `cloud_cover` needs several cells across the visible ground to read as cloud rather than
// a flat tint, so a scale much past a third of the region's width does nothing at all.
// Measured on the 48-tile region: usable to ~16, negligible by 40, exactly zero by 80.
uniform float cloud_scale = 12.0;
uniform float cloud_speed = 1.2;

varying vec3 world_position;

float hash21(vec2 p) {
	return fract(sin(dot(p, vec2(127.1, 311.7))) * 43758.5453123);
}

float value_noise(vec2 p) {
	vec2 i = floor(p);
	vec2 f = fract(p);
	vec2 u = f * f * (3.0 - 2.0 * f);
	float a = hash21(i);
	float b = hash21(i + vec2(1.0, 0.0));
	float c = hash21(i + vec2(0.0, 1.0));
	float d = hash21(i + vec2(1.0, 1.0));
	return mix(mix(a, b, u.x), mix(c, d, u.x), u.y);
}

// Four octaves, then contrast-stretched so the result is patchy cloud rather than uniform
// haze. Generated rather than sampled: no particular cloud shape has been asked for, and a
// texture would be one more asset to keep in step with the region art.
float cloud_cover(vec2 p) {
	float total = 0.0;
	float amplitude = 1.0;
	float sum = 0.0;
	for (int octave = 0; octave < 4; octave++) {
		total += amplitude * value_noise(p);
		sum += amplitude;
		amplitude *= 0.5;
		p *= 2.0;
	}
	return clamp((total / sum - 0.38) / 0.34, 0.0, 1.0);
}

void vertex() {
	// Undisplaced world position: the curvature is a visual bend, so texture lookup and
	// the region rectangle must both use where the ground actually is, not where it is
	// drawn. Taking this before the displacement is the whole reason it is a varying.
	world_position = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;

	if (curvature_k > 0.0) {
		float forward_distance = -(MODELVIEW_MATRIX * vec4(VERTEX, 1.0)).z;
		VERTEX.y -= curvature_k * forward_distance * forward_distance;
	}
}

void fragment() {
	vec2 uv = (world_position.xz - region_origin) / region_size;
	bool off_map = uv.x < 0.0 || uv.x > 1.0 || uv.y < 0.0 || uv.y > 1.0;

	vec3 albedo;
	if (filter_mode == 0) {
		albedo = texture(region_nearest, uv).rgb;
	} else if (filter_mode == 2) {
		albedo = texture(region_linear_mip, uv).rgb;
	} else {
		albedo = texture(region_nearest_mip, uv).rgb;
	}

	if (cloud_strength > 0.0) {
		vec2 cloud_uv = world_position.xz / cloud_scale + vec2(TIME * cloud_speed * 0.05, 0.0);
		albedo *= 1.0 - cloud_strength * cloud_cover(cloud_uv);
	}

	// Planar depth, not radial: each screen row of this rig is a constant world depth, so
	// planar depth keeps the haze a horizontal band instead of bulging at the screen edges.
	float depth = -VERTEX.z;
	float fog = pow(clamp((depth - fog_start) / max(fog_end - fog_start, 0.001), 0.0, 1.0), fog_curve);
	albedo = mix(albedo, fog_color.rgb, fog);

	ALBEDO = off_map ? mix(void_color.rgb, fog_color.rgb, fog) : albedo;
}
