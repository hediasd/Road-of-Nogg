## Reference-locked generic spell-cast aura playback.
##
## One restrained footprint, one alpha-mixed body haze, and one additive
## far-side ghost-ray field reconstruct the source without billboards.

class_name SpellCastAura
extends "res://src/presentation/effects/VfxPlayback.gd"

const _FOOTPRINT_SHADER = preload(
		"res://assets/shaders/effects/spell_cast_footprint_aperture.gdshader")
const _HAZE_SHADER = preload(
		"res://assets/shaders/effects/spell_cast_haze_field.gdshader")
const _RAY_SHADER = preload(
		"res://assets/shaders/effects/spell_cast_ghost_rays.gdshader")
const _PLUME_ATLAS = preload(
		"res://assets/vfx/spell_cast_aura/plume_flow_atlas.png")
const _DEBUG_TRANSPARENT_CENTER_FLAG := "--spell-aura-transparent-center"
const _DEBUG_CROSSFADE_PLUME_FLAG := "--spell-aura-crossfade-plume"

const VISIBLE_DURATION := SpellCastAuraProfile.DURATION_SECONDS
const SETTLE_NORMALIZED_TIME := SpellCastAuraProfile.SETTLE_NORMALIZED_TIME
const LAYER_FOOTPRINT := "footprint_aperture"
const LAYER_HAZE := "haze_field"
const LAYER_RAYS := "ghost_rays"

var _elementColor := Color.WHITE
var _footprintInstance: MeshInstance3D
var _footprintMaterial: ShaderMaterial
var _hazeInstance: MeshInstance3D
var _hazeMaterial: ShaderMaterial
var _rayInstance: MeshInstance3D
var _rayMaterial: ShaderMaterial
var _centerDarkeningEnabled := true
var _hazeStateCrossfade := SpellCastAuraProfile.HAZE_STATE_CROSSFADE
var _rayStateCrossfade := SpellCastAuraProfile.RAY_STATE_CROSSFADE
var _elapsedTime := 0.0
var _playbackScale := 1.0
var _activeSeed := 0
var _mode := MODE_BATTLE
var _playing := false
var _finished := true
var _disposed := false
var _autoDispose := false


static func spawn(parent: Node3D, world_pos: Vector3, element_color: Color) -> void:
	var playback := createPlayback(parent, world_pos, element_color)
	playback._autoDispose = true
	playback.play(0, MODE_BATTLE)


static func createPlayback(
		parent: Node3D,
		world_pos: Vector3,
		element_color: Color,
		overrides: Dictionary = {}) -> SpellCastAura:
	var playback := SpellCastAura.new()
	playback.name = "SpellCastAura"
	playback.position = world_pos
	playback._elementColor = element_color
	parent.add_child(playback)
	# Before `_buildLayers()`: the plume meshes and the aperture's uniforms are
	# assembled there, so an override arriving afterwards changes nothing.
	playback.set_tunable_overrides(overrides)
	playback._buildLayers()
	return playback


func play(seed: int, mode: String) -> void:
	assert(not _disposed, "Cannot play a disposed SpellCastAura.")
	assert(mode == MODE_REFERENCE or mode == MODE_BATTLE, "Unknown VFX playback mode.")
	_activeSeed = seed
	_mode = mode
	_elapsedTime = 0.0
	_finished = false
	_playing = true
	_applySeed(seed)
	_applyProgress(0.0)
	set_process(true)


func set_playback_scale(scale: float) -> void:
	_playbackScale = maxf(scale, 0.0)


func seek_normalized(time: float) -> void:
	if _disposed:
		return
	var normalizedTime := clampf(time, 0.0, 1.0)
	_elapsedTime = normalizedTime * VISIBLE_DURATION
	_finished = normalizedTime >= 1.0
	if _finished:
		_playing = false
	_applyProgress(normalizedTime)


func skip_to_settle() -> void:
	seek_normalized(SETTLE_NORMALIZED_TIME)


func get_normalized_time() -> float:
	return clampf(_elapsedTime / VISIBLE_DURATION, 0.0, 1.0)


func get_elapsed_time() -> float:
	return _elapsedTime


func get_total_duration() -> float:
	return VISIBLE_DURATION


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
	if is_inside_tree():
		queue_free()
	else:
		# Scene teardown can invoke disposal while the object is notification-
		# locked. Deferral releases that lock before the final free.
		call_deferred("free")


func get_layer_names() -> Array[String]:
	return [LAYER_FOOTPRINT, LAYER_HAZE, LAYER_RAYS]


func set_layer_visible(layer_name: String, visible: bool) -> void:
	match layer_name:
		LAYER_FOOTPRINT:
			if _footprintInstance != null:
				_footprintInstance.visible = visible
		LAYER_HAZE:
			if _hazeInstance != null:
				_hazeInstance.visible = visible
		LAYER_RAYS:
			if _rayInstance != null:
				_rayInstance.visible = visible
		_:
			push_warning("Unknown SpellCastAura layer: %s" % layer_name)


## Debug A/B hook. Battle playback uses the approved navy-darkened centre;
## authoring captures may still select transparent for comparison.
func set_center_darkening(enabled: bool) -> void:
	_centerDarkeningEnabled = enabled
	if _footprintMaterial != null:
		_footprintMaterial.set_shader_parameter(
			"center_darkening",
			SpellCastAuraProfile.CENTER_DARKENING_ALPHA if enabled else 0.0
		)


func is_center_darkening_enabled() -> bool:
	return _centerDarkeningEnabled


## Debug transition control. Zero holds the current atlas cell; one crossfades
## continuously into the next. Both paths are deterministic normalized seeks.
func set_plume_state_crossfade(amount: float) -> void:
	_hazeStateCrossfade = clampf(amount, 0.0, 1.0)
	_rayStateCrossfade = _hazeStateCrossfade
	for material: ShaderMaterial in [_hazeMaterial, _rayMaterial]:
		if material != null:
			material.set_shader_parameter("state_crossfade", _hazeStateCrossfade)


func get_plume_state_crossfade() -> float:
	return _rayStateCrossfade


func get_live_particle_count() -> int:
	return 0


func get_live_instance_count() -> int:
	if _finished:
		return 0
	var count := 0
	for instance: MeshInstance3D in [
		_footprintInstance, _hazeInstance, _rayInstance
	]:
		if instance != null and instance.visible:
			count += 1
	return count


func get_live_node_count() -> int:
	if _disposed:
		return 0
	return _countNodes(self)


func is_particle_seek_exact() -> bool:
	return true


func get_active_seed() -> int:
	return _activeSeed


func get_mode() -> String:
	return _mode


func _process(delta: float) -> void:
	if not _playing or _playbackScale <= 0.0:
		return
	_elapsedTime = minf(_elapsedTime + delta * _playbackScale, VISIBLE_DURATION)
	_applyProgress(get_normalized_time())
	if _elapsedTime >= VISIBLE_DURATION:
		_finished = true
		_playing = false
		if _autoDispose:
			dispose()


## Parameters this effect exposes for live authoring. Defaults are the profile's
## own AUTHORED constants, which stay the documented source of truth; these make
## them adjustable without a relaunch, not authoritative.
##
## Every row rebuilds: the flow shells are meshes generated at build time and
## the aperture's values are baked into shader uniforms as the material is
## assembled, so there is no live-uniform path to nudge.
static func tunables() -> Array[Dictionary]:
	return [
		{
			"id": "HAZE_BOTTOM_RADIUS_U", "label": "Bottom radius",
			"group": "Body haze", "min": 0.05, "max": 3.0, "step": 0.01,
			"default": SpellCastAuraProfile.HAZE_BOTTOM_RADIUS_U, "rebuild": true,
		},
		{
			"id": "HAZE_MIDDLE_RADIUS_U", "label": "Middle radius",
			"group": "Body haze", "min": 0.05, "max": 4.0, "step": 0.01,
			"default": SpellCastAuraProfile.HAZE_MIDDLE_RADIUS_U, "rebuild": true,
		},
		{
			"id": "HAZE_TOP_RADIUS_U", "label": "Top radius",
			"group": "Body haze", "min": 0.05, "max": 5.0, "step": 0.01,
			"default": SpellCastAuraProfile.HAZE_TOP_RADIUS_U, "rebuild": true,
		},
		{
			"id": "HAZE_MIDDLE_HEIGHT_FRACTION", "label": "Middle height",
			"group": "Body haze", "min": 0.05, "max": 0.95, "step": 0.01,
			"default": SpellCastAuraProfile.HAZE_MIDDLE_HEIGHT_FRACTION, "rebuild": true,
		},
		{
			"id": "HAZE_HEIGHT_U", "label": "Height",
			"group": "Body haze", "min": 0.1, "max": 5.0, "step": 0.05,
			"default": SpellCastAuraProfile.HAZE_HEIGHT_U, "rebuild": true,
		},
		{
			"id": "HAZE_OPACITY", "label": "Opacity",
			"group": "Body haze", "min": 0.0, "max": 1.0, "step": 0.01,
			"default": SpellCastAuraProfile.HAZE_OPACITY, "rebuild": true,
		},
		{
			"id": "HAZE_EMISSION_ENERGY", "label": "Emission",
			"group": "Body haze", "min": 0.0, "max": 6.0, "step": 0.05,
			"default": SpellCastAuraProfile.HAZE_EMISSION_ENERGY, "rebuild": true,
		},
		{
			"id": "HAZE_STATE_CROSSFADE", "label": "State crossfade",
			"group": "Body haze", "min": 0.0, "max": 1.0, "step": 0.05,
			"default": SpellCastAuraProfile.HAZE_STATE_CROSSFADE, "rebuild": true,
		},
		{
			"id": "HAZE_SPIN_TURNS", "label": "Sequence spin",
			"group": "Body haze", "min": 0.0, "max": 0.24, "step": 0.01,
			"default": SpellCastAuraProfile.HAZE_SPIN_TURNS, "rebuild": true,
		},
		{
			"id": "RAY_BOTTOM_RADIUS_U", "label": "Bottom radius",
			"group": "Ghost rays", "min": 0.05, "max": 3.0, "step": 0.01,
			"default": SpellCastAuraProfile.RAY_BOTTOM_RADIUS_U, "rebuild": true,
		},
		{
			"id": "RAY_MIDDLE_RADIUS_U", "label": "Middle radius",
			"group": "Ghost rays", "min": 0.05, "max": 4.0, "step": 0.01,
			"default": SpellCastAuraProfile.RAY_MIDDLE_RADIUS_U, "rebuild": true,
		},
		{
			"id": "RAY_TOP_RADIUS_U", "label": "Top radius",
			"group": "Ghost rays", "min": 0.05, "max": 5.0, "step": 0.01,
			"default": SpellCastAuraProfile.RAY_TOP_RADIUS_U, "rebuild": true,
		},
		{
			"id": "RAY_MIDDLE_HEIGHT_FRACTION", "label": "Middle height",
			"group": "Ghost rays", "min": 0.05, "max": 0.95, "step": 0.01,
			"default": SpellCastAuraProfile.RAY_MIDDLE_HEIGHT_FRACTION, "rebuild": true,
		},
		{
			"id": "RAY_HEIGHT_U", "label": "Height",
			"group": "Ghost rays", "min": 0.1, "max": 5.0, "step": 0.05,
			"default": SpellCastAuraProfile.RAY_HEIGHT_U, "rebuild": true,
		},
		{
			"id": "RAY_OPACITY", "label": "Opacity",
			"group": "Ghost rays", "min": 0.0, "max": 1.0, "step": 0.01,
			"default": SpellCastAuraProfile.RAY_OPACITY, "rebuild": true,
		},
		{
			"id": "RAY_EMISSION_ENERGY", "label": "Emission",
			"group": "Ghost rays", "min": 0.0, "max": 8.0, "step": 0.05,
			"default": SpellCastAuraProfile.RAY_EMISSION_ENERGY, "rebuild": true,
		},
		{
			"id": "RAY_STATE_CROSSFADE", "label": "State crossfade",
			"group": "Ghost rays", "min": 0.0, "max": 1.0, "step": 0.05,
			"default": SpellCastAuraProfile.RAY_STATE_CROSSFADE, "rebuild": true,
		},
		{
			"id": "RAY_SPIN_TURNS", "label": "Sequence spin",
			"group": "Ghost rays", "min": 0.0, "max": 0.24, "step": 0.01,
			"default": SpellCastAuraProfile.RAY_SPIN_TURNS, "rebuild": true,
		},
		{
			"id": "RAY_TIP_OSCILLATION_CYCLES", "label": "Tip cycles",
			"group": "Ghost rays", "min": 0.0, "max": 3.0, "step": 0.05,
			"default": SpellCastAuraProfile.RAY_TIP_OSCILLATION_CYCLES, "rebuild": true,
		},
		{
			"id": "RAY_TIP_OSCILLATION_AMPLITUDE", "label": "Tip amplitude",
			"group": "Ghost rays", "min": 0.0, "max": 0.25, "step": 0.005,
			"default": SpellCastAuraProfile.RAY_TIP_OSCILLATION_AMPLITUDE,
			"rebuild": true,
		},
		{
			"id": "APERTURE_RIM_WIDTH", "label": "Rim width",
			"group": "Aperture", "min": 0.0, "max": 0.5, "step": 0.005,
			"default": SpellCastAuraProfile.APERTURE_RIM_WIDTH, "rebuild": true,
		},
		{
			"id": "APERTURE_RIM_ALPHA", "label": "Rim alpha",
			"group": "Aperture", "min": 0.0, "max": 1.0, "step": 0.01,
			"default": SpellCastAuraProfile.APERTURE_RIM_ALPHA, "rebuild": true,
		},
		{
			"id": "APERTURE_STRIATION_ALPHA", "label": "Striation alpha",
			"group": "Aperture", "min": 0.0, "max": 1.0, "step": 0.01,
			"default": SpellCastAuraProfile.APERTURE_STRIATION_ALPHA, "rebuild": true,
		},
		{
			"id": "APERTURE_RIM_EMISSION_ENERGY", "label": "Rim emission",
			"group": "Aperture", "min": 0.0, "max": 4.0, "step": 0.02,
			"default": SpellCastAuraProfile.APERTURE_RIM_EMISSION_ENERGY, "rebuild": true,
		},
		{
			"id": "FOOTPRINT_OUTER_RADIUS_U", "label": "Footprint radius",
			"group": "Aperture", "min": 0.2, "max": 3.0, "step": 0.01,
			"default": SpellCastAuraProfile.FOOTPRINT_OUTER_RADIUS_U, "rebuild": true,
		},
	]


func _buildLayers() -> void:
	_centerDarkeningEnabled = not OS.get_cmdline_user_args().has(
		_DEBUG_TRANSPARENT_CENTER_FLAG
	)
	var forceCrossfade := OS.get_cmdline_user_args().has(_DEBUG_CROSSFADE_PLUME_FLAG)
	_hazeStateCrossfade = (
		1.0 if forceCrossfade else tunable(
			"HAZE_STATE_CROSSFADE", SpellCastAuraProfile.HAZE_STATE_CROSSFADE
		)
	)
	_rayStateCrossfade = (
		1.0 if forceCrossfade else tunable(
			"RAY_STATE_CROSSFADE", SpellCastAuraProfile.RAY_STATE_CROSSFADE
		)
	)
	_footprintInstance = _createFootprintAperture(_elementColor, _centerDarkeningEnabled)
	add_child(_footprintInstance)
	_footprintMaterial = _footprintInstance.material_override as ShaderMaterial
	_hazeInstance = _createFlowShell(
		"BodyHazeField",
		_HAZE_SHADER,
		_elementColor,
		tunable("HAZE_BOTTOM_RADIUS_U", SpellCastAuraProfile.HAZE_BOTTOM_RADIUS_U),
		tunable("HAZE_MIDDLE_RADIUS_U", SpellCastAuraProfile.HAZE_MIDDLE_RADIUS_U),
		tunable("HAZE_TOP_RADIUS_U", SpellCastAuraProfile.HAZE_TOP_RADIUS_U),
		tunable(
			"HAZE_MIDDLE_HEIGHT_FRACTION",
			SpellCastAuraProfile.HAZE_MIDDLE_HEIGHT_FRACTION
		),
		tunable("HAZE_HEIGHT_U", SpellCastAuraProfile.HAZE_HEIGHT_U),
		SpellCastAuraProfile.HAZE_UV_PHASE,
		tunable("HAZE_SPIN_TURNS", SpellCastAuraProfile.HAZE_SPIN_TURNS),
		tunable("HAZE_OPACITY", SpellCastAuraProfile.HAZE_OPACITY),
		tunable("HAZE_EMISSION_ENERGY", SpellCastAuraProfile.HAZE_EMISSION_ENERGY),
		SpellCastAuraProfile.HAZE_RENDER_PRIORITY,
		_hazeStateCrossfade
	)
	add_child(_hazeInstance)
	_hazeMaterial = _hazeInstance.material_override as ShaderMaterial
	_rayInstance = _createFlowShell(
		"GhostRayField",
		_RAY_SHADER,
		_elementColor,
		tunable("RAY_BOTTOM_RADIUS_U", SpellCastAuraProfile.RAY_BOTTOM_RADIUS_U),
		tunable("RAY_MIDDLE_RADIUS_U", SpellCastAuraProfile.RAY_MIDDLE_RADIUS_U),
		tunable("RAY_TOP_RADIUS_U", SpellCastAuraProfile.RAY_TOP_RADIUS_U),
		tunable(
			"RAY_MIDDLE_HEIGHT_FRACTION",
			SpellCastAuraProfile.RAY_MIDDLE_HEIGHT_FRACTION
		),
		tunable("RAY_HEIGHT_U", SpellCastAuraProfile.RAY_HEIGHT_U),
		SpellCastAuraProfile.RAY_UV_PHASE,
		tunable("RAY_SPIN_TURNS", SpellCastAuraProfile.RAY_SPIN_TURNS),
		tunable("RAY_OPACITY", SpellCastAuraProfile.RAY_OPACITY),
		tunable("RAY_EMISSION_ENERGY", SpellCastAuraProfile.RAY_EMISSION_ENERGY),
		SpellCastAuraProfile.RAY_RENDER_PRIORITY,
		_rayStateCrossfade
	)
	add_child(_rayInstance)
	_rayMaterial = _rayInstance.material_override as ShaderMaterial
	_rayMaterial.set_shader_parameter(
		"tip_oscillation_cycles",
		tunable(
			"RAY_TIP_OSCILLATION_CYCLES",
			SpellCastAuraProfile.RAY_TIP_OSCILLATION_CYCLES
		)
	)
	_rayMaterial.set_shader_parameter(
		"tip_oscillation_amplitude",
		tunable(
			"RAY_TIP_OSCILLATION_AMPLITUDE",
			SpellCastAuraProfile.RAY_TIP_OSCILLATION_AMPLITUDE
		)
	)
	_rayMaterial.set_shader_parameter(
		"tip_phase_step", SpellCastAuraProfile.RAY_TIP_PHASE_STEP
	)
	_applySeed(0)
	assert(
		_countNodes(self) <= SpellCastAuraProfile.MAX_EFFECT_NODES,
		"Spell-cast aura exceeded its authored node ceiling."
	)
	assert(
		SpellCastAuraProfile.EXPECTED_DRAW_CALLS <= SpellCastAuraProfile.MAX_DRAW_CALLS,
		"Spell-cast aura exceeded its authored draw-call ceiling."
	)
	assert(
		SpellCastAuraProfile.EXPECTED_GEOMETRY_INSTANCES
				<= SpellCastAuraProfile.MAX_GEOMETRY_INSTANCES,
		"Spell-cast aura exceeded its authored geometry-instance ceiling."
	)
	set_process(false)


func _applyProgress(progress: float) -> void:
	var statePosition := _sourceStatePosition(progress)
	var lifecycleVisibility := _lifecycleVisibility(progress)
	var footprintIgnition := _footprintIgnition(progress)
	var plumeRootIgnition := _plumeRootIgnition(progress)
	var plumeRevealFront := _plumeRevealFront(progress)
	if _footprintMaterial != null:
		_footprintMaterial.set_shader_parameter("source_state_position", statePosition)
		_footprintMaterial.set_shader_parameter(
			"aperture_radius",
			_sampleSourceCurve(progress, SpellCastAuraProfile.APERTURE_RADIUS_CURVE)
		)
		_footprintMaterial.set_shader_parameter(
			"rim_width",
			_sampleSourceCurve(progress, SpellCastAuraProfile.APERTURE_RIM_WIDTH_CURVE)
					* tunable(
						"APERTURE_RIM_WIDTH", SpellCastAuraProfile.APERTURE_RIM_WIDTH
					)
					/ SpellCastAuraProfile.APERTURE_RIM_WIDTH
		)
		_footprintMaterial.set_shader_parameter(
			"striation_visibility",
			_sampleSourceCurve(progress, SpellCastAuraProfile.APERTURE_STRIATION_CURVE)
		)
		_footprintMaterial.set_shader_parameter("root_ignition", footprintIgnition)
		_footprintMaterial.set_shader_parameter(
			"lifecycle_visibility", lifecycleVisibility
		)
	var sourceEnergy := _sampleSourceCurve(
		progress, SpellCastAuraProfile.PLUME_ENERGY_CURVE
	)
	if _hazeInstance != null:
		var hazeWidth := _sampleSourceCurve(
			progress, SpellCastAuraProfile.HAZE_WIDTH_SCALE_CURVE
		)
		var hazeHeight := _sampleSourceCurve(
			progress, SpellCastAuraProfile.HAZE_HEIGHT_SCALE_CURVE
		)
		_hazeInstance.scale = Vector3(hazeWidth, hazeHeight, hazeWidth)
	if _rayInstance != null:
		var rayWidth := _sampleSourceCurve(
			progress, SpellCastAuraProfile.RAY_WIDTH_SCALE_CURVE
		)
		var rayHeight := _sampleSourceCurve(
			progress, SpellCastAuraProfile.RAY_HEIGHT_SCALE_CURVE
		)
		_rayInstance.scale = Vector3(rayWidth, rayHeight, rayWidth)
	if _hazeMaterial != null:
		_hazeMaterial.set_shader_parameter("atlas_state_position", statePosition)
		_hazeMaterial.set_shader_parameter(
			"plume_energy",
			sourceEnergy * _sampleSourceCurve(
				progress, SpellCastAuraProfile.HAZE_VISIBILITY_SCALE_CURVE
			)
		)
	if _rayMaterial != null:
		_rayMaterial.set_shader_parameter("atlas_state_position", statePosition)
		_rayMaterial.set_shader_parameter(
			"plume_energy",
			sourceEnergy * _sampleSourceCurve(
				progress, SpellCastAuraProfile.RAY_VISIBILITY_SCALE_CURVE
			)
		)
	for material: ShaderMaterial in [_hazeMaterial, _rayMaterial]:
		if material != null:
			material.set_shader_parameter("root_ignition", plumeRootIgnition)
			material.set_shader_parameter("reveal_front", plumeRevealFront)
			material.set_shader_parameter(
				"reveal_softness", SpellCastAuraProfile.PLUME_REVEAL_SOFTNESS
			)
			material.set_shader_parameter(
				"lifecycle_visibility", lifecycleVisibility
			)


func _applySeed(seed: int) -> void:
	for material: ShaderMaterial in [
		_footprintMaterial, _hazeMaterial, _rayMaterial
	]:
		if material != null:
			material.set_shader_parameter("seed_value", float(seed))


## No longer static: the aperture's uniforms are the effect's most-authored
## surface, so they read through the instance's tunable overrides. The profile
## constants remain their defaults.
func _createFootprintAperture(
		color: Color,
		darkenCenter: bool) -> MeshInstance3D:
	var plane := PlaneMesh.new()
	plane.size = Vector2(
		SpellCastAuraProfile.FOOTPRINT_PLANE_SIZE_U,
		SpellCastAuraProfile.FOOTPRINT_PLANE_SIZE_U
	)
	var material := ShaderMaterial.new()
	material.shader = _FOOTPRINT_SHADER
	material.render_priority = SpellCastAuraProfile.FOOTPRINT_RENDER_PRIORITY
	material.set_shader_parameter("aura_color", color)
	material.set_shader_parameter("seed_value", 0.0)
	material.set_shader_parameter("outer_radius", tunable(
		"FOOTPRINT_OUTER_RADIUS_U", SpellCastAuraProfile.FOOTPRINT_OUTER_RADIUS_U
	))
	material.set_shader_parameter("aperture_radius", SpellCastAuraProfile.APERTURE_RADIUS_START)
	material.set_shader_parameter("rim_width", tunable(
		"APERTURE_RIM_WIDTH", SpellCastAuraProfile.APERTURE_RIM_WIDTH
	))
	material.set_shader_parameter("rim_alpha", tunable(
		"APERTURE_RIM_ALPHA", SpellCastAuraProfile.APERTURE_RIM_ALPHA
	))
	material.set_shader_parameter("striation_alpha", tunable(
		"APERTURE_STRIATION_ALPHA", SpellCastAuraProfile.APERTURE_STRIATION_ALPHA
	))
	material.set_shader_parameter("striation_visibility", 1.0)
	material.set_shader_parameter("rim_emission_energy", tunable(
		"APERTURE_RIM_EMISSION_ENERGY",
		SpellCastAuraProfile.APERTURE_RIM_EMISSION_ENERGY
	))
	material.set_shader_parameter(
		"center_darkening",
		SpellCastAuraProfile.CENTER_DARKENING_ALPHA if darkenCenter else 0.0
	)
	material.set_shader_parameter("source_state_position", 0.0)
	material.set_shader_parameter(
		"spin_turns", SpellCastAuraProfile.FOOTPRINT_SPIN_TURNS
	)
	material.set_shader_parameter("root_ignition", 0.0)
	material.set_shader_parameter("lifecycle_visibility", 1.0)

	var instance := MeshInstance3D.new()
	instance.name = "FootprintAperture"
	instance.mesh = plane
	instance.position.y = SpellCastAuraProfile.FOOTPRINT_HEIGHT_U
	instance.material_override = material
	instance.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	return instance


static func _createFlowShell(
		instanceName: String,
		shader: Shader,
		color: Color,
		bottomRadius: float,
		middleRadius: float,
		topRadius: float,
		middleHeightFraction: float,
		height: float,
		uvPhase: float,
		spinTurns: float,
		opacity: float,
		emissionEnergy: float,
		renderPriority: int,
		stateCrossfade: float) -> MeshInstance3D:
	var material := ShaderMaterial.new()
	material.shader = shader
	material.render_priority = renderPriority
	material.set_shader_parameter("plume_atlas", _PLUME_ATLAS)
	material.set_shader_parameter(
		"atlas_pixel_size", SpellCastAuraProfile.PLUME_ATLAS_PIXEL_SIZE
	)
	material.set_shader_parameter("aura_color", color)
	material.set_shader_parameter("seed_value", 0.0)
	material.set_shader_parameter("uv_phase", uvPhase)
	material.set_shader_parameter("spin_turns", spinTurns)
	material.set_shader_parameter("shell_opacity", opacity)
	material.set_shader_parameter("emission_energy", emissionEnergy)
	material.set_shader_parameter("state_crossfade", stateCrossfade)
	material.set_shader_parameter("atlas_state_position", 0.0)
	material.set_shader_parameter("plume_energy", SpellCastAuraProfile.PLUME_ENERGY_CURVE[0])
	material.set_shader_parameter("root_ignition", 0.0)
	material.set_shader_parameter("reveal_front", 0.0)
	material.set_shader_parameter(
		"reveal_softness", SpellCastAuraProfile.PLUME_REVEAL_SOFTNESS
	)
	material.set_shader_parameter("lifecycle_visibility", 1.0)

	var instance := MeshInstance3D.new()
	instance.name = instanceName
	instance.mesh = _createProfiledShellMesh(
		bottomRadius, middleRadius, topRadius, middleHeightFraction, height
	)
	instance.position.y = SpellCastAuraProfile.PLUME_BASE_HEIGHT_U
	instance.material_override = material
	instance.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	instance.custom_aabb = AABB(
		Vector3(-maxf(middleRadius, topRadius), -0.02, -maxf(middleRadius, topRadius)),
		Vector3(maxf(middleRadius, topRadius) * 2.0, height + 0.04,
			maxf(middleRadius, topRadius) * 2.0)
	)
	return instance


## Each role owns a measured lower/middle/upper radius profile. Outward-facing
## winding lets the haze control its front contribution while the ray shader
## discards its front faces without camera-facing geometry.
static func _createProfiledShellMesh(
		bottomRadius: float,
		middleRadius: float,
		topRadius: float,
		middleHeightFraction: float,
		height: float) -> ArrayMesh:
	assert(
		bottomRadius <= middleRadius and middleRadius <= topRadius,
		"Spell-cast aura carrier radius must expand monotonically upward."
	)
	var segments := SpellCastAuraProfile.PLUME_SHELL_SEGMENTS
	var heightBands := SpellCastAuraProfile.PLUME_SHELL_HEIGHT_BANDS
	var vertices := PackedVector3Array()
	var normals := PackedVector3Array()
	var uvs := PackedVector2Array()
	var indices := PackedInt32Array()

	for row: int in range(heightBands + 1):
		var heightFraction := float(row) / float(heightBands)
		var radius := 0.0
		if heightFraction <= middleHeightFraction:
			var lowerWeight := smoothstep(
				0.0, middleHeightFraction, heightFraction
			)
			radius = lerpf(bottomRadius, middleRadius, lowerWeight)
		else:
			var upperWeight := smoothstep(
				middleHeightFraction, 1.0, heightFraction
			)
			radius = lerpf(middleRadius, topRadius, upperWeight)
		for segment: int in range(segments + 1):
			var angularFraction := float(segment) / float(segments)
			var angle := angularFraction * TAU
			var outward := Vector3(cos(angle), 0.0, sin(angle))
			vertices.append(outward * radius + Vector3.UP * height * heightFraction)
			normals.append(outward)
			uvs.append(Vector2(angularFraction, heightFraction))

	var rowStride := segments + 1
	for row: int in range(heightBands):
		for segment: int in range(segments):
			var lowerCurrent := row * rowStride + segment
			var lowerNext := lowerCurrent + 1
			var upperCurrent := lowerCurrent + rowStride
			var upperNext := upperCurrent + 1
			indices.append_array(PackedInt32Array([
				lowerCurrent, upperNext, upperCurrent,
				lowerCurrent, lowerNext, upperNext,
			]))

	var arrays: Array = []
	arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX] = vertices
	arrays[Mesh.ARRAY_NORMAL] = normals
	arrays[Mesh.ARRAY_TEX_UV] = uvs
	arrays[Mesh.ARRAY_INDEX] = indices
	var mesh := ArrayMesh.new()
	mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
	return mesh


static func _sourceStatePosition(progress: float) -> float:
	var times: Array = SpellCastAuraProfile.SOURCE_STATE_PROGRESS
	if progress <= float(times[0]):
		return 0.0
	for index: int in range(times.size() - 1):
		var start := float(times[index])
		var finish := float(times[index + 1])
		if progress <= finish:
			return float(index) + inverse_lerp(start, finish, progress)
	return float(times.size() - 1)


static func _sampleSourceCurve(progress: float, values: Array) -> float:
	assert(
		values.size() == SpellCastAuraProfile.SOURCE_STATE_PROGRESS.size(),
		"Spell-cast aura source curve length does not match its state timeline."
	)
	var position := _sourceStatePosition(progress)
	var current := mini(int(floor(position)), values.size() - 1)
	var following := mini(current + 1, values.size() - 1)
	return lerpf(
		float(values[current]), float(values[following]), position - floor(position)
	)


static func _footprintIgnition(progress: float) -> float:
	return smoothstep(0.0, SpellCastAuraProfile.FOOTPRINT_IGNITION_END, progress)


static func _plumeRootIgnition(progress: float) -> float:
	return smoothstep(
		SpellCastAuraProfile.PLUME_EMISSION_START,
		SpellCastAuraProfile.PLUME_ROOT_IGNITION_END,
		progress
	)


static func _plumeRevealFront(progress: float) -> float:
	var revealProgress := smoothstep(
		SpellCastAuraProfile.PLUME_EMISSION_START,
		SpellCastAuraProfile.CHARGE_END,
		progress
	)
	return revealProgress * SpellCastAuraProfile.PLUME_REVEAL_END


static func _lifecycleVisibility(progress: float) -> float:
	var sourceEnd := float(SpellCastAuraProfile.SOURCE_STATE_PROGRESS[-1])
	if progress <= sourceEnd:
		return 1.0
	return 1.0 - smoothstep(sourceEnd, SpellCastAuraProfile.DECAY_END, progress)


static func _countNodes(node: Node) -> int:
	var count := 1
	for child: Node in node.get_children():
		count += _countNodes(child)
	return count
