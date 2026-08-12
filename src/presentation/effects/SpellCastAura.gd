## Element-tinted ground aura implementing the uniform VFX playback contract.
##
## Runtime and debug callers both create this effect through SpellVfxCatalog,
## so target-centred battle playback and authoring controls share one
## implementation.

class_name SpellCastAura
extends "res://src/presentation/effects/VfxPlayback.gd"

const _SPELL_AURA_SHADER = preload("res://assets/shaders/spell_aura.gdshader")
const _RAY_SHELL_SHADER = preload(
		"res://assets/shaders/effects/spell_cast_ray_shell.gdshader")

const VISIBLE_DURATION := SpellCastAuraProfile.DURATION_SECONDS
const SETTLE_NORMALIZED_TIME := SpellCastAuraProfile.SETTLE_NORMALIZED_TIME
const LAYER_GROUND := "ground_rupture"
const LAYER_WISPS := "motes"
const LAYER_RAYS := "ray_burst"

## Where the inherited ground shader's own 0-to-1 sits when the crown is fully
## erupted: open, but not yet into its built-in fade.
const _GROUND_OPEN_PROGRESS := 0.55

static var _noiseTexture: NoiseTexture2D = null
static var _wispTexture: GradientTexture2D = null
static var _shellMesh: ArrayMesh = null

var _elementColor := Color.WHITE
var _groundDecal: MeshInstance3D
var _groundMaterial: ShaderMaterial
var _rayInstance: MeshInstance3D
var _rayMaterial: ShaderMaterial
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
	_applyShellSeed(seed)
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
	if is_queued_for_deletion():
		return
	if is_inside_tree():
		queue_free()
	else:
		# Disposal reaches here during scene and process teardown, where this
		# node is already out of the tree and frequently mid-notification. A
		# direct free() on an object the engine has locked for the duration of
		# that call prints `Object is locked and can't be freed`; deferring runs
		# it once the lock has been released.
		call_deferred("free")


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
		if _particles != null:
			_particles.speed_scale = 0.0
		if _autoDispose:
			dispose()


func _buildLayers() -> void:
	assert(
		SpellCastAuraProfile.SHELL_RIM_RADIUS_U > SpellCastAuraProfile.SHELL_BASE_RADIUS_U,
		"Spell-cast aura shell must flare outward from its seat."
	)
	_groundDecal = _createGroundDecal(_elementColor)
	add_child(_groundDecal)
	_groundMaterial = _groundDecal.material_override as ShaderMaterial
	_rayInstance = _createRayShell(_elementColor)
	add_child(_rayInstance)
	_rayMaterial = _rayInstance.material_override as ShaderMaterial
	_particles = _createRisingWisps(_elementColor)
	add_child(_particles)
	_applyShellSeed(0)
	assert(
		_countNodes(self) <= SpellCastAuraProfile.MAX_EFFECT_NODES,
		"Spell-cast aura exceeded its authored node ceiling."
	)
	set_process(false)


func _applyProgress(progress: float) -> void:
	if _groundMaterial != null:
		_groundMaterial.set_shader_parameter(
			"lifetime_progress", _groundTimelineProgress(progress)
		)
		_groundMaterial.set_shader_parameter("playback_time", _elapsedTime)
	if _rayMaterial != null:
		_rayMaterial.set_shader_parameter("burst_progress", progress)


## The ground layer predates this timeline and spends its own 0-to-1 expanding
## and then fading. Remapping it onto the named windows keeps the rupture
## opening while the blades erupt and clearing while they fade, so the two
## belong to one event. The layer's own rebuild is the next item's work.
func _groundTimelineProgress(progress: float) -> float:
	if progress <= SpellCastAuraProfile.HOLD_END:
		return remap(
			progress, 0.0, SpellCastAuraProfile.HOLD_END, 0.0, _GROUND_OPEN_PROGRESS
		)
	return remap(
		progress, SpellCastAuraProfile.HOLD_END, 1.0, _GROUND_OPEN_PROGRESS, 1.0
	)


## The shell derives every stripe's width, brightness, top height, and
## eruption delay by hash from its index and this seed, so a new seed
## reshuffles the crown without any placement pass and without a single
## random call at playback time.
func _applyShellSeed(shellSeed: int) -> void:
	if _rayMaterial == null:
		return
	_rayMaterial.set_shader_parameter("shell_seed", float(shellSeed))


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


## A unit cylinder: radius 1, height 1, open at both ends. The cone's actual
## proportions are shader uniforms, so the silhouette can be retuned without
## rebuilding geometry. UV.x runs around the shell and UV.y from seat to rim.
static func _ensureShellMesh() -> void:
	if _shellMesh != null:
		return
	var radialSegments := SpellCastAuraProfile.SHELL_RADIAL_SEGMENTS
	var verticalSegments := SpellCastAuraProfile.SHELL_VERTICAL_SEGMENTS
	var vertices := PackedVector3Array()
	var uvs := PackedVector2Array()
	var indices := PackedInt32Array()

	for ring: int in range(verticalSegments + 1):
		var along := float(ring) / float(verticalSegments)
		for segment: int in range(radialSegments + 1):
			var around := float(segment) / float(radialSegments)
			var angle := around * TAU
			vertices.append(Vector3(cos(angle), along, sin(angle)))
			uvs.append(Vector2(around, along))

	var stride := radialSegments + 1
	for ring: int in range(verticalSegments):
		for segment: int in range(radialSegments):
			var lower := ring * stride + segment
			var upper := lower + stride
			indices.append_array([lower, upper, lower + 1, lower + 1, upper, upper + 1])

	var arrays := []
	arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX] = vertices
	arrays[Mesh.ARRAY_TEX_UV] = uvs
	arrays[Mesh.ARRAY_INDEX] = indices

	var mesh := ArrayMesh.new()
	mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
	_shellMesh = mesh


static func _createRayShell(color: Color) -> MeshInstance3D:
	_ensureShellMesh()
	var material := ShaderMaterial.new()
	material.shader = _RAY_SHELL_SHADER
	material.render_priority = SpellCastAuraProfile.RAY_RENDER_PRIORITY
	material.set_shader_parameter("aura_color", color)
	material.set_shader_parameter("burst_progress", 0.0)
	material.set_shader_parameter("shell_seed", 0.0)
	material.set_shader_parameter("base_radius", SpellCastAuraProfile.SHELL_BASE_RADIUS_U)
	material.set_shader_parameter("rim_radius", SpellCastAuraProfile.SHELL_RIM_RADIUS_U)
	material.set_shader_parameter("height", SpellCastAuraProfile.SHELL_HEIGHT_U)
	material.set_shader_parameter("open_start", SpellCastAuraProfile.SHELL_OPEN_START)
	material.set_shader_parameter("stripe_count", SpellCastAuraProfile.STRIPE_COUNT)
	material.set_shader_parameter(
		"stripe_width_min", SpellCastAuraProfile.STRIPE_WIDTH_MIN
	)
	material.set_shader_parameter(
		"stripe_width_max", SpellCastAuraProfile.STRIPE_WIDTH_MAX
	)
	material.set_shader_parameter("stripe_alpha", SpellCastAuraProfile.STRIPE_ALPHA)
	material.set_shader_parameter("wall_glow_alpha", SpellCastAuraProfile.WALL_GLOW_ALPHA)
	material.set_shader_parameter("tooth_min", SpellCastAuraProfile.TOOTH_MIN)
	material.set_shader_parameter("tooth_max", SpellCastAuraProfile.TOOTH_MAX)
	material.set_shader_parameter("tooth_soft", SpellCastAuraProfile.TOOTH_SOFT)
	material.set_shader_parameter("edge_gain", SpellCastAuraProfile.EDGE_GAIN)
	material.set_shader_parameter("edge_power", SpellCastAuraProfile.EDGE_POWER)
	material.set_shader_parameter("base_white_mix", SpellCastAuraProfile.BASE_WHITE_MIX)
	material.set_shader_parameter("body_white_mix", SpellCastAuraProfile.BODY_WHITE_MIX)
	material.set_shader_parameter("rim_deepen", SpellCastAuraProfile.RIM_DEEPEN)
	material.set_shader_parameter(
		"body_gradient_end", SpellCastAuraProfile.BODY_GRADIENT_END
	)
	material.set_shader_parameter(
		"rim_gradient_start", SpellCastAuraProfile.RIM_GRADIENT_START
	)
	material.set_shader_parameter("emission_energy", SpellCastAuraProfile.EMISSION_ENERGY)
	material.set_shader_parameter(
		"seat_glow_height", SpellCastAuraProfile.SEAT_GLOW_HEIGHT
	)
	material.set_shader_parameter("eruption_start", SpellCastAuraProfile.ERUPTION_START)
	material.set_shader_parameter("eruption_span", SpellCastAuraProfile.ERUPTION_SPAN)
	material.set_shader_parameter(
		"stagger_span", SpellCastAuraProfile.ERUPTION_STAGGER_SPAN
	)
	material.set_shader_parameter("hold_end", SpellCastAuraProfile.HOLD_END)
	material.set_shader_parameter("decay_end", SpellCastAuraProfile.DECAY_END)
	material.set_shader_parameter(
		"overshoot_amount", SpellCastAuraProfile.OVERSHOOT_AMOUNT
	)
	material.set_shader_parameter("decay_stretch", SpellCastAuraProfile.DECAY_STRETCH)

	var instance := MeshInstance3D.new()
	instance.name = "RayShell"
	instance.mesh = _shellMesh
	instance.material_override = material
	instance.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	# The vertex stage reshapes the unit cylinder into the cone, so the mesh's
	# own bounds describe nothing the renderer can cull against.
	var reach := SpellCastAuraProfile.SHELL_RIM_RADIUS_U
	var top := SpellCastAuraProfile.SHELL_HEIGHT_U * (
		1.0 + SpellCastAuraProfile.DECAY_STRETCH
	)
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
