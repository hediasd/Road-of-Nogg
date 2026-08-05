## Deterministic, previewable area fire storm composed from procedural layers.
##
## Structurally a sibling of `IceStormEffect`: same `VfxPlayback` contract, same
## seed/scrub/dispose lifecycle, same build-time budget asserts. The two are
## separate files rather than a shared base because the profile constants are
## `const` on a class rather than an injectable resource, so there is no seam to
## subclass against. That is a recorded decision, not an oversight — see the
## plan that introduced this file. A third elemental storm is the point to
## revisit it.
##
## What differs from the ice storm: embers rise instead of flakes falling, the
## motion is a tapering vortex rather than a wind-driven field, there are two
## particle layers instead of one, and the frost-vein and hero-shard layers have
## no fire equivalent and are gone.

class_name FireStormEffect
extends "res://src/presentation/effects/VfxPlayback.gd"

const _VORTEX_SHADER = preload("res://assets/shaders/effects/fire_storm_vortex.gdshader")

const LAYER_GROUND_WASH := "ground_wash"
const LAYER_EMBER_COLUMN := "ember_column"
const LAYER_EMBER_MOTES := "ember_motes"
const LAYER_SMOKE_CROWN := "smoke_crown"
const LAYER_SWIRL := "swirl"
const LAYER_FLICKER := "flicker"

var _elapsedTime := 0.0
var _totalDuration := FireStormProfile.BATTLE_DURATION_SECONDS
var _playbackScale := 1.0
var _activeSeed := 1
var _mode := MODE_BATTLE
var _playing := false
var _finished := true
var _disposed := false
var _autoDispose := false
var _intensityScale := 1.0
var _footprintRadius := FireStormProfile.REFERENCE_CARRIER_RADIUS_TILES
var _groundSpan := 0.0
## Matches `Spell.area_shape` / `data/spells.json`'s `AREA_SHAPE`. Defaults to
## "circle", the same default `SpellReferences` normalizes onto every spell
## reference, which `ShapeCaster.getCircle` actually renders as a Manhattan
## diamond. See `_isDiamondShape()`.
var _areaShape := "circle"

var _groundWash: MeshInstance3D
var _groundMesh: CylinderMesh
var _groundMaterial: StandardMaterial3D
var _crownNodes: Array[MeshInstance3D] = []
var _crownMeshes: Array[QuadMesh] = []
var _crownMaterials: Array[StandardMaterial3D] = []
var _crownBasePositions: Array[Vector3] = []
var _crownPhases: Array[float] = []
var _emberColumn: GPUParticles3D
var _emberColumnMaterial: ShaderMaterial
var _emberMotes: GPUParticles3D
var _emberMotesMaterial: ShaderMaterial
var _layerVisibility := {
	LAYER_GROUND_WASH: true,
	LAYER_EMBER_COLUMN: true,
	LAYER_EMBER_MOTES: true,
	LAYER_SMOKE_CROWN: true,
	LAYER_SWIRL: true,
	LAYER_FLICKER: true,
}


static func spawn(
		parent: Node3D,
		worldPosition: Vector3,
		seed: int,
		mode: String = MODE_BATTLE) -> FireStormEffect:
	var playback := createPlayback(parent, worldPosition, Color.WHITE)
	playback._autoDispose = true
	playback.play(seed, mode)
	return playback


## `_elementColor` is accepted to satisfy the catalog's factory signature and
## deliberately ignored, exactly as `IceStormEffect` does: this profile owns its
## own palette, and tinting a fire storm by an arbitrary element colour would
## produce a fire-shaped effect in the wrong hue rather than a new element.
static func createPlayback(
		parent: Node3D,
		worldPosition: Vector3,
		_elementColor: Color) -> FireStormEffect:
	var playback := FireStormEffect.new()
	playback.name = "FireStormEffect"
	playback.position = worldPosition
	parent.add_child(playback)
	playback._buildLayers()
	return playback


func play(seed: int, mode: String) -> void:
	assert(not _disposed, "Cannot play a disposed FireStormEffect.")
	assert(mode == MODE_REFERENCE or mode == MODE_BATTLE, "Unknown VFX playback mode.")
	_activeSeed = seed
	_mode = mode
	_totalDuration = (
			FireStormProfile.REFERENCE_DURATION_SECONDS
			if mode == MODE_REFERENCE
			else FireStormProfile.BATTLE_DURATION_SECONDS)
	_elapsedTime = 0.0
	_finished = false
	_playing = true
	_configureSeed(seed)
	_updateVisuals(0.0)
	_restartEmittersAt(0.0)
	set_process(true)


func set_playback_scale(scale: float) -> void:
	_playbackScale = maxf(scale, 0.0)
	var emitterScale := _playbackScale if _playing else 0.0
	if _emberColumn != null:
		_emberColumn.speed_scale = emitterScale
	if _emberMotes != null:
		_emberMotes.speed_scale = emitterScale


func seek_normalized(time: float) -> void:
	if _disposed:
		return
	var normalizedTime := clampf(time, 0.0, 1.0)
	_elapsedTime = normalizedTime * _totalDuration
	_finished = normalizedTime >= 1.0
	_playing = not _finished
	_updateVisuals(normalizedTime)
	_restartEmittersAt(_elapsedTime)
	if _finished:
		_finishPlayback()


func skip_to_settle() -> void:
	seek_normalized(FireStormProfile.SETTLE_START_FRACTION)


func get_normalized_time() -> float:
	return clampf(_elapsedTime / maxf(_totalDuration, 0.001), 0.0, 1.0)


func get_elapsed_time() -> float:
	return _elapsedTime


func get_total_duration() -> float:
	return _totalDuration


func is_finished() -> bool:
	return _finished


func dispose() -> void:
	if _disposed:
		return
	_disposed = true
	_playing = false
	set_process(false)
	for emitter: GPUParticles3D in _liveEmitters():
		emitter.emitting = false
		emitter.speed_scale = 0.0
	if is_inside_tree() or get_parent() != null:
		queue_free()
	else:
		free()


func get_layer_names() -> Array[String]:
	return [
		LAYER_GROUND_WASH,
		LAYER_EMBER_COLUMN,
		LAYER_EMBER_MOTES,
		LAYER_SMOKE_CROWN,
		LAYER_SWIRL,
		LAYER_FLICKER,
	]


func set_layer_visible(layerName: String, visible: bool) -> void:
	if not _layerVisibility.has(layerName):
		push_warning("Unknown FireStormEffect layer: %s" % layerName)
		return
	_layerVisibility[layerName] = visible
	match layerName:
		LAYER_GROUND_WASH:
			_groundWash.visible = visible
		LAYER_EMBER_COLUMN:
			_emberColumn.visible = visible
		LAYER_EMBER_MOTES:
			_emberMotes.visible = visible
		LAYER_SMOKE_CROWN:
			for crown: MeshInstance3D in _crownNodes:
				crown.visible = visible
		LAYER_SWIRL, LAYER_FLICKER:
			_updateEmitterUniforms()
	_updateVisuals(get_normalized_time())


func get_live_particle_count() -> int:
	if _finished:
		return 0
	var density := 1.0 - _smoothstep(0.80, 0.96, get_normalized_time())
	var total := 0
	for emitter: GPUParticles3D in _liveEmitters():
		if emitter.visible:
			total += roundi(float(emitter.amount) * density)
	return total


func get_live_node_count() -> int:
	return 0 if _disposed else _countNodes(self)


func is_particle_seek_exact() -> bool:
	return true


func setIntensityScale(scale: float) -> void:
	_intensityScale = clampf(scale, 0.0, 1.0)
	_updateVisuals(get_normalized_time())


func getIntensityScale() -> float:
	return _intensityScale


func setFootprint(radius: int, groundSpan: float, areaShape: String = "circle") -> void:
	_footprintRadius = maxi(radius, 1)
	_groundSpan = maxf(groundSpan, 0.0)
	_areaShape = areaShape
	_updateFootprintGeometry()
	_configureSeed(_activeSeed)
	_updateVisuals(get_normalized_time())


func getFootprintRadius() -> int:
	return _footprintRadius


func getGroundSpan() -> float:
	return _groundSpan


func getDrawCallBudgetEstimate() -> int:
	return 1 + 2 + _crownNodes.size()


func _process(delta: float) -> void:
	if not _playing or _playbackScale <= 0.0:
		return
	_elapsedTime = minf(_elapsedTime + delta * _playbackScale, _totalDuration)
	_updateVisuals(get_normalized_time())
	if _elapsedTime >= _totalDuration:
		_finishPlayback()


func _finishPlayback() -> void:
	_finished = true
	_playing = false
	set_process(false)
	for emitter: GPUParticles3D in _liveEmitters():
		emitter.emitting = false
		emitter.speed_scale = 0.0
	if _autoDispose and not _disposed:
		call_deferred("dispose")


func _liveEmitters() -> Array[GPUParticles3D]:
	var emitters: Array[GPUParticles3D] = []
	if _emberColumn != null:
		emitters.append(_emberColumn)
	if _emberMotes != null:
		emitters.append(_emberMotes)
	return emitters


func _buildLayers() -> void:
	_buildGroundWash()
	_buildSmokeCrown()
	_buildEmitters()
	_updateFootprintGeometry()
	_configureSeed(_activeSeed)
	_updateVisuals(0.0)
	set_process(false)
	assert(get_live_node_count() <= FireStormProfile.MAX_EFFECT_NODES)
	assert(getDrawCallBudgetEstimate() <= FireStormProfile.MAX_DRAW_CALLS)
	assert(
			_emberColumn.amount + _emberMotes.amount
			<= FireStormProfile.MAX_LIVE_PARTICLES)


func _buildGroundWash() -> void:
	_groundWash = MeshInstance3D.new()
	_groundWash.name = "GroundWash"
	_groundMesh = CylinderMesh.new()
	_groundMesh.radial_segments = 32
	_groundMesh.rings = 1
	_groundWash.mesh = _groundMesh
	_groundMaterial = VfxTextures.groundWashMaterial().duplicate() as StandardMaterial3D
	_groundWash.material_override = _groundMaterial
	add_child(_groundWash)


func _buildSmokeCrown() -> void:
	for index: int in range(FireStormProfile.CROWN_QUAD_COUNT):
		var crown := MeshInstance3D.new()
		crown.name = "SmokeCrown%d" % index
		var mesh := QuadMesh.new()
		crown.mesh = mesh
		var material := VfxTextures.canopyMaterial().duplicate() as StandardMaterial3D
		material.billboard_mode = BaseMaterial3D.BILLBOARD_ENABLED
		crown.material_override = material
		_crownNodes.append(crown)
		_crownMeshes.append(mesh)
		_crownMaterials.append(material)
		_crownBasePositions.append(Vector3.ZERO)
		_crownPhases.append(0.0)
		add_child(crown)


func _buildEmitters() -> void:
	_emberColumn = _createEmitter(
			"EmberColumn", FireStormProfile.EMBER_COLUMN_PARTICLE_AMOUNT)
	_emberColumnMaterial = _emberColumn.process_material as ShaderMaterial
	_emberMotes = _createEmitter(
			"EmberMotes", FireStormProfile.EMBER_MOTE_PARTICLE_AMOUNT)
	_emberMotesMaterial = _emberMotes.process_material as ShaderMaterial


func _createEmitter(emitterName: String, amount: int) -> GPUParticles3D:
	var emitter := GPUParticles3D.new()
	emitter.name = emitterName
	emitter.amount = amount
	emitter.lifetime = 1.0
	emitter.preprocess = 1.0
	emitter.randomness = 0.0
	emitter.fixed_fps = 30
	emitter.interpolate = true
	emitter.fract_delta = true
	emitter.local_coords = true
	emitter.use_fixed_seed = true
	emitter.visibility_aabb = AABB(
			Vector3(-3.0, -0.2, -3.0),
			Vector3(6.0, FireStormProfile.COLUMN_HEIGHT_U + 0.6, 6.0))
	var shaderMaterial := ShaderMaterial.new()
	shaderMaterial.shader = _VORTEX_SHADER
	emitter.process_material = shaderMaterial
	var drawMesh := QuadMesh.new()
	drawMesh.size = Vector2.ONE
	var drawMaterial := VfxTextures.flurryMaterial().duplicate() as StandardMaterial3D
	# The shared flurry material is built ice-tinted, and `_createMaterial` sets
	# `vertex_color_use_as_albedo`, so its albedo would multiply against the
	# per-ember colour the vortex shader writes to COLOR and skew the whole
	# hot-to-cool gradient blue. Neutralising albedo and emission to white lets
	# the shader own the palette outright — which is the point of having a
	# per-particle gradient at all.
	drawMaterial.albedo_color = Color.WHITE
	drawMaterial.emission = Color.WHITE
	drawMaterial.billboard_mode = BaseMaterial3D.BILLBOARD_ENABLED
	drawMesh.material = drawMaterial
	emitter.draw_pass_1 = drawMesh
	add_child(emitter)
	return emitter


func _updateFootprintGeometry() -> void:
	if _groundMesh == null:
		return
	var diameter := float(_footprintRadius * 2 + 1)
	_groundMesh.top_radius = diameter * 0.5
	_groundMesh.bottom_radius = diameter * 0.5
	_groundMesh.height = maxf(_groundSpan + 0.06, 0.06)
	_groundWash.position.y = 0.0
	var groundTexture := VfxTextures.groundWash(
			VfxTextures.groundWashShapeFor(_areaShape), _footprintRadius)
	_groundMaterial.albedo_texture = groundTexture
	_groundMaterial.emission_texture = groundTexture
	for index: int in range(_crownMeshes.size()):
		_crownMeshes[index].size = Vector2(
				diameter * FireStormProfile.CROWN_WIDTH_SCALE,
				diameter * (0.30 + float(index) * 0.05))
	for emitter: GPUParticles3D in _liveEmitters():
		emitter.visibility_aabb = AABB(
				Vector3(-diameter * 0.7, -0.2, -diameter * 0.7),
				Vector3(
					diameter * 1.4,
					FireStormProfile.COLUMN_HEIGHT_U + 0.6,
					diameter * 1.4))
	_updateEmitterUniforms()


func _configureSeed(seed: int) -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = seed
	var diameter := float(_footprintRadius * 2 + 1)
	for index: int in range(_crownNodes.size()):
		_crownBasePositions[index] = Vector3(
				rng.randf_range(-diameter * 0.12, diameter * 0.12),
				rng.randf_range(
						FireStormProfile.CROWN_MIN_HEIGHT_U,
						FireStormProfile.CROWN_MAX_HEIGHT_U),
				rng.randf_range(-diameter * 0.08, diameter * 0.08))
		_crownPhases[index] = rng.randf_range(0.0, TAU)
	_updateEmitterUniforms()


func _updateVisuals(normalizedTime: float) -> void:
	if _groundMaterial == null:
		return
	var onset := _smoothstep(0.0, FireStormProfile.ONSET_FRACTION, normalizedTime)
	var pulse := _pulseAccent() if bool(_layerVisibility[LAYER_FLICKER]) else 0.0
	var pulseBrightness := lerpf(1.0, FireStormProfile.PULSE_BRIGHTNESS_MULTIPLIER, pulse)

	_setMaterialOpacity(
			_groundMaterial,
			FireStormProfile.GROUND_WASH_COLOR,
			onset * (1.0 - _smoothstep(0.80, 0.92, normalizedTime)))
	_groundMaterial.emission_energy_multiplier = pulseBrightness

	for index: int in range(_crownNodes.size()):
		var phase := _crownPhases[index]
		var breath := (
				1.0
				+ sin(normalizedTime * TAU + phase)
				* FireStormProfile.CROWN_SCALE_BREATH_FRACTION)
		var basePosition := _crownBasePositions[index]
		_crownNodes[index].position = basePosition + Vector3(
				sin(normalizedTime * TAU + phase) * FireStormProfile.CROWN_DRIFT_DISTANCE_U,
				0.0,
				cos(normalizedTime * TAU * 0.7 + phase)
				* FireStormProfile.CROWN_DRIFT_DISTANCE_U * 0.35)
		_crownNodes[index].scale = Vector3.ONE * breath
		# Smoke builds rather than appearing with the embers, so the crown fades
		# in later than `onset` and lingers past the ember die-off.
		var crownFade := (
				_smoothstep(0.10, 0.34, normalizedTime)
				* (1.0 - _smoothstep(0.88, 1.0, normalizedTime)))
		# Larger-index quads are the larger ones (see the size ramp in
		# `_updateFootprintGeometry`), so they carry more of the edge tint,
		# giving the plume a core-to-edge falloff instead of one flat value.
		var edgeAmount := float(index) / float(maxi(_crownNodes.size() - 1, 1))
		var crownColor := FireStormProfile.SMOKE_CROWN_CORE_COLOR.lerp(
				FireStormProfile.SMOKE_CROWN_EDGE_COLOR, edgeAmount)
		_setMaterialOpacity(_crownMaterials[index], crownColor, crownFade)

	_updateEmitterUniforms()


func _setMaterialOpacity(
		material: StandardMaterial3D,
		baseColor: Color,
		visibility: float) -> void:
	var color := baseColor
	color.a *= clampf(visibility * _intensityScale, 0.0, 1.0)
	material.albedo_color = color
	# `VfxTextures._createMaterial` bakes `emission` once from the material's
	# construction-time colour and never revisits it, so a caller varying
	# `baseColor` per call (the crown's core-to-edge lerp) would otherwise see
	# the tint only in unlit albedo, not in the additive glow that actually
	# reads as brightness.
	material.emission = Color(baseColor.r, baseColor.g, baseColor.b, 1.0)


func _pulseAccent() -> float:
	var interval := (
			FireStormProfile.REFERENCE_PULSE_INTERVAL_SECONDS
			if _mode == MODE_REFERENCE
			else FireStormProfile.BATTLE_PULSE_INTERVAL_SECONDS)
	var phase := fposmod(_elapsedTime, interval) / interval
	return 1.0 - _smoothstep(0.0, FireStormProfile.PULSE_ACCENT_FRACTION, phase)


func _restartEmittersAt(elapsed: float) -> void:
	_updateEmitterUniforms()
	for emitter: GPUParticles3D in _liveEmitters():
		emitter.speed_scale = 0.0
		emitter.use_fixed_seed = true
		emitter.seed = _activeSeed
		emitter.emitting = true
		emitter.restart(true)
		if elapsed > 0.0:
			emitter.request_particles_process(minf(elapsed, _totalDuration))
		if _finished:
			emitter.emitting = false
		emitter.speed_scale = _playbackScale if _playing else 0.0


func _updateEmitterUniforms() -> void:
	if _emberColumnMaterial == null or _emberMotesMaterial == null:
		return
	_applyEmitterUniforms(
			_emberColumnMaterial,
			FireStormProfile.EMBER_MIN_SIZE_U,
			FireStormProfile.EMBER_MAX_SIZE_U,
			FireStormProfile.EMBER_MIN_RISE_SPEED,
			FireStormProfile.EMBER_MAX_RISE_SPEED,
			FireStormProfile.BASE_RADIUS_FRACTION,
			FireStormProfile.FLICKER_RATE)
	_applyEmitterUniforms(
			_emberMotesMaterial,
			FireStormProfile.MOTE_MIN_SIZE_U,
			FireStormProfile.MOTE_MAX_SIZE_U,
			FireStormProfile.MOTE_MIN_RISE_SPEED,
			FireStormProfile.MOTE_MAX_RISE_SPEED,
			FireStormProfile.MOTE_BASE_RADIUS_FRACTION,
			FireStormProfile.MOTE_FLICKER_RATE)


## The two emitters share one shader and differ only in the six values passed
## here, so the depth layer cannot silently drift out of step with the column
## on anything else.
func _applyEmitterUniforms(
		material: ShaderMaterial,
		minScale: float,
		maxScale: float,
		minRiseSpeed: float,
		maxRiseSpeed: float,
		baseRadiusFraction: float,
		flickerRate: float) -> void:
	# radius_tiles + 0.5, matching the ground wash cylinder's own radius so the
	# column's boundary and the wash's edge agree.
	var footprintRadiusU := float(_footprintRadius) + 0.5
	material.set_shader_parameter("playback_time", _elapsedTime)
	material.set_shader_parameter("total_duration", _totalDuration)
	material.set_shader_parameter("footprint_radius_u", footprintRadiusU)
	material.set_shader_parameter("column_height", FireStormProfile.COLUMN_HEIGHT_U)
	material.set_shader_parameter("base_radius_fraction", baseRadiusFraction)
	material.set_shader_parameter("crown_taper", FireStormProfile.CROWN_TAPER)
	material.set_shader_parameter("swirl_base", FireStormProfile.SWIRL_BASE)
	material.set_shader_parameter("swirl_crown", FireStormProfile.SWIRL_CROWN)
	material.set_shader_parameter("swirl_speed", FireStormProfile.SWIRL_SPEED)
	material.set_shader_parameter("min_rise_speed", minRiseSpeed)
	material.set_shader_parameter("max_rise_speed", maxRiseSpeed)
	material.set_shader_parameter("min_scale", minScale)
	material.set_shader_parameter("max_scale", maxScale)
	material.set_shader_parameter("ember_shrink", FireStormProfile.EMBER_SHRINK)
	material.set_shader_parameter("flicker_rate", flickerRate)
	material.set_shader_parameter("flicker_depth", FireStormProfile.FLICKER_DEPTH)
	material.set_shader_parameter("lean_offset", FireStormProfile.LEAN_OFFSET)
	material.set_shader_parameter("onset_fraction", FireStormProfile.ONSET_FRACTION)
	material.set_shader_parameter("intensity_scale", _intensityScale)
	material.set_shader_parameter(
			"swirl_enabled", 1.0 if bool(_layerVisibility[LAYER_SWIRL]) else 0.0)
	material.set_shader_parameter(
			"flicker_enabled", 1.0 if bool(_layerVisibility[LAYER_FLICKER]) else 0.0)
	material.set_shader_parameter(
			"diamond_shape", 1.0 if _isDiamondShape(_areaShape) else 0.0)
	material.set_shader_parameter("vfx_seed", float(_activeSeed))
	material.set_shader_parameter("ember_alpha", FireStormProfile.EMBER_ALPHA)
	material.set_shader_parameter("ember_hot_color", FireStormProfile.EMBER_HOT_COLOR)
	material.set_shader_parameter("ember_mid_color", FireStormProfile.EMBER_MID_COLOR)
	material.set_shader_parameter("ember_cool_color", FireStormProfile.EMBER_COOL_COLOR)


static func _smoothstep(edge0: float, edge1: float, value: float) -> float:
	if edge1 <= edge0:
		return 1.0 if value >= edge1 else 0.0
	var amount := clampf((value - edge0) / (edge1 - edge0), 0.0, 1.0)
	return amount * amount * (3.0 - 2.0 * amount)


## Mirrors `CombatResolver._spellAffectedPositions`'s own shape match: only
## `cross` and `line` are special-cased there, and everything else — including
## `circle` and any unrecognized value — falls through to `ShapeCaster.getCircle`,
## which is a Manhattan diamond, not a Euclidean circle. For `cross`/`line` the
## vortex falls back to the inscribed circle, which under-claims rather than
## over-claims the footprint; the ground wash carries the true shape.
static func _isDiamondShape(areaShape: String) -> bool:
	return areaShape != "cross" and areaShape != "line"


static func _countNodes(node: Node) -> int:
	var count := 1
	for child: Node in node.get_children():
		count += _countNodes(child)
	return count
