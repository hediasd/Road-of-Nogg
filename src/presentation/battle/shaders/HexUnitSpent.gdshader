// Spent-unit treatment, applied through `material_overlay` so the unit's own materials are never
// touched. It reads the already-drawn unit back from the screen and replaces it with its own
// luminance under a cool slate tint.
//
// Drains colour rather than darkening it: a flat dark overlay turned a yellow unit olive, which is
// the grass colour, and a dimmed red still read as "a red unit". Grey-slate reads as "used" on
// every terrain and team colour. The team plinth is not overlaid, so the side stays readable.
shader_type spatial;
render_mode unshaded, cull_back, depth_draw_never, blend_mix;

uniform sampler2D screen_tex : hint_screen_texture, filter_nearest;
uniform vec3 tint : source_color = vec3(0.36, 0.39, 0.46);
// A thin hull over the model. Drawn exactly on the surface, the overlay lost the depth test to the
// unit's own (vertex-snapped) faces in speckles that showed the original colour through.
uniform float inflate = 0.03;

void vertex() {
	VERTEX += NORMAL * inflate;
}

void fragment() {
	vec3 drawn = texture(screen_tex, SCREEN_UV).rgb;
	float luminance = dot(drawn, vec3(0.299, 0.587, 0.114));
	ALBEDO = vec3(luminance) * tint;
}
