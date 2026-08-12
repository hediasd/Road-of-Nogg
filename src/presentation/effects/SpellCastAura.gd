## Element-tinted ground aura implementing the uniform VFX playback contract.
##
## Runtime and debug callers both create this effect through SpellVfxCatalog,
## so target-centred battle playback and authoring controls share one
## implementation.

class_name SpellCastAura
extends "res://src/presentation/effects/VfxPlayback.gd"

const _SPELL_AURA_SHADER = preload("res://assets/shaders/spell_aura.gdshader")
const _RAY_BURST_SHADER = preload(
		"res://assets/shaders/effects/spell_cast_ray_burst.gdshader")

const VISIBLE_DURATION := 1.1
const SETTLE_NORMALIZED_TIME := 0.82
const LAYER_GROUND := "ground"
const LAYER_WISPS := "wisps"
const LAYER_RAYS := "ray_burst"

static var _noiseTexture: NoiseTexture2D = null
static var _wispTexture: GradientTexture2D = null
static var _bladeMesh: ArrayMesh = null

var _elementColor := Color.WHITE
var _groundDecal: MeshInstance3D
var _groundMaterial: ShaderMaterial
var _rayInstance: MultiMeshInstance3D
var _rayMultiMesh: MultiMesh
var _rayMaterial: ShaderMaterial
var _rayLayoutSeed: int = -1
var _particles: GPUParticles3D
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
	_ensureSharedResources()
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
	_rebuildBladeLayout(seed)
	_applyProgress(0.0)
	_restartParticlesAt(0.0)
	set_process(true)


func set_playback_scale(scale: float) -> void:
	_playbackScale = maxf(scale, 0.0)
	if _particles != null:
		_particles.speed_scale = _playbackScale if _playing else 0.0


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
	if _particles != null:
		_particles.emitting = false
		_particles.speed_scale = 0.0
	if is_inside_tree():
		queue_free()
	else:
		free()


func get_layer_names() -> Array[String]:
	return [LAYER_RAYS, LAYER_GROUND, LAYER_WISPS]


func set_layer_visible(layer_name: String, visible: bool) -> void:
	match layer_name:
		LAYER_RAYS:
			if _rayInstance != null:
				_rayInstance.visible = visible
		LAYER_GROUND:
			if _groundDecal != null:
				_groundDecal.visible = visible
		LAYER_WISPS:
			if _particles != null:
				_particles.visible = visible
		_:
			push_warning("Unknown SpellCastAura layer: %s" % layer_name)


func get_live_particle_count() -> int:
	if _particles == null or not _particles.visible or _finished:
		return 0
	return _particles.amount


func get_live_instance_count() -> int:
	if _rayInstance == null or not _rayInstance.visible or _finished:
		return 0
	return SpellCastAuraProfile.BLADE_COUNT


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
		if _particles != null:
			_particles.speed_scale = 0.0
		if _autoDispose:
			dispose()


func _buildLayers() -> void:
	assert(
		SpellCastAuraProfile.BLADE_COUNT >= SpellCastAuraProfile.MIN_BLADE_COUNT
		and SpellCastAuraProfile.BLADE_COUNT <= SpellCastAuraProfile.MAX_BLADE_COUNT,
		"Spell-cast aura blade count is outside its authored bounds."
	)
	_groundDecal = _createGroundDecal(_elementColor)
	add_child(_groundDecal)
	_groundMaterial = _groundDecal.material_override as ShaderMaterial
	_rayInstance = _createRayBurst(_elementColor)
	add_child(_rayInstance)
	_rayMultiMesh = _rayInstance.multimesh
	_rayMaterial = _rayInstance.material_override as ShaderMaterial
	_particles = _createRisingWisps(_elementColor)
	add_child(_particles)
	_rebuildBladeLayout(0)
	assert(
		_countNodes(self) <= SpellCastAuraProfile.MAX_EFFECT_NODES,
		"Spell-cast aura exceeded its authored node ceiling."
	)
	set_process(false)


func _applyProgress(progress: float) -> void:
	if _groundMaterial != null:
		_groundMaterial.set_shader_parameter("lifetime_progress", progress)
		_groundMaterial.set_shader_parameter("playback_time", _elapsedTime)
	if _rayMaterial != null:
		_rayMaterial.set_shader_parameter("burst_progress", progress)


## Blade placement is sampled once per seed, never per frame, so the crown is
## reproducible under scrub, replay, and overlap. Hero blades are spread around
## the ring by index before jitter, so the size hierarchy survives any seed.
func _rebuildBladeLayout(layoutSeed: int) -> void:
	if _rayMultiMesh == null or _rayLayoutSeed == layoutSeed:
		return
	_rayLayoutSeed = layoutSeed
	var rng := RandomNumberGenerator.new()
	rng.seed = layoutSeed
	var bladeCount := SpellCastAuraProfile.BLADE_COUNT
	var heroIndices := {}
	for hero: int in range(SpellCastAuraProfile.HERO_BLADE_COUNT):
		var heroIndex := int(
			round(float(hero) * float(bladeCount) / SpellCastAuraProfile.HERO_BLADE_COUNT)
		) % bladeCount
		heroIndices[heroIndex] = true

	for index: int in range(bladeCount):
		var isHero: bool = heroIndices.has(index)
		var jitter := rng.randf_range(-1.0, 1.0) \
			* SpellCastAuraProfile.GOLDEN_ANGLE_RADIANS \
			* SpellCastAuraProfile.AZIMUTH_JITTER_FRACTION
		var azimuth := float(index) * SpellCastAuraProfile.GOLDEN_ANGLE_RADIANS + jitter
		var seatRadius := rng.randf_range(
			SpellCastAuraProfile.SEAT_RADIUS_MIN_U,
			SpellCastAuraProfile.SEAT_RADIUS_MAX_U
		)
		var height := rng.randf_range(
			SpellCastAuraProfile.HERO_HEIGHT_MIN_U if isHero
					else SpellCastAuraProfile.SUPPORT_HEIGHT_MIN_U,
			SpellCastAuraProfile.HERO_HEIGHT_MAX_U if isHero
					else SpellCastAuraProfile.SUPPORT_HEIGHT_MAX_U
		)
		var width := rng.randf_range(
			SpellCastAuraProfile.HERO_WIDTH_MIN_U if isHero
					else SpellCastAuraProfile.SUPPORT_WIDTH_MIN_U,
			SpellCastAuraProfile.HERO_WIDTH_MAX_U if isHero
					else SpellCastAuraProfile.SUPPORT_WIDTH_MAX_U
		)
		# Taller blades lean further, which turns the ring into a flare.
		var heightNorm := inverse_lerp(
			SpellCastAuraProfile.SUPPORT_HEIGHT_MIN_U,
			SpellCastAuraProfile.HERO_HEIGHT_MAX_U,
			height
		)
		var lean := lerpf(
			SpellCastAuraProfile.LEAN_MIN_U,
			SpellCastAuraProfile.LEAN_MAX_U,
			clampf(heightNorm, 0.0, 1.0)
		) * rng.randf_range(0.7, 1.0)
		var outward := Vector3(cos(azimuth), 0.0, sin(azimuth))

		var transform := Transform3D()
		transform.basis.x = Vector3(width * 0.5, 0.0, 0.0)
		transform.basis.y = Vector3(0.0, height, 0.0)
		transform.basis.z = outward * lean
		transform.origin = outward * seatRadius
		transform.origin.y = SpellCastAuraProfile.SEAT_HEIGHT_U
		_rayMultiMesh.set_instance_transform(index, transform)
		_rayMultiMesh.set_instance_custom_data(index, Color(
			rng.randf() * SpellCastAuraProfile.PROVISIONAL_MAX_DELAY,
			rng.randf_range(
				SpellCastAuraProfile.BRIGHTNESS_MIN,
				SpellCastAuraProfile.BRIGHTNESS_MAX
			),
			SpellCastAuraProfile.HERO_ALPHA_MULTIPLIER if isHero else 1.0,
			1.0 if isHero else 0.0
		))


func _restartParticlesAt(elapsed: float) -> void:
	if _particles == null:
		return
	_particles.speed_scale = 0.0
	_particles.use_fixed_seed = true
	_particles.seed = _activeSeed
	_particles.emitting = true
	_particles.restart(true)
	if elapsed > 0.0:
		_particles.request_particles_process(minf(elapsed, VISIBLE_DURATION))
	if _finished:
		_particles.emitting = false
	_particles.speed_scale = _playbackScale if _playing else 0.0


static func _ensureSharedResources() -> void:
	if _noiseTexture == null:
		var noise := FastNoiseLite.new()
		noise.noise_type = FastNoiseLite.TYPE_SIMPLEX_SMOOTH
		noise.frequency = 2.8
		noise.fractal_type = FastNoiseLite.FRACTAL_FBM
		noise.fractal_octaves = 3
		var texture := NoiseTexture2D.new()
		texture.width = 128
		texture.height = 128
		texture.seamless = true
		texture.noise = noise
		_noiseTexture = texture

	if _wispTexture == null:
		var gradient := Gradient.new()
		gradient.set_color(0, Color(1.0, 1.0, 1.0, 1.0))
		gradient.add_point(0.55, Color(1.0, 1.0, 1.0, 0.4))
		gradient.set_color(2, Color(1.0, 1.0, 1.0, 0.0))
		var texture := GradientTexture2D.new()
		texture.gradient = gradient
		texture.fill = GradientTexture2D.FILL_RADIAL
		texture.fill_from = Vector2(0.5, 0.5)
		texture.fill_to = Vector2(0.5, 0.0)
		texture.width = 32
		texture.height = 64
		_wispTexture = texture


## One blade: a broad seat, shoulders at roughly two thirds, and a single sharp
## apex. UV2 carries the authored local geometry the shader rebuilds the blade
## from; UV carries the shading coordinates, with x normalized across the
## blade's width at that height so the alpha profile follows the taper rather
## than the bounding box.
static func _ensureBladeMesh() -> void:
	if _bladeMesh != null:
		return
	var seatX := SpellCastAuraProfile.SILHOUETTE_SEAT_WIDTH * 0.5
	var shoulderX := SpellCastAuraProfile.SILHOUETTE_SHOULDER_WIDTH * 0.5
	var shoulderY := SpellCastAuraProfile.SILHOUETTE_SHOULDER_HEIGHT

	var vertices := PackedVector3Array([
		Vector3(-seatX, 0.0, 0.0),
		Vector3(seatX, 0.0, 0.0),
		Vector3(shoulderX, shoulderY, 0.0),
		Vector3(0.0, 1.0, 0.0),
		Vector3(-shoulderX, shoulderY, 0.0),
	])
	var shadingUvs := PackedVector2Array([
		Vector2(0.0, 0.0),
		Vector2(1.0, 0.0),
		Vector2(1.0, shoulderY),
		Vector2(0.5, 1.0),
		Vector2(0.0, shoulderY),
	])
	var geometryUvs := PackedVector2Array([
		Vector2(0.0, 0.0),
		Vector2(1.0, 0.0),
		Vector2(0.5 + shoulderX, shoulderY),
		Vector2(0.5, 1.0),
		Vector2(0.5 - shoulderX, shoulderY),
	])
	var indices := PackedInt32Array([0, 1, 2, 0, 2, 4, 4, 2, 3])

	var arrays := []
	arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX] = vertices
	arrays[Mesh.ARRAY_TEX_UV] = shadingUvs
	arrays[Mesh.ARRAY_TEX_UV2] = geometryUvs
	arrays[Mesh.ARRAY_INDEX] = indices

	var mesh := ArrayMesh.new()
	mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
	_bladeMesh = mesh


static func _createRayBurst(color: Color) -> MultiMeshInstance3D:
	_ensureBladeMesh()
	var multiMesh := MultiMesh.new()
	multiMesh.transform_format = MultiMesh.TRANSFORM_3D
	multiMesh.use_custom_data = true
	multiMesh.mesh = _bladeMesh
	multiMesh.instance_count = SpellCastAuraProfile.BLADE_COUNT

	var material := ShaderMaterial.new()
	material.shader = _RAY_BURST_SHADER
	material.render_priority = SpellCastAuraProfile.RAY_RENDER_PRIORITY
	material.set_shader_parameter("aura_color", color)
	material.set_shader_parameter("burst_progress", 0.0)
	material.set_shader_parameter("growth_end", SpellCastAuraProfile.PROVISIONAL_GROWTH_END)
	material.set_shader_parameter("hold_end", SpellCastAuraProfile.PROVISIONAL_HOLD_END)
	material.set_shader_parameter("clear_end", SpellCastAuraProfile.PROVISIONAL_CLEAR_END)
	material.set_shader_parameter("edge_alpha_steps", SpellCastAuraProfile.EDGE_ALPHA_STEPS)
	material.set_shader_parameter(
		"core_width_fraction", SpellCastAuraProfile.CORE_WIDTH_FRACTION
	)
	material.set_shader_parameter("peak_alpha", SpellCastAuraProfile.PEAK_ALPHA)
	material.set_shader_parameter("tip_fade_start", SpellCastAuraProfile.TIP_FADE_START)
	material.set_shader_parameter("seat_glow_height", SpellCastAuraProfile.SEAT_GLOW_HEIGHT)
	material.set_shader_parameter("seat_white_mix", SpellCastAuraProfile.SEAT_WHITE_MIX)
	material.set_shader_parameter("body_white_mix", SpellCastAuraProfile.BODY_WHITE_MIX)
	material.set_shader_parameter("tip_deepen", SpellCastAuraProfile.TIP_DEEPEN)
	material.set_shader_parameter(
		"body_gradient_end", SpellCastAuraProfile.BODY_GRADIENT_END
	)
	material.set_shader_parameter(
		"tip_gradient_start", SpellCastAuraProfile.TIP_GRADIENT_START
	)
	material.set_shader_parameter("emission_energy", SpellCastAuraProfile.EMISSION_ENERGY)
	material.set_shader_parameter(
		"lean_height_exponent", SpellCastAuraProfile.LEAN_HEIGHT_EXPONENT
	)

	var instance := MultiMeshInstance3D.new()
	instance.name = "RayBurst"
	instance.multimesh = multiMesh
	instance.material_override = material
	instance.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	# The vertex stage builds each blade in world space, so the mesh's own
	# bounds describe nothing the renderer can cull against. This box covers the
	# widest seat, the longest lean, and the tallest hero blade.
	var reach := SpellCastAuraProfile.SEAT_RADIUS_MAX_U \
		+ SpellCastAuraProfile.LEAN_MAX_U \
		+ SpellCastAuraProfile.HERO_WIDTH_MAX_U
	var top := SpellCastAuraProfile.HERO_HEIGHT_MAX_U + SpellCastAuraProfile.SEAT_HEIGHT_U
	instance.custom_aabb = AABB(
		Vector3(-reach, -0.1, -reach),
		Vector3(reach * 2.0, top + 0.1, reach * 2.0)
	)
	return instance


static func _createGroundDecal(color: Color) -> MeshInstance3D:
	var meshInstance := MeshInstance3D.new()
	meshInstance.name = "GroundDecal"
	var plane := PlaneMesh.new()
	plane.size = Vector2(2.0, 2.0)
	plane.subdivide_width = 1
	plane.subdivide_depth = 1
	meshInstance.mesh = plane
	meshInstance.position.y = 0.025
	var material := ShaderMaterial.new()
	material.shader = _SPELL_AURA_SHADER
	material.set_shader_parameter("aura_color", color)
	material.set_shader_parameter("noise_tex", _noiseTexture)
	material.set_shader_parameter("lifetime_progress", 0.0)
	material.set_shader_parameter("playback_time", 0.0)
	material.set_shader_parameter("intensity", 6.0)
	material.set_shader_parameter("ring_width", 0.13)
	material.set_shader_parameter("edge_distortion", 0.07)
	material.set_shader_parameter("scroll_speed", 0.4)
	meshInstance.material_override = material
	return meshInstance


static func _createRisingWisps(color: Color) -> GPUParticles3D:
	var particles := GPUParticles3D.new()
	particles.name = "RisingWisps"
	particles.amount = 7
	particles.lifetime = VISIBLE_DURATION
	particles.one_shot = true
	particles.explosiveness = 0.5
	particles.randomness = 0.6
	particles.fixed_fps = 30
	particles.use_fixed_seed = true
	particles.emitting = false

	var processMaterial := ParticleProcessMaterial.new()
	processMaterial.emission_shape = ParticleProcessMaterial.EMISSION_SHAPE_RING
	processMaterial.emission_ring_radius = 0.38
	processMaterial.emission_ring_inner_radius = 0.18
	processMaterial.emission_ring_height = 0.04
	processMaterial.emission_ring_axis = Vector3.UP
	processMaterial.direction = Vector3.UP
	processMaterial.spread = 15.0
	processMaterial.initial_velocity_min = 0.5
	processMaterial.initial_velocity_max = 1.3
	processMaterial.gravity = Vector3(0.0, 0.2, 0.0)
	processMaterial.damping_min = 0.2
	processMaterial.damping_max = 0.6
	processMaterial.scale_min = 0.7
	processMaterial.scale_max = 1.5
	var bright := color.lightened(0.5)
	bright.a = 1.0
	processMaterial.color = bright
	var gradient := Gradient.new()
	gradient.set_color(0, bright)
	gradient.add_point(0.55, Color(bright.r, bright.g, bright.b, 0.6))
	gradient.set_color(2, Color(bright.r, bright.g, bright.b, 0.0))
	var rampTexture := GradientTexture1D.new()
	rampTexture.gradient = gradient
	processMaterial.color_ramp = rampTexture
	particles.process_material = processMaterial

	var drawMesh := QuadMesh.new()
	drawMesh.size = Vector2(0.10, 0.22)
	particles.draw_pass_1 = drawMesh
	var drawMaterial := StandardMaterial3D.new()
	drawMaterial.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	drawMaterial.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
	drawMaterial.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	drawMaterial.billboard_mode = BaseMaterial3D.BILLBOARD_ENABLED
	drawMaterial.vertex_color_use_as_albedo = true
	drawMaterial.albedo_color = Color.WHITE
	drawMaterial.albedo_texture = _wispTexture
	drawMaterial.emission_enabled = true
	drawMaterial.emission = color.lightened(0.4)
	drawMaterial.emission_energy_multiplier = 3.0
	drawMaterial.emission_texture = _wispTexture
	particles.material_override = drawMaterial
	return particles


static func _countNodes(node: Node) -> int:
	var count := 1
	for child: Node in node.get_children():
		count += _countNodes(child)
	return count
