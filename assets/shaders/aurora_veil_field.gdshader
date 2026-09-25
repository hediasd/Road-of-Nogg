// Iridescent veil panel for the Aurora Veil spell.
//
// The field is carried by one upright quad standing at the impact centre,
// Y-axis billboarded: the panel keeps world up and yaws to face the camera, so
// the reflection's waterline stays horizontal on screen at every camera yaw.
// A full billboard would tilt that seam with the camera pitch and the mirror
// would stop reading as a reflection, which is the motif the reference leans on
// hardest. See §4 of docs/VFX_DESIGN.md for the fork-vs-fresh decision.
//
// Every value is a pure function of `playback_time` and position. Nothing
// integrates across frames, which is what lets AuroraVeilEffect report exact
// normalized seek and lets the debug harness scrub in either direction. The
// grain is animated but still seek-exact: it hashes a *quantized* frame index
// derived from playback_time, never a running counter. Adding any
// frame-accumulated term here silently breaks scrubbing -- put state in the
// GDScript timeline instead.
//
// Grain samples FRAGCOORD whenever the field is not snapped to cells. On mesh
// UV it would magnify as the camera closes and read as painted texture; on
// FRAGCOORD it stays pinned to screen pixels and keeps reading as film grain.
// Once `pixel_cells` is active that argument inverts and the grain moves onto
// the cell grid -- see the note at the grain itself.

// Blending is `blend_mix`, not `blend_add`, and the distinction only exists
// because the veil left the reference's black frame. Over black the two are
// identical -- but added over lit terrain every hue climbs toward white and the
// iridescence turns grey, which is exactly the information the effect exists to
// carry. Mixing keeps the ramp's colour on any background.
// Depth testing is *disabled* so the curtain draws over the models rather than
// being clipped by them, and the occlusion is then resolved in the fragment
// instead: where scene geometry sits in front of the panel, the curtain goes
// transparent and lights the model rather than covering it. That trade is
// deliberate -- it costs the reference's silhouette-in-front composition and
// buys the curtain passing over the board as light.
shader_type spatial;
render_mode unshaded, blend_mix, depth_draw_never, depth_test_disabled, cull_disabled;

const float TAU_VALUE = 6.28318530718;
const int RAMP_STOPS = 9;
const vec3 WORLD_UP = vec3(0.0, 1.0, 0.0);

// --- Panel framing ----------------------------------------------------------
// Where the field sits inside the quad's own UV. `y` is the reflection seam.
uniform vec2 veil_anchor = vec2(0.5, 0.54);
// Quad width over height, so the field stays circular in world units rather
// than in UV.
uniform float aspect_ratio = 1.27;

// --- Field geometry ---------------------------------------------------------
uniform float core_offset = 0.220;
uniform vec2 band_radius = vec2(0.265, 0.390);
uniform vec2 envelope_radius = vec2(0.340, 0.365);
// Shrinks both ellipses together so the falloff reaches zero inside the quad.
// A bounded carrier is the one real cost of leaving screen space: an edge that
// clips the field announces the panel immediately.
uniform float field_scale = 0.72;
uniform float falloff_knee = 0.55;
uniform float falloff_soft = 1.55;
uniform float band_scale = 0.78;
uniform float band_offset = 0.0;
uniform float warp_amplitude = 0.022;
uniform float band_warp_amplitude = 0.045;
// Width of the guaranteed vanish at the quad border, in UV. Without it the
// field's reach depends on four constants continuing to agree, and any retune
// can push it past an edge -- which reveals the carrier as a rectangle
// instantly and is the one failure a bounded panel cannot recover from.
uniform float edge_fade = 0.12;

// --- Reflection -------------------------------------------------------------
uniform float lower_blend = 0.060;
uniform float lower_compress = 1.12;
uniform float lower_dim = 0.96;
uniform float lower_smear = 0.010;
uniform float seam_width = 0.055;
uniform float seam_floor = 0.86;
uniform float ripple_frequency = 4.5;
uniform float ripple_depth = 0.040;
// Zero retires the whole reflection -- seam, ripple, and lower lobe together --
// leaving one continuous field. One is the default because the reference's
// waterline needs empty space below it, which a body standing on ground lacks.
uniform float mirror_strength = 0.0;

// --- Wave and pixelation ----------------------------------------------------
// Two separate ideas that have to be applied in this order: the wave displaces
// where the field is sampled, then the result is snapped to a cell grid. Waving
// after snapping would drag the blocks around as a wobbling mosaic; waving
// before it keeps the grid locked to the panel and lets the colour flow through
// fixed cells, which is what reads as a pixelated field rather than a shaken one.
uniform float wave_amplitude = 0.018;
uniform float wave_frequency = 3.5;
uniform float wave_speed = 2.0;
// Cells across the panel's width. Zero disables snapping entirely; the vertical
// count is derived from the aspect so cells stay square in world units.
uniform float pixel_cells = 72.0;

// --- Aurora curtain ---------------------------------------------------------
// Vertical filaments with low-frequency folds, which is what a real aurora is:
// not a blob but a hanging sheet seen edge-on in places and face-on in others.
// The folds shear with height so the sheet reads as hanging rather than as flat
// stripes painted on the panel.
uniform float curtain_strength = 0.55;
uniform float curtain_detail = 7.0;
uniform float curtain_fold_frequency = 1.3;
uniform float curtain_fold_depth = 0.85;
uniform float curtain_fold_shear = 0.80;
uniform float curtain_drift_speed = 0.35;

// --- Occlusion handling -----------------------------------------------------
// The scene as already rendered, plus its depth, so the fragment can decide per
// pixel whether it is covering a model.
uniform sampler2D screen_texture : hint_screen_texture, filter_linear;
uniform sampler2D depth_texture : hint_depth_texture, filter_nearest;
// How hard the curtain lights a model it passes in front of.
uniform float model_boost = 3.0;
// Coverage multiplier for the lit path only. The added light is
// `veil * model_boost * ALPHA`, so the curtain's own faint regions would light a
// model barely at all no matter how high the boost goes; this lifts the
// coverage in front of geometry so the whole silhouette responds, not just the
// few pixels under the curtain's brightest filaments.
uniform float occlusion_gain = 2.4;
// Softening on the depth comparison, in world units, so the hand-off between
// covering and lighting is a gradient rather than a cut-out along the silhouette.
uniform float occlusion_feather = 0.18;

// --- Grade and lifecycle ----------------------------------------------------
uniform float intensity = 0.80;
uniform float grain_strength = 0.050;
uniform float grain_hz = 12.0;
uniform float black_lift = 0.022;
uniform float playback_time = 0.0;
uniform float lifecycle_visibility = 1.0;
uniform float band_drift = 0.0;
uniform float seed_value = 0.0;

// MEASURED-by-eye from the reference frame: pale core, warm midrange, magenta
// and violet run, deep blue outer field. Held as parallel arrays because a
// const array of structs is not portable across Godot's shader backends.
const float RAMP_POSITION[RAMP_STOPS] = float[](
	0.00, 0.13, 0.29, 0.42, 0.55, 0.67, 0.74, 0.87, 1.00
);
const vec3 RAMP_COLOR[RAMP_STOPS] = vec3[](
	vec3(0.87, 0.89, 0.69),
	vec3(0.93, 0.84, 0.47),
	vec3(0.91, 0.66, 0.38),
	vec3(0.88, 0.54, 0.46),
	vec3(0.83, 0.45, 0.56),
	vec3(0.72, 0.40, 0.63),
	vec3(0.59, 0.36, 0.62),
	vec3(0.36, 0.28, 0.55),
	vec3(0.14, 0.15, 0.31)
);

// The ramp above is authored in sRGB, measured by eye against the reference
// image, but ALBEDO is consumed as linear. Feeding sRGB values straight through
// lightens and desaturates every stop -- which is precisely the pale, washed
// field this shader produced before the conversion was added. Convert once, at
// the end, after grain and lift have been applied in the space they were
// authored in.
vec3 srgb_to_linear(vec3 channel) {
	return mix(
		channel / 12.92,
		pow((channel + vec3(0.055)) / 1.055, vec3(2.4)),
		step(vec3(0.04045), channel)
	);
}

vec3 ramp_color(float t) {
	t = clamp(t, 0.0, 1.0);
	vec3 color = RAMP_COLOR[RAMP_STOPS - 1];
	for (int index = 1; index < RAMP_STOPS; index++) {
		float low = RAMP_POSITION[index - 1];
		float high = RAMP_POSITION[index];
		if (t <= high) {
			float span = max(high - low, 0.0001);
			color = mix(
				RAMP_COLOR[index - 1], RAMP_COLOR[index], (t - low) / span
			);
			break;
		}
	}
	return color;
}

// Low-frequency domain warp. Keeps the silhouette from reading as an ellipse
// without disturbing where its edge sits.
vec2 domain_warp(float x, float m, float drift) {
	float wx = sin((m * 2.3 + 0.31 + drift) * TAU_VALUE) * 0.55
		+ sin((m * 4.7 - x * 1.9 + 0.13) * TAU_VALUE) * 0.28;
	float wm = sin((x * 2.9 - 0.21 + drift * 0.6) * TAU_VALUE) * 0.48
		+ sin((x * 5.3 + m * 2.1 + 0.57) * TAU_VALUE) * 0.24;
	return vec2(x + wx * warp_amplitude, m + wm * warp_amplitude);
}

// Vertical curtain filaments. `x` is the aspect-corrected horizontal coordinate
// and `m` the height above the anchor; the fold term carries `m` so filaments
// lean as they rise instead of standing as parallel bars.
float curtain_field(float x, float m, float phase) {
	float fold =
		sin((x * curtain_fold_frequency + phase) * TAU_VALUE) * 0.55
		+ sin(
			(x * curtain_fold_frequency * 2.3 - phase * 0.7 + m * curtain_fold_shear)
				* TAU_VALUE
		) * 0.28;
	float filament = 0.5 + 0.5 * sin(
		(x * curtain_detail + fold * curtain_fold_depth) * TAU_VALUE
	);
	return mix(1.0, filament, curtain_strength);
}

float hash_grain(vec2 pixel, float frame) {
	vec3 seeded = vec3(pixel, frame);
	return fract(sin(dot(seeded, vec3(12.9898, 78.233, 37.719))) * 43758.5453);
}

void vertex() {
	// Y-axis billboard. The quad's own mesh size carries the panel dimensions,
	// so the rebuilt basis stays unit-length and scale is preserved.
	vec3 camera_forward = INV_VIEW_MATRIX[2].xyz;
	vec3 flat_forward = camera_forward - WORLD_UP * dot(camera_forward, WORLD_UP);
	// Guard the degenerate straight-down case; the harness allows 84 degrees of
	// pitch and a zero-length basis would collapse the panel to nothing.
	flat_forward = length(flat_forward) < 0.0001
		? vec3(0.0, 0.0, 1.0)
		: normalize(flat_forward);
	vec3 right = normalize(cross(WORLD_UP, flat_forward));
	MODELVIEW_MATRIX = VIEW_MATRIX * mat4(
		vec4(right, 0.0),
		vec4(WORLD_UP, 0.0),
		vec4(flat_forward, 0.0),
		MODEL_MATRIX[3]
	);
}

void fragment() {
	// Wave, then snap. The phase is a plain product with playback_time rather
	// than an accumulator, so scrubbing backwards lands on the same frame.
	float wave_phase = playback_time * wave_speed;
	vec2 field_uv = UV;
	field_uv.x += sin((UV.y * wave_frequency + wave_phase) * TAU_VALUE)
		* wave_amplitude;
	field_uv.y += sin((UV.x * wave_frequency * 0.7 - wave_phase * 0.8) * TAU_VALUE)
		* wave_amplitude * 0.6;

	vec2 cell_index = vec2(0.0);
	if (pixel_cells > 0.5) {
		vec2 grid = vec2(pixel_cells, pixel_cells / aspect_ratio);
		cell_index = floor(field_uv * grid);
		field_uv = (cell_index + 0.5) / grid;
	}

	// Work in aspect-corrected panel space around the anchor, so the field is
	// circular in world units rather than stretched by the quad's proportions.
	float x = (field_uv.x - veil_anchor.x) * aspect_ratio;
	float signed_height = field_uv.y - veil_anchor.y;

	// The reflected half blends in over a band rather than switching on at the
	// axis. A hard switch lands every lower-half modifier as a one-pixel
	// discontinuity, which reads as a line drawn across the seam.
	//
	// `mirror_strength` at zero folds the whole reflection away and leaves one
	// continuous lobe: `m` becomes the signed height, so the field simply falls
	// off below the core instead of restarting as a second blob. The reflection
	// is faithful to the reference frame, but the reference is a free-floating
	// light phenomenon with room beneath it -- a body standing on the ground has
	// none, and the compression needed to keep the lower lobe off the floor is
	// what turned it into a smear rather than a mirror.
	// UV.y grows downward, so height above the anchor is the negated distance.
	// Mirrored, `m` is the unsigned distance from the seam and the core appears
	// twice; unmirrored it must stay the upward distance, or the single lobe
	// lands below the anchor instead of over the target.
	float below = smoothstep(0.0, lower_blend, signed_height) * mirror_strength;
	float mirrored = abs(signed_height) * mix(1.0, lower_compress, below);
	float m = mix(-signed_height, mirrored, mirror_strength);

	vec2 warped = domain_warp(x, m, band_drift);
	warped.x += sin((m * 6.1 + 0.4) * TAU_VALUE) * lower_smear * below;

	// Envelope: the silhouette, warped only slightly so its edge stays soft.
	vec2 envelope_delta =
		vec2(warped.x, warped.y - core_offset) / (envelope_radius * field_scale);
	float envelope_r = length(envelope_delta);

	// Bands: the colour sweep. Warped hard so the interference contours flow
	// instead of ringing, without moving the silhouette computed above. The two
	// ellipses are deliberately separate -- one cannot be both a fast hue run
	// across the short axis and a tall soft outline down the long one.
	float band_warp = (
		sin((m * 1.7 + x * 0.9 + 0.22 + band_drift) * TAU_VALUE) * 0.62
		+ sin((m * 3.1 - x * 2.4 + 0.71) * TAU_VALUE) * 0.27
	) * band_warp_amplitude;
	vec2 band_delta =
		vec2(warped.x, warped.y - core_offset) / (band_radius * field_scale);
	float band_r = length(band_delta) + band_warp;

	vec3 color = ramp_color(band_r * band_scale + band_offset);

	float falloff = 1.0 - smoothstep(falloff_knee, falloff_soft, envelope_r);
	float seam_distance = abs(signed_height) / max(seam_width, 0.0001);
	// Seam and ripple exist only to sell the reflection, so both retire with it.
	float seam = mix(1.0, mix(
		seam_floor, 1.0, clamp(1.0 - exp(-seam_distance * seam_distance), 0.0, 1.0)
	), mirror_strength);

	// Horizontal ripple striations, reflected half only. This is the cue that
	// reads the lower lobe as a reflection rather than a duplicated blob.
	float ripple = 1.0
		+ sin((m * ripple_frequency + 0.17) * TAU_VALUE) * ripple_depth * below;

	vec2 border = min(UV, vec2(1.0) - UV);
	float edge = smoothstep(0.0, edge_fade, min(border.x, border.y));

	float curtain = curtain_field(x, m, playback_time * curtain_drift_speed);

	float energy = falloff * seam * ripple * intensity * edge * curtain
		* mix(1.0, lower_dim, below) * lifecycle_visibility;

	// Quantized frame index: animated grain that still scrubs exactly.
	float grain_frame = floor(playback_time * grain_hz) + seed_value;
	// While the field is snapped, the grain hashes the cell rather than the
	// pixel. Per-pixel noise over chunky cells reads as two unrelated effects
	// stacked; per-cell noise makes the whole field one coherent grid.
	vec2 grain_coordinate = pixel_cells > 0.5 ? cell_index : FRAGCOORD.xy;
	float grain = (hash_grain(grain_coordinate, grain_frame) - 0.5) * grain_strength;

	// Under mix blending the ramp colour is carried by ALBEDO and the field's
	// strength by ALPHA, so the hue survives whatever is behind the panel.
	// Grain and lifted black ride the colour rather than the coverage; gating
	// them on the same envelope keeps the panel from tinting its own margins.
	vec3 graded = clamp(color + vec3(grain + black_lift), vec3(0.0), vec3(1.0));

	if (energy < 0.0015) {
		discard;
	}

	// Reconstruct the view-space depth of whatever was already drawn here, and
	// compare it with this fragment's own. Scene nearer than the panel means a
	// model stands between the camera and the curtain.
	float scene_raw_depth = texture(depth_texture, SCREEN_UV).r;
	vec4 scene_view = INV_PROJECTION_MATRIX
		* vec4(SCREEN_UV * 2.0 - 1.0, scene_raw_depth, 1.0);
	scene_view.xyz /= scene_view.w;
	float scene_distance = -scene_view.z;
	float panel_distance = -VERTEX.z;
	float occluded = 1.0 - smoothstep(
		panel_distance - occlusion_feather, panel_distance, scene_distance
	);

	vec3 veil = srgb_to_linear(graded);
	vec3 behind = texture(screen_texture, SCREEN_UV).rgb;

	// Mix blending computes `behind * (1 - ALPHA) + ALBEDO * ALPHA`. To make the
	// occluded case come out *additive* -- `behind + veil * ALPHA * boost`, the
	// model showing through and lit rather than painted over -- ALBEDO has to be
	// `behind + veil * boost`. Solving that identity for ALBEDO is what lets one
	// pass be a veil over the background and a light on the models at once,
	// without a second draw or a second blend mode.
	ALBEDO = mix(veil, behind + veil * model_boost, occluded);
	ALPHA = mix(
		clamp(energy, 0.0, 1.0),
		clamp(energy * occlusion_gain, 0.0, 1.0),
		occluded
	);
}
