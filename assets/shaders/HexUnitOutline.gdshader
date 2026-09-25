// The quiet hover cue on a hex battle unit: a thick, pixel-cut white rim around the unit's
// combined projected silhouette.
//
// ALPHA deliberately moves this overlay to the transparent pass. By then every opaque component
// of the model has written depth, so a head, body, weapon, and ornament occlude one another's
// expanded hull instead of each receiving a separate halo. Only the union's outer edge survives.
//
// Each vertex is pushed outward in clip space, scaled by viewport size and w, so the rim keeps a
// constant screen-pixel width at every camera zoom. Quantising that direction to eight compass
// steps replaces the smooth vector-like fringe with the game's chiseled pixel character.
shader_type spatial;
render_mode unshaded, cull_front, depth_draw_never, shadows_disabled, fog_disabled;

uniform vec4 outline_color : source_color = vec4(1.0, 1.0, 1.0, 1.0);
uniform float width_px = 4.0;

void vertex() {
	vec4 clip = PROJECTION_MATRIX * (MODELVIEW_MATRIX * vec4(VERTEX, 1.0));
	vec3 viewNormal = normalize(MODELVIEW_NORMAL_MATRIX * NORMAL);
	vec2 clipNormal = (PROJECTION_MATRIX * vec4(viewNormal, 0.0)).xy;
	float len = length(clipNormal);
	if (len > 0.00001) {
		const float DIRECTION_STEP = 0.78539816339;
		float angle = atan(clipNormal.y, clipNormal.x);
		float chiseledAngle = round(angle / DIRECTION_STEP) * DIRECTION_STEP;
		vec2 chiseledNormal = vec2(cos(chiseledAngle), sin(chiseledAngle));
		clip.xy += chiseledNormal * (width_px * 2.0 / VIEWPORT_SIZE) * clip.w;
	}
	POSITION = clip;
}

void fragment() {
	ALBEDO = outline_color.rgb;
	ALPHA = outline_color.a;
}
