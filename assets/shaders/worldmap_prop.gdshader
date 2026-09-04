// Standing structures on the world map: one quad per prop, billboarded and fogged by the same
// numbers as the ground it stands on.
//
// WHY THIS EXISTS RATHER THAN Sprite3D's OWN MATERIAL. Sprite3D gives billboarding away for
// free, which is what made `face` cheap -- but its material cannot be replaced without losing
// that, so `gain` had to be a CPU pass rescaling every sprite every frame, and there was
// nowhere to put fog at all. Props therefore did not fog while the ground did, and a distant
// structure sat un-hazed on ground that had already faded. Doing the billboard here costs one
// vertex branch and buys back both.
//
// The fog below is a transcription of worldmap_ground.gdshader's, not a reimplementation. Two
// of its properties are deliberate departures from the obvious and each was a defect once --
// see the comments at both sites. If the ground's fog changes, this must change with it.

shader_type spatial;
render_mode unshaded, cull_disabled, depth_draw_opaque, shadows_disabled;

uniform sampler2D atlas : source_color, filter_nearest, repeat_disable;
// Where this prop's art sits in the atlas, in UV: xy origin, zw size. The atlas keeps the
// region's own coordinates, so a prop's rect is simply where the structure was found and
// there is no packing step to hold in sync.
uniform vec4 sprite_rect = vec4(0.0, 0.0, 1.0, 1.0);

// 0 world-vertical, 1 proportion gain, 2 face camera. Matches BILLBOARD_IDS' order minus
// `off`, which never reaches a material.
uniform int billboard_mode : hint_range(0, 2) = 2;
// The prop's true world height, before any correction. The gain mode solves against it.
uniform float prop_height = 1.0;

uniform float fog_start = 21.0;
uniform float fog_end = 116.0;
uniform float fog_curve : hint_range(0.2, 4.0) = 1.4;
uniform vec4 fog_color : source_color = vec4(0.812, 0.914, 0.961, 1.0);

// The day's light. A multiplier so the sprite and the ground move together; the value comes
// from WorldMapSun so the two cannot disagree about what time it is.
uniform vec3 light_tint = vec3(1.0, 1.0, 1.0);

// The ground bends by `curvature_k * d^2` in its own vertex stage. A prop that does not take
// the same drop hangs in the air, and the gap grows with the SQUARE of distance -- measured at
// 13 px of daylight between a building and its own shadow at k = 0.006.
//
// The drop is taken from the BASE's depth and applied to the whole quad, so the curve CARRIES
// the sprite rather than shearing it. Per-vertex would stretch a building as the ground falls
// away under it, which is the same mistake the sketch made before it projected props rigidly.
uniform float curvature_k : hint_range(0.0, 0.02) = 0.0;

// Pixels that light themselves after dark, in the atlas's own coordinates. A lit window is
// EMISSIVE: it replaces the night rather than being multiplied by it. Multiplying a window by
// a blue night and adding warmth back gives a muddy grey-green; lerping the whole pixel toward
// the lamp colour is what reads as "there is a light in there".
uniform sampler2D emissive_mask : hint_default_black, filter_nearest, repeat_disable;
uniform vec3 emissive_color = vec3(1.0, 0.839, 0.541);
uniform float emissive_amount : hint_range(0.0, 1.0) = 0.0;

// A cloud passing over darkens the building too, by the same amount it darkens the ground
// around it -- otherwise the shadow's edge slides UNDER the structures instead of crossing the
// scene as one line, which is the seam the subtractive lamps exist to remove on the night side.
//
// SAMPLED ONCE AT THE BASE, not per fragment, and not through the ground's own shadow_mask
// uniform -- this is `cloud_mask` alone, deliberately without the cast-shadow layer mixed in.
// A standing sprite occupies map pixels it is not actually standing ON; a per-fragment lookup
// would sample ground the building merely stands in FRONT of, and the sprite would be striped
// by whatever shadow happens to fall behind it. The base is the one map pixel that is honestly
// this prop's own position, which is the same reasoning that puts `prop_fog` at the foot.
uniform sampler2D cloud_mask : hint_default_black, filter_nearest, repeat_disable;
uniform float cloud_shadow_strength : hint_range(0.0, 1.0) = 0.0;
uniform vec2 region_origin = vec2(0.0, 0.0);
uniform vec2 region_size = vec2(48.0, 64.0);

// Fog is evaluated once per PROP, at its foot, and carried down as a varying. A structure is
// one object a tile across, not a surface: fogging it per fragment would run a haze gradient
// up its height, and under `face` the quad leans toward the camera so that gradient would
// change with the camera rather than with where the building is.
varying float prop_fog;
// How much a cloud is shadowing this prop's own ground point, in [0, 1]. Carried the same way
// `prop_fog` is: computed once at the base, applied flatly across the whole quad.
varying float prop_cloud_shade;

vec3 to_gamma(vec3 c) {
	return pow(max(c, vec3(0.0)), vec3(1.0 / 2.2));
}

vec3 to_linear(vec3 c) {
	return pow(max(c, vec3(0.0)), vec3(2.2));
}

void vertex() {
	// The quad is authored with its FOOT on the model origin, extending +Y, so the origin is
	// the point standing on the ground and every mode below moves only the top.
	vec3 base_world = MODEL_MATRIX[3].xyz;
	vec3 camera_world = INV_VIEW_MATRIX[3].xyz;

	// GROUND-PLANE forward distance, not view-space depth. These are different quantities and
	// the difference is roughly 3x at this pitch. Every fog number in WorldMapFramingCatalog
	// was derived against the former; using view depth here would fog props on a different
	// curve from the ground they stand on, which is the exact mismatch this shader removes.
	// Yaw is pinned and forward is -Z, so ground distance is the world-Z difference.
	float depth = camera_world.z - base_world.z;
	prop_fog = pow(clamp((depth - fog_start) / max(fog_end - fog_start, 0.001), 0.0, 1.0), fog_curve);

	vec2 cloud_uv = (base_world.xz - region_origin) / region_size;
	prop_cloud_shade = cloud_shadow_strength * texture(cloud_mask, cloud_uv).r;

	// Matches the ground's curve exactly: same constant, same quantity. The ground uses the
	// VIEW depth of the vertex, so this uses the view depth of the prop's base.
	float view_depth = -(VIEW_MATRIX * vec4(base_world, 1.0)).z;
	float curve_drop = curvature_k * view_depth * view_depth;

	if (billboard_mode == 2) {
		// FACE CAMERA. Rebuild the modelview from the camera's own basis, keeping the model's
		// translation -- so the quad turns about its foot and stays planted.
		//
		// Put the camera's up-axis into the projection identity and it gives A = 1, B = 0, so
		// hpx/wpx = h/W exactly: painted proportions at every distance and every pitch, with
		// no correction term at all. That, and not "it cancels cos(pitch)", is why this mode
		// is the robust one.
		// The curve drop rides in the translation column, because this mode replaces the
		// model transform outright and a VERTEX offset would be discarded with it.
		MODELVIEW_MATRIX = VIEW_MATRIX * mat4(
			vec4(normalize(INV_VIEW_MATRIX[0].xyz), 0.0),
			vec4(normalize(INV_VIEW_MATRIX[1].xyz), 0.0),
			vec4(normalize(INV_VIEW_MATRIX[2].xyz), 0.0),
			MODEL_MATRIX[3] - vec4(0.0, curve_drop, 0.0, 0.0)
		);
	} else if (billboard_mode == 1) {
		// PROPORTION GAIN. The quad stays honestly vertical and its world height is scaled
		// until the projection lands on painted proportions anyway.
		//
		// The squash a vertical quad takes is NOT cos(pitch) -- that value holds only at the
		// exact centre of the frame. It is f / D, ground distance over view depth, and across
		// one frame at the reference framing it runs 0.33 near to 0.76 far. So the correction
		// is per prop, from this prop's own distance, and it is a closed-form solve:
		//     h = h0 * D / (f + h0 * sin(pitch))
		// The camera's basis lives in INV_VIEW_MATRIX, not VIEW_MATRIX -- VIEW_MATRIX is the
		// world-to-view transform and its columns are not the camera's axes. Camera forward is
		// -INV_VIEW_MATRIX[2], so sin(pitch) is that column's own y.
		float sin_pitch = clamp(INV_VIEW_MATRIX[2].y, 0.0, 1.0);
		float denom = depth + prop_height * sin_pitch;
		// NOT clamped below at 1. Past the frame centre a vertical quad is magnified rather
		// than squashed, so far props correct DOWNWARD; a floor of 1.0 looks like the obvious
		// guard and silently leaves everything beyond mid-frame too tall, which is the very
		// defect this mode exists to remove.
		float gain = denom > 0.001 ? clamp(view_depth / denom, 0.1, 8.0) : 1.0;
		VERTEX.y *= gain;
	}
	// billboard_mode == 0 is world-vertical: the quad as authored, and the uncorrected look.

	if (billboard_mode != 2) {
		// The model has an identity basis, so a model-space Y offset is a world-space one.
		VERTEX.y -= curve_drop;
	}
}

void fragment() {
	vec2 uv = sprite_rect.xy + UV * sprite_rect.zw;
	vec4 texel = texture(atlas, uv);
	// Hard-edged pixel art: discard rather than blend, so props write depth and sort against
	// each other instead of living in the transparent pass where neither is reliable.
	if (texel.a < 0.5) { discard; }

	// Blended in GAMMA space. A deliberate departure from physical correctness, matching the
	// ground's; blending in linear space put the two on visibly different curves and was one
	// of the three defects behind the original convergence failure.
	vec3 albedo = texel.rgb * light_tint;
	if (emissive_amount > 0.0 && texture(emissive_mask, uv).r > 0.5) {
		albedo = mix(albedo, emissive_color, emissive_amount);
	}
	// Before the fog blend, not after: a cloud shadow lies ON the surface the same way the
	// ground's own cast shadows do, so it has to be dimmed by distance along with everything
	// else rather than painted over the haze.
	albedo *= 1.0 - prop_cloud_shade;
	ALBEDO = to_linear(mix(to_gamma(albedo), to_gamma(fog_color.rgb * light_tint), prop_fog));
}
