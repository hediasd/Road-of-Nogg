## Iridescent veil panel playback for the Aurora Veil spell.
##
## Authored fresh rather than forked. `docs/VFX_DESIGN.md` §4 asks whether an
## existing effect is a structural *sibling*; none is. The storms are ground
## wash plus particle field plus crown on one continuous arc, the implosion runs
## a four-beat inward timeline, and the encasement wraps a body in solid
## geometry. This is a single continuous field on one quad, run over four beats
## whose third holds. What it keeps is the `VfxPlayback` contract: seeded,
## exactly seekable, budget-asserted.
##
## The carrier is one Y-axis billboarded quad standing at the impact centre, so
## the panel keeps world up and yaws to face the camera. A full billboard would
## tilt the curtain with the camera pitch and its filaments would stop hanging.
##
## The quad's base sits at the target's feet and the whole panel rises from
## there. It scales uniformly with the carrier's footprint through `setFootprint`,
## while the curtain's anchor and core stay pinned in *world* units -- so a wider
## radius spreads the curtain across the board instead of lifting it off the units.
##
## Depth testing is disabled and occlusion is resolved in the fragment instead:
## where a model stands in front of the panel the curtain goes transparent and
## lights it rather than covering it. That costs the reference's
## silhouette-in-front composition and buys the curtain passing over the board as
## light. `MIRROR_STRENGTH` retires the reference's reflection by default; see
## the profile for why a body standing on ground cannot host one.

class_name AuroraVeilEffect
extends "res://src/presentation/effects/VfxPlayback.gd"

const _VEIL_SHADER = preload("res://assets/shaders/effects/aurora_veil_field.gdshader")

const VISIBLE_DURATION := AuroraVeilProfile.DURATION_SECONDS
const SETTLE_NORMALIZED_TIME := AuroraVeilProfile.SETTLE_NORMALIZED_TIME
const LAYER_VEIL := "veil_field"

var _elementColor := Color.WHITE
var _panelInstance: MeshInstance3D
var _panelMesh: QuadMesh
var _veilMaterial: ShaderMaterial
var _groundWorldPosition := Vector3.ZERO
var _footprintRadius := AuroraVeilProfile.CARRIER_RADIUS_TILES
var _panelSize := Vector2(
	AuroraVeilProfile.PANEL_WIDTH_U, AuroraVeilProfile.PANEL_HEIGHT_U
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
		overrides: Dictionary = {}) -> AuroraVeilEffect:
	var playback := AuroraVeilEffect.new()
	playback.name = "AuroraVeilEffect"
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


## The panel anchors on the impact position rather than on individual targets.
## A radius-2 area can hold several bodies, and overlapping additive panels
## would compound their grade instead of reading as several auras.
func configure_cast_context(context: VfxCastContext) -> void:
	if context == null:
		return
	_groundWorldPosition = context.impact_world_position
	_applyPanelTransform()


func play(seed: int, mode: String) -> void:
	assert(not _disposed, "Cannot play a disposed AuroraVeilEffect.")
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
	return [LAYER_VEIL]


func set_layer_visible(layer_name: String, visible: bool) -> void:
	match layer_name:
		LAYER_VEIL:
			if _panelInstance != null:
				_panelInstance.visible = visible
		_:
			push_warning("Unknown AuroraVeilEffect layer: %s" % layer_name)


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
			"id": "INTENSITY", "label": "Intensity", "group": "Grade",
			"min": 0.0, "max": 3.0, "step": 0.01,
			"default": AuroraVeilProfile.INTENSITY, "rebuild": false,
		},
		{
			"id": "GRAIN_STRENGTH", "label": "Grain", "group": "Grade",
			"min": 0.0, "max": 0.30, "step": 0.005,
			"default": AuroraVeilProfile.GRAIN_STRENGTH, "rebuild": false,
		},
		{
			"id": "BLACK_LIFT", "label": "Black lift", "group": "Grade",
			"min": 0.0, "max": 0.15, "step": 0.002,
			"default": AuroraVeilProfile.BLACK_LIFT, "rebuild": false,
		},
		{
			"id": "BAND_SCALE", "label": "Band scale", "group": "Bands",
			"min": 0.2, "max": 3.0, "step": 0.01,
			"default": AuroraVeilProfile.BAND_SCALE, "rebuild": false,
		},
		{
			"id": "BAND_WARP_AMPLITUDE", "label": "Band warp", "group": "Bands",
			"min": 0.0, "max": 0.40, "step": 0.005,
			"default": AuroraVeilProfile.BAND_WARP_AMPLITUDE, "rebuild": false,
		},
		{
			"id": "WARP_AMPLITUDE", "label": "Shape warp", "group": "Bands",
			"min": 0.0, "max": 0.20, "step": 0.002,
			"default": AuroraVeilProfile.WARP_AMPLITUDE, "rebuild": false,
		},
		{
			"id": "FALLOFF_KNEE", "label": "Falloff knee", "group": "Envelope",
			"min": 0.0, "max": 1.5, "step": 0.01,
			"default": AuroraVeilProfile.FALLOFF_KNEE, "rebuild": false,
		},
		{
			"id": "FALLOFF_SOFT", "label": "Falloff edge", "group": "Envelope",
			"min": 0.2, "max": 3.0, "step": 0.01,
			"default": AuroraVeilProfile.FALLOFF_SOFT, "rebuild": false,
		},
		{
			"id": "SEAM_FLOOR", "label": "Seam floor", "group": "Reflection",
			"min": 0.0, "max": 1.0, "step": 0.01,
			"default": AuroraVeilProfile.SEAM_FLOOR, "rebuild": false,
		},
		{
			"id": "SEAM_WIDTH", "label": "Seam width", "group": "Reflection",
			"min": 0.005, "max": 0.30, "step": 0.005,
			"default": AuroraVeilProfile.SEAM_WIDTH, "rebuild": false,
		},
		{
			"id": "LOWER_COMPRESS", "label": "Reflection squash", "group": "Reflection",
			"min": 1.0, "max": 8.0, "step": 0.05,
			"default": AuroraVeilProfile.LOWER_COMPRESS, "rebuild": false,
		},
		{
			"id": "RIPPLE_DEPTH", "label": "Ripple depth", "group": "Reflection",
			"min": 0.0, "max": 0.40, "step": 0.005,
			"default": AuroraVeilProfile.RIPPLE_DEPTH, "rebuild": false,
		},
		{
			"id": "WAVE_AMPLITUDE", "label": "Wave amount", "group": "Wave and pixels",
			"min": 0.0, "max": 0.12, "step": 0.002,
			"default": AuroraVeilProfile.WAVE_AMPLITUDE, "rebuild": false,
		},
		{
			"id": "WAVE_FREQUENCY", "label": "Wave frequency", "group": "Wave and pixels",
			"min": 0.0, "max": 16.0, "step": 0.1,
			"default": AuroraVeilProfile.WAVE_FREQUENCY, "rebuild": false,
		},
		{
			"id": "WAVE_SPEED", "label": "Wave speed", "group": "Wave and pixels",
			"min": 0.0, "max": 12.0, "step": 0.05,
			"default": AuroraVeilProfile.WAVE_SPEED, "rebuild": false,
		},
		{
			"id": "PIXEL_CELLS", "label": "Cells across", "group": "Wave and pixels",
			"min": 0.0, "max": 240.0, "step": 1.0,
			"default": AuroraVeilProfile.PIXEL_CELLS, "rebuild": false,
		},
		{
			"id": "MIRROR_STRENGTH", "label": "Reflection", "group": "Reflection",
			"min": 0.0, "max": 1.0, "step": 0.05,
			"default": AuroraVeilProfile.MIRROR_STRENGTH, "rebuild": false,
		},
		{
			"id": "CURTAIN_STRENGTH", "label": "Curtain depth", "group": "Curtain",
			"min": 0.0, "max": 1.0, "step": 0.05,
			"default": AuroraVeilProfile.CURTAIN_STRENGTH, "rebuild": false,
		},
		{
			"id": "CURTAIN_DETAIL", "label": "Filament count", "group": "Curtain",
			"min": 1.0, "max": 32.0, "step": 0.5,
			"default": AuroraVeilProfile.CURTAIN_DETAIL, "rebuild": false,
		},
		{
			"id": "CURTAIN_FOLD_FREQUENCY", "label": "Fold frequency", "group": "Curtain",
			"min": 0.0, "max": 6.0, "step": 0.1,
			"default": AuroraVeilProfile.CURTAIN_FOLD_FREQUENCY, "rebuild": false,
		},
		{
			"id": "MODEL_BOOST", "label": "Model lighting", "group": "Curtain",
			"min": 0.0, "max": 8.0, "step": 0.05,
			"default": AuroraVeilProfile.MODEL_BOOST, "rebuild": false,
		},
		{
			"id": "OCCLUSION_GAIN", "label": "Model coverage", "group": "Curtain",
			"min": 1.0, "max": 6.0, "step": 0.1,
			"default": AuroraVeilProfile.OCCLUSION_GAIN, "rebuild": false,
		},
	]


func _on_tunables_applied() -> void:
	if _veilMaterial == null:
		return
	_applyTunableUniforms()
	_applyProgress(get_normalized_time())


func _buildLayers() -> void:
	_veilMaterial = ShaderMaterial.new()
	_veilMaterial.shader = _VEIL_SHADER

	# The mesh carries the panel's world dimensions so the shader's rebuilt
	# billboard basis can stay unit-length and preserve scale.
	_panelMesh = QuadMesh.new()

	_panelInstance = MeshInstance3D.new()
	_panelInstance.name = "VeilPanel"
	_panelInstance.mesh = _panelMesh
	_panelInstance.material_override = _veilMaterial
	add_child(_panelInstance)

	_applyStaticUniforms()
	_applyTunableUniforms()
	_applyPanelSize()
	_applyPanelTransform()

	assert(
		get_live_draw_call_count() <= AuroraVeilProfile.MAX_DRAW_CALLS,
		"Aurora Veil exceeded its authored draw-call ceiling."
	)
	assert(
		_countNodes(self) <= AuroraVeilProfile.MAX_EFFECT_NODES,
		"Aurora Veil exceeded its authored node ceiling."
	)


func _applyStaticUniforms() -> void:
	# `veil_anchor`, `aspect_ratio`, and `core_offset` are published by
	# `_applyPanelSize()` instead: all three are functions of the live panel size.
	_veilMaterial.set_shader_parameter(
		"occlusion_feather", AuroraVeilProfile.OCCLUSION_FEATHER
	)
	_veilMaterial.set_shader_parameter("field_scale", AuroraVeilProfile.FIELD_SCALE)
	_veilMaterial.set_shader_parameter("edge_fade", AuroraVeilProfile.EDGE_FADE)
	_veilMaterial.set_shader_parameter(
		"curtain_fold_depth", AuroraVeilProfile.CURTAIN_FOLD_DEPTH
	)
	_veilMaterial.set_shader_parameter(
		"curtain_fold_shear", AuroraVeilProfile.CURTAIN_FOLD_SHEAR
	)
	_veilMaterial.set_shader_parameter(
		"curtain_drift_speed", AuroraVeilProfile.CURTAIN_DRIFT_SPEED
	)
	_veilMaterial.set_shader_parameter("band_radius", AuroraVeilProfile.BAND_RADIUS)
	_veilMaterial.set_shader_parameter(
		"envelope_radius", AuroraVeilProfile.ENVELOPE_RADIUS
	)
	_veilMaterial.set_shader_parameter("band_offset", AuroraVeilProfile.BAND_OFFSET)
	_veilMaterial.set_shader_parameter("lower_blend", AuroraVeilProfile.LOWER_BLEND)
	_veilMaterial.set_shader_parameter("lower_dim", AuroraVeilProfile.LOWER_DIM)
	_veilMaterial.set_shader_parameter("lower_smear", AuroraVeilProfile.LOWER_SMEAR)
	_veilMaterial.set_shader_parameter(
		"ripple_frequency", AuroraVeilProfile.RIPPLE_FREQUENCY
	)
	_veilMaterial.set_shader_parameter("grain_hz", AuroraVeilProfile.GRAIN_HZ)


## Tunables are read once here and pushed to uniforms, never sampled per frame.
func _applyTunableUniforms() -> void:
	_veilMaterial.set_shader_parameter(
		"intensity", tunable("INTENSITY", AuroraVeilProfile.INTENSITY)
	)
	_veilMaterial.set_shader_parameter(
		"grain_strength", tunable("GRAIN_STRENGTH", AuroraVeilProfile.GRAIN_STRENGTH)
	)
	_veilMaterial.set_shader_parameter(
		"black_lift", tunable("BLACK_LIFT", AuroraVeilProfile.BLACK_LIFT)
	)
	_veilMaterial.set_shader_parameter(
		"band_scale", tunable("BAND_SCALE", AuroraVeilProfile.BAND_SCALE)
	)
	_veilMaterial.set_shader_parameter(
		"band_warp_amplitude",
		tunable("BAND_WARP_AMPLITUDE", AuroraVeilProfile.BAND_WARP_AMPLITUDE)
	)
	_veilMaterial.set_shader_parameter(
		"warp_amplitude", tunable("WARP_AMPLITUDE", AuroraVeilProfile.WARP_AMPLITUDE)
	)
	_veilMaterial.set_shader_parameter(
		"falloff_knee", tunable("FALLOFF_KNEE", AuroraVeilProfile.FALLOFF_KNEE)
	)
	_veilMaterial.set_shader_parameter(
		"falloff_soft", tunable("FALLOFF_SOFT", AuroraVeilProfile.FALLOFF_SOFT)
	)
	_veilMaterial.set_shader_parameter(
		"seam_floor", tunable("SEAM_FLOOR", AuroraVeilProfile.SEAM_FLOOR)
	)
	_veilMaterial.set_shader_parameter(
		"seam_width", tunable("SEAM_WIDTH", AuroraVeilProfile.SEAM_WIDTH)
	)
	_veilMaterial.set_shader_parameter(
		"lower_compress", tunable("LOWER_COMPRESS", AuroraVeilProfile.LOWER_COMPRESS)
	)
	_veilMaterial.set_shader_parameter(
		"ripple_depth", tunable("RIPPLE_DEPTH", AuroraVeilProfile.RIPPLE_DEPTH)
	)
	_veilMaterial.set_shader_parameter(
		"wave_amplitude", tunable("WAVE_AMPLITUDE", AuroraVeilProfile.WAVE_AMPLITUDE)
	)
	_veilMaterial.set_shader_parameter(
		"pixel_cells", tunable("PIXEL_CELLS", AuroraVeilProfile.PIXEL_CELLS)
	)
	_veilMaterial.set_shader_parameter(
		"wave_frequency", tunable("WAVE_FREQUENCY", AuroraVeilProfile.WAVE_FREQUENCY)
	)
	_veilMaterial.set_shader_parameter(
		"wave_speed", tunable("WAVE_SPEED", AuroraVeilProfile.WAVE_SPEED)
	)
	_veilMaterial.set_shader_parameter(
		"mirror_strength", tunable("MIRROR_STRENGTH", AuroraVeilProfile.MIRROR_STRENGTH)
	)
	_veilMaterial.set_shader_parameter(
		"curtain_strength",
		tunable("CURTAIN_STRENGTH", AuroraVeilProfile.CURTAIN_STRENGTH)
	)
	_veilMaterial.set_shader_parameter(
		"curtain_detail", tunable("CURTAIN_DETAIL", AuroraVeilProfile.CURTAIN_DETAIL)
	)
	_veilMaterial.set_shader_parameter(
		"curtain_fold_frequency",
		tunable("CURTAIN_FOLD_FREQUENCY", AuroraVeilProfile.CURTAIN_FOLD_FREQUENCY)
	)
	_veilMaterial.set_shader_parameter(
		"model_boost", tunable("MODEL_BOOST", AuroraVeilProfile.MODEL_BOOST)
	)
	_veilMaterial.set_shader_parameter(
		"occlusion_gain", tunable("OCCLUSION_GAIN", AuroraVeilProfile.OCCLUSION_GAIN)
	)


func _applySeed(seed: int) -> void:
	if _veilMaterial == null:
		return
	_veilMaterial.set_shader_parameter("seed_value", float(seed))


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
	if _veilMaterial == null:
		return
	_veilMaterial.set_shader_parameter("playback_time", progress * VISIBLE_DURATION)
	_veilMaterial.set_shader_parameter(
		"lifecycle_visibility",
		_sampleKeyedCurve(progress, AuroraVeilProfile.VISIBILITY_CURVE)
	)
	_veilMaterial.set_shader_parameter(
		"grain_strength",
		tunable("GRAIN_STRENGTH", AuroraVeilProfile.GRAIN_STRENGTH)
			* _sampleKeyedCurve(progress, AuroraVeilProfile.GRAIN_CURVE)
	)
	_veilMaterial.set_shader_parameter(
		"band_drift", progress * AuroraVeilProfile.BAND_DRIFT_TURNS
	)


## Duck-typed footprint hook, called by both `VFXDebugController` and
## `GodotVisualAdapter`. Resizing needs no rebuild: the panel is one quad, so the
## mesh size, cull margin, aspect uniform, and lift are all that change.
func setFootprint(radius: int, _ground_span: float, _area_shape: String = "circle") -> void:
	_footprintRadius = maxi(radius, AuroraVeilProfile.MIN_FOOTPRINT_RADIUS_TILES)
	_applyPanelSize()
	_applyPanelTransform()


func getFootprintRadius() -> int:
	return _footprintRadius


## Scales the panel to the carrier's footprint. Width tracks the span linearly;
## height grows on a fractional power of the same scale, so a large area spreads
## the curtain sideways instead of raising a tower over the board.
func _applyPanelSize() -> void:
	var diameter := float(_footprintRadius * 2 + 1)
	var scale := diameter / float(AuroraVeilProfile.REFERENCE_DIAMETER_TILES)
	_panelSize = Vector2(
		AuroraVeilProfile.PANEL_WIDTH_U * scale,
		AuroraVeilProfile.PANEL_HEIGHT_U * scale
	)
	if _panelMesh != null:
		_panelMesh.size = _panelSize
	if _panelInstance != null:
		# The vertex stage rewrites MODELVIEW_MATRIX every frame, so Godot's own
		# frustum cull would test a box that no longer matches where the quad is.
		_panelInstance.extra_cull_margin = maxf(_panelSize.x, _panelSize.y)
	if _veilMaterial == null:
		return
	# The field is aspect-corrected, so a resized panel republishes both its
	# proportions and the two world-pinned heights converted into panel UV.
	var height := maxf(_panelSize.y, 0.0001)
	_veilMaterial.set_shader_parameter("aspect_ratio", _panelSize.x / height)
	_veilMaterial.set_shader_parameter(
		"veil_anchor",
		Vector2(0.5, 1.0 - AuroraVeilProfile.ANCHOR_HEIGHT_U / height)
	)
	_veilMaterial.set_shader_parameter(
		"core_offset", AuroraVeilProfile.CORE_HEIGHT_U / height
	)


## Lifts the panel so its base sits at the target's feet. The quad is centred on
## its own origin, so half its height is the offset. No per-frame work is needed
## beyond this -- the billboard yaw lives in the vertex stage.
func _applyPanelTransform() -> void:
	position = _groundWorldPosition + Vector3.UP * (_panelSize.y * 0.5)


static func _sampleKeyedCurve(progress: float, values: Array) -> float:
	var keys: Array = AuroraVeilProfile.VISIBILITY_KEYS
	assert(
		values.size() == keys.size(),
		"Aurora Veil curve length does not match its beat timeline."
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
