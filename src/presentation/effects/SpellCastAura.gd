## Reference-locked generic spell-cast aura playback.
##
## The rejected core cards, ray ribbons, and particles are gone. One restrained
## footprint and two continuous world-space crown shells surround the caster.

class_name SpellCastAura
extends "res://src/presentation/effects/VfxPlayback.gd"

const _FOOTPRINT_SHADER = preload(
		"res://assets/shaders/effects/spell_cast_footprint_aperture.gdshader")
const _PLUME_SHADER = preload(
		"res://assets/shaders/effects/spell_cast_plume_curtain.gdshader")
const _PLUME_ATLAS = preload(
		"res://assets/vfx/spell_cast_aura/plume_flow_atlas.png")
const _DEBUG_TRANSPARENT_CENTER_FLAG := "--spell-aura-transparent-center"
const _DEBUG_CROSSFADE_PLUME_FLAG := "--spell-aura-crossfade-plume"

const VISIBLE_DURATION := SpellCastAuraProfile.DURATION_SECONDS
const SETTLE_NORMALIZED_TIME := SpellCastAuraProfile.SETTLE_NORMALIZED_TIME
const LAYER_FOOTPRINT := "footprint_aperture"
const LAYER_PLUME_INNER := "plume_inner"
const LAYER_PLUME_OUTER := "plume_outer"

var _elementColor := Color.WHITE
var _footprintInstance: MeshInstance3D
var _footprintMaterial: ShaderMaterial
var _innerPlumeInstance: MeshInstance3D
var _innerPlumeMaterial: ShaderMaterial
var _outerPlumeInstance: MeshInstance3D
var _outerPlumeMaterial: ShaderMaterial
var _centerDarkeningEnabled := true
var _plumeStateCrossfade := SpellCastAuraProfile.PLUME_STATE_CROSSFADE
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
	return [LAYER_FOOTPRINT, LAYER_PLUME_INNER, LAYER_PLUME_OUTER]


func set_layer_visible(layer_name: String, visible: bool) -> void:
	match layer_name:
		LAYER_FOOTPRINT:
			if _footprintInstance != null:
				_footprintInstance.visible = visible
		LAYER_PLUME_INNER:
			if _innerPlumeInstance != null:
				_innerPlumeInstance.visible = visible
		LAYER_PLUME_OUTER:
			if _outerPlumeInstance != null:
				_outerPlumeInstance.visible = visible
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
	_plumeStateCrossfade = clampf(amount, 0.0, 1.0)
	for material: ShaderMaterial in [_innerPlumeMaterial, _outerPlumeMaterial]:
		if material != null:
			material.set_shader_parameter("state_crossfade", _plumeStateCrossfade)


func get_plume_state_crossfade() -> float:
	return _plumeStateCrossfade


func get_live_particle_count() -> int:
	return 0


func get_live_instance_count() -> int:
	if _finished:
		return 0
	var count := 0
	for instance: MeshInstance3D in [
		_footprintInstance, _innerPlumeInstance, _outerPlumeInstance
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


func _buildLayers() -> void:
	_centerDarkeningEnabled = not OS.get_cmdline_user_args().has(
		_DEBUG_TRANSPARENT_CENTER_FLAG
	)
	_plumeStateCrossfade = (
		1.0 if OS.get_cmdline_user_args().has(_DEBUG_CROSSFADE_PLUME_FLAG)
		else SpellCastAuraProfile.PLUME_STATE_CROSSFADE
	)
	_footprintInstance = _createFootprintAperture(_elementColor, _centerDarkeningEnabled)
	add_child(_footprintInstance)
	_footprintMaterial = _footprintInstance.material_override as ShaderMaterial
	_innerPlumeInstance = _createPlumeShell(
		"InnerPlumeCurtain",
		_elementColor,
		SpellCastAuraProfile.PLUME_INNER_BOTTOM_RADIUS_U,
		SpellCastAuraProfile.PLUME_INNER_TOP_RADIUS_U,
		SpellCastAuraProfile.PLUME_INNER_HEIGHT_U,
		SpellCastAuraProfile.PLUME_INNER_UV_PHASE,
		SpellCastAuraProfile.PLUME_INNER_OPACITY,
		SpellCastAuraProfile.PLUME_INNER_EMISSION_ENERGY,
		SpellCastAuraProfile.PLUME_INNER_RENDER_PRIORITY,
		_plumeStateCrossfade
	)
	add_child(_innerPlumeInstance)
	_innerPlumeMaterial = _innerPlumeInstance.material_override as ShaderMaterial
	_outerPlumeInstance = _createPlumeShell(
		"OuterPlumeCurtain",
		_elementColor,
		SpellCastAuraProfile.PLUME_OUTER_BOTTOM_RADIUS_U,
		SpellCastAuraProfile.PLUME_OUTER_TOP_RADIUS_U,
		SpellCastAuraProfile.PLUME_OUTER_HEIGHT_U,
		SpellCastAuraProfile.PLUME_OUTER_UV_PHASE,
		SpellCastAuraProfile.PLUME_OUTER_OPACITY,
		SpellCastAuraProfile.PLUME_OUTER_EMISSION_ENERGY,
		SpellCastAuraProfile.PLUME_OUTER_RENDER_PRIORITY,
		_plumeStateCrossfade
	)
	add_child(_outerPlumeInstance)
	_outerPlumeMaterial = _outerPlumeInstance.material_override as ShaderMaterial
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
	var visibility := _sourceVisibility(progress)
	if _footprintMaterial != null:
		_footprintMaterial.set_shader_parameter("source_state_position", statePosition)
		_footprintMaterial.set_shader_parameter(
			"aperture_radius",
			_sampleSourceCurve(progress, SpellCastAuraProfile.APERTURE_RADIUS_CURVE)
		)
		_footprintMaterial.set_shader_parameter(
			"rim_width",
			_sampleSourceCurve(progress, SpellCastAuraProfile.APERTURE_RIM_WIDTH_CURVE)
		)
		_footprintMaterial.set_shader_parameter(
			"striation_visibility",
			_sampleSourceCurve(progress, SpellCastAuraProfile.APERTURE_STRIATION_CURVE)
		)
		_footprintMaterial.set_shader_parameter("effect_visibility", visibility)
	var plumeEnergy := _sampleSourceCurve(
		progress, SpellCastAuraProfile.PLUME_ENERGY_CURVE
	)
	for material: ShaderMaterial in [_innerPlumeMaterial, _outerPlumeMaterial]:
		if material != null:
			material.set_shader_parameter("atlas_state_position", statePosition)
			material.set_shader_parameter("plume_energy", plumeEnergy)
			material.set_shader_parameter("effect_visibility", visibility)


func _applySeed(seed: int) -> void:
	for material: ShaderMaterial in [
		_footprintMaterial, _innerPlumeMaterial, _outerPlumeMaterial
	]:
		if material != null:
			material.set_shader_parameter("seed_value", float(seed))


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
	material.set_shader_parameter("seed_value", 0.0)
	material.set_shader_parameter(
		"outer_radius", SpellCastAuraProfile.FOOTPRINT_OUTER_RADIUS_U)
	material.set_shader_parameter("aperture_radius", SpellCastAuraProfile.APERTURE_RADIUS_START)
	material.set_shader_parameter("rim_width", SpellCastAuraProfile.APERTURE_RIM_WIDTH)
	material.set_shader_parameter("rim_alpha", SpellCastAuraProfile.APERTURE_RIM_ALPHA)
	material.set_shader_parameter(
		"striation_alpha", SpellCastAuraProfile.APERTURE_STRIATION_ALPHA)
	material.set_shader_parameter("striation_visibility", 1.0)
	material.set_shader_parameter(
		"rim_emission_energy", SpellCastAuraProfile.APERTURE_RIM_EMISSION_ENERGY)
	material.set_shader_parameter(
		"center_darkening",
		SpellCastAuraProfile.CENTER_DARKENING_ALPHA if darkenCenter else 0.0
	)
	material.set_shader_parameter("source_state_position", 0.0)
	material.set_shader_parameter("effect_visibility", 0.0)

	var instance := MeshInstance3D.new()
	instance.name = "FootprintAperture"
	instance.mesh = plane
	instance.position.y = SpellCastAuraProfile.FOOTPRINT_HEIGHT_U
	instance.material_override = material
	instance.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	return instance


static func _createPlumeShell(
		instanceName: String,
		color: Color,
		bottomRadius: float,
		topRadius: float,
		height: float,
		uvPhase: float,
		opacity: float,
		emissionEnergy: float,
		renderPriority: int,
		stateCrossfade: float) -> MeshInstance3D:
	var material := ShaderMaterial.new()
	material.shader = _PLUME_SHADER
	material.render_priority = renderPriority
	material.set_shader_parameter("plume_atlas", _PLUME_ATLAS)
	material.set_shader_parameter(
		"atlas_pixel_size", SpellCastAuraProfile.PLUME_ATLAS_PIXEL_SIZE
	)
	material.set_shader_parameter("aura_color", color)
	material.set_shader_parameter("seed_value", 0.0)
	material.set_shader_parameter("uv_phase", uvPhase)
	material.set_shader_parameter("shell_opacity", opacity)
	material.set_shader_parameter("emission_energy", emissionEnergy)
	material.set_shader_parameter("state_crossfade", stateCrossfade)
	material.set_shader_parameter("atlas_state_position", 0.0)
	material.set_shader_parameter("plume_energy", SpellCastAuraProfile.PLUME_ENERGY_CURVE[0])
	material.set_shader_parameter("effect_visibility", 0.0)

	var instance := MeshInstance3D.new()
	instance.name = instanceName
	instance.mesh = _createFlaredShellMesh(bottomRadius, topRadius, height)
	instance.position.y = SpellCastAuraProfile.PLUME_BASE_HEIGHT_U
	instance.material_override = material
	instance.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	instance.custom_aabb = AABB(
		Vector3(-topRadius, -0.02, -topRadius),
		Vector3(topRadius * 2.0, height + 0.04, topRadius * 2.0)
	)
	return instance


## Outward-facing triangle winding is intentional. The plume shader uses face
## orientation to keep the outer shell behind the caster and restrict the
## inner shell's camera-side contribution to a soft body-enclosing wash.
static func _createFlaredShellMesh(
		bottomRadius: float,
		topRadius: float,
		height: float) -> ArrayMesh:
	var segments := SpellCastAuraProfile.PLUME_SHELL_SEGMENTS
	var heightBands := SpellCastAuraProfile.PLUME_SHELL_HEIGHT_BANDS
	var vertices := PackedVector3Array()
	var normals := PackedVector3Array()
	var uvs := PackedVector2Array()
	var indices := PackedInt32Array()

	for row: int in range(heightBands + 1):
		var heightFraction := float(row) / float(heightBands)
		var flareFraction := pow(heightFraction, 0.72)
		var radius := lerpf(bottomRadius, topRadius, flareFraction)
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


static func _sourceVisibility(progress: float) -> float:
	if progress <= SpellCastAuraProfile.CHARGE_END:
		return smoothstep(0.0, SpellCastAuraProfile.CHARGE_END, progress)
	var sourceEnd := float(SpellCastAuraProfile.SOURCE_STATE_PROGRESS[-1])
	if progress <= sourceEnd:
		return 1.0
	return 1.0 - smoothstep(sourceEnd, SpellCastAuraProfile.DECAY_END, progress)


static func _countNodes(node: Node) -> int:
	var count := 1
	for child: Node in node.get_children():
		count += _countNodes(child)
	return count
