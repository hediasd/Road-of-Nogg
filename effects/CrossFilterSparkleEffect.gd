## Cross-filter sparkle aura: pink four-ray stars twinkling round a body's
## outline, on a held 12 fps clock.
##
## Structurally new, so authored fresh against the `VfxPlayback` contract (no
## donor). One layer, one draw call: a MultiMesh of camera-facing quads whose
## every property is computed in `cross_filter_sparkle.gdshader` from the slot
## index, the seed and the effect's own clock. The only time state here is
## `_elapsedTime`, and the shader receives it floored to the profile's frame
## rate, so seeks are exact and the held-drawing look survives scrubbing.
##
## Body-bound: it surrounds every cast-context target, or the effect's own
## position with the standard body box when there is none. The element colour
## the factory receives is ignored on purpose; the palette is the profile's.

class_name CrossFilterSparkleEffect
extends VfxPlayback

const Profile = preload("res://effects/CrossFilterSparkleProfile.gd")
const SparkleShader = preload("res://assets/shaders/cross_filter_sparkle.gdshader")

const LAYER_SPARKLES := "sparkles"
## Generous fixed bounds: the shader places every quad, so the CPU never knows
## where they are. Wide enough for a spread of targets across the board.
const _RENDER_AABB := AABB(Vector3(-40.0, -8.0, -40.0), Vector3(80.0, 24.0, 80.0))

var _context: VfxCastContext = null
var _instance: MultiMeshInstance3D
var _multimesh: MultiMesh
var _material: ShaderMaterial

var _groupCount := Profile.GROUP_COUNT
var _frameRate := Profile.FRAME_RATE
var _elapsedTime := 0.0
var _totalDuration := Profile.BATTLE_DURATION_SECONDS
var _playbackScale := 1.0
var _activeSeed := 0
var _playing := false
var _finished := true
var _disposed := false
var _layerVisible := true


## Catalog factory: `SpellVfxCatalog.create()` calls it with these four
## arguments.
static func create(
		parent: Node3D,
		worldPosition: Vector3,
		_elementColor: Color,
		overrides: Dictionary = {}) -> CrossFilterSparkleEffect:
	var playback := CrossFilterSparkleEffect.new()
	playback.name = "CrossFilterSparkles"
	parent.add_child(playback)
	playback.global_position = worldPosition
	playback.set_tunable_overrides(overrides)
	return playback


static func tunables() -> Array[Dictionary]:
	return [
		{"id": "FRAME_RATE", "label": "Frame rate (0 = smooth)", "group": "Timing",
			"min": 0.0, "max": 24.0, "step": 1.0, "default": Profile.FRAME_RATE, "rebuild": false},
		{"id": "GROUP_COUNT", "label": "Groups", "group": "Population",
			"min": 1.0, "max": float(Profile.MAX_INSTANCES / (Profile.CHAIN_SLOTS * Profile.LANE_COUNT)),
			"step": 1.0,
			"default": float(Profile.GROUP_COUNT), "rebuild": true},
		{"id": "IDLE_ACTIVE_CHANCE", "label": "Idle active chance", "group": "Population",
			"min": 0.0, "max": 1.0, "step": 0.05, "default": Profile.IDLE_ACTIVE_CHANCE, "rebuild": false},
		{"id": "CHAIN_CHANCE", "label": "Chain chance", "group": "Population",
			"min": 0.0, "max": 1.0, "step": 0.05, "default": Profile.CHAIN_CHANCE, "rebuild": false},
		{"id": "EDGE_SPREAD", "label": "Edge spread", "group": "Placement",
			"min": 0.0, "max": 0.5, "step": 0.01, "default": Profile.EDGE_SPREAD, "rebuild": false},
		{"id": "RAY_ANGLE_DEGREES", "label": "Ray angle", "group": "Star",
			"min": 0.0, "max": 90.0, "step": 1.0, "default": Profile.RAY_ANGLE_DEGREES, "rebuild": false},
		{"id": "RAY_LENGTH", "label": "Ray length", "group": "Star",
			"min": 0.04, "max": 0.6, "step": 0.01, "default": Profile.RAY_LENGTH, "rebuild": false},
	]


func configure_cast_context(context: VfxCastContext) -> void:
	_context = context
	if _material != null:
		_applyBodies()


func play(seed: int, mode: String) -> void:
	assert(not _disposed, "Cannot play a disposed cross-filter sparkle effect.")
	assert(mode == MODE_REFERENCE or mode == MODE_BATTLE, "Unknown VFX playback mode.")
	_activeSeed = seed
	_totalDuration = (Profile.REFERENCE_DURATION_SECONDS if mode == MODE_REFERENCE
			else Profile.BATTLE_DURATION_SECONDS)
	_build()
	_elapsedTime = 0.0
	_finished = false
	_playing = true
	_applyTime()
	set_process(true)


func set_playback_scale(scale: float) -> void:
	_playbackScale = maxf(scale, 0.0)


func seek_normalized(time: float) -> void:
	if _disposed:
		return
	if _material == null:
		_build()
	var progress := clampf(time, 0.0, 1.0)
	_elapsedTime = progress * _totalDuration
	_finished = progress >= 1.0
	if _finished:
		_playing = false
	_applyTime()


func skip_to_settle() -> void:
	seek_normalized(1.0)


func get_normalized_time() -> float:
	return clampf(_elapsedTime / maxf(_totalDuration, 0.001), 0.0, 1.0)


func get_elapsed_time() -> float:
	return _elapsedTime


func get_total_duration() -> float:
	return _totalDuration


func is_finished() -> bool:
	return _finished


func get_layer_names() -> Array[String]:
	return [LAYER_SPARKLES]


func set_layer_visible(layerName: String, visible: bool) -> void:
	if layerName != LAYER_SPARKLES:
		push_warning("Unknown cross-filter sparkle layer: %s" % layerName)
		return
	_layerVisible = visible
	if _material != null:
		_material.set_shader_parameter("layer_visible", visible)


func get_live_particle_count() -> int:
	return 0


## Slots submitted to the GPU. Which of them are lit at a given instant is
## decided in the shader; idle slots collapse to zero-area quads.
func get_live_instance_count() -> int:
	return _multimesh.instance_count if _multimesh != null and not _disposed else 0


func get_live_node_count() -> int:
	return 0 if _disposed else 1 + get_child_count()


func get_live_draw_call_count() -> int:
	return 1 if _instance != null and not _disposed else 0


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
		call_deferred("free")


func _on_tunables_applied() -> void:
	if _material != null:
		_applyUniforms()
		_applyTime()


func _process(delta: float) -> void:
	if _disposed or not _playing:
		return
	_elapsedTime += delta * _playbackScale
	if _elapsedTime >= _totalDuration:
		_elapsedTime = _totalDuration
		_playing = false
		_finished = true
	_applyTime()


func _build() -> void:
	if _instance != null:
		remove_child(_instance)
		_instance.queue_free()
		_instance = null
	_groupCount = tunable_int("GROUP_COUNT", Profile.GROUP_COUNT)
	var count := _groupCount * Profile.CHAIN_SLOTS * Profile.LANE_COUNT
	assert(count <= Profile.MAX_INSTANCES,
			"Cross-filter sparkles: %d instances exceeds MAX_INSTANCES %d." % [count, Profile.MAX_INSTANCES])
	assert(Profile.PERIOD_MAX_SECONDS >= Profile.PERIOD_MIN_SECONDS,
			"Cross-filter sparkles: PERIOD_MAX_SECONDS is below the derived minimum.")

	var quad := QuadMesh.new()
	quad.size = Vector2.ONE
	_multimesh = MultiMesh.new()
	_multimesh.transform_format = MultiMesh.TRANSFORM_3D
	_multimesh.mesh = quad
	_multimesh.instance_count = count
	for index in count:
		_multimesh.set_instance_transform(index, Transform3D.IDENTITY)

	_material = ShaderMaterial.new()
	_material.shader = SparkleShader
	_instance = MultiMeshInstance3D.new()
	_instance.name = "Sparkles"
	_instance.multimesh = _multimesh
	_instance.material_override = _material
	_instance.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_instance.custom_aabb = _RENDER_AABB
	add_child(_instance)
	# The quads are placed in world space by the shader; keep the node itself
	# at the origin so the custom AABB covers the board wherever the cast lands.
	_instance.top_level = true
	_instance.global_transform = Transform3D.IDENTITY

	assert(1 + get_child_count() <= Profile.MAX_EFFECT_NODES,
			"Cross-filter sparkles exceeded MAX_EFFECT_NODES.")
	_applyUniforms()
	_applyBodies()
	_material.set_shader_parameter("layer_visible", _layerVisible)


func _applyUniforms() -> void:
	_frameRate = tunable("FRAME_RATE", Profile.FRAME_RATE)
	var rayLength := tunable("RAY_LENGTH", Profile.RAY_LENGTH)
	var m := _material
	m.set_shader_parameter("seed", _activeSeed)
	m.set_shader_parameter("total_duration", _totalDuration)
	m.set_shader_parameter("settle_seconds", Profile.SETTLE_SECONDS)
	m.set_shader_parameter("group_count", _groupCount)
	m.set_shader_parameter("chain_slots", Profile.CHAIN_SLOTS)
	m.set_shader_parameter("lane_count", Profile.LANE_COUNT)
	m.set_shader_parameter("idle_active_chance", tunable("IDLE_ACTIVE_CHANCE", Profile.IDLE_ACTIVE_CHANCE))
	m.set_shader_parameter("chain_chance", tunable("CHAIN_CHANCE", Profile.CHAIN_CHANCE))
	m.set_shader_parameter("entrance_spread", Profile.ENTRANCE_SPREAD_SECONDS)
	m.set_shader_parameter("entrance_peak_gain", Profile.ENTRANCE_PEAK_GAIN)
	m.set_shader_parameter("entrance_decay", Profile.ENTRANCE_DECAY_SECONDS)
	m.set_shader_parameter("life_min", Profile.LIFE_MIN_SECONDS)
	m.set_shader_parameter("life_max", Profile.LIFE_MAX_SECONDS)
	m.set_shader_parameter("rise_min", Profile.RISE_MIN_SECONDS)
	m.set_shader_parameter("rise_max", Profile.RISE_MAX_SECONDS)
	m.set_shader_parameter("fall_exponent", Profile.FALL_EXPONENT)
	m.set_shader_parameter("birth_jitter", Profile.BIRTH_JITTER_SECONDS)
	m.set_shader_parameter("chain_step_min", Profile.CHAIN_STEP_MIN_SECONDS)
	m.set_shader_parameter("chain_step_max", Profile.CHAIN_STEP_MAX_SECONDS)
	m.set_shader_parameter("period_min", Profile.PERIOD_MIN_SECONDS)
	m.set_shader_parameter("period_max", Profile.PERIOD_MAX_SECONDS)
	m.set_shader_parameter("peak_min", Profile.PEAK_MIN)
	m.set_shader_parameter("peak_skew", Profile.PEAK_SKEW)
	m.set_shader_parameter("chain_peak_min", Profile.CHAIN_PEAK_MIN)
	m.set_shader_parameter("chain_peak_max", Profile.CHAIN_PEAK_MAX)
	m.set_shader_parameter("flicker_depth", Profile.FLICKER_DEPTH)
	m.set_shader_parameter("flicker_rate_min", Profile.FLICKER_RATE_MIN)
	m.set_shader_parameter("flicker_rate_max", Profile.FLICKER_RATE_MAX)
	m.set_shader_parameter("edge_scale", Profile.EDGE_SCALE)
	m.set_shader_parameter("edge_spread", tunable("EDGE_SPREAD", Profile.EDGE_SPREAD))
	m.set_shader_parameter("edge_outward_bias", Profile.EDGE_OUTWARD_BIAS)
	m.set_shader_parameter("drift_up_min", Profile.DRIFT_UP_MIN)
	m.set_shader_parameter("drift_up_max", Profile.DRIFT_UP_MAX)
	m.set_shader_parameter("drift_side", Profile.DRIFT_SIDE)
	m.set_shader_parameter("chain_gap_fraction", Profile.CHAIN_GAP_FRACTION)
	m.set_shader_parameter("ray_angle_degrees", tunable("RAY_ANGLE_DEGREES", Profile.RAY_ANGLE_DEGREES))
	m.set_shader_parameter("ray_length", rayLength)
	m.set_shader_parameter("ray_min_fraction", Profile.RAY_MIN_FRACTION)
	m.set_shader_parameter("ray_length_exponent", Profile.RAY_LENGTH_EXPONENT)
	m.set_shader_parameter("ray_gain", Profile.RAY_GAIN)
	m.set_shader_parameter("ray_exponent", Profile.RAY_EXPONENT)
	m.set_shader_parameter("ray_taper", Profile.RAY_TAPER)
	m.set_shader_parameter("ray_width", Profile.RAY_WIDTH)
	m.set_shader_parameter("ray_min_pixels", Profile.RAY_MIN_PIXELS)
	m.set_shader_parameter("ray_root_widen", Profile.RAY_ROOT_WIDEN)
	m.set_shader_parameter("core_base", Profile.CORE_BASE)
	m.set_shader_parameter("core_gain", Profile.CORE_GAIN)
	m.set_shader_parameter("core_sigma", Profile.CORE_SIGMA)
	m.set_shader_parameter("core_sigma_min", Profile.CORE_SIGMA_MIN)
	m.set_shader_parameter("core_sigma_gain", Profile.CORE_SIGMA_GAIN)
	m.set_shader_parameter("core_min_pixels", Profile.CORE_MIN_PIXELS)
	m.set_shader_parameter("halo_gain", Profile.HALO_GAIN)
	m.set_shader_parameter("halo_sigma_scale", Profile.HALO_SIGMA_SCALE)
	# The quad has to hold the longest arm and the halo's visible tail.
	m.set_shader_parameter("quad_half",
			maxf(rayLength, Profile.CORE_SIGMA * Profile.HALO_SIGMA_SCALE * 3.0) * 1.1)
	assert(Profile.RAMP_ENERGY.size() == 8 and Profile.RAMP_COLORS.size() == 8,
			"Cross-filter sparkle ramp must have exactly eight stops.")
	for k in 8:
		m.set_shader_parameter("ramp_e%d" % k, Profile.RAMP_ENERGY[k])
		m.set_shader_parameter("ramp_c%d" % k, Profile.RAMP_COLORS[k])


## One body per cast-context target, or the effect's own position with the
## standard body box when the context has none.
func _applyBodies() -> void:
	var centres := PackedVector3Array()
	var halves := PackedVector2Array()
	if _context != null:
		for index in _context.target_world_positions.size():
			if centres.size() >= Profile.MAX_BODIES:
				break
			var bounds: AABB = _context.target_body_bounds[index]
			centres.append(_context.target_world_positions[index] + bounds.get_center())
			halves.append(_halvesOf(bounds))
	if centres.is_empty():
		var bounds := VfxCastContext.DEFAULT_TARGET_BODY_BOUNDS
		centres.append(global_position + bounds.get_center())
		halves.append(_halvesOf(bounds))
	var count := centres.size()
	while centres.size() < Profile.MAX_BODIES:
		centres.append(Vector3.ZERO)
		halves.append(Vector2.ZERO)
	_material.set_shader_parameter("body_count", count)
	_material.set_shader_parameter("body_centers", centres)
	_material.set_shader_parameter("body_halves", halves)


static func _halvesOf(bounds: AABB) -> Vector2:
	return Vector2(maxf(bounds.size.x, bounds.size.z) * 0.5, bounds.size.y * 0.5)


func _applyTime() -> void:
	if _material == null:
		return
	var shown := _elapsedTime
	if _frameRate > 0.0:
		shown = floorf(_elapsedTime * _frameRate) / _frameRate
	_material.set_shader_parameter("playback_time", shown)
