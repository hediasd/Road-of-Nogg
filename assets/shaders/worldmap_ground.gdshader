// Ground plane for the out-of-battle world map: a painted region texture laid flat,
// viewed from a fixed yaw at a steep pitch, with the far distance washing out into haze.
//
// Fog is computed HERE rather than by a WorldEnvironment. Godot 4 skips environment fog
// on unshaded materials, so routing it there yields either no fog or a lit ground, and it
// would couple the map's haze to whatever environment the battle scene wants. See
// docs/WORLDMAP_DESIGN.md.
//
// Pass order is fixed: sample -> shadows (cast and cloud, unioned) -> light -> fog blend ->
// void substitution.
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
//   0 NEAREST      no mipmaps. Maximum sparkle. The DEFAULT, and what the reference
//                  does -- the sparkle is wanted here, see WORLDMAP_DESIGN.md.
//   1 NEAREST_MIP  crisp when magnified, stable when minified. Measurably softer.
//   2 LINEAR_MIP   smooth. The comparison that shows what the clean version costs.
uniform sampler2D region_nearest : source_color, filter_nearest, repeat_disable;
uniform sampler2D region_nearest_mip : source_color, filter_nearest_mipmap_anisotropic, repeat_disable;
uniform sampler2D region_linear_mip : source_color, filter_linear_mipmap_anisotropic, repeat_disable;
uniform int filter_mode : hint_range(0, 2) = 0;

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
// With a backdrop enabled the off-map area must show it rather than a void colour. The
// plane is deliberately far larger than the region, so without this its fogged void sits in
// front of the sky and hides all but the strip above the plane's own edge.
uniform bool show_sky_beyond = false;

// Cast shadows, as a mask in MAP-PIXEL space sampled with the region's own UV and its own
// nearest filter. That is the whole reason shadows land on the terrain's pixel grid instead of
// at arbitrary sub-pixel screen positions, and why they do not crawl when the camera pans -- a
// screen-space shadow quad cannot be made to read as pixel art at any edge treatment.
//
// It also means a shadow is fogged, curved and filtered for free: it rides the same sample the
// ground does, because it IS the ground.
// R carries the cast shadow, G the lamp light. One texture because they are the same
// mechanism seen twice: both modulate a per-pixel light level on the ground.
uniform sampler2D shadow_mask : hint_default_black, filter_nearest, repeat_disable;
uniform float shadow_strength : hint_range(0.0, 1.0) = 0.0;

// The day's light, as a multiplier. `lamp_lit` is what a lamp-lit pixel is tinted BY -- not
// white, because a lamp is warm and holding it slightly warm keeps a lit circle from reading
// as a hole punched in the night.
uniform vec3 light_tint = vec3(1.0, 1.0, 1.0);
uniform vec3 lamp_lit = vec3(1.06, 0.98, 0.84);
// How much night there is to withhold. A lamp is SUBTRACTIVE: it does not add warm light on
// top, it is a region where the night is not applied, so the ground under it keeps its daytime
// colours. Nothing in this path can produce a colour the region's art does not contain, which
// is the whole difference between a light that belongs to a flat palette and one grafted on.
uniform float night_amount : hint_range(0.0, 1.0) = 0.0;

// How a shadowed pixel gets its colour. 0 multiplies, which is arithmetic and invents colours
// the palette does not contain -- a darkened sand that is not any of this map's seven. 1 snaps
// the darkened result back to the nearest colour the art actually uses, so every shadowed
// pixel is one somebody painted. The palette is read from the region texture at load: it IS
// whatever was painted, and a hand-kept list would drift from the PNG silently.
uniform int shadow_color_mode : hint_range(0, 1) = 0;
uniform vec4 palette[16];
uniform int palette_size = 0;

vec3 snap_to_palette(vec3 c) {
	if (palette_size <= 0) { return c; }
	vec3 best = palette[0].rgb;
	float bestDistance = 1e9;
	for (int i = 0; i < palette_size; i++) {
		vec3 entry = palette[i].rgb;
		vec3 d = c - entry;
		float distance = dot(d, d);
		if (distance < bestDistance) { bestDistance = distance; best = entry; }
	}
	return best;
}

// Ground curvature: y = -k * d^2 in view space, so the world falls away with distance.
// Zero is flat and is the reference. Non-zero pulls the horizon nearer.
uniform float curvature_k : hint_range(0.0, 0.02) = 0.0;

// Cloud shadows, as COVERAGE IN MAP-PIXEL SPACE -- the same space the cast-shadow mask lives
// in, sampled with the same region UV and the same nearest filter, for the same reasons: edges
// land on the terrain's own grid, they do not crawl when the camera pans, and the shadow is
// fogged and curved and filtered for free because it rides the ground's own sample.
//
// It replaced four octaves of value noise, which had no shape anybody drew, no cloud above it
// to explain it, and no altitude. Do not reintroduce a procedural fallback: a cloud shadow with
// no cloud is the thing this removed.
uniform sampler2D cloud_mask : hint_default_black, filter_nearest, repeat_disable;
uniform float cloud_shadow_strength : hint_range(0.0, 1.0) = 0.0;
// How far the dithered fringe reaches, in MAP pixels. Zero is a hard edge, which is what the
// art is and what the rest of the map does.
uniform float cloud_softness : hint_range(0.0, 4.0) = 0.0;
// The region in map pixels. Needed so the dither can be anchored to MAP pixels rather than to
// screen pixels -- a screen-anchored pattern swims under the camera and is the single fastest
// way to make pixel art stop looking like pixel art.
uniform vec2 map_size = vec2(248.0, 176.0);

varying vec3 world_position;

// The fog blend happens in GAMMA space, not linear. That is a deliberate departure from
// physical correctness: the framing and fog numbers were tuned in an 8-bit sRGB explorer
// against console captures, and 8-bit hardware blended in gamma space too. Blending the
// same fog fraction in linear space lands visibly lighter -- roughly 0.50 against 0.39 on a
// mid green at 29% fog -- so a linear blend would silently invalidate every tuned number.
vec3 to_gamma(vec3 c) {
	return mix(c * 12.92, 1.055 * pow(max(c, vec3(0.0031308)), vec3(1.0 / 2.4)) - 0.055,
		step(vec3(0.0031308), c));
}

vec3 to_linear(vec3 c) {
	return mix(c / 12.92, pow((max(c, vec3(0.04045)) + 0.055) / 1.055, vec3(2.4)),
		step(vec3(0.04045), c));
}

// Ordered dither for the cloud shadow's fringe, indexed by MAP pixel. Same 4x4 matrix
// WorldMapShadowMask uses on the CPU for the lamps, so the two treatments cannot drift.
const float BAYER4[16] = float[16](
	0.0, 8.0, 2.0, 10.0,
	12.0, 4.0, 14.0, 6.0,
	3.0, 11.0, 1.0, 9.0,
	15.0, 7.0, 13.0, 5.0
);

// Cloud coverage at a map position, with its edge broken up rather than blurred.
//
// A BLUR IS NOT AVAILABLE HERE. The art's alpha is binary, and the whole point of the palette
// snap is that no colour appears that the region does not already contain -- a blurred edge
// produces exactly those in-between values. So softness dithers instead, and only in a band at
// the boundary: applied across the whole shape it checkerboards the entire shadow, which the
// sketch did once before confining it.
float cloud_shadow_coverage(vec2 uv) {
	float centre = texture(cloud_mask, uv).r;
	if (cloud_softness <= 0.0 || centre <= 0.0) { return centre; }
	vec2 step_uv = (cloud_softness + 0.5) / map_size;
	float outside = 1.0 - min(
		min(texture(cloud_mask, uv + vec2(step_uv.x, 0.0)).r,
			texture(cloud_mask, uv - vec2(step_uv.x, 0.0)).r),
		min(texture(cloud_mask, uv + vec2(0.0, step_uv.y)).r,
			texture(cloud_mask, uv - vec2(0.0, step_uv.y)).r)
	);
	if (outside <= 0.0) { return centre; }
	ivec2 cell = ivec2(mod(floor(uv * map_size), 4.0));
	float threshold = (BAYER4[cell.y * 4 + cell.x] + 0.5) / 16.0;
	return threshold < 0.5 ? centre : 0.0;
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

	// Before the clouds and well before the fog: a shadow is something lying ON the ground, so
	// it must be dimmed by distance along with the ground rather than painted over the haze.
	vec2 masks = off_map ? vec2(0.0) : texture(shadow_mask, uv).rg;
	float cast_shade = shadow_strength * masks.r;
	float cloud_shade = 0.0;
	if (!off_map && cloud_shadow_strength > 0.0) {
		cloud_shade = cloud_shadow_strength * cloud_shadow_coverage(uv);
	}
	// MAX, NOT SUM. A building already in shadow does not get darker for being under a cloud
	// too -- shadows union, they do not stack, and summing them lands between palette entries
	// where snapping has to guess. It is the same reasoning the lamps use, and it is why this
	// is ONE darkening followed by ONE snap rather than two of each.
	float shade = max(cast_shade, cloud_shade);
	if (shade > 0.0) {
		vec3 shaded = albedo * (1.0 - shade);
		albedo = shadow_color_mode == 1 ? snap_to_palette(shaded) : shaded;
	}

	// The day's light, with the night withheld wherever a lamp reaches. Ground and props take
	// this from the same values, so a building cannot end up lit to one value while the grass
	// under it is lit to another -- that seam is invisible in a thumbnail and obvious in motion.
	vec3 tint = mix(light_tint, lamp_lit, clamp(masks.g * night_amount, 0.0, 1.0));
	albedo *= tint;

	// GROUND-PLANE forward distance, not view-space depth. These are different quantities
	// and the difference is roughly 3x at this pitch: a fragment at the bottom of the frame
	// is 21 units forward along the ground but 68 units along the camera's tilted forward
	// axis. Every fog number in WorldMapFramingCatalog was derived against the former, so
	// using `-VERTEX.z` here fogged the entire frame and compressed the gradient to half its
	// range. Yaw is pinned to 0 and forward is -Z, so the ground distance is exactly the
	// world-Z difference -- which also keeps the haze a horizontal band rather than bulging
	// at the screen edges.
	float depth = CAMERA_POSITION_WORLD.z - world_position.z;
	float fog = pow(clamp((depth - fog_start) / max(fog_end - fog_start, 0.001), 0.0, 1.0), fog_curve);

	if (off_map && show_sky_beyond) { discard; }

	// Fog and void take the same light as the ground. Leaving them fixed is what makes a day
	// cycle fall apart: a pale teal horizon behind a midnight-blue map reads as a bug.
	vec3 ground = off_map ? void_color.rgb * light_tint : albedo;
	ALBEDO = to_linear(mix(to_gamma(ground), to_gamma(fog_color.rgb * light_tint), fog));
}
