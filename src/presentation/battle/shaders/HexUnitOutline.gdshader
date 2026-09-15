// The quiet hover cue on a hex battle unit: a white rim a constant few pixels wide around the
// unit's projected silhouette.
//
// An inverted hull drawn through `material_overlay`, so the unit's own materials are never
// touched. Each vertex is pushed outward along its normal in clip space, scaled by the viewport
// size and by w, so the rim is the same number of screen pixels wide whether the camera is zoomed
// in on the unit or framing the whole board. A world-space push would thin to nothing at the far
// zoom and turn into a slab up close. Front faces are culled, so the near side of the hull never
// covers the unit; only the part that pokes out past the silhouette is seen.
shader_type spatial;
render_mode unshaded, cull_front, shadows_disabled, fog_disabled;

uniform vec4 outline_color : source_color = vec4(1.0, 1.0, 1.0, 1.0);
uniform float width_px = 2.5;

void vertex() {
	vec4 clip = PROJECTION_MATRIX * (MODELVIEW_MATRIX * vec4(VERTEX, 1.0));
	vec3 viewNormal = normalize(MODELVIEW_NORMAL_MATRIX * NORMAL);
	vec2 clipNormal = (PROJECTION_MATRIX * vec4(viewNormal, 0.0)).xy;
	float len = length(clipNormal);
	if (len > 0.00001) {
		clip.xy += (clipNormal / len) * (width_px * 2.0 / VIEWPORT_SIZE) * clip.w;
	}
	POSITION = clip;
}

void fragment() {
	ALBEDO = outline_color.rgb;
}
