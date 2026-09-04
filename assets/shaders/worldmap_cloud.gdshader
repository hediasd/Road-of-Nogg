// Clouds over the world map: one horizontal quad per cloud, lying at an altitude above the
// ground and fogged by the same numbers the ground uses.
//
// THERE IS NO BILLBOARDING HERE, and that is the point of the approach rather than an omission.
// A standing structure has to be corrected because a vertical quad's squash is `f / D` and runs
// across the frame; a cloud is a flat sprite on a plane parallel to the ground, so the camera's
// own projection already does exactly the right thing to it -- the same thing it does to the
// terrain art. Perspective and parallax both come out free, which is the whole reason a cloud
// is modelled as a sprite at altitude and not as a scrolling texture.
//
// The fog and the curvature below are transcriptions of worldmap_ground.gdshader's, not
// reimplementations. If the ground's change, these must change with them.

shader_type spatial;
// Blended rather than discarded, unlike the props. A prop is opaque pixel art that must write
// depth and sort against its neighbours; a cloud is deliberately see-through, and the field
// guarantees no two overlap, so there is nothing for it to sort against.
render_mode unshaded, cull_disabled, depth_draw_never, shadows_disabled, blend_mix;

uniform sampler2D atlas : source_color, filter_nearest, repeat_disable;
// Where this cloud's art sits in the sheet, in UV: xy origin, zw size.
uniform vec4 sprite_rect = vec4(0.0, 0.0, 1.0, 1.0);

uniform float cloud_opacity : hint_range(0.0, 1.0) = 0.85;

uniform float fog_start = 21.0;
uniform float fog_end = 116.0;
uniform float fog_curve : hint_range(0.2, 4.0) = 1.4;
uniform vec4 fog_color : source_color = vec4(0.812, 0.914, 0.961, 1.0);

// The day's light, from WorldMapSun, so a cloud cannot disagree with the ground about what
// time it is.
uniform vec3 light_tint = vec3(1.0, 1.0, 1.0);

uniform float curvature_k : hint_range(0.0, 0.02) = 0.0;

// Fog is evaluated once per CLOUD, at its centre, and carried down as a varying -- for the same
// reason the props do it: a cloud is one object, not a surface, and a haze gradient running
// across an 11-tile sprite would read as the cloud fading out rather than as distance.
varying float cloud_fog;

vec3 to_gamma(vec3 c) {
	return pow(max(c, vec3(0.0)), vec3(1.0 / 2.2));
}

vec3 to_linear(vec3 c) {
	return pow(max(c, vec3(0.0)), vec3(2.2));
}

void vertex() {
	vec3 base_world = MODEL_MATRIX[3].xyz;
	vec3 camera_world = INV_VIEW_MATRIX[3].xyz;

	// GROUND-PLANE forward distance, not view-space depth -- the difference is roughly 3x at
	// this pitch, and every fog number in WorldMapFramingCatalog was derived against the
	// former. Yaw is pinned and forward is -Z, so ground distance is the world-Z difference.
	float depth = camera_world.z - base_world.z;
	cloud_fog = pow(clamp((depth - fog_start) / max(fog_end - fog_start, 0.001), 0.0, 1.0), fog_curve);

	// The curve is taken at the GROUND POINT BENEATH the cloud, not at the cloud itself. Those
	// are different view depths, and using the cloud's own would drop it by the wrong amount and
	// let its height above the terrain drift with distance. Dropping by the ground's own value
	// is what keeps a cloud exactly `altitude` above the bent ground everywhere.
	//
	// And it is taken once, from the centre, then applied to the whole quad: the curve must
	// CARRY a sprite, not shear it. That is the same finding the prop shader records.
	vec3 ground_below = vec3(base_world.x, 0.0, base_world.z);
	float view_depth = -(VIEW_MATRIX * vec4(ground_below, 1.0)).z;
	VERTEX.y -= curvature_k * view_depth * view_depth;
}

void fragment() {
	vec2 uv = sprite_rect.xy + UV * sprite_rect.zw;
	vec4 texel = texture(atlas, uv);
	if (texel.a < 0.5) { discard; }

	// Blended in GAMMA space, matching the ground and the props. A deliberate departure from
	// physical correctness; blending in linear space put the ground and its sprites on visibly
	// different curves once already.
	vec3 albedo = texel.rgb * light_tint;
	ALBEDO = to_linear(mix(to_gamma(albedo), to_gamma(fog_color.rgb * light_tint), cloud_fog));
	ALPHA = cloud_opacity;
}
