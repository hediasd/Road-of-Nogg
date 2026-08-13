## Reference-locked generic spell-cast aura playback.
##
## This implementation boundary intentionally carries only the footprint
## aperture. The rejected core cards, ray ribbons, and particles are gone; the
## following plan item adds the authored world-space plume curtain.

class_name SpellCastAura
extends "res://src/presentation/effects/VfxPlayback.gd"

const _FOOTPRINT_SHADER = preload(
		"res://assets/shaders/effects/spell_cast_footprint_aperture.gdshader")
const _DEBUG_DARK_CENTER_FLAG := "--spell-aura-dark-center"

const VISIBLE_DURATION := SpellCastAuraProfile.DURATION_SECONDS
const SETTLE_NORMALIZED_TIME := SpellCastAuraProfile.SETTLE_NORMALIZED_TIME
const LAYER_FOOTPRINT := "footprint_aperture"

var _elementColor := Color.WHITE
var _footprintInstance: MeshInstance3D
var _footprintMaterial: ShaderMaterial
var _centerDarkeningEnabled := false
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
		element_color: Color) -> SpellCastAura:
	var playback := SpellCastAura.new()
	playback.name = "SpellCastAura"
	playback.position = world_pos
	playback._elementColor = element_color
	parent.add_child(playback)
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
	return [LAYER_FOOTPRINT]


func set_layer_visible(layer_name: String, visible: bool) -> void:
	if layer_name == LAYER_FOOTPRINT:
		if _footprintInstance != null:
			_footprintInstance.visible = visible
		return
	push_warning("Unknown SpellCastAura layer: %s" % layer_name)


## Debug A/B hook. Battle playback remains transparent until the supplied
## black-background reference is disambiguated on real light and dark terrain.
func set_center_darkening(enabled: bool) -> void:
	_centerDarkeningEnabled = enabled
	if _footprintMaterial != null:
		_footprintMaterial.set_shader_parameter(
			"center_darkening",
			SpellCastAuraProfile.CENTER_DARKENING_ALPHA if enabled else 0.0
		)


func is_center_darkening_enabled() -> bool:
	return _centerDarkeningEnabled


func get_live_particle_count() -> int:
	return 0


func get_live_instance_count() -> int:
	if _finished or _footprintInstance == null or not _footprintInstance.visible:
		return 0
	return 1


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


func _buildLayers() -> void:
	_centerDarkeningEnabled = OS.get_cmdline_user_args().has(_DEBUG_DARK_CENTER_FLAG)
	_footprintInstance = _createFootprintAperture(_elementColor, _centerDarkeningEnabled)
	add_child(_footprintInstance)
	_footprintMaterial = _footprintInstance.material_override as ShaderMaterial
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
	if _footprintMaterial != null:
		_footprintMaterial.set_shader_parameter("burst_progress", progress)


func _applySeed(seed: int) -> void:
	if _footprintMaterial != null:
		_footprintMaterial.set_shader_parameter("seed_value", float(seed))


static func _createFootprintAperture(
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
	material.set_shader_parameter("burst_progress", 0.0)
	material.set_shader_parameter("seed_value", 0.0)
	material.set_shader_parameter("outer_radius", SpellCastAuraProfile.FOOTPRINT_OUTER_RADIUS_U)
	material.set_shader_parameter(
		"aperture_radius_start", SpellCastAuraProfile.APERTURE_RADIUS_START
	)
	material.set_shader_parameter(
		"aperture_radius_trough", SpellCastAuraProfile.APERTURE_RADIUS_TROUGH
	)
	material.set_shader_parameter("aperture_radius_end", SpellCastAuraProfile.APERTURE_RADIUS_END)
	material.set_shader_parameter("rim_width", SpellCastAuraProfile.APERTURE_RIM_WIDTH)
	material.set_shader_parameter("rim_alpha", SpellCastAuraProfile.APERTURE_RIM_ALPHA)
	material.set_shader_parameter(
		"striation_alpha", SpellCastAuraProfile.APERTURE_STRIATION_ALPHA
	)
	material.set_shader_parameter(
		"rim_emission_energy", SpellCastAuraProfile.APERTURE_RIM_EMISSION_ENERGY
	)
	material.set_shader_parameter(
		"center_darkening",
		SpellCastAuraProfile.CENTER_DARKENING_ALPHA if darkenCenter else 0.0
	)
	material.set_shader_parameter("charge_end", SpellCastAuraProfile.CHARGE_END)
	material.set_shader_parameter("decay_end", SpellCastAuraProfile.DECAY_END)

	var instance := MeshInstance3D.new()
	instance.name = "FootprintAperture"
	instance.mesh = plane
	instance.position.y = SpellCastAuraProfile.FOOTPRINT_HEIGHT_U
	instance.material_override = material
	instance.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	return instance


static func _countNodes(node: Node) -> int:
	var count := 1
	for child: Node in node.get_children():
		count += _countNodes(child)
	return count
