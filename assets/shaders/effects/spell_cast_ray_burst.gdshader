// spell_cast_ray_burst.gdshader
// Pointed translucent light blades for the generic spell-cast aura.
//
// Each MultiMesh instance is one blade. The instance transform carries only
// scalars and a lean vector; the blade's orientation is rebuilt here, so the
// quad always faces the camera while standing exactly on the world's up axis:
//
//   MODEL_MATRIX[0]  x column, length = blade half width
//   MODEL_MATRIX[1]  y column, length = blade height
//   MODEL_MATRIX[2]  z column  = apex lean, a world-space horizontal offset
//   MODEL_MATRIX[3]  origin    = the blade's seat on the ground
//
//   INSTANCE_CUSTOM.x = growth delay, in fractions of the growth window
//   INSTANCE_CUSTOM.y = brightness multiplier
//   INSTANCE_CUSTOM.z = alpha multiplier
//   INSTANCE_CUSTOM.w = 1.0 for a hero blade, 0.0 otherwise
//
// UV2 carries the authored local geometry (x across the blade, y along it);
// UV carries shading coordinates, with x normalized across the blade's width
// at that height so the alpha profile follows the taper.
//
// The camera is orthographic and never rolls — `look_at(focus, Vector3.UP)`
// in both `BattleCameraController` and the debug harness — so a world-vertical
// edge is a screen-vertical raster line at any yaw or pitch, which is what
// makes these blades read sharp rather than soft or dashed.

shader_type spatial;
render_mode unshaded, blend_add, depth_draw_never, cull_disabled, world_vertex_coords;

// ---------------------------------------------------------------------------
// Uniforms
// ---------------------------------------------------------------------------

uniform vec4 aura_color : source_color = vec4(0.6, 0.9, 0.9, 1.0);
uniform float burst_progress : hint_range(0.0, 1.0) = 0.0;

uniform float eruption_start : hint_range(0.0, 1.0) = 0.03;
uniform float eruption_span : hint_range(0.01, 1.0) = 0.16;
uniform float stagger_span : hint_range(0.0, 1.0) = 0.16;
uniform float hold_end : hint_range(0.01, 1.0) = 0.44;
uniform float decay_end : hint_range(0.01, 1.0) = 0.88;
uniform float overshoot_amount : hint_range(0.0, 1.0) = 0.16;
uniform float decay_stretch : hint_range(0.0, 1.0) = 0.14;

uniform float edge_alpha_steps : hint_range(1.0, 8.0) = 3.0;
uniform float core_width_fraction : hint_range(0.0, 1.0) = 0.34;
uniform float peak_alpha : hint_range(0.0, 1.0) = 0.40;
uniform float tip_fade_start : hint_range(0.0, 1.0) = 0.72;
uniform float seat_glow_height : hint_range(0.01, 1.0) = 0.26;

uniform float seat_white_mix : hint_range(0.0, 1.0) = 0.76;
uniform float body_white_mix : hint_range(0.0, 1.0) = 0.22;
uniform float tip_deepen : hint_range(0.0, 2.0) = 0.78;
uniform float body_gradient_end : hint_range(0.0, 1.0) = 0.34;
uniform float tip_gradient_start : hint_range(0.0, 1.0) = 0.40;
uniform float emission_energy : hint_range(0.0, 8.0) = 1.9;

uniform float lean_height_exponent : hint_range(1.0, 4.0) = 2.0;

varying float v_energy;

// ---------------------------------------------------------------------------
// Vertex
// ---------------------------------------------------------------------------

// Where a blade sits inside its own growth window, 0 before it starts and 1
// once it has arrived. The delay is per instance, so the eruption staggers
// without anything accumulating between frames — every value below is a pure
// function of normalized time, which is what makes backward seek exact.
float blade_local(float progress, float delay) {
	float start = eruption_start + delay * stagger_span;
	return clamp((progress - start) / max(eruption_span, 0.0001), 0.0, 1.0);
}

// Eased-out growth plus an overshoot that peaks mid-window and is exactly zero
// at both ends, so the blade snaps past its height and settles on it without
// drifting off its authored size.
float blade_rise(float local) {
	float grow = 1.0 - pow(1.0 - local, 3.0);
	float over = overshoot_amount * sin(PI * local) * (1.0 - local);
	return grow + over;
}

float blade_fade(float progress) {
	return 1.0 - smoothstep(hold_end, decay_end, progress);
}

void vertex() {
	vec3 seat = MODEL_MATRIX[3].xyz;
	float half_width = length(MODEL_MATRIX[0].xyz);
	float height = length(MODEL_MATRIX[1].xyz);
	vec3 lean = MODEL_MATRIX[2].xyz;

	float local_x = UV2.x - 0.5;
	float local_y = UV2.y;

	float local = blade_local(burst_progress, INSTANCE_CUSTOM.x);
	float fade = blade_fade(burst_progress);
	// Blades keep climbing as they fade, so the crown disperses upward instead
	// of being switched off in place.
	float grow = blade_rise(local) * (1.0 + decay_stretch * (1.0 - fade));
	// A blade that has only just broken the surface should not arrive at full
	// brightness, or the stagger reads as popping rather than erupting.
	v_energy = fade
			* min(local * 6.0, 1.0)
			* INSTANCE_CUSTOM.y
			* INSTANCE_CUSTOM.z;

	// Y-axis billboard: spin the blade around world up to face the camera, so
	// it can never turn edge-on and vanish as the camera orbits, and can never
	// tilt off vertical either.
	vec3 camera_right = normalize(INV_VIEW_MATRIX[0].xyz);
	vec3 flat_right = camera_right - vec3(0.0, 1.0, 0.0) * camera_right.y;
	float flat_length = length(flat_right);
	flat_right = flat_length > 0.001 ? flat_right / flat_length : vec3(1.0, 0.0, 0.0);

	float risen = local_y * grow;
	VERTEX = seat
			+ flat_right * (local_x * 2.0 * half_width)
			+ vec3(0.0, 1.0, 0.0) * (risen * height)
			+ lean * pow(risen, lean_height_exponent);
	NORMAL = normalize(cross(flat_right, vec3(0.0, 1.0, 0.0)));
}

// ---------------------------------------------------------------------------
// Fragment
// ---------------------------------------------------------------------------

void fragment() {
	// Distance across the blade, 0 at its spine and 1 at either edge. UV.x is
	// normalized per row, so this follows the taper rather than the bounding box.
	float across = clamp(abs(UV.x - 0.5) * 2.0, 0.0, 1.0);
	float along = clamp(UV.y, 0.0, 1.0);

	// A quantized ramp, not a smooth falloff: whole steps keep the edge hard.
	float ramp = 1.0 - across;
	float stepped = ceil(ramp * edge_alpha_steps) / edge_alpha_steps;
	// The spine stays solid so the blade has a spine at all.
	stepped = max(stepped, step(across, core_width_fraction));

	// Fade just short of the apex, so the point ends in a point.
	float tip = 1.0 - smoothstep(tip_fade_start, 1.0, along);
	// Extra weight at the seat, where the blades overlap into the white core.
	float seat = 1.0 + (1.0 - smoothstep(0.0, seat_glow_height, along));

	vec3 seat_color = mix(aura_color.rgb, vec3(1.0), seat_white_mix);
	vec3 body_color = mix(aura_color.rgb, vec3(1.0), body_white_mix);
	vec3 tip_color = aura_color.rgb * tip_deepen;

	vec3 color = mix(seat_color, body_color, smoothstep(0.0, body_gradient_end, along));
	color = mix(color, tip_color, smoothstep(tip_gradient_start, 1.0, along));

	float alpha = stepped * tip * peak_alpha * v_energy;

	ALBEDO = color;
	EMISSION = color * emission_energy * seat;
	ALPHA = clamp(alpha, 0.0, 1.0);
}
