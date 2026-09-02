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

// Fog is evaluated once per PROP, at its foot, and carried down as a varying. A structure is
// one object a tile across, not a surface: fogging it per fragment would run a haze gradient
// up its height, and under `face` the quad leans toward the camera so that gradient would
// change with the camera rather than with where the building is.
varying float prop_fog;

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

	if (billboard_mode == 2) {
		// FACE CAMERA. Rebuild the modelview from the camera's own basis, keeping the model's
		// translation -- so the quad turns about its foot and stays planted.
		//
		// Put the camera's up-axis into the projection identity and it gives A = 1, B = 0, so
		// hpx/wpx = h/W exactly: painted proportions at every distance and every pitch, with
		// no correction term at all. That, and not "it cancels cos(pitch)", is why this mode
		// is the robust one.
		MODELVIEW_MATRIX = VIEW_MATRIX * mat4(
			vec4(normalize(INV_VIEW_MATRIX[0].xyz), 0.0),
			vec4(normalize(INV_VIEW_MATRIX[1].xyz), 0.0),
			vec4(normalize(INV_VIEW_MATRIX[2].xyz), 0.0),
			MODEL_MATRIX[3]
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
		float view_depth = -(VIEW_MATRIX * vec4(base_world, 1.0)).z;
		float denom = depth + prop_height * sin_pitch;
		// NOT clamped below at 1. Past the frame centre a vertical quad is magnified rather
		// than squashed, so far props correct DOWNWARD; a floor of 1.0 looks like the obvious
		// guard and silently leaves everything beyond mid-frame too tall, which is the very
		// defect this mode exists to remove.
		float gain = denom > 0.001 ? clamp(view_depth / denom, 0.1, 8.0) : 1.0;
		VERTEX.y *= gain;
	}
	// billboard_mode == 0 is world-vertical: the quad as authored, and the uncorrected look.
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
	ALBEDO = to_linear(mix(to_gamma(albedo), to_gamma(fog_color.rgb * light_tint), prop_fog));
}
