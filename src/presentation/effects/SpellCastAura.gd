## Element-tinted spiritual vortex implementing the uniform VFX playback contract.
##
## Runtime and debug callers both create this effect through SpellVfxCatalog,
## so target-centred battle playback and authoring controls share one
## implementation.

class_name SpellCastAura
extends "res://src/presentation/effects/VfxPlayback.gd"

const _VORTEX_SHADER = preload(
		"res://assets/shaders/effects/spell_cast_ground_vortex.gdshader")
const _CORE_SHADER = preload(
		"res://assets/shaders/effects/spell_cast_core_glow.gdshader")
const _RAY_SHADER = preload(
		"res://assets/shaders/effects/spell_cast_ray_fan.gdshader")

const VISIBLE_DURATION := SpellCastAuraProfile.DURATION_SECONDS
const SETTLE_NORMALIZED_TIME := SpellCastAuraProfile.SETTLE_NORMALIZED_TIME
const LAYER_VORTEX := "ground_vortex"
const LAYER_RAYS := "radial_rays"
const LAYER_CORE := "core_glow"
const LAYER_WISPS := "rising_wisps"

var _elementColor := Color.WHITE
var _vortexInstance: MeshInstance3D
var _vortexMaterial: ShaderMaterial
var _rayInstance: MeshInstance3D
var _rayMaterial: ShaderMaterial
var _coreInstance: MeshInstance3D
var _coreMaterial: ShaderMaterial
var _wisps: GPUParticles3D
var _elapsedTime: float = 0.0
var _playbackScale: float = 1.0
var _activeSeed: int = 0
var _mode: String = MODE_BATTLE
var _playing: bool = false
var _finished: bool = true
var _disposed: bool = false
var _autoDispose: bool = false


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
	_restartParticlesAt(0.0)
	set_process(true)


func set_playback_scale(scale: float) -> void:
	_playbackScale = maxf(scale, 0.0)
	if _wisps != null:
		_wisps.speed_scale = _playbackScale if _playing else 0.0


func seek_normalized(time: float) -> void:
	if _disposed:
		return
	var normalizedTime := clampf(time, 0.0, 1.0)
	_elapsedTime = normalizedTime * VISIBLE_DURATION
	_finished = normalizedTime >= 1.0
	if _finished:
		_playing = false
	_applyProgress(normalizedTime)
	_restartParticlesAt(_elapsedTime)


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
	if _wisps != null:
		_wisps.emitting = false
		_wisps.speed_scale = 0.0
	if is_queued_for_deletion():
		return
	if is_inside_tree():
		queue_free()
	else:
		# Scene teardown can invoke disposal while the object is notification-
		# locked. Deferral releases that lock before the final free.
		call_deferred("free")


func get_layer_names() -> Array[String]:
	return [LAYER_VORTEX, LAYER_RAYS, LAYER_CORE, LAYER_WISPS]


func set_layer_visible(layer_name: String, visible: bool) -> void:
	match layer_name:
		LAYER_VORTEX:
			if _vortexInstance != null:
				_vortexInstance.visible = visible
		LAYER_RAYS:
			if _rayInstance != null:
				_rayInstance.visible = visible
		LAYER_CORE:
			if _coreInstance != null:
				_coreInstance.visible = visible
		LAYER_WISPS:
			if _wisps != null:
				_wisps.visible = visible
		_:
			push_warning("Unknown SpellCastAura layer: %s" % layer_name)


func get_live_particle_count() -> int:
	if (
		_wisps == null
		or not _wisps.visible
		or _finished
		or get_normalized_time() >= SpellCastAuraProfile.DECAY_END
	):
		return 0
	return _wisps.amount


func get_live_instance_count() -> int:
	if _finished:
		return 0
	var count := 0
	for instance: MeshInstance3D in [_vortexInstance, _rayInstance, _coreInstance]:
		if instance != null and instance.visible:
			count += 1
	return count


func get_live_node_count() -> int:
	if _disposed:
		return 0
	return _countNodes(self)


func is_particle_seek_exact() -> bool:
	# Shader layers seek exactly. GPUParticles3D restart/process requests retain
	# the renderer-scheduling variance documented by the VFX harness.
	return false


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
		if _wisps != null:
			_wisps.speed_scale = 0.0
		if _autoDispose:
			dispose()


func _buildLayers() -> void:
	assert(
		SpellCastAuraProfile.RAY_COUNT <= SpellCastAuraProfile.RAY_SHADER_CAPACITY,
		"Spell-cast aura ray count exceeds its shader loop capacity."
	)
	_vortexInstance = _createGroundVortex(_elementColor)
	add_child(_vortexInstance)
	_vortexMaterial = _vortexInstance.material_override as ShaderMaterial
	_rayInstance = _createRayFan(_elementColor)
	add_child(_rayInstance)
	_rayMaterial = _rayInstance.material_override as ShaderMaterial
	_coreInstance = _createCoreGlow(_elementColor)
	add_child(_coreInstance)
	_coreMaterial = _coreInstance.material_override as ShaderMaterial
	_wisps = _createRisingWisps(_elementColor)
	add_child(_wisps)
	_applySeed(0)
	assert(
		_countNodes(self) <= SpellCastAuraProfile.MAX_EFFECT_NODES,
		"Spell-cast aura exceeded its authored node ceiling."
	)
	assert(
		SpellCastAuraProfile.EXPECTED_DRAW_CALLS <= SpellCastAuraProfile.MAX_DRAW_CALLS,
		"Spell-cast aura exceeded its authored draw-call ceiling."
	)
	set_process(false)


func _applyProgress(progress: float) -> void:
	for material: ShaderMaterial in [_vortexMaterial, _rayMaterial, _coreMaterial]:
		if material != null:
			material.set_shader_parameter("burst_progress", progress)


func _applySeed(seed: int) -> void:
	var seedValue := float(seed)
	for material: ShaderMaterial in [_vortexMaterial, _rayMaterial, _coreMaterial]:
		if material != null:
			material.set_shader_parameter("seed_value", seedValue)


func _restartParticlesAt(elapsed: float) -> void:
	if _wisps == null:
		return
	_wisps.speed_scale = 0.0
	_wisps.use_fixed_seed = true
	_wisps.seed = _activeSeed
	_wisps.emitting = true
	_wisps.restart(true)
	if elapsed > 0.0:
		_wisps.request_particles_process(minf(elapsed, VISIBLE_DURATION))
	if _finished or elapsed >= VISIBLE_DURATION:
		_wisps.emitting = false
	_wisps.speed_scale = _playbackScale if _playing else 0.0


static func _createGroundVortex(color: Color) -> MeshInstance3D:
	var plane := PlaneMesh.new()
	plane.size = Vector2(
		SpellCastAuraProfile.VORTEX_PLANE_SIZE_U,
		SpellCastAuraProfile.VORTEX_PLANE_SIZE_U
	)
	var material := ShaderMaterial.new()
	material.shader = _VORTEX_SHADER
	material.render_priority = SpellCastAuraProfile.VORTEX_RENDER_PRIORITY
	material.set_shader_parameter("aura_color", color)
	material.set_shader_parameter("burst_progress", 0.0)
	material.set_shader_parameter("seed_value", 0.0)
	material.set_shader_parameter("outer_radius", SpellCastAuraProfile.VORTEX_OUTER_RADIUS_U)
	material.set_shader_parameter(
		"inner_dark_alpha", SpellCastAuraProfile.VORTEX_INNER_DARK_ALPHA
	)
	material.set_shader_parameter("ring_alpha", SpellCastAuraProfile.VORTEX_RING_ALPHA)
	material.set_shader_parameter("rim_alpha", SpellCastAuraProfile.VORTEX_RIM_ALPHA)
	material.set_shader_parameter(
		"rim_emission_energy", SpellCastAuraProfile.VORTEX_RIM_EMISSION_ENERGY
	)
	material.set_shader_parameter("charge_end", SpellCastAuraProfile.CHARGE_END)
	material.set_shader_parameter("hold_end", SpellCastAuraProfile.HOLD_END)
	material.set_shader_parameter("decay_end", SpellCastAuraProfile.DECAY_END)

	var instance := MeshInstance3D.new()
	instance.name = "GroundVortex"
	instance.mesh = plane
	instance.position.y = SpellCastAuraProfile.VORTEX_HEIGHT_U
	instance.material_override = material
	instance.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	return instance


static func _createRayFan(color: Color) -> MeshInstance3D:
	var quad := QuadMesh.new()
	quad.size = Vector2(
		SpellCastAuraProfile.RAY_FAN_WIDTH_U,
		SpellCastAuraProfile.RAY_FAN_HEIGHT_U
	)
	var material := ShaderMaterial.new()
	material.shader = _RAY_SHADER
	material.render_priority = SpellCastAuraProfile.RAY_RENDER_PRIORITY
	material.set_shader_parameter("aura_color", color)
	material.set_shader_parameter("burst_progress", 0.0)
	material.set_shader_parameter("seed_value", 0.0)
	material.set_shader_parameter("quad_width", SpellCastAuraProfile.RAY_FAN_WIDTH_U)
	material.set_shader_parameter("quad_height", SpellCastAuraProfile.RAY_FAN_HEIGHT_U)
	material.set_shader_parameter("ray_count", SpellCastAuraProfile.RAY_COUNT)
	material.set_shader_parameter("angle_span", SpellCastAuraProfile.RAY_ANGLE_SPAN_RADIANS)
	material.set_shader_parameter("length_min", SpellCastAuraProfile.RAY_LENGTH_MIN)
	material.set_shader_parameter("length_max", SpellCastAuraProfile.RAY_LENGTH_MAX)
	material.set_shader_parameter("width_min", SpellCastAuraProfile.RAY_WIDTH_MIN)
	material.set_shader_parameter("width_max", SpellCastAuraProfile.RAY_WIDTH_MAX)
	material.set_shader_parameter("peak_alpha", SpellCastAuraProfile.RAY_PEAK_ALPHA)
	material.set_shader_parameter("white_mix", SpellCastAuraProfile.RAY_WHITE_MIX)
	material.set_shader_parameter(
		"emission_energy", SpellCastAuraProfile.RAY_EMISSION_ENERGY
	)
	material.set_shader_parameter("flicker_cycles", SpellCastAuraProfile.RAY_FLICKER_CYCLES)
	_setTimelineParameters(material)

	var instance := MeshInstance3D.new()
	instance.name = "RadialRayFan"
	instance.mesh = quad
	instance.position.y = SpellCastAuraProfile.RAY_FAN_HEIGHT_U * 0.5
	instance.material_override = material
	instance.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	return instance


static func _createCoreGlow(color: Color) -> MeshInstance3D:
	var quad := QuadMesh.new()
	quad.size = Vector2(SpellCastAuraProfile.CORE_WIDTH_U, SpellCastAuraProfile.CORE_HEIGHT_U)
	var material := ShaderMaterial.new()
	material.shader = _CORE_SHADER
	material.render_priority = SpellCastAuraProfile.CORE_RENDER_PRIORITY
	material.set_shader_parameter("aura_color", color)
	material.set_shader_parameter("burst_progress", 0.0)
	material.set_shader_parameter("seed_value", 0.0)
	material.set_shader_parameter("quad_height", SpellCastAuraProfile.CORE_HEIGHT_U)
	material.set_shader_parameter("peak_alpha", SpellCastAuraProfile.CORE_PEAK_ALPHA)
	material.set_shader_parameter("white_mix", SpellCastAuraProfile.CORE_WHITE_MIX)
	material.set_shader_parameter(
		"emission_energy", SpellCastAuraProfile.CORE_EMISSION_ENERGY
	)
	material.set_shader_parameter("noise_scale", SpellCastAuraProfile.CORE_NOISE_SCALE)
	material.set_shader_parameter("turbulence", SpellCastAuraProfile.CORE_TURBULENCE)
	_setTimelineParameters(material)

	var instance := MeshInstance3D.new()
	instance.name = "CoreGlow"
	instance.mesh = quad
	instance.position.y = SpellCastAuraProfile.CORE_HEIGHT_U * 0.5
	instance.material_override = material
	instance.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	return instance


static func _setTimelineParameters(material: ShaderMaterial) -> void:
	material.set_shader_parameter("eruption_start", SpellCastAuraProfile.ERUPTION_START)
	material.set_shader_parameter("eruption_end", SpellCastAuraProfile.ERUPTION_END)
	material.set_shader_parameter("hold_end", SpellCastAuraProfile.HOLD_END)
	material.set_shader_parameter("decay_end", SpellCastAuraProfile.DECAY_END)


static func _createRisingWisps(color: Color) -> GPUParticles3D:
	var particles := GPUParticles3D.new()
	particles.name = "RisingWisps"
	particles.amount = SpellCastAuraProfile.WISP_COUNT
	particles.lifetime = SpellCastAuraProfile.WISP_LIFETIME_SECONDS
	particles.one_shot = true
	particles.explosiveness = 0.36
	particles.randomness = 0.58
	particles.fixed_fps = 30
	particles.use_fixed_seed = true
	particles.emitting = false
	particles.visibility_aabb = AABB(Vector3(-1.5, -0.1, -1.5), Vector3(3.0, 3.2, 3.0))

	var processMaterial := ParticleProcessMaterial.new()
	processMaterial.emission_shape = ParticleProcessMaterial.EMISSION_SHAPE_RING
	processMaterial.emission_ring_radius = SpellCastAuraProfile.WISP_EMISSION_RADIUS_U
	processMaterial.emission_ring_inner_radius = SpellCastAuraProfile.WISP_EMISSION_INNER_RADIUS_U
	processMaterial.emission_ring_height = 0.06
	processMaterial.emission_ring_axis = Vector3.UP
	processMaterial.direction = Vector3.UP
	processMaterial.spread = 28.0
	processMaterial.initial_velocity_min = SpellCastAuraProfile.WISP_VELOCITY_MIN_U
	processMaterial.initial_velocity_max = SpellCastAuraProfile.WISP_VELOCITY_MAX_U
	processMaterial.gravity = Vector3(0.0, 0.16, 0.0)
	processMaterial.damping_min = 0.15
	processMaterial.damping_max = 0.55
	processMaterial.scale_min = 0.72
	processMaterial.scale_max = 1.38
	var mistColor := color.lerp(Color.WHITE, 0.18)
	mistColor.a = SpellCastAuraProfile.WISP_PEAK_ALPHA
	processMaterial.color = mistColor
	var gradient := Gradient.new()
	gradient.set_color(0, Color(mistColor.r, mistColor.g, mistColor.b, 0.0))
	gradient.add_point(0.12, mistColor)
	gradient.add_point(0.62, Color(mistColor.r, mistColor.g, mistColor.b, mistColor.a * 0.55))
	gradient.set_color(1, Color(mistColor.r, mistColor.g, mistColor.b, 0.0))
	var rampTexture := GradientTexture1D.new()
	rampTexture.gradient = gradient
	processMaterial.color_ramp = rampTexture
	particles.process_material = processMaterial

	var drawMesh := QuadMesh.new()
	drawMesh.size = Vector2(
		SpellCastAuraProfile.WISP_SPRITE_WIDTH_U,
		SpellCastAuraProfile.WISP_SPRITE_HEIGHT_U
	)
	particles.draw_pass_1 = drawMesh
	var drawMaterial := StandardMaterial3D.new()
	drawMaterial.render_priority = SpellCastAuraProfile.WISP_RENDER_PRIORITY
	drawMaterial.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	drawMaterial.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
	drawMaterial.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	drawMaterial.billboard_mode = BaseMaterial3D.BILLBOARD_ENABLED
	drawMaterial.vertex_color_use_as_albedo = true
	drawMaterial.albedo_color = Color.WHITE
	drawMaterial.albedo_texture = VfxTextures.neutralSoftPuff()
	drawMaterial.texture_filter = BaseMaterial3D.TEXTURE_FILTER_LINEAR
	drawMaterial.emission_enabled = true
	drawMaterial.emission = color.lerp(Color.WHITE, 0.12)
	drawMaterial.emission_energy_multiplier = SpellCastAuraProfile.WISP_EMISSION_ENERGY
	drawMaterial.emission_texture = VfxTextures.neutralSoftPuff()
	particles.material_override = drawMaterial
	return particles


static func _countNodes(node: Node) -> int:
	var count := 1
	for child: Node in node.get_children():
		count += _countNodes(child)
	return count
