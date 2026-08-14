## Coronagraph storm panel playback for the Solar Storm spell.
##
## Forked from `AuroraVeilEffect` under docs/VFX_DESIGN.md §4's sibling test, and
## the sibling relationship is structural rather than convenient: identical
## Y-billboarded quad carrier, identical four-beat timeline shape, identical
## pixel snap, wave displacement, uniform radius response, and depth-resolved
## model lighting. The field is the only genuinely new part, which is exactly the
## case the policy says to fork rather than author fresh.
##
## The quad's base sits at the target's feet and the panel rises from there,
## scaling uniformly with the carrier's footprint through `setFootprint` while
## the occulter's anchor stays pinned in *world* units -- so a wider radius
## spreads the storm across the board instead of lifting it off the units.
##
## Depth testing is disabled and occlusion resolved in the fragment: where a
## model stands in front of the panel the storm goes transparent and lights it
## rather than covering it.

class_name SolarStormEffect
extends "res://src/presentation/effects/VfxPlayback.gd"

const _STORM_SHADER = preload("res://assets/shaders/effects/solar_storm_field.gdshader")

const VISIBLE_DURATION := SolarStormProfile.DURATION_SECONDS
const SETTLE_NORMALIZED_TIME := SolarStormProfile.SETTLE_NORMALIZED_TIME
const LAYER_STORM := "storm_field"

var _elementColor := Color.WHITE
var _panelInstance: MeshInstance3D
var _panelMesh: QuadMesh
var _stormMaterial: ShaderMaterial
var _groundWorldPosition := Vector3.ZERO
var _footprintRadius := SolarStormProfile.CARRIER_RADIUS_TILES
var _panelSize := Vector2(
	SolarStormProfile.PANEL_WIDTH_U, SolarStormProfile.PANEL_HEIGHT_U
)
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
		overrides: Dictionary = {}) -> SolarStormEffect:
	var playback := SolarStormEffect.new()
	playback.name = "SolarStormEffect"
	playback._elementColor = element_color
	playback._groundWorldPosition = world_pos
	parent.add_child(playback)
	playback._applyPanelTransform()
	# Before `_buildLayers()`, matching every other effect's factory: the shader
	# uniforms are seeded there, so an override arriving afterwards reaches
	# nothing and the debug panel reports a change that never hit the screen.
	playback.set_tunable_overrides(overrides)
	playback._buildLayers()
	return playback


## The panel anchors on the impact position rather than on individual targets:
## one storm covers the whole footprint, and overlapping panels would compound
## their grade instead of reading as several storms.
func configure_cast_context(context: VfxCastContext) -> void:
	if context == null:
		return
	_groundWorldPosition = context.impact_world_position
	_applyPanelTransform()


func play(seed: int, mode: String) -> void:
	assert(not _disposed, "Cannot play a disposed SolarStormEffect.")
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


func get_layer_names() -> Array[String]:
	return [LAYER_STORM]


func set_layer_visible(layer_name: String, visible: bool) -> void:
	match layer_name:
		LAYER_STORM:
			if _panelInstance != null:
				_panelInstance.visible = visible
		_:
			push_warning("Unknown SolarStormEffect layer: %s" % layer_name)


func get_live_particle_count() -> int:
	return 0


func get_live_instance_count() -> int:
	if _finished or _panelInstance == null or not _panelInstance.visible:
		return 0
	return 1


func get_live_node_count() -> int:
	if _disposed:
		return 0
	return _countNodes(self)


func get_live_draw_call_count() -> int:
	return get_live_instance_count()


func is_particle_seek_exact() -> bool:
	return true


func get_active_seed() -> int:
	return _activeSeed


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
		# Scene teardown can invoke disposal while the object is notification-
		# locked. Deferral releases that lock before the final free.
		call_deferred("free")


static func tunables() -> Array[Dictionary]:
	return [
		{
			"id": "EXPOSURE", "label": "Exposure", "group": "Grade",
			"min": 0.0, "max": 3.0, "step": 0.01,
			"default": SolarStormProfile.EXPOSURE, "rebuild": false,
		},
		{
			"id": "GRAIN_STRENGTH", "label": "Grain", "group": "Grade",
			"min": 0.0, "max": 0.30, "step": 0.005,
			"default": SolarStormProfile.GRAIN_STRENGTH, "rebuild": false,
		},
		{
			"id": "BLACK_LIFT", "label": "Black lift", "group": "Grade",
			"min": 0.0, "max": 0.15, "step": 0.002,
			"default": SolarStormProfile.BLACK_LIFT, "rebuild": false,
		},
		{
			"id": "CORONA_GAIN", "label": "Corona gain", "group": "Corona",
			"min": 0.0, "max": 2.0, "step": 0.01,
			"default": SolarStormProfile.CORONA_GAIN, "rebuild": false,
		},
		{
			"id": "CORONA_FALLOFF", "label": "Corona falloff", "group": "Corona",
			"min": 0.05, "max": 2.0, "step": 0.01,
			"default": SolarStormProfile.CORONA_FALLOFF, "rebuild": false,
		},
		{
			"id": "FOV_RADIUS", "label": "Field of view", "group": "Corona",
			"min": 0.1, "max": 1.5, "step": 0.01,
			"default": SolarStormProfile.FOV_RADIUS, "rebuild": false,
		},
		{
			"id": "FOV_EDGE", "label": "View edge fade", "group": "Corona",
			"min": 0.01, "max": 0.60, "step": 0.01,
			"default": SolarStormProfile.FOV_EDGE, "rebuild": false,
		},
		{
			"id": "STREAMER_THRESHOLD", "label": "Stream width", "group": "Streams",
			"min": 0.0, "max": 0.95, "step": 0.01,
			"default": SolarStormProfile.STREAMER_THRESHOLD, "rebuild": false,
		},
		{
			"id": "STREAMER_SHARPNESS", "label": "Stream edge", "group": "Streams",
			"min": 0.2, "max": 8.0, "step": 0.1,
			"default": SolarStormProfile.STREAMER_SHARPNESS, "rebuild": false,
		},
		{
			"id": "STREAMER_GAIN", "label": "Stream gain", "group": "Streams",
			"min": 0.0, "max": 3.0, "step": 0.05,
			"default": SolarStormProfile.STREAMER_GAIN, "rebuild": false,
		},
		{
			"id": "STREAMER_REACH", "label": "Stream reach", "group": "Streams",
			"min": 0.05, "max": 2.0, "step": 0.01,
			"default": SolarStormProfile.STREAMER_REACH, "rebuild": false,
		},
		{
			"id": "STREAMER_BROAD", "label": "Stream octave mix", "group": "Streams",
			"min": 0.0, "max": 1.0, "step": 0.02,
			"default": SolarStormProfile.STREAMER_BROAD, "rebuild": false,
		},
		{
			"id": "STREAMER_WARP", "label": "Stream splay", "group": "Streams",
			"min": 0.0, "max": 0.20, "step": 0.002,
			"default": SolarStormProfile.STREAMER_WARP, "rebuild": false,
		},
		{
			"id": "STREAMER_DRIFT", "label": "Stream drift", "group": "Streams",
			"min": 0.0, "max": 3.0, "step": 0.05,
			"default": SolarStormProfile.STREAMER_DRIFT, "rebuild": false,
		},
		{
			"id": "ARC_RADIUS", "label": "Front distance", "group": "Front",
			"min": 0.05, "max": 1.2, "step": 0.01,
			"default": SolarStormProfile.ARC_RADIUS, "rebuild": false,
		},
		{
			"id": "ARC_WIDTH", "label": "Front width", "group": "Front",
			"min": 0.005, "max": 0.20, "step": 0.002,
			"default": SolarStormProfile.ARC_WIDTH, "rebuild": false,
		},
		{
			"id": "ARC_GAIN", "label": "Front gain", "group": "Front",
			"min": 0.0, "max": 4.0, "step": 0.05,
			"default": SolarStormProfile.ARC_GAIN, "rebuild": false,
		},
		{
			"id": "ARC_SPAN", "label": "Front span", "group": "Front",
			"min": 0.05, "max": 1.0, "step": 0.01,
			"default": SolarStormProfile.ARC_SPAN, "rebuild": false,
		},
		{
			"id": "ARC_WARP", "label": "Front waviness", "group": "Front",
			"min": 0.0, "max": 0.30, "step": 0.005,
			"default": SolarStormProfile.ARC_WARP, "rebuild": false,
		},
		{
			"id": "OCCULTER_RADIUS", "label": "Occulter radius", "group": "Occulter",
			"min": 0.02, "max": 0.40, "step": 0.005,
			"default": SolarStormProfile.OCCULTER_RADIUS, "rebuild": false,
		},
		{
			"id": "LIMB_RADIUS", "label": "Limb radius", "group": "Occulter",
			"min": 0.01, "max": 0.35, "step": 0.002,
			"default": SolarStormProfile.LIMB_RADIUS, "rebuild": false,
		},
		{
			"id": "LIMB_GAIN", "label": "Limb gain", "group": "Occulter",
			"min": 0.0, "max": 2.0, "step": 0.05,
			"default": SolarStormProfile.LIMB_GAIN, "rebuild": false,
		},
		{
			"id": "WAVE_AMPLITUDE", "label": "Wave amount", "group": "Wave and pixels",
			"min": 0.0, "max": 0.08, "step": 0.001,
			"default": SolarStormProfile.WAVE_AMPLITUDE, "rebuild": false,
		},
		{
			"id": "WAVE_FREQUENCY", "label": "Wave frequency", "group": "Wave and pixels",
			"min": 0.0, "max": 16.0, "step": 0.1,
			"default": SolarStormProfile.WAVE_FREQUENCY, "rebuild": false,
		},
		{
			"id": "WAVE_SPEED", "label": "Wave speed", "group": "Wave and pixels",
			"min": 0.0, "max": 12.0, "step": 0.05,
			"default": SolarStormProfile.WAVE_SPEED, "rebuild": false,
		},
		{
			"id": "PIXEL_CELLS", "label": "Cells across", "group": "Wave and pixels",
			"min": 0.0, "max": 240.0, "step": 1.0,
			"default": SolarStormProfile.PIXEL_CELLS, "rebuild": false,
		},
		{
			"id": "MODEL_BOOST", "label": "Model lighting", "group": "Occlusion",
			"min": 0.0, "max": 8.0, "step": 0.05,
			"default": SolarStormProfile.MODEL_BOOST, "rebuild": false,
		},
		{
			"id": "OCCLUSION_GAIN", "label": "Model coverage", "group": "Occlusion",
			"min": 1.0, "max": 6.0, "step": 0.1,
			"default": SolarStormProfile.OCCLUSION_GAIN, "rebuild": false,
		},
	]


func _on_tunables_applied() -> void:
	if _stormMaterial == null:
		return
	_applyTunableUniforms()
	_applyPanelSize()
	_applyProgress(get_normalized_time())


## Duck-typed footprint hook, called by both `VFXDebugController` and
## `GodotVisualAdapter`. Resizing needs no rebuild: the panel is one quad, so the
## mesh size, cull margin, aspect uniform, and lift are all that change.
func setFootprint(radius: int, _ground_span: float, _area_shape: String = "circle") -> void:
	_footprintRadius = maxi(radius, SolarStormProfile.MIN_FOOTPRINT_RADIUS_TILES)
	_applyPanelSize()
	_applyPanelTransform()


func getFootprintRadius() -> int:
	return _footprintRadius


func _buildLayers() -> void:
	_stormMaterial = ShaderMaterial.new()
	_stormMaterial.shader = _STORM_SHADER

	# The mesh carries the panel's world dimensions so the shader's rebuilt
	# billboard basis can stay unit-length and preserve scale.
	_panelMesh = QuadMesh.new()

	_panelInstance = MeshInstance3D.new()
	_panelInstance.name = "StormPanel"
	_panelInstance.mesh = _panelMesh
	_panelInstance.material_override = _stormMaterial
	add_child(_panelInstance)

	_applyStaticUniforms()
	_applyTunableUniforms()
	_applyPanelSize()
	_applyPanelTransform()

	assert(
		get_live_draw_call_count() <= SolarStormProfile.MAX_DRAW_CALLS,
		"Solar Storm exceeded its authored draw-call ceiling."
	)
	assert(
		_countNodes(self) <= SolarStormProfile.MAX_EFFECT_NODES,
		"Solar Storm exceeded its authored node ceiling."
	)


func _applyStaticUniforms() -> void:
	_stormMaterial.set_shader_parameter("field_scale", SolarStormProfile.FIELD_SCALE)
	_stormMaterial.set_shader_parameter("edge_fade", SolarStormProfile.EDGE_FADE)
	_stormMaterial.set_shader_parameter(
		"occulter_edge", SolarStormProfile.OCCULTER_EDGE
	)
	_stormMaterial.set_shader_parameter("limb_width", SolarStormProfile.LIMB_WIDTH)
	_stormMaterial.set_shader_parameter("grain_hz", SolarStormProfile.GRAIN_HZ)
	_stormMaterial.set_shader_parameter(
		"occlusion_feather", SolarStormProfile.OCCLUSION_FEATHER
	)


## Tunables are read once here and pushed to uniforms, never sampled per frame.
func _applyTunableUniforms() -> void:
	var rows := {
		"exposure": ["EXPOSURE", SolarStormProfile.EXPOSURE],
		"black_lift": ["BLACK_LIFT", SolarStormProfile.BLACK_LIFT],
		"corona_gain": ["CORONA_GAIN", SolarStormProfile.CORONA_GAIN],
		"corona_falloff": ["CORONA_FALLOFF", SolarStormProfile.CORONA_FALLOFF],
		"fov_radius": ["FOV_RADIUS", SolarStormProfile.FOV_RADIUS],
		"fov_edge": ["FOV_EDGE", SolarStormProfile.FOV_EDGE],
		"streamer_threshold": [
			"STREAMER_THRESHOLD", SolarStormProfile.STREAMER_THRESHOLD
		],
		"streamer_sharpness": [
			"STREAMER_SHARPNESS", SolarStormProfile.STREAMER_SHARPNESS
		],
		"streamer_gain": ["STREAMER_GAIN", SolarStormProfile.STREAMER_GAIN],
		"streamer_reach": ["STREAMER_REACH", SolarStormProfile.STREAMER_REACH],
		"streamer_broad": ["STREAMER_BROAD", SolarStormProfile.STREAMER_BROAD],
		"streamer_warp": ["STREAMER_WARP", SolarStormProfile.STREAMER_WARP],
		"streamer_drift": ["STREAMER_DRIFT", SolarStormProfile.STREAMER_DRIFT],
		"arc_radius": ["ARC_RADIUS", SolarStormProfile.ARC_RADIUS],
		"arc_width": ["ARC_WIDTH", SolarStormProfile.ARC_WIDTH],
		"arc_gain": ["ARC_GAIN", SolarStormProfile.ARC_GAIN],
		"arc_span": ["ARC_SPAN", SolarStormProfile.ARC_SPAN],
		"arc_warp": ["ARC_WARP", SolarStormProfile.ARC_WARP],
		"occulter_radius": ["OCCULTER_RADIUS", SolarStormProfile.OCCULTER_RADIUS],
		"limb_radius": ["LIMB_RADIUS", SolarStormProfile.LIMB_RADIUS],
		"limb_gain": ["LIMB_GAIN", SolarStormProfile.LIMB_GAIN],
		"wave_amplitude": ["WAVE_AMPLITUDE", SolarStormProfile.WAVE_AMPLITUDE],
		"wave_frequency": ["WAVE_FREQUENCY", SolarStormProfile.WAVE_FREQUENCY],
		"wave_speed": ["WAVE_SPEED", SolarStormProfile.WAVE_SPEED],
		"pixel_cells": ["PIXEL_CELLS", SolarStormProfile.PIXEL_CELLS],
		"model_boost": ["MODEL_BOOST", SolarStormProfile.MODEL_BOOST],
		"occlusion_gain": ["OCCLUSION_GAIN", SolarStormProfile.OCCLUSION_GAIN],
	}
	for uniform: String in rows:
		var row: Array = rows[uniform]
		_stormMaterial.set_shader_parameter(
			uniform, tunable(str(row[0]), float(row[1]))
		)


## Scales the panel to the carrier's footprint, uniformly. Non-uniform scaling is
## tempting and wrong: the field is aspect-corrected, which makes its world width
## a product of the field radii and the panel's *height*, so holding height back
## while widening the quad grows the carrier without growing the storm on it.
func _applyPanelSize() -> void:
	var diameter := float(_footprintRadius * 2 + 1)
	var scale := diameter / float(SolarStormProfile.REFERENCE_DIAMETER_TILES)
	_panelSize = Vector2(
		SolarStormProfile.PANEL_WIDTH_U * scale,
		SolarStormProfile.PANEL_HEIGHT_U * scale
	)
	if _panelMesh != null:
		_panelMesh.size = _panelSize
	if _panelInstance != null:
		# The vertex stage rewrites MODELVIEW_MATRIX every frame, so Godot's own
		# frustum cull would test a box that no longer matches where the quad is.
		_panelInstance.extra_cull_margin = maxf(_panelSize.x, _panelSize.y)
	if _stormMaterial == null:
		return
	var height := maxf(_panelSize.y, 0.0001)
	_stormMaterial.set_shader_parameter("aspect_ratio", _panelSize.x / height)
	# The anchor stays a fixed UV fraction so the whole composition scales
	# together; see the profile for why this is the opposite of the sibling's
	# world-unit pin.
	_stormMaterial.set_shader_parameter(
		"storm_anchor", SolarStormProfile.STORM_ANCHOR
	)


## Lifts the panel so its base sits at the target's feet. The quad is centred on
## its own origin, so half its height is the offset.
func _applyPanelTransform() -> void:
	position = _groundWorldPosition + Vector3.UP * (_panelSize.y * 0.5)


func _applySeed(seed: int) -> void:
	if _stormMaterial == null:
		return
	_stormMaterial.set_shader_parameter("seed_value", float(seed))


func _process(delta: float) -> void:
	if _disposed or not _playing:
		return
	_elapsedTime += delta * _playbackScale
	var progress := get_normalized_time()
	if _elapsedTime >= VISIBLE_DURATION:
		_elapsedTime = VISIBLE_DURATION
		progress = 1.0
		_playing = false
		_finished = true
	_applyProgress(progress)
	if _finished and _autoDispose:
		dispose()


func _applyProgress(progress: float) -> void:
	if _stormMaterial == null:
		return
	_stormMaterial.set_shader_parameter("playback_time", progress * VISIBLE_DURATION)
	_stormMaterial.set_shader_parameter(
		"lifecycle_visibility",
		_sampleKeyedCurve(progress, SolarStormProfile.VISIBILITY_CURVE)
	)
	_stormMaterial.set_shader_parameter(
		"front_progress",
		_sampleKeyedCurve(progress, SolarStormProfile.FRONT_PROGRESS_CURVE)
	)
	_stormMaterial.set_shader_parameter(
		"grain_strength",
		tunable("GRAIN_STRENGTH", SolarStormProfile.GRAIN_STRENGTH)
			* _sampleKeyedCurve(progress, SolarStormProfile.GRAIN_CURVE)
	)


static func _sampleKeyedCurve(progress: float, values: Array) -> float:
	var keys: Array = SolarStormProfile.VISIBILITY_KEYS
	assert(
		values.size() == keys.size(),
		"Solar Storm curve length does not match its beat timeline."
	)
	var clamped := clampf(progress, 0.0, 1.0)
	for index in range(keys.size() - 1):
		var start := float(keys[index])
		var finish := float(keys[index + 1])
		if clamped <= finish:
			if finish <= start:
				return float(values[index])
			return lerpf(
				float(values[index]),
				float(values[index + 1]),
				inverse_lerp(start, finish, clamped)
			)
	return float(values[-1])


static func _countNodes(node: Node) -> int:
	var count := 1
	for child: Node in node.get_children():
		count += _countNodes(child)
	return count
