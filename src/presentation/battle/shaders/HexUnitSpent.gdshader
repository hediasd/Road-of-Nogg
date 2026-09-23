// How a piece shows that its turn is going or gone, applied through `material_overlay` so the
// unit's own materials are never touched.
//
// It darkens rather than drains. An earlier version replaced the piece with its own luminance under
// a slate tint, which made every used unit the same grey and threw away the thing a player reads
// first: whose it is and what it is. A unit that has acted should look like itself in shadow.
//
// Two depths, because a turn has two endings. A unit that has moved but still holds its action is
// **partly** done and takes the shallower darkening; one that has acted or waited is finished and
// takes the deeper one. The gap between them has to survive being seen next to a ready unit at a
// glance, which is why they are set from constants in the adapter rather than guessed per call.
shader_type spatial;
render_mode unshaded, cull_back, depth_draw_never, blend_mix;

uniform sampler2D screen_tex : hint_screen_texture, filter_nearest;
// What the drawn pixel is multiplied by. Below one it darkens; the slight cool bias keeps a
// darkened yellow from reading as brown.
//
// Deliberately not `source_color`: this is a multiplier, not a colour, and tagging it would have
// Godot convert it between colour spaces on the way in. The multiply itself happens in linear
// space, so the darkening a player sees is roughly this value raised to 1/2.2 -- 0.15 here shows
// as a little under half brightness on screen. The adapter's constants are chosen against
// measured on-screen ratios rather than against these numbers.
uniform vec3 darken = vec3(0.15, 0.16, 0.20);
// Nudged toward the camera in clip space rather than outward along the surface. Pushing each
// vertex along its own normal splits the hull wherever the model has a hard crease -- the faces
// meeting at the collar and the base rim carry different normals, so inflating pulled them apart
// and opened rings of undarkened colour exactly there. A depth bias moves nothing on screen and so
// cannot open a seam, while still winning the depth test against the vertex-snapped faces that
// made the original overlay speckle.
uniform float depth_bias = 0.0015;

void vertex() {
	vec4 clip = PROJECTION_MATRIX * (MODELVIEW_MATRIX * vec4(VERTEX, 1.0));
	clip.z += depth_bias * clip.w;
	POSITION = clip;
}

void fragment() {
	vec3 drawn = texture(screen_tex, SCREEN_UV).rgb;
	ALBEDO = drawn * darken;
	// Writing ALPHA moves the overlay to the transparent pass, which is what makes it one
	// treatment over one piece instead of one per component. In the opaque pass the overlay of a
	// component and the body of its neighbour were drawn in arbitrary order, so at every seam
	// between the stacked meshes a pawn is built from, the body sometimes won. By the transparent
	// pass every component has written depth, so each fragment tests against the finished
	// silhouette and covers it.
	ALPHA = 1.0;
}
