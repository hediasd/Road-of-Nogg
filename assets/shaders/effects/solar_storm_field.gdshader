// Coronagraph storm panel for the Solar Storm spell.
//
// Forked from `aurora_veil_field.gdshader` under docs/VFX_DESIGN.md §4's sibling
// test, and the sibling relationship is real rather than convenient: identical
// Y-billboarded quad carrier, identical four-beat timeline, identical pixel
// snap, wave displacement, radius scaling, and depth-resolved model lighting.
// Only the field itself is new. What that field draws is a coronagraph frame --
// an occulting disk with the star's limb ring behind it, streams fanning out
// from the occultation, a bright ejection front, and the broad corona inside the
// instrument's circular field of view.
//
// Every value is a pure function of `playback_time` and position. Nothing
// integrates across frames, which is what lets SolarStormEffect report exact
// normalized seek and lets the debug harness scrub in either direction. The
// grain is animated but still seek-exact: it hashes a *quantized* frame index
// derived from playback_time, never a running counter. Adding any
// frame-accumulated term here silently breaks scrubbing -- put state in the
// GDScript timeline instead.
//
// Depth testing is disabled so the storm draws over the models, with occlusion
// resolved in the fragment: where geometry stands in front of the panel the
// storm goes transparent and lights it instead of covering it.

shader_type spatial;
render_mode unshaded, blend_mix, depth_draw_never, depth_test_disabled, cull_disabled;

const float TAU_VALUE = 6.28318530718;
const int RAMP_STOPS = 7;
const vec3 WORLD_UP = vec3(0.0, 1.0, 0.0);

// --- Panel framing ----------------------------------------------------------
// Occulter centre inside the quad's own UV. Deliberately off-centre: left of
// the midline and high, matching the source frame rather than sitting the disk
// dead centre, which reads as a target reticle instead of an instrument.
uniform vec2 storm_anchor = vec2(0.435, 0.118);
uniform float aspect_ratio = 1.207;
uniform float field_scale = 0.72;
uniform float edge_fade = 0.12;

// --- Occulter and limb ------------------------------------------------------
uniform float occulter_radius = 0.115;
uniform float occulter_edge = 0.010;
uniform float limb_radius = 0.072;
uniform float limb_width = 0.005;
uniform float limb_gain = 0.85;

// --- Corona -----------------------------------------------------------------
uniform float corona_falloff = 0.78;
uniform float corona_gain = 0.66;

// --- Streams ----------------------------------------------------------------
// Built from summed octaves at incommensurate frequencies, not one periodic
// spoke function. A single sine raised to a power can only produce identical,
// evenly spaced rays; summing octaves and thresholding gives streams of
// genuinely different widths, brightnesses, and spacings.
uniform float streamer_broad = 0.62;
uniform float streamer_threshold = 0.40;
uniform float streamer_sharpness = 1.5;
uniform float streamer_gain = 1.10;
uniform float streamer_reach = 0.55;
uniform float streamer_warp = 0.018;
uniform float streamer_drift = 0.20;

// --- Ejection front ---------------------------------------------------------
uniform float arc_radius = 0.44;
uniform float arc_width = 0.028;
uniform float arc_gain = 1.05;
uniform float arc_warp = 0.075;
uniform float arc_span = 0.62;

// --- Prominences ------------------------------------------------------------
// Plasma loops anchored at two points on the limb, arching out and back. Modelled
// as a semi-ellipse in polar space whose radial height falls to the occulter
// radius at both footpoints, so each loop attaches to the limb by construction
// rather than needing its ends faded out. Three are authored; `prominence_rise`
// scales their height over the timeline so they grow and subside.
uniform vec3 prominence_centre = vec3(0.62, 0.90, 0.28);
uniform vec3 prominence_width = vec3(0.085, 0.060, 0.045);
uniform vec3 prominence_height = vec3(0.230, 0.165, 0.120);
uniform vec3 prominence_weight = vec3(1.00, 0.80, 0.65);
uniform float prominence_thickness = 0.022;
uniform float prominence_gain = 1.25;
uniform float prominence_rise = 1.0;

// --- Field of view ----------------------------------------------------------
uniform float fov_radius = 0.78;
uniform float fov_edge = 0.26;

// --- Pulse and pixels -------------------------------------------------------
// Outward radial travel, replacing the sibling's lateral sine wobble. That
// wobble is a mirage shimmer -- the right verb for a hallucination and the wrong
// one for an invocation. This displaces and brightens *along* the radial
// direction with phase `r * frequency - time * speed`, so fronts propagate from
// the occulter out to the edges the way a solar shock does, and the motion
// agrees with the field's own polar geometry instead of cutting across it.
uniform float pulse_amplitude = 0.010;
uniform float pulse_frequency = 4.0;
uniform float pulse_speed = 1.1;
uniform float pulse_intensity = 0.22;
uniform float pixel_cells = 56.0;

// --- Occlusion --------------------------------------------------------------
uniform sampler2D screen_texture : hint_screen_texture, filter_linear;
uniform sampler2D depth_texture : hint_depth_texture, filter_nearest;
uniform float model_boost = 3.0;
uniform float occlusion_gain = 2.4;
uniform float occlusion_feather = 0.18;
// Heat wash: geometry standing under the storm takes on its own warm glow,
// ramping as the ejection front arrives. This is what gives the storm a ground
// consequence rather than leaving it a backdrop -- the board is lit by the event
// instead of merely being behind it. Bounded by the corona's own falloff so the
// wash stops where the storm does.
uniform vec3 heat_tint : source_color = vec3(1.0, 0.42, 0.13);
uniform float heat_wash = 0.0;
uniform float heat_wash_gain = 0.85;

// --- Grade and lifecycle ----------------------------------------------------
// Flare bloom: a short whiteout at the launch beat. Driven as a separate scalar
// rather than folded into the visibility envelope, because it has to be able to
// spike far past full brightness and recover without dragging the storm's own
// fade with it.
uniform float flare_bloom = 0.0;
uniform float flare_gain = 1.30;
uniform float flare_reach = 0.45;

uniform float exposure = 1.0;
uniform float grain_strength = 0.055;
uniform float grain_hz = 12.0;
uniform float black_lift = 0.012;
uniform float playback_time = 0.0;
uniform float lifecycle_visibility = 1.0;
uniform float front_progress = 1.0;
uniform float seed_value = 0.0;

// ESTIMATED by eye from the source: deep red rim, through orange, into the
// near-white cores of the streams and the front.
const float RAMP_POSITION[RAMP_STOPS] = float[](
	0.00, 0.16, 0.34, 0.52, 0.70, 0.85, 1.00
);
const vec3 RAMP_COLOR[RAMP_STOPS] = vec3[](
	vec3(0.05, 0.004, 0.002),
	vec3(0.34, 0.030, 0.008),
	vec3(0.62, 0.110, 0.020),
	vec3(0.84, 0.260, 0.040),
	vec3(0.96, 0.470, 0.090),
	vec3(1.00, 0.700, 0.280),
	vec3(1.00, 0.960, 0.820)
);

vec3 ramp_color(float t) {
	t = clamp(t, 0.0, 1.0);
	vec3 color = RAMP_COLOR[RAMP_STOPS - 1];
	for (int index = 1; index < RAMP_STOPS; index++) {
		float low = RAMP_POSITION[index - 1];
		float high = RAMP_POSITION[index];
		if (t <= high) {
			float span = max(high - low, 0.0001);
			color = mix(RAMP_COLOR[index - 1], RAMP_COLOR[index], (t - low) / span);
			break;
		}
	}
	return color;
}

vec3 srgb_to_linear(vec3 channel) {
	return mix(
		channel / 12.92,
		pow((channel + vec3(0.055)) / 1.055, vec3(2.4)),
		step(vec3(0.04045), channel)
	);
}

float hash_grain(vec2 pixel, float frame) {
	vec3 seeded = vec3(pixel, frame);
	return fract(sin(dot(seeded, vec3(12.9898, 78.233, 37.719))) * 43758.5453);
}

float gaussian(float distance, float width) {
	float k = distance / max(width, 0.0001);
	return exp(-k * k);
}

// One plasma loop. `d` is the wrapped angular distance from the loop's centre,
// so the arch is a semi-ellipse whose crown sits at `height` above the limb and
// whose radius returns to the limb exactly at both footpoints.
float prominence_arch(
		float theta, float r, float centre, float half_width, float height) {
	float d = abs(fract(theta - centre + 0.5) - 0.5);
	float k = d / max(half_width, 0.0001);
	if (k >= 1.0) {
		return 0.0;
	}
	float arch = occulter_radius + height * sqrt(max(1.0 - k * k, 0.0));
	// Loops are brightest along their legs and at the crown, and thin in
	// between, which is what stops them reading as plain semicircles.
	float leg = 0.72 + 0.28 * cos(k * 3.0 * TAU_VALUE * 0.25);
	return gaussian(r - arch, prominence_thickness) * leg;
}

void vertex() {
	// Y-axis billboard. The quad's own mesh size carries the panel dimensions,
	// so the rebuilt basis stays unit-length and scale is preserved.
	vec3 camera_forward = INV_VIEW_MATRIX[2].xyz;
	vec3 flat_forward = camera_forward - WORLD_UP * dot(camera_forward, WORLD_UP);
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
	// Radial pulse. The polar frame has to be built from the *undisplaced* UV
	// first, because the displacement is defined along that frame's own outward
	// direction -- displacing in UV and then deriving polar would rotate the
	// pulse into a swirl.
	vec2 raw = vec2(
		(UV.x - storm_anchor.x) * aspect_ratio, UV.y - storm_anchor.y
	);
	float raw_r = length(raw);
	vec2 outward = raw_r < 0.0001 ? vec2(0.0, -1.0) : raw / raw_r;
	// Minus on the time term is what sends fronts outward; plus would draw them
	// back into the occulter.
	float pulse_phase = (raw_r * pulse_frequency - playback_time * pulse_speed)
		* TAU_VALUE;
	float pulse = sin(pulse_phase);
	// Back into UV: the outward vector lives in aspect-corrected space, so its
	// x component has to be undone or the displacement stretches horizontally.
	vec2 field_uv = UV + outward * (pulse * pulse_amplitude)
		* vec2(1.0 / max(aspect_ratio, 0.0001), 1.0);

	vec2 cell_index = vec2(0.0);
	if (pixel_cells > 0.5) {
		vec2 grid = vec2(pixel_cells, pixel_cells / aspect_ratio);
		cell_index = floor(field_uv * grid);
		field_uv = (cell_index + 0.5) / grid;
	}

	// Aspect-corrected polar coordinates around the occulter, so the disk stays
	// circular in world units rather than stretching with the quad.
	float x = (field_uv.x - storm_anchor.x) * aspect_ratio;
	float y = field_uv.y - storm_anchor.y;
	float r = length(vec2(x, y)) / max(field_scale, 0.0001);
	float theta = atan(y, x) / TAU_VALUE;

	// --- corona: the broad radial glow behind everything --------------------
	float corona = exp(-max(r - occulter_radius, 0.0) / max(corona_falloff, 0.0001));
	corona *= smoothstep(occulter_radius - 0.02, occulter_radius + 0.06, r);
	corona *= corona_gain;

	// --- streams ------------------------------------------------------------
	// Also minus on time: with a plus the splay pattern crawls back toward the
	// occulter, which reads as the storm inhaling.
	float splay = sin((r * 2.1 + 0.4 - playback_time * streamer_drift) * TAU_VALUE)
		* streamer_warp;
	float t = theta + splay;
	float broad = sin((t * 3.1 + 0.00) * TAU_VALUE) * 0.50
		+ sin((t * 5.7 - 1.30) * TAU_VALUE) * 0.30
		+ sin((t * 11.3 + 2.10) * TAU_VALUE) * 0.20;
	float fine = sin((t * 8.3 + 0.90) * TAU_VALUE) * 0.55
		+ sin((t * 17.1 - 0.40) * TAU_VALUE) * 0.45;
	float stream_field = 0.5
		+ 0.5 * (broad * streamer_broad + fine * (1.0 - streamer_broad));
	// Thresholding rather than exponentiating: the cut separates streams from
	// background, and moving it changes their width without dimming them.
	float streamer = pow(
		smoothstep(streamer_threshold, 1.0, stream_field), streamer_sharpness
	);
	// A much slower octave gates whole sectors on and off, so the fan clumps into
	// active and quiet regions instead of covering every angle evenly.
	float gate = 0.5 + 0.5 * sin((theta * 2.3 - 0.6) * TAU_VALUE);
	streamer *= 0.18 + 1.25 * gate;
	streamer *= exp(-max(r - occulter_radius, 0.0) / max(streamer_reach, 0.0001));
	streamer *= smoothstep(occulter_radius, occulter_radius + 0.05, r);
	// The source's activity fans downward; the upper hemisphere is much quieter.
	streamer *= mix(0.12, 1.0, smoothstep(-0.10, 0.22, y));
	streamer *= streamer_gain;

	// --- ejection front -----------------------------------------------------
	float warped_r = r + sin((theta * 5.0 + 0.3) * TAU_VALUE) * arc_warp;
	float arc = gaussian(warped_r - arc_radius * front_progress, arc_width);
	// The front is a loop over the lower hemisphere, not a full ring. The `+ 0.5`
	// before the wrap is what makes this a distance *from* the span's centre;
	// without it the window inverts and the front vanishes exactly where it
	// should be brightest.
	float angular = clamp(
		1.0 - abs(fract(theta - 0.25 + 0.5) - 0.5) / max(arc_span * 0.5, 0.0001),
		0.0, 1.0
	);
	arc *= smoothstep(0.0, 1.0, angular) * arc_gain;

	// The brightness half of the pulse, and the half that actually reads as
	// energy leaving the star. Displacement alone only nudges geometry; banding
	// the light is what makes fronts visibly propagate outward. The ejection
	// front is excluded -- it already carries its own travel on
	// `front_progress`, and modulating it too would beat against that.
	// --- prominences --------------------------------------------------------
	float prominences = 0.0;
	for (int index = 0; index < 3; index++) {
		prominences += prominence_arch(
			theta,
			r,
			prominence_centre[index],
			prominence_width[index],
			prominence_height[index] * prominence_rise
		) * prominence_weight[index];
	}
	prominences *= prominence_gain;

	float pulse_gain = 1.0 + pulse * pulse_intensity;
	float intensity = (corona + streamer) * pulse_gain + arc + prominences;

	// The flare blooms out of the occulter, so its lift falls off with radius:
	// applied flat it reads as the exposure being pulled rather than as the star
	// releasing. `flare_reach` sets how far out the whiteout carries.
	float flare = flare_bloom * exp(-max(r - occulter_radius, 0.0)
		/ max(flare_reach, 0.0001));
	intensity += flare * flare_gain;

	// --- occulter, limb, and instrument field of view ------------------------
	float disk = smoothstep(occulter_radius - occulter_edge, occulter_radius, r);
	float limb = gaussian(r - limb_radius, limb_width) * limb_gain;
	float fov = 1.0 - smoothstep(fov_radius - fov_edge, fov_radius, r);

	intensity = (intensity * disk + limb) * fov;

	// Belt-and-braces against a clipped quad edge announcing the panel.
	vec2 border = min(field_uv, vec2(1.0) - field_uv);
	float edge = smoothstep(0.0, max(edge_fade, 0.0001), min(border.x, border.y));

	float energy = clamp(intensity * exposure, 0.0, 1.0) * edge * lifecycle_visibility;
	if (energy < 0.0015) {
		discard;
	}

	vec3 color = ramp_color(clamp(intensity * exposure, 0.0, 1.0));

	// Grain rides the cell grid when the field is snapped, so it reads as part of
	// the pixelation rather than fighting it at a finer scale.
	vec2 grain_coordinate = pixel_cells > 0.5 ? cell_index : FRAGCOORD.xy;
	float grain_frame = floor(playback_time * grain_hz) + seed_value;
	float grain = (hash_grain(grain_coordinate, grain_frame) - 0.5) * grain_strength;
	vec3 graded = clamp(color + vec3(grain + black_lift) * fov, vec3(0.0), vec3(1.0));

	// Reconstruct what was already drawn here and how far away it is.
	float scene_raw_depth = texture(depth_texture, SCREEN_UV).r;
	vec4 scene_view = INV_PROJECTION_MATRIX
		* vec4(SCREEN_UV * 2.0 - 1.0, scene_raw_depth, 1.0);
	scene_view.xyz /= scene_view.w;
	float occluded = 1.0 - smoothstep(
		-VERTEX.z - occlusion_feather, -VERTEX.z, -scene_view.z
	);

	vec3 storm = srgb_to_linear(graded);
	vec3 behind = texture(screen_texture, SCREEN_UV).rgb;

	// Mix blending computes `behind * (1 - ALPHA) + ALBEDO * ALPHA`. Solving that
	// for an additive result -- `behind + storm * ALPHA * boost`, the model
	// showing through and lit rather than painted over -- gives this ALBEDO. One
	// pass is therefore both a field over the background and a light on the
	// models, with no second draw and no second blend mode.
	// The wash is spatially bounded by `corona`, not by the storm's full
	// intensity: keyed to intensity it would only appear under the streams and
	// the front, giving the board a striped scorch instead of an even heat.
	float wash = heat_wash * heat_wash_gain * clamp(corona / max(corona_gain, 0.0001), 0.0, 1.0) * fov;
	vec3 lit = behind + storm * model_boost + srgb_to_linear(heat_tint) * wash;

	ALBEDO = mix(storm, lit, occluded);
	// The wash also lifts coverage, or it would be invisible wherever the
	// storm's own field is faint -- which is most of where the board actually is.
	ALPHA = mix(
		energy,
		clamp(max(energy * occlusion_gain, wash), 0.0, 1.0),
		occluded
	);
}
