// Backdrop for the world map. Deliberately NOT a WorldEnvironment sky: environment fog is
// skipped by unshaded materials, so the ground computes its own haze, and introducing an
// environment purely for a background would couple the two for no gain. See
// docs/WORLDMAP_DESIGN.md section 4.
//
// This is a quad parented to the camera, sized to fill the frustum at a distance far beyond
// the ground plane, so anything the ground does not cover shows sky. Yaw is pinned to 0 and
// the camera never rolls, so a flat backdrop is enough; no dome is needed.
shader_type spatial;
render_mode unshaded, cull_disabled, depth_draw_never, shadows_disabled;

uniform sampler2D sky_texture : source_color, filter_nearest, repeat_disable;
// Offset and zoom happen in UV rather than by moving the quad, so the quad always fills the
// frame exactly and only the image slides inside it.
uniform float sky_offset : hint_range(-1.0, 1.0) = 0.0;
uniform float sky_scale : hint_range(0.2, 4.0) = 1.0;
uniform vec4 sky_tint : source_color = vec4(1.0, 1.0, 1.0, 1.0);

void fragment() {
	// Clamped rather than tiled: the top row of a sky should extend upward forever, and a
	// repeat would stack a second horizon above the first.
	vec2 uv = clamp((UV - vec2(0.5)) / max(sky_scale, 0.001) + vec2(0.5, 0.5 + sky_offset),
		vec2(0.0), vec2(1.0));
	ALBEDO = texture(sky_texture, uv).rgb * sky_tint.rgb;
}
