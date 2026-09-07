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

// EDITOR GRID OVERLAY. Off by default, and every uniform below is inert at 0 -- the shipping
// path sets none of them and renders exactly as it did before this existed.
//
// It lives in THIS shader rather than a second pass on purpose. The alternative is a separate
// overlay mesh with its own shader transcribing the curvature displacement, and the project
// already has one of those arrangements: `worldmap_prop.gdshader` transcribes this file's fog,
// and section 9 of WORLDMAP_DESIGN.md records that the two must be kept in step by hand
// forever. One displacement is worth sharing this file for.
//
// Drawing it here is also what makes it ride the curved surface for free: the lines are a
// function of `world_position`, the UNDISPLACED position that already exists as a varying, so
// they land on the ground wherever the vertex stage put it without knowing that it moved.
//
// 0 off, 1 tile lines, 2 tile and cel lines.
uniform int grid_mode : hint_range(0, 2) = 0;
uniform vec4 grid_tile_color : source_color = vec4(1.0, 1.0, 1.0, 0.30);
uniform vec4 grid_cel_color : source_color = vec4(1.0, 1.0, 1.0, 0.12);
// Line thickness in SCREEN pixels, held constant with distance -- see `grid_coverage`.
uniform float grid_line_px = 1.25;
// Cursor highlight: xy is the corner in world units, zw the size. Zero size draws nothing.
uniform vec4 cursor_rect = vec4(0.0, 0.0, 0.0, 0.0);
uniform vec4 cursor_color : source_color = vec4(1.0, 0.85, 0.30, 0.45);

// HEX GEOMETRY SWITCH. Off by default -- the square path above is entirely untouched by
// anything below, and every uniform here is inert while this is false. `WorldMapSurfacePick.
// applyGrid()` is the only place that ever sets it true, and only when a caller explicitly asks
// for hex mode; nothing currently does (the wiring from an open document's layout is a later
// item's job, same as WALKABLE and LIFTABLE sat unread on a tile for two items before anything
// used them).
uniform bool grid_hex = false;
// The hex cursor's CENTRE, not a corner -- a hex has no natural width/height the way a square
// selection does, its shape is fixed by geometry and only its centre moves. `.z > 0.5` means
// active; kept separate from `cursor_rect` rather than overloading it, because a reader seeing
// `cursor_rect` used as xy=corner in one branch and xy=centre in another is exactly the kind of
// thing that reads correctly once and wrongly the next time someone touches this file.
uniform vec3 hex_cursor = vec3(0.0, 0.0, 0.0);

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

// Coverage of a grid line at `spacing` world units, about `grid_line_px` screen pixels wide
// however far away the ground is.
//
// `fwidth` of the scaled coordinate is how much of that coordinate one screen pixel spans, so
// dividing the distance-to-line by it converts a world-space measurement into a screen-space
// one. Without that the far half of a pitch-60 frame turns the lattice into a moire -- the
// lines converge below one pixel apart and alias against each other. This is deliberately NOT
// the treatment the ART gets: section 4 keeps the ground's sparkle because pixel noise is the
// look, but an editor overlay is chrome, and chrome that shimmers is just hard to aim with.
float grid_coverage(vec2 p, float spacing) {
	vec2 scaled = p / spacing;
	vec2 half_width = max(fwidth(scaled) * grid_line_px * 0.5, vec2(1e-6));
	vec2 to_line = abs(fract(scaled - 0.5) - 0.5) / half_width;
	return 1.0 - clamp(min(to_line.x, to_line.y), 0.0, 1.0);
}


// HEX GRID OVERLAY. `fract()` on world XZ has no hex analogue -- a hex lattice is not a
// rectangular repeat -- so this is a different technique from `grid_coverage()` above, not an
// extension of it. Every function here is a direct port of
// `src/presentation/worldmap/editor/WorldMapHexGrid.gd`, and it has to be a PORT rather than a
// re-derivation: that file's own header explains why independent-axis rounding fails at every
// hex seam, and a shader-side re-derivation that got the same detail wrong would draw a lattice
// that looks plausible while disagreeing with the picker along every boundary -- exactly the
// risk this item was scoped against. `probe_hex_grid_overlay.gd` asserts the two agree rather
// than trusting the port by inspection.

// World position (region-local) -> the nearest hex's AXIAL coordinate, as floats. Cube rounding,
// restoring `x + y + z = 0` by recomputing whichever of the three moved furthest -- see
// `WorldMapHexGrid.roundAxial`'s own comment for why independent rounding is wrong, not merely
// imprecise. The forward map (world -> fractional axial) is `WorldMapHexGrid.worldToCell`'s own,
// stopped one step before its final `axialToOffset` conversion.
vec2 hex_nearest_axial(vec2 p) {
	vec2 centred = p - vec2(1.0, 1.0);
	float qf = centred.x / 1.5;
	float rf = (centred.y - qf) / 2.0;

	float xf = qf;
	float zf = rf;
	float yf = -xf - zf;
	float rx = round(xf);
	float ry = round(yf);
	float rz = round(zf);
	float dx = abs(rx - xf);
	float dy = abs(ry - yf);
	float dz = abs(rz - zf);
	if (dx > dy && dx > dz) {
		rx = -ry - rz;
	} else if (dy > dz) {
		ry = -rx - rz;
	} else {
		rz = -rx - ry;
	}
	return vec2(rx, rz);
}

// Axial (q, r) -> its cell centre, in the same region-local world units `WorldMapHexGrid.
// cellCentre()` returns. Derived by inverting `hex_nearest_axial`'s own forward map; checked
// against that file's own hand-computed table (axial (1, 0) -> world (2.5, 2.0)) while writing
// this, and asserted against it by the probe rather than left to have been checked once by eye.
vec2 hex_axial_centre(vec2 axial) {
	return vec2(1.5 * axial.x + 1.0, 2.0 * axial.y + axial.x + 1.0);
}

// Signed distance to THIS PROJECT'S OWN flat-top hex shape -- not a generic regular hexagon.
// World-space width equals height here (both 2 units), which is deliberately NOT the 2:sqrt(3)
// ratio a regular hexagon has: it is what BECOMES regular once the pitch-60 camera's vertical
// squash (sin 60 = sqrt(3)/2) is applied on screen. `local` is a world position relative to the
// hex's own centre. Negative is inside, positive outside, zero on the boundary.
//
// Folding by `abs()` on both axes collapses the six edges to two unique ones -- the flat
// top/bottom edge and one slanted edge -- and the standard rule for a convex shape's SDF, the
// MAX of each edge's own signed distance, covers all six through that fold. `0.4472135955` is
// `1/sqrt(5)`, the slanted edge's normal length (the edge runs from (0.5, 1) to (1, 0), a
// direction of length sqrt(1.25); its perpendicular has length sqrt(1+4)=sqrt(5)).
float hex_edge_distance(vec2 local) {
	vec2 q = abs(local);
	// `flat` is a reserved GLSL keyword (an interpolation qualifier) and cannot be a variable
	// name here -- caught by an actual shader compile, not by GDScript's own parser, which has
	// no opinion on GLSL keywords at all.
	float flat_edge = q.y - 1.0;
	float slant = (2.0 * q.x + q.y - 2.0) * 0.4472135955;
	return max(flat_edge, slant);
}

// Distance from `p` to the line SEGMENT from the origin to `endpoint`. Used for the
// sub-triangle fan lines below -- six spokes from a hex's centre to its own six vertices, the
// same fan WMH-8's terrain triangulation and WMH-10's detail slots will use.
float distance_to_spoke(vec2 p, vec2 endpoint) {
	float t = clamp(dot(p, endpoint) / dot(endpoint, endpoint), 0.0, 1.0);
	return length(p - endpoint * t);
}

// Coverage of the hex lattice's boundary lines. Same screen-space-constant-width treatment as
// `grid_coverage()`, and the same reason: without it, the far half of a pitch-60 frame turns the
// lattice into a moire.
float hex_line_coverage(vec2 p) {
	vec2 centre = hex_axial_centre(hex_nearest_axial(p));
	float d = hex_edge_distance(p - centre);
	float w = max(fwidth(d) * grid_line_px * 0.5, 1e-6);
	return 1.0 - clamp(abs(d) / w, 0.0, 1.0);
}

// Coverage of the sub-triangle fan: six spokes from a hex's own centre to its six vertices --
// GEOMETRY only, drawn ahead of there being any data or tool to gate it on. Folding by `abs()`
// the same way `hex_edge_distance` does collapses the six spokes to the two unique ones this
// tests distance against, (1, 0) and (0.5, 1).
float hex_subtriangle_coverage(vec2 p) {
	vec2 centre = hex_axial_centre(hex_nearest_axial(p));
	vec2 q = abs(p - centre);
	float d = min(distance_to_spoke(q, vec2(1.0, 0.0)), distance_to_spoke(q, vec2(0.5, 1.0)));
	float w = max(fwidth(d) * grid_line_px * 0.5, 1e-6);
	return 1.0 - clamp(d / w, 0.0, 1.0);
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
	vec3 composed = mix(to_gamma(ground), to_gamma(fog_color.rgb * light_tint), fog);

	// AFTER the fog, and only on-map. The overlay is chrome rather than part of the scene, so it
	// stays legible at the far edge of the frame instead of hazing out exactly where the tiles
	// are smallest and aiming is hardest. Off-map it is suppressed: there is no tile out there
	// to point at.
	if (grid_mode > 0 && !off_map) {
		vec2 p = world_position.xz;
		if (grid_hex) {
			// A HEX DOCUMENT'S OVERLAY. Entirely separate from the square branch below --
			// nothing here shares state with it beyond `p`, `grid_mode` and the two colour
			// uniforms, which the hex path reuses for the same roles (coarse lattice, fine
			// detail) rather than needing its own.
			if (hex_cursor.z > 0.5) {
				float cursorDistance = hex_edge_distance(p - hex_cursor.xy);
				float cursorWidth = max(fwidth(cursorDistance), 1e-6);
				float fill = clamp(0.5 - cursorDistance / cursorWidth, 0.0, 1.0);
				composed = mix(composed, to_gamma(cursor_color.rgb), cursor_color.a * fill);
			}
			// Sub-triangle fan first so the hex lattice draws over it, matching the square
			// path's own cel-under-tile ordering: the coarser grid wins where they coincide.
			if (grid_mode == 2) {
				float fan = hex_subtriangle_coverage(p) * grid_cel_color.a;
				composed = mix(composed, to_gamma(grid_cel_color.rgb), fan);
			}
			float hexLine = hex_line_coverage(p) * grid_tile_color.a;
			composed = mix(composed, to_gamma(grid_tile_color.rgb), hexLine);
		} else {
			if (cursor_rect.z > 0.0 && cursor_rect.w > 0.0) {
				vec2 inside = step(cursor_rect.xy, p) * step(p, cursor_rect.xy + cursor_rect.zw);
				composed = mix(composed, to_gamma(cursor_color.rgb), cursor_color.a * inside.x * inside.y);
			}
			// Cel lines first so the tile lines draw over them: a tile boundary is also a cel
			// boundary, and the coarser grid is the one that should win where they coincide.
			if (grid_mode == 2) {
				// One cel is half a world unit -- the tile law's constant ratio, spelled here as
				// the spacing it implies rather than as a second constant to keep in step.
				float cel = grid_coverage(p, 0.5) * grid_cel_color.a;
				composed = mix(composed, to_gamma(grid_cel_color.rgb), cel);
			}
			float tile = grid_coverage(p, 1.0) * grid_tile_color.a;
			composed = mix(composed, to_gamma(grid_tile_color.rgb), tile);
		}
	}

	ALBEDO = to_linear(composed);
}
