## Element-tinted ground aura implementing the uniform VFX playback contract.
##
## Gameplay call sites keep using SpellCastAura.spawn(...). The debug catalog
## uses createPlayback(...) and controls the same visual through VfxPlayback.

class_name SpellCastAura
extends "res://src/presentation/effects/VfxPlayback.gd"

const _SPELL_AURA_SHADER = preload("res://assets/shaders/spell_aura.gdshader")

const VISIBLE_DURATION := 1.1
const SETTLE_NORMALIZED_TIME := 0.82
const LAYER_GROUND := "ground"
const LAYER_WISPS := "wisps"

static var _noiseTexture: NoiseTexture2D = null
static var _wispTexture: GradientTexture2D = null

var _elementColor := Color.WHITE
var _groundDecal: MeshInstance3D
var _groundMaterial: ShaderMaterial
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
	_setGroundProgress(0.0)
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
	_setGroundProgress(normalizedTime)
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
	return [LAYER_GROUND, LAYER_WISPS]


func set_layer_visible(layer_name: String, visible: bool) -> void:
	match layer_name:
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
	_setGroundProgress(get_normalized_time())
	if _elapsedTime >= VISIBLE_DURATION:
		_finished = true
		_playing = false
		if _particles != null:
			_particles.speed_scale = 0.0
		if _autoDispose:
			dispose()


func _buildLayers() -> void:
	_groundDecal = _createGroundDecal(_elementColor)
	add_child(_groundDecal)
	_groundMaterial = _groundDecal.material_override as ShaderMaterial
	_particles = _createRisingWisps(_elementColor)
	add_child(_particles)
	set_process(false)


func _setGroundProgress(progress: float) -> void:
	if _groundMaterial != null:
		_groundMaterial.set_shader_parameter("lifetime_progress", progress)
		_groundMaterial.set_shader_parameter("playback_time", _elapsedTime)


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
