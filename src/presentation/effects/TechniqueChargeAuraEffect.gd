## Debug-only polygonal technique-charge aura playback.
##
## Authored fresh under docs/VFX_DESIGN.md's isolation rule. Solar Storm is a
## process reference only: this effect owns its mesh construction, materials,
## texture, profile, and lifecycle implementation.

class_name TechniqueChargeAuraEffect
extends "res://src/presentation/effects/VfxPlayback.gd"

const _AURA_SHADER = preload(
	"res://assets/shaders/effects/technique_charge_aura.gdshader"
)
const _AURA_MASK = preload(
	"res://assets/vfx/technique_charge_aura/aura_panel.png"
)

const LAYER_GROUND := "ground_circle"
const LAYER_WALL := "polygonal_wall"

var _groundInstance: MeshInstance3D
var _wallInstance: MeshInstance3D
var _groundMaterial: ShaderMaterial
var _wallMaterial: ShaderMaterial
var _elapsedTime := 0.0
var _playbackScale := 1.0
var _playing := false
var _finished := true
var _disposed := false
var _autoDispose := false
var _seedOffset := 0.0

## Live-class authored values, resolved once at build time and again whenever
## the debug panel pushes an override. Read through `tunable()` there rather
## than per frame: a dictionary lookup inside the per-frame path would cost
## real performance in the one tool used to judge performance.
var _igniteEnd := TechniqueChargeAuraProfile.IGNITE_END_NORMALIZED
var _groundIgniteEnd := TechniqueChargeAuraProfile.GROUND_IGNITE_LEAD_NORMALIZED
var _releaseStart := TechniqueChargeAuraProfile.RELEASE_START_NORMALIZED
var _noiseScaleCoarse := TechniqueChargeAuraProfile.NOISE_SCALE_COARSE
var _noiseScaleFine := TechniqueChargeAuraProfile.NOISE_SCALE_FINE
var _noiseRiseSpeed := TechniqueChargeAuraProfile.NOISE_RISE_SPEED
var _flickerAmount := TechniqueChargeAuraProfile.FLICKER_AMOUNT
var _displacement := TechniqueChargeAuraProfile.DISPLACEMENT_U
var _wallBottomStrength := TechniqueChargeAuraProfile.WALL_BOTTOM_STRENGTH
var _groundSpillAlpha := TechniqueChargeAuraProfile.GROUND_SPILL_ALPHA
var _groundSpillOuter := TechniqueChargeAuraProfile.GROUND_SPILL_OUTER_UV


## Live-authoring roster. `rebuild: true` marks the values consumed while the
## mesh is assembled — the panel replays the effect for those rather than
## nudging a uniform that nothing would re-read.
static func tunables() -> Array[Dictionary]:
	return [
		{
			"id": "WALL_SIDES", "label": "Sides", "group": "Dimensions",
			"min": 3.0, "max": 16.0, "step": 1.0,
			"default": float(TechniqueChargeAuraProfile.WALL_SIDES),
			"rebuild": true,
		},
		{
			"id": "WALL_RADIUS_U", "label": "Radius", "group": "Dimensions",
			"min": 0.2, "max": 2.0, "step": 0.01,
			"default": TechniqueChargeAuraProfile.WALL_RADIUS_U,
			"rebuild": true,
		},
		{
			"id": "WALL_HEIGHT_U", "label": "Height", "group": "Dimensions",
			"min": 0.4, "max": 4.0, "step": 0.01,
			"default": TechniqueChargeAuraProfile.WALL_HEIGHT_U,
			"rebuild": true,
		},
		{
			"id": "GROUND_DIAMETER_U", "label": "Ground size",
			"group": "Dimensions",
			"min": 0.5, "max": 5.0, "step": 0.01,
			"default": TechniqueChargeAuraProfile.GROUND_DIAMETER_U,
			"rebuild": true,
		},
		{
			"id": "WALL_BOTTOM_STRENGTH", "label": "Bottom strength",
			"group": "Wall",
			"min": 0.0, "max": 1.0, "step": 0.01,
			"default": TechniqueChargeAuraProfile.WALL_BOTTOM_STRENGTH,
			"rebuild": false,
		},
		{
			"id": "NOISE_SCALE_COARSE", "label": "Noise coarse", "group": "Noise",
			"min": 0.5, "max": 12.0, "step": 0.1,
			"default": TechniqueChargeAuraProfile.NOISE_SCALE_COARSE,
			"rebuild": false,
		},
		{
			"id": "NOISE_SCALE_FINE", "label": "Noise fine", "group": "Noise",
			"min": 2.0, "max": 40.0, "step": 0.5,
			"default": TechniqueChargeAuraProfile.NOISE_SCALE_FINE,
			"rebuild": false,
		},
		{
			"id": "NOISE_RISE_SPEED", "label": "Rise speed", "group": "Noise",
			"min": 0.0, "max": 3.0, "step": 0.01,
			"default": TechniqueChargeAuraProfile.NOISE_RISE_SPEED,
			"rebuild": false,
		},
		{
			"id": "FLICKER_AMOUNT", "label": "Flicker", "group": "Motion",
			"min": 0.0, "max": 0.6, "step": 0.01,
			"default": TechniqueChargeAuraProfile.FLICKER_AMOUNT,
			"rebuild": false,
		},
		{
			"id": "DISPLACEMENT_U", "label": "Height flutter", "group": "Motion",
			"min": 0.0, "max": 0.3, "step": 0.005,
			"default": TechniqueChargeAuraProfile.DISPLACEMENT_U,
			"rebuild": false,
		},
		{
			"id": "IGNITE_END_NORMALIZED", "label": "Ignite end", "group": "Fade",
			"min": 0.02, "max": 0.6, "step": 0.01,
			"default": TechniqueChargeAuraProfile.IGNITE_END_NORMALIZED,
			"rebuild": false,
		},
		{
			"id": "RELEASE_START_NORMALIZED", "label": "Release start",
			"group": "Fade",
			"min": 0.4, "max": 1.0, "step": 0.01,
			"default": TechniqueChargeAuraProfile.RELEASE_START_NORMALIZED,
			"rebuild": false,
		},
		{
			"id": "GROUND_SPILL_ALPHA", "label": "Spill strength",
			"group": "Circle",
			"min": 0.0, "max": 1.0, "step": 0.01,
			"default": TechniqueChargeAuraProfile.GROUND_SPILL_ALPHA,
			"rebuild": false,
		},
		{
			"id": "GROUND_SPILL_OUTER_UV", "label": "Spill reach",
			"group": "Circle",
			"min": 0.2, "max": 0.5, "step": 0.005,
			"default": TechniqueChargeAuraProfile.GROUND_SPILL_OUTER_UV,
			"rebuild": false,
		},
		{
			"id": "BOUNCE_OVERSHOOT", "label": "Overshoot", "group": "Bounce",
			"min": 0.0, "max": 1.0, "step": 0.01,
			"default": TechniqueChargeAuraProfile.RING_OVERSHOOT[0],
			# The mesh is built at the core's ceiling extension; a larger
			# overshoot needs more of it built or the bounce clips against
			# geometry sized for the old, smaller peak.
			"rebuild": true,
		},
		{
			"id": "BOUNCE_PERIOD", "label": "Period", "group": "Bounce",
			"min": 0.1, "max": 1.0, "step": 0.01,
			"default": TechniqueChargeAuraProfile.RING_BOUNCE_PERIOD_SECONDS[0],
			"rebuild": false,
		},
		{
			"id": "BOUNCE_DECAY", "label": "Decay", "group": "Bounce",
			"min": 0.5, "max": 8.0, "step": 0.05,
			"default": TechniqueChargeAuraProfile.RING_BOUNCE_DECAY[0],
			"rebuild": false,
		},
		{
			"id": "BREATH_MIN", "label": "Min amplitude", "group": "Breath",
			"min": 0.0, "max": 0.15, "step": 0.005,
			"default": TechniqueChargeAuraProfile.BREATH_MIN,
			"rebuild": false,
		},
		{
			"id": "BREATH_MAX", "label": "Max amplitude", "group": "Breath",
			"min": 0.0, "max": 0.20, "step": 0.005,
			"default": TechniqueChargeAuraProfile.BREATH_MAX,
			# Feeds every ring's ceiling, core included -- same reasoning as
			# BOUNCE_OVERSHOOT above.
			"rebuild": true,
		},
		{
			"id": "BREATH_FACE_MIX", "label": "Face mix", "group": "Breath",
			"min": 0.0, "max": 1.0, "step": 0.01,
			"default": TechniqueChargeAuraProfile.BREATH_FACE_MIX,
			"rebuild": false,
		},
		{
			"id": "BREATH_BRIGHT_COUPLING", "label": "Bright coupling",
			"group": "Breath",
			"min": 0.0, "max": 4.0, "step": 0.05,
			"default": TechniqueChargeAuraProfile.BREATH_BRIGHT_COUPLING,
			"rebuild": false,
		},
		{
			"id": "BREATH_RATE_SLOW", "label": "Rate (slow)", "group": "Breath",
			"min": 0.2, "max": 6.0, "step": 0.1,
			"default": TechniqueChargeAuraProfile.BREATH_RATE_SLOW,
			"rebuild": false,
		},
		{
			"id": "BREATH_RATE_FAST", "label": "Rate (fast)", "group": "Breath",
			"min": 0.2, "max": 10.0, "step": 0.1,
			"default": TechniqueChargeAuraProfile.BREATH_RATE_FAST,
			"rebuild": false,
		},
		{
			"id": "RING_PHASE_A1", "label": "Spread (1st)", "group": "Ring",
			"min": 0.0, "max": 0.15, "step": 0.005,
			"default": TechniqueChargeAuraProfile.RING_PHASE_A1,
			"rebuild": false,
		},
		{
			"id": "RING_PHASE_A2", "label": "Spread (2nd)", "group": "Ring",
			"min": 0.0, "max": 0.10, "step": 0.005,
			"default": TechniqueChargeAuraProfile.RING_PHASE_A2,
			"rebuild": false,
		},
		{
			"id": "FLARE_LEAN_OFFSET_DEGREES", "label": "Lean", "group": "Flares",
			"min": -20.0, "max": 20.0, "step": 0.5,
			"default": 0.0,
			"rebuild": true,
		},
		{
			"id": "FLARE_REACH_SCALE", "label": "Reach", "group": "Flares",
			"min": 0.5, "max": 1.8, "step": 0.02,
			"default": 1.0,
			"rebuild": true,
		},
		{
			"id": "FLARE_OPACITY_SCALE", "label": "Opacity", "group": "Flares",
			"min": 0.0, "max": 2.0, "step": 0.02,
			"default": 1.0,
			"rebuild": false,
		},
	]


static func createPlayback(
		parent: Node3D,
		world_position: Vector3,
		_element_color: Color,
		overrides: Dictionary = {}) -> TechniqueChargeAuraEffect:
	var playback := TechniqueChargeAuraEffect.new()
	playback.name = "TechniqueChargeAuraEffect"
	playback.position = world_position
	parent.add_child(playback)
	playback.set_tunable_overrides(overrides)
	playback._buildOwnedLayers()
	return playback


func configure_cast_context(context: VfxCastContext) -> void:
	if context == null:
		return
	context.assert_valid()
	position = context.source_world_position


func play(seed: int, mode: String) -> void:
	assert(not _disposed, "Cannot play a disposed TechniqueChargeAuraEffect.")
	assert(mode == MODE_REFERENCE or mode == MODE_BATTLE, "Unknown VFX playback mode.")
	# The seed only ever offsets the noise sample point, so two seeds are two
	# draws of the same authored material rather than two different looks.
	#
	# The offset must stay *small*. The shader's hash runs fract() on the sample
	# point scaled by ~123, so a large offset lands where float32 has no
	# fractional precision left and every seed collapses to an identical
	# pattern. A first version scaled a wrapped seed up to ~718 and did exactly
	# that; the seed-variation check reported no difference between two seeds.
	# The golden-ratio scramble is computed in GDScript's 64-bit float and
	# handed over already wrapped into a range the shader can resolve.
	_seedOffset = fmod(float(absi(seed)) * 0.61803398875, 16.0)
	_elapsedTime = 0.0
	_finished = false
	_playing = true
	_applyTimeline()
	set_process(true)


func set_playback_scale(scale: float) -> void:
	_playbackScale = maxf(scale, 0.0)


func seek_normalized(time: float) -> void:
	if _disposed:
		return
	var normalized_time := clampf(time, 0.0, 1.0)
	_elapsedTime = normalized_time * TechniqueChargeAuraProfile.DURATION_SECONDS
	_finished = normalized_time >= 1.0
	_playing = not _finished
	if _finished:
		_applyVisibility(0.0)
	else:
		_applyTimeline()


func skip_to_settle() -> void:
	seek_normalized(TechniqueChargeAuraProfile.SETTLE_NORMALIZED_TIME)


func get_normalized_time() -> float:
	return clampf(
		_elapsedTime / TechniqueChargeAuraProfile.DURATION_SECONDS,
		0.0,
		1.0
	)


func get_elapsed_time() -> float:
	return _elapsedTime


func get_total_duration() -> float:
	return TechniqueChargeAuraProfile.DURATION_SECONDS


func is_finished() -> bool:
	return _finished


func dispose() -> void:
	if _disposed:
		return
	_disposed = true
	_playing = false
	set_process(false)
	if is_queued_for_deletion():
		return
	if is_inside_tree() or get_parent() != null:
		queue_free()
	else:
		call_deferred("free")


func get_layer_names() -> Array[String]:
	return [LAYER_GROUND, LAYER_WALL]


func set_layer_visible(layer_name: String, visible: bool) -> void:
	match layer_name:
		LAYER_GROUND:
			if _groundInstance != null:
				_groundInstance.visible = visible
		LAYER_WALL:
			if _wallInstance != null:
				_wallInstance.visible = visible
		_:
			push_warning("Unknown TechniqueChargeAuraEffect layer: %s" % layer_name)


func get_live_particle_count() -> int:
	return 0


func get_live_instance_count() -> int:
	if _disposed or _finished:
		return 0
	var count := 0
	for instance: MeshInstance3D in [_groundInstance, _wallInstance]:
		if instance != null and instance.visible:
			count += 1
	return count


func get_live_draw_call_count() -> int:
	return get_live_instance_count()


func get_live_node_count() -> int:
	if _disposed:
		return 0
	return 1 + get_child_count()


func is_particle_seek_exact() -> bool:
	return true


func _process(delta: float) -> void:
	if _disposed or not _playing:
		return
	_elapsedTime += delta * _playbackScale
	if _elapsedTime < TechniqueChargeAuraProfile.DURATION_SECONDS:
		_applyTimeline()
		return
	_elapsedTime = TechniqueChargeAuraProfile.DURATION_SECONDS
	_playing = false
	_finished = true
	_applyVisibility(0.0)
	if _autoDispose:
		dispose()


func _readLiveTunables() -> void:
	_igniteEnd = tunable(
		"IGNITE_END_NORMALIZED", TechniqueChargeAuraProfile.IGNITE_END_NORMALIZED
	)
	_groundIgniteEnd = tunable(
		"GROUND_IGNITE_LEAD_NORMALIZED",
		TechniqueChargeAuraProfile.GROUND_IGNITE_LEAD_NORMALIZED
	)
	_releaseStart = tunable(
		"RELEASE_START_NORMALIZED",
		TechniqueChargeAuraProfile.RELEASE_START_NORMALIZED
	)
	_noiseScaleCoarse = tunable(
		"NOISE_SCALE_COARSE", TechniqueChargeAuraProfile.NOISE_SCALE_COARSE
	)
	_noiseScaleFine = tunable(
		"NOISE_SCALE_FINE", TechniqueChargeAuraProfile.NOISE_SCALE_FINE
	)
	_noiseRiseSpeed = tunable(
		"NOISE_RISE_SPEED", TechniqueChargeAuraProfile.NOISE_RISE_SPEED
	)
	_flickerAmount = tunable(
		"FLICKER_AMOUNT", TechniqueChargeAuraProfile.FLICKER_AMOUNT
	)
	_displacement = tunable(
		"DISPLACEMENT_U", TechniqueChargeAuraProfile.DISPLACEMENT_U
	)
	_wallBottomStrength = tunable(
		"WALL_BOTTOM_STRENGTH", TechniqueChargeAuraProfile.WALL_BOTTOM_STRENGTH
	)
	_groundSpillAlpha = tunable(
		"GROUND_SPILL_ALPHA", TechniqueChargeAuraProfile.GROUND_SPILL_ALPHA
	)
	_groundSpillOuter = tunable(
		"GROUND_SPILL_OUTER_UV", TechniqueChargeAuraProfile.GROUND_SPILL_OUTER_UV
	)


func _pushLiveTunables() -> void:
	for material: ShaderMaterial in [_groundMaterial, _wallMaterial]:
		if material == null:
			continue
		material.set_shader_parameter("noise_scale_coarse", _noiseScaleCoarse)
		material.set_shader_parameter("noise_scale_fine", _noiseScaleFine)
		material.set_shader_parameter("noise_rise_speed", _noiseRiseSpeed)
		material.set_shader_parameter("flicker_amount", _flickerAmount)
		material.set_shader_parameter("displacement_u", _displacement)
		material.set_shader_parameter("wall_bottom_strength", _wallBottomStrength)
	if _groundMaterial != null:
		_groundMaterial.set_shader_parameter(
			"ground_spill_alpha", _groundSpillAlpha
		)
		_groundMaterial.set_shader_parameter(
			"ground_spill_outer", _groundSpillOuter
		)


func _buildOwnedLayers() -> void:
	_readLiveTunables()
	_groundMaterial = _createOwnedMaterial(1)
	_groundMaterial.render_priority = TechniqueChargeAuraProfile.GROUND_RENDER_PRIORITY
	_groundMaterial.set_shader_parameter(
		"opacity", TechniqueChargeAuraProfile.GROUND_OPACITY
	)
	_groundMaterial.set_shader_parameter(
		"emission_energy", TechniqueChargeAuraProfile.GROUND_EMISSION_ENERGY
	)
	_groundMaterial.set_shader_parameter(
		"ground_spill_inner", TechniqueChargeAuraProfile.GROUND_SPILL_INNER_UV
	)
	_groundMaterial.set_shader_parameter("ground_spill_outer", _groundSpillOuter)
	_groundMaterial.set_shader_parameter("ground_spill_alpha", _groundSpillAlpha)

	var ground_mesh := PlaneMesh.new()
	ground_mesh.size = Vector2.ONE * tunable(
		"GROUND_DIAMETER_U", TechniqueChargeAuraProfile.GROUND_DIAMETER_U
	)
	_groundInstance = MeshInstance3D.new()
	_groundInstance.name = "GroundCircle"
	_groundInstance.mesh = ground_mesh
	_groundInstance.position.y = TechniqueChargeAuraProfile.GROUND_HEIGHT_U
	_groundInstance.material_override = _groundMaterial
	_groundInstance.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(_groundInstance)

	var ring_specs := _ringSpecs()

	_wallMaterial = _createOwnedMaterial(0)
	_wallMaterial.render_priority = TechniqueChargeAuraProfile.WALL_RENDER_PRIORITY
	_wallMaterial.set_shader_parameter(
		"emission_energy", TechniqueChargeAuraProfile.WALL_EMISSION_ENERGY
	)

	_wallInstance = MeshInstance3D.new()
	_wallInstance.name = "PolygonalWall"
	_wallInstance.mesh = _createRingStackMesh(ring_specs)
	_wallInstance.material_override = _wallMaterial
	_wallInstance.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(_wallInstance)

	_pushRingUniforms(_wallMaterial, ring_specs)
	_pushRingUniforms(_groundMaterial, ring_specs)
	_pushLiveTunables()

	assert(
		get_child_count() + 1 <= TechniqueChargeAuraProfile.MAX_EFFECT_NODES,
		"Technique charge aura exceeded its authored node ceiling."
	)
	assert(
		2 <= TechniqueChargeAuraProfile.MAX_GEOMETRY_INSTANCES,
		"Technique charge aura exceeded its authored geometry ceiling."
	)
	assert(
		2 <= TechniqueChargeAuraProfile.MAX_DRAW_CALLS,
		"Technique charge aura exceeded its authored draw-call ceiling."
	)


func _createOwnedMaterial(layer_kind: int) -> ShaderMaterial:
	var material := ShaderMaterial.new()
	material.shader = _AURA_SHADER
	material.set_shader_parameter("aura_mask", _AURA_MASK)
	material.set_shader_parameter("aura_color", TechniqueChargeAuraProfile.AURA_COLOR)
	material.set_shader_parameter("layer_kind", layer_kind)
	material.set_shader_parameter("lifecycle_visibility", 1.0)
	return material


func _applyVisibility(visibility: float) -> void:
	for material: ShaderMaterial in [_groundMaterial, _wallMaterial]:
		if material != null:
			material.set_shader_parameter("lifecycle_visibility", visibility)


## Pushes the whole per-instant state: the envelope and the effect's own clock.
##
## The shader never reads `TIME`, so this is the only thing that advances it.
## That is what makes a normalized seek exact — the image is a pure function of
## `playback_time` and the seed — and it is why pause and speed need no special
## handling at all: a scale of zero simply stops changing the value pushed here.
func _applyTimeline() -> void:
	var normalized := get_normalized_time()
	if _wallMaterial != null:
		_wallMaterial.set_shader_parameter(
			"lifecycle_visibility", _wallEnvelopeAt(normalized)
		)
	if _groundMaterial != null:
		_groundMaterial.set_shader_parameter(
			"lifecycle_visibility", _groundEnvelopeAt(normalized)
		)
	for material: ShaderMaterial in [_groundMaterial, _wallMaterial]:
		if material != null:
			material.set_shader_parameter("playback_time", normalized)
			# The ring oscillator works in seconds, not in normalized time: its
			# periods and decay rates are authored as real durations so that
			# changing the effect's length does not silently retune every
			# bounce in it.
			material.set_shader_parameter("playback_seconds", _elapsedTime)
			material.set_shader_parameter("playback_seed", _seedOffset)


## The ground carries its own envelope rather than sharing the wall's.
##
## It leads the wall into ignition -- GROUND_IGNITE_LEAD_NORMALIZED is roughly
## a third of the wall's own IGNITE_END_NORMALIZED, so the floor visibly lights
## an instant before the ring above it does, rather than the two appearing
## together. It shares the wall's release timing, so the two layers still
## vanish as one source at the end. The crest-tracking pulse that answers the
## core ring's bounce is a per-fragment brightness multiplier in the shader,
## not something this normalized-time envelope carries -- it needs the ring
## oscillator's own seconds-based state, which only the shader has.
func _groundEnvelopeAt(normalized: float) -> float:
	var ignite_end: float = maxf(_groundIgniteEnd, 0.0001)
	if normalized < ignite_end:
		return smoothstep(0.0, ignite_end, normalized)
	if normalized < _releaseStart:
		return 1.0
	return 1.0 - smoothstep(_releaseStart, 1.0, normalized)


## Authored ignition / hold / release. Release begins at the settle point, so
## `skip_to_settle()` lands on the last fully-charged frame instead of inside
## the fade.
func _wallEnvelopeAt(normalized: float) -> float:
	var ignite_end: float = maxf(_igniteEnd, 0.0001)
	if normalized < ignite_end:
		return smoothstep(0.0, ignite_end, normalized)
	if normalized < _releaseStart:
		return 1.0
	return 1.0 - smoothstep(_releaseStart, 1.0, normalized)


## Live-class overrides only. Anything that shapes geometry is marked
## `rebuild: true` in the descriptor roster and reaches the effect through
## `set_tunable_overrides()` before `_buildOwnedLayers()` instead.
func _on_tunables_applied() -> void:
	if _disposed:
		return
	_readLiveTunables()
	_pushLiveTunables()
	_applyTimeline()


## The three rings the wall mesh is assembled from, core first.
##
## Only the core takes the live Dimensions tunables. The flares are authored
## relative to their own radii, and letting one slider move the core without
## them would let the core wall cross straight through the mid flare; a
## FLARE_LEAN_OFFSET_DEGREES / FLARE_REACH_SCALE pair moves both flares
## together instead, which is what keeps the panel to one set of geometry
## sliders per flare concept rather than two independent, easily-desynced sets.
##
## Overshoot and the breath's max amplitude both feed a ring's ceiling
## extension, so the live BOUNCE_OVERSHOOT and BREATH_MAX values are read here
## too and passed through `ring_ceiling_for()` -- the mesh has to be built at
## whatever ceiling the live values imply, not the authored default, or a
## larger overshoot would silently clip against geometry sized for the smaller
## one.
func _ringSpecs() -> Array:
	var sides := tunable_int("WALL_SIDES", TechniqueChargeAuraProfile.WALL_SIDES)
	var core_overshoot := tunable(
		"BOUNCE_OVERSHOOT", TechniqueChargeAuraProfile.RING_OVERSHOOT[0]
	)
	var breath_max := tunable("BREATH_MAX", TechniqueChargeAuraProfile.BREATH_MAX)
	var flare_lean_offset := tunable("FLARE_LEAN_OFFSET_DEGREES", 0.0)
	var flare_reach_scale := tunable("FLARE_REACH_SCALE", 1.0)

	var specs: Array = []
	for index in TechniqueChargeAuraProfile.RING_COUNT:
		var base_radius := float(TechniqueChargeAuraProfile.RING_BASE_RADIUS_U[index])
		var length := float(TechniqueChargeAuraProfile.RING_LENGTH_U[index])
		var lean := float(TechniqueChargeAuraProfile.RING_LEAN_DEGREES[index])
		var overshoot := float(TechniqueChargeAuraProfile.RING_OVERSHOOT[index])
		if index == 0:
			base_radius = tunable("WALL_RADIUS_U", base_radius)
			length = tunable("WALL_HEIGHT_U", length)
			overshoot = core_overshoot
		else:
			length *= flare_reach_scale
			lean += flare_lean_offset
		var ceiling := TechniqueChargeAuraProfile.ring_ceiling_for(
			overshoot,
			breath_max,
			float(TechniqueChargeAuraProfile.RING_BREATH_SCALE[index])
		)
		specs.append({
			"sides": sides,
			"base_radius": base_radius,
			"length": length,
			"lean_degrees": lean,
			"extension_scale": ceiling,
		})
	return specs


## Hands a material the constants describing the ring stack.
##
## These are pushed once, at build time: they describe the rings, not the
## moment. The only uniforms that change per frame remain the clock, the seed
## and the two lifecycle values, which is what keeps the image a pure function
## of the seek position.
##
## Pushed to both materials, not just the wall's: the ground layer's pulse
## needs ring 0's bounce constants to answer the core's crests, and the grade
## and geometry uniforms it has no use for are harmless sitting unread in a
## fragment stage that never takes the layer_kind == 0 branch.
##
## Base radii come from the spec list the mesh was built from rather than from
## the profile, so a live Dimensions tunable cannot leave the shader anchoring
## the core ring somewhere the geometry is not.
func _pushRingUniforms(material: ShaderMaterial, rings: Array) -> void:
	if material == null:
		return

	# Read once: BOUNCE_* and BREATH_MAX apply to the core only (index 0), but
	# BREATH_MAX also has to match what `_ringSpecs()` already baked into
	# rings[index]["extension_scale"] -- both call `tunable()` with the same id
	# and fallback, which is what keeps a pure dict lookup consistent between
	# the two call sites without threading a value through.
	var core_period := tunable(
		"BOUNCE_PERIOD", TechniqueChargeAuraProfile.RING_BOUNCE_PERIOD_SECONDS[0]
	)
	var core_decay := tunable(
		"BOUNCE_DECAY", TechniqueChargeAuraProfile.RING_BOUNCE_DECAY[0]
	)
	var core_overshoot := tunable(
		"BOUNCE_OVERSHOOT", TechniqueChargeAuraProfile.RING_OVERSHOOT[0]
	)
	var flare_opacity_scale := tunable("FLARE_OPACITY_SCALE", 1.0)

	var base_radius := PackedFloat32Array()
	var ceiling := PackedFloat32Array()
	var launch := PackedFloat32Array()
	var rise := PackedFloat32Array()
	var period := PackedFloat32Array()
	var decay := PackedFloat32Array()
	var overshoot := PackedFloat32Array()
	var breath_scale := PackedFloat32Array()
	var ring_opacity := PackedFloat32Array()
	var ring_tip_bright := PackedFloat32Array()

	for index in TechniqueChargeAuraProfile.RING_COUNT:
		base_radius.append(float(rings[index]["base_radius"]))
		# Sourced from the spec list the mesh was actually built from, not
		# recomputed from the profile's authored default -- the geometry and
		# this uniform have to describe the same ceiling.
		ceiling.append(float(rings[index]["extension_scale"]))
		launch.append(float(TechniqueChargeAuraProfile.RING_LAUNCH_SECONDS[index]))
		rise.append(float(TechniqueChargeAuraProfile.RING_RISE_SECONDS[index]))
		if index == 0:
			period.append(core_period)
			decay.append(core_decay)
			overshoot.append(core_overshoot)
		else:
			period.append(
				float(TechniqueChargeAuraProfile.RING_BOUNCE_PERIOD_SECONDS[index])
			)
			decay.append(float(TechniqueChargeAuraProfile.RING_BOUNCE_DECAY[index]))
			overshoot.append(float(TechniqueChargeAuraProfile.RING_OVERSHOOT[index]))
		breath_scale.append(
			float(TechniqueChargeAuraProfile.RING_BREATH_SCALE[index])
		)
		var op := float(TechniqueChargeAuraProfile.RING_OPACITY[index])
		if index != 0:
			op *= flare_opacity_scale
		ring_opacity.append(op)
		ring_tip_bright.append(
			float(TechniqueChargeAuraProfile.RING_TIP_BRIGHT[index])
		)

	material.set_shader_parameter("ring_base_radius", base_radius)
	material.set_shader_parameter("ring_ceiling", ceiling)
	material.set_shader_parameter("ring_launch", launch)
	material.set_shader_parameter("ring_rise", rise)
	material.set_shader_parameter("ring_period", period)
	material.set_shader_parameter("ring_decay", decay)
	material.set_shader_parameter("ring_overshoot", overshoot)
	material.set_shader_parameter("ring_breath_scale", breath_scale)
	material.set_shader_parameter("ring_opacity", ring_opacity)
	material.set_shader_parameter("ring_tip_bright", ring_tip_bright)

	material.set_shader_parameter(
		"breath_min", tunable("BREATH_MIN", TechniqueChargeAuraProfile.BREATH_MIN)
	)
	material.set_shader_parameter(
		"breath_max", tunable("BREATH_MAX", TechniqueChargeAuraProfile.BREATH_MAX)
	)
	material.set_shader_parameter(
		"breath_face_mix",
		tunable("BREATH_FACE_MIX", TechniqueChargeAuraProfile.BREATH_FACE_MIX)
	)
	material.set_shader_parameter(
		"breath_bright_coupling",
		tunable(
			"BREATH_BRIGHT_COUPLING",
			TechniqueChargeAuraProfile.BREATH_BRIGHT_COUPLING
		)
	)
	material.set_shader_parameter(
		"breath_flutter_coupling",
		TechniqueChargeAuraProfile.BREATH_FLUTTER_COUPLING
	)
	material.set_shader_parameter(
		"breath_rate_slow",
		tunable("BREATH_RATE_SLOW", TechniqueChargeAuraProfile.BREATH_RATE_SLOW)
	)
	material.set_shader_parameter(
		"breath_rate_fast",
		tunable("BREATH_RATE_FAST", TechniqueChargeAuraProfile.BREATH_RATE_FAST)
	)
	material.set_shader_parameter(
		"ring_phase_a1",
		tunable("RING_PHASE_A1", TechniqueChargeAuraProfile.RING_PHASE_A1)
	)
	material.set_shader_parameter(
		"ring_phase_a2",
		tunable("RING_PHASE_A2", TechniqueChargeAuraProfile.RING_PHASE_A2)
	)
	material.set_shader_parameter(
		"ground_pulse_strength", TechniqueChargeAuraProfile.GROUND_PULSE_STRENGTH
	)
	material.set_shader_parameter(
		"ground_pulse_floor", TechniqueChargeAuraProfile.GROUND_PULSE_FLOOR
	)


## Builds every ring into a single surface.
##
## Three MeshInstance3D children would be three geometry instances and three
## draw calls against authored ceilings of two. One hundred and twenty vertices
## in one surface are one of each, so the stack is free at the only budget that
## was ever asserted. Each vertex carries its ring's identity in COLOR.r, which
## is the only thing the shader needs in order to look the rest of that ring's
## constants up.
static func _createRingStackMesh(rings: Array) -> ArrayMesh:
	assert(not rings.is_empty(), "Technique charge aura needs at least one ring.")
	var vertices := PackedVector3Array()
	var normals := PackedVector3Array()
	var uvs := PackedVector2Array()
	var colors := PackedColorArray()
	var indices := PackedInt32Array()

	for ring_index in rings.size():
		_appendRing(
			ring_index, rings[ring_index], vertices, normals, uvs, colors, indices
		)

	var arrays: Array = []
	arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX] = vertices
	arrays[Mesh.ARRAY_NORMAL] = normals
	arrays[Mesh.ARRAY_TEX_UV] = uvs
	arrays[Mesh.ARRAY_COLOR] = colors
	arrays[Mesh.ARRAY_INDEX] = indices
	var mesh := ArrayMesh.new()
	mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
	return mesh


## One open polygonal ring, leaning outward from the ground plane.
##
## Faces keep the shipped construction: four unwelded vertices each, so every
## face maps the complete mask rather than stretching it around the
## circumference. The corners of neighbouring faces are built at coincident
## positions, which is what lets the shader derive a phase from vertex position
## and have both sides of a corner resolve to the same value.
static func _appendRing(
		ring_index: int,
		ring: Dictionary,
		vertices: PackedVector3Array,
		normals: PackedVector3Array,
		uvs: PackedVector2Array,
		colors: PackedColorArray,
		indices: PackedInt32Array) -> void:
	var sides: int = ring["sides"]
	var base_radius := float(ring["base_radius"])
	var extension := float(ring["length"]) * float(ring.get("extension_scale", 1.0))
	var lean := deg_to_rad(float(ring["lean_degrees"]))
	assert(sides >= 3, "Technique charge aura rings need at least three sides.")
	assert(base_radius > 0.0 and extension > 0.0, "Aura ring dimensions must be positive.")
	# A lean of zero lays the ring flat on the floor and, worse, collapses the
	# radial part of its normal -- which is the only thing carrying the face's
	# own azimuth to the shader.
	assert(
		lean > 0.0 and lean <= PI * 0.5,
		"Aura ring lean must be inside (0, 90] degrees."
	)

	var tip_radius := base_radius + extension * cos(lean)
	var tip_height := extension * sin(lean)
	var radial_normal := sin(lean)
	var vertical_normal := -cos(lean)
	# Vertex colour survives as 8-bit through every compression setting, and
	# 0.0 / 0.5 / 1.0 round-trip exactly through that, so the identity cannot be
	# quantised into the wrong ring.
	var identity := float(ring_index) / float(TechniqueChargeAuraProfile.RING_COUNT - 1)
	var ring_color := Color(identity, 0.0, 0.0, 1.0)

	for side in range(sides):
		var angle_a := TAU * float(side) / float(sides)
		var angle_b := TAU * float(side + 1) / float(sides)
		var dir_a := Vector3(cos(angle_a), 0.0, sin(angle_a))
		var dir_b := Vector3(cos(angle_b), 0.0, sin(angle_b))
		var outward_angle := (angle_a + angle_b) * 0.5
		var outward := Vector3(
			cos(outward_angle) * radial_normal,
			vertical_normal,
			sin(outward_angle) * radial_normal
		).normalized()
		var base := vertices.size()

		vertices.append_array(PackedVector3Array([
			dir_a * base_radius,
			dir_b * base_radius,
			dir_a * tip_radius + Vector3.UP * tip_height,
			dir_b * tip_radius + Vector3.UP * tip_height,
		]))
		normals.append_array(PackedVector3Array([outward, outward, outward, outward]))
		uvs.append_array(PackedVector2Array([
			Vector2(0.0, 1.0),
			Vector2(1.0, 1.0),
			Vector2(0.0, 0.0),
			Vector2(1.0, 0.0),
		]))
		colors.append_array(PackedColorArray([
			ring_color, ring_color, ring_color, ring_color
		]))
		indices.append_array(PackedInt32Array([
			base,
			base + 3,
			base + 2,
			base,
			base + 1,
			base + 3,
		]))
