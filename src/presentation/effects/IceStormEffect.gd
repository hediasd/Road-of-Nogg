## Deterministic, previewable area ice storm composed from procedural layers.

class_name IceStormEffect
extends "res://src/presentation/effects/VfxPlayback.gd"

const _FLURRY_SHADER = preload("res://assets/shaders/effects/ice_storm_flurry.gdshader")

const LAYER_GROUND_WASH := "ground_wash"
const LAYER_FROST_VEINS := "frost_veins"
const LAYER_CANOPY := "canopy"
const LAYER_FLURRY := "flurry"
const LAYER_GUST := "gust"
const LAYER_HERO_SHARDS := "hero_shards"
const LAYER_PULSE_ACCENTS := "pulse_accents"

var _elapsedTime := 0.0
var _totalDuration := IceStormProfile.BATTLE_DURATION_SECONDS
var _playbackScale := 1.0
var _activeSeed := 1
var _mode := MODE_BATTLE
var _playing := false
var _finished := true
var _disposed := false
var _autoDispose := false
var _intensityScale := 1.0
var _footprintRadius := IceStormProfile.REFERENCE_CARRIER_RADIUS_TILES
var _groundSpan := 0.0
## Matches `Spell.area_shape` / `data/spells.json`'s `AREA_SHAPE`. Defaults to
## "circle", the same default `SpellReferences` normalizes onto every spell
## reference, which `ShapeCaster.getCircle` actually renders as a Manhattan
## diamond. See `_isDiamondShape()`.
var _areaShape := "circle"

var _groundWash: MeshInstance3D
var _groundMesh: CylinderMesh
var _groundMaterial: StandardMaterial3D
var _frostVeins: MeshInstance3D
var _frostVeinMesh: QuadMesh
var _frostVeinMaterial: StandardMaterial3D
var _canopyNodes: Array[MeshInstance3D] = []
var _canopyMeshes: Array[QuadMesh] = []
var _canopyMaterials: Array[StandardMaterial3D] = []
var _canopyBasePositions: Array[Vector3] = []
var _canopyPhases: Array[float] = []
var _flurry: GPUParticles3D
var _flurryShaderMaterial: ShaderMaterial
var _shardNodes: Array[MultiMeshInstance3D] = []
var _shardData: Array[Dictionary] = []
var _layerVisibility := {
	LAYER_GROUND_WASH: true,
	LAYER_FROST_VEINS: true,
	LAYER_CANOPY: true,
	LAYER_FLURRY: true,
	LAYER_GUST: true,
	LAYER_HERO_SHARDS: true,
	LAYER_PULSE_ACCENTS: true,
}


static func spawn(
		parent: Node3D,
		worldPosition: Vector3,
		seed: int,
		mode: String = MODE_BATTLE) -> IceStormEffect:
	var playback := createPlayback(parent, worldPosition, Color.WHITE)
	playback._autoDispose = true
	playback.play(seed, mode)
	return playback


static func createPlayback(
		parent: Node3D,
		worldPosition: Vector3,
		_elementColor: Color,
		overrides: Dictionary = {}) -> IceStormEffect:
	var playback := IceStormEffect.new()
	playback.name = "IceStormEffect"
	playback.position = worldPosition
	parent.add_child(playback)
	# Before the build below: geometry and shader uniforms are assembled there,
	# so an override arriving afterwards changes nothing.
	playback.set_tunable_overrides(overrides)
	playback._buildLayers()
	return playback


func play(seed: int, mode: String) -> void:
	assert(not _disposed, "Cannot play a disposed IceStormEffect.")
	assert(mode == MODE_REFERENCE or mode == MODE_BATTLE, "Unknown VFX playback mode.")
	_activeSeed = seed
	_mode = mode
	_totalDuration = (
			IceStormProfile.REFERENCE_DURATION_SECONDS
			if mode == MODE_REFERENCE
			else IceStormProfile.BATTLE_DURATION_SECONDS)
	_elapsedTime = 0.0
	_finished = false
	_playing = true
	_configureSeed(seed)
	_updateVisuals(0.0)
	_restartFlurryAt(0.0)
	set_process(true)


func set_playback_scale(scale: float) -> void:
	_playbackScale = maxf(scale, 0.0)
	if _flurry != null:
		_flurry.speed_scale = _playbackScale if _playing else 0.0


func seek_normalized(time: float) -> void:
	if _disposed:
		return
	var normalizedTime := clampf(time, 0.0, 1.0)
	_elapsedTime = normalizedTime * _totalDuration
	_finished = normalizedTime >= 1.0
	_playing = not _finished
	_updateVisuals(normalizedTime)
	_restartFlurryAt(_elapsedTime)
	if _finished:
		_finishPlayback()


func skip_to_settle() -> void:
	seek_normalized(IceStormProfile.SETTLE_START_FRACTION)


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
	if _flurry != null:
		_flurry.emitting = false
		_flurry.speed_scale = 0.0
	if is_inside_tree() or get_parent() != null:
		queue_free()
	else:
		free()


func get_layer_names() -> Array[String]:
	return [
		LAYER_GROUND_WASH,
		LAYER_FROST_VEINS,
		LAYER_CANOPY,
		LAYER_FLURRY,
		LAYER_GUST,
		LAYER_HERO_SHARDS,
		LAYER_PULSE_ACCENTS,
	]


func set_layer_visible(layerName: String, visible: bool) -> void:
	if not _layerVisibility.has(layerName):
		push_warning("Unknown IceStormEffect layer: %s" % layerName)
		return
	_layerVisibility[layerName] = visible
	match layerName:
		LAYER_GROUND_WASH:
			_groundWash.visible = visible
		LAYER_FROST_VEINS:
			_frostVeins.visible = visible
		LAYER_CANOPY:
			for canopy: MeshInstance3D in _canopyNodes:
				canopy.visible = visible
		LAYER_FLURRY:
			_flurry.visible = visible
		LAYER_HERO_SHARDS:
			for shardNode: MultiMeshInstance3D in _shardNodes:
				shardNode.visible = visible
		LAYER_GUST, LAYER_PULSE_ACCENTS:
			_updateFlurryUniforms()
	_updateVisuals(get_normalized_time())


func get_live_particle_count() -> int:
	if _flurry == null or not _flurry.visible or _finished:
		return 0
	var density := _exponentialSettle(get_normalized_time())
	return roundi(float(_flurry.amount) * density)


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


func getLiveShardCount() -> int:
	var count := 0
	var normalizedTime := get_normalized_time()
	for shard: Dictionary in _shardData:
		if _shardLife(shard, normalizedTime) >= 0.0:
			count += 1
	return count


func getDrawCallBudgetEstimate() -> int:
	return 1 + 1 + _canopyNodes.size() + 1 + _shardNodes.size()


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
	if _flurry != null:
		_flurry.emitting = false
		_flurry.speed_scale = 0.0
	if _autoDispose and not _disposed:
		call_deferred("dispose")


func _buildLayers() -> void:
	_buildGroundWash()
	_buildFrostVeins()
	_buildCanopy()
	_buildFlurry()
	_buildHeroShards()
	_updateFootprintGeometry()
	_configureSeed(_activeSeed)
	_updateVisuals(0.0)
	set_process(false)
	assert(get_live_node_count() <= IceStormProfile.MAX_EFFECT_NODES)
	assert(getDrawCallBudgetEstimate() <= IceStormProfile.MAX_DRAW_CALLS)
	assert(_flurry.amount <= IceStormProfile.MAX_LIVE_PARTICLES)


func _buildGroundWash() -> void:
	_groundWash = MeshInstance3D.new()
	_groundWash.name = "GroundWash"
	_groundMesh = CylinderMesh.new()
	_groundMesh.radial_segments = 32
	_groundMesh.rings = 1
	_groundWash.mesh = _groundMesh
	_groundMaterial = VfxTextures.groundWashMaterial().duplicate() as StandardMaterial3D
	_groundMaterial.texture_filter = BaseMaterial3D.TEXTURE_FILTER_NEAREST
	_groundWash.material_override = _groundMaterial
	add_child(_groundWash)


func _buildFrostVeins() -> void:
	_frostVeins = MeshInstance3D.new()
	_frostVeins.name = "FrostVeins"
	_frostVeinMesh = QuadMesh.new()
	_frostVeins.mesh = _frostVeinMesh
	_frostVeinMaterial = VfxTextures.frostVeinMaterial().duplicate() as StandardMaterial3D
	_frostVeinMaterial.billboard_mode = BaseMaterial3D.BILLBOARD_ENABLED
	_frostVeins.material_override = _frostVeinMaterial
	_frostVeins.position = Vector3(0.0, _stormHeight() * 0.48, -0.35)
	add_child(_frostVeins)


func _buildCanopy() -> void:
	for index: int in range(IceStormProfile.CANOPY_QUAD_COUNT):
		var canopy := MeshInstance3D.new()
		canopy.name = "Canopy%d" % index
		var mesh := QuadMesh.new()
		canopy.mesh = mesh
		var material := VfxTextures.iceCanopyMaterial().duplicate() as StandardMaterial3D
		material.billboard_mode = BaseMaterial3D.BILLBOARD_ENABLED
		canopy.material_override = material
		_canopyNodes.append(canopy)
		_canopyMeshes.append(mesh)
		_canopyMaterials.append(material)
		_canopyBasePositions.append(Vector3.ZERO)
		_canopyPhases.append(0.0)
		add_child(canopy)


func _buildFlurry() -> void:
	_flurry = GPUParticles3D.new()
	_flurry.name = "Flurry"
	_flurry.amount = _scaledFlurryCount()
	_flurry.lifetime = 1.0
	_flurry.preprocess = 1.0
	_flurry.randomness = 0.0
	_flurry.fixed_fps = int(IceStormProfile.TEMPORAL_SAMPLE_RATE_HZ)
	_flurry.interpolate = false
	_flurry.fract_delta = false
	_flurry.local_coords = true
	_flurry.use_fixed_seed = true
	_flurry.visibility_aabb = AABB(Vector3(-3.0, -0.2, -3.0), Vector3(6.0, 4.2, 6.0))
	_flurryShaderMaterial = ShaderMaterial.new()
	_flurryShaderMaterial.shader = _FLURRY_SHADER
	_flurry.process_material = _flurryShaderMaterial
	var drawMesh := QuadMesh.new()
	drawMesh.size = Vector2.ONE
	var drawMaterial := VfxTextures.snowParticleFramesMaterial().duplicate() as StandardMaterial3D
	drawMaterial.billboard_mode = BaseMaterial3D.BILLBOARD_PARTICLES
	drawMesh.material = drawMaterial
	_flurry.draw_pass_1 = drawMesh
	add_child(_flurry)


func _buildHeroShards() -> void:
	for variant: int in range(IceStormProfile.HERO_SHARD_VARIANT_COUNT):
		var shardNode := MultiMeshInstance3D.new()
		shardNode.name = "HeroShards%d" % variant
		var quad := QuadMesh.new()
		quad.size = Vector2.ONE
		var material := VfxTextures.heroShardMaterial(variant).duplicate() as StandardMaterial3D
		material.billboard_mode = BaseMaterial3D.BILLBOARD_ENABLED
		quad.material = material
		var multiMesh := MultiMesh.new()
		multiMesh.transform_format = MultiMesh.TRANSFORM_3D
		multiMesh.use_colors = true
		multiMesh.instance_count = IceStormProfile.HERO_SHARDS_PER_VARIANT
		multiMesh.mesh = quad
		shardNode.multimesh = multiMesh
		_shardNodes.append(shardNode)
		add_child(shardNode)
		for slot: int in range(IceStormProfile.HERO_SHARDS_PER_VARIANT):
			_hideShardInstance(shardNode, slot)


func _updateFootprintGeometry() -> void:
	if _groundMesh == null:
		return
	var diameter := float(_footprintRadius * 2 + 1)
	var snowCeiling := _snowCeiling()
	_groundMesh.top_radius = diameter * 0.5
	_groundMesh.bottom_radius = diameter * 0.5
	_groundMesh.height = maxf(_groundSpan + 0.06, 0.06)
	_groundWash.position.y = 0.0
	var groundTexture := VfxTextures.groundWash(
			VfxTextures.groundWashShapeFor(_areaShape), _footprintRadius)
	_groundMaterial.albedo_texture = groundTexture
	_groundMaterial.emission_texture = groundTexture
	var frostHeight := snowCeiling * IceStormProfile.FROST_HEIGHT_FRACTION
	_frostVeinMesh.size = Vector2(diameter, frostHeight)
	_frostVeins.position = Vector3(0.0, frostHeight * 0.5, -0.35)
	for index: int in range(_canopyMeshes.size()):
		_canopyMeshes[index].size = Vector2(
				diameter * (
						IceStormProfile.CANOPY_WIDTH_MIN_SCALE
						+ float(index) * IceStormProfile.CANOPY_WIDTH_STEP_SCALE),
				_canopyHeight(index))
	_flurry.amount = _scaledFlurryCount()
	_flurry.visibility_aabb = AABB(
			Vector3(-diameter * 0.6, -0.2, -diameter * 0.6),
			Vector3(diameter * 1.2, _cloudTopHeight() + 0.4, diameter * 1.2))
	_updateFlurryUniforms()


func _configureSeed(seed: int) -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = seed
	var diameter := float(_footprintRadius * 2 + 1)
	var footprintRadiusU := diameter * 0.5
	var snowCeiling := _snowCeiling()
	var seedPhase := rng.randf_range(0.0, TAU)
	for index: int in range(_canopyNodes.size()):
		var canopyAngle := seedPhase + float(index) * IceStormProfile.GOLDEN_ANGLE_RADIANS
		var canopyProgress := sqrt(
				(float(index) + 0.5) / float(maxi(_canopyNodes.size(), 1)))
		var canopyBoundary := footprintRadiusU / maxf(
				absf(cos(canopyAngle)) + absf(sin(canopyAngle)), 0.001)
		var canopyOffset := (
				canopyBoundary
				* canopyProgress
				* IceStormProfile.CANOPY_SPREAD_FRACTION)
		var canopyHeight := _canopyHeight(index)
		_canopyBasePositions[index] = Vector3(
				cos(canopyAngle) * canopyOffset,
				snowCeiling
						+ canopyHeight * IceStormProfile.CANOPY_CENTER_ABOVE_SNOW_FRACTION
						+ rng.randf_range(
								-IceStormProfile.CANOPY_VERTICAL_JITTER_FRACTION,
								IceStormProfile.CANOPY_VERTICAL_JITTER_FRACTION) * canopyHeight,
				sin(canopyAngle) * canopyOffset)
		_canopyPhases[index] = rng.randf_range(0.0, TAU)

	_shardData.clear()
	var shardCount := _scaledShardCount()
	for index: int in range(shardCount):
		var variant := index % IceStormProfile.HERO_SHARD_VARIANT_COUNT
		var slot := floori(float(index) / float(IceStormProfile.HERO_SHARD_VARIANT_COUNT))
		var progress := (float(index) + 0.5) / float(shardCount)
		var angleJitter := rng.randf_range(
				-IceStormProfile.GOLDEN_ANGLE_JITTER_FRACTION,
				IceStormProfile.GOLDEN_ANGLE_JITTER_FRACTION)
		var angle := (
				seedPhase
				+ float(index) * IceStormProfile.GOLDEN_ANGLE_RADIANS
				+ angleJitter * IceStormProfile.GOLDEN_ANGLE_RADIANS)
		var boundary := footprintRadiusU / maxf(absf(cos(angle)) + absf(sin(angle)), 0.001)
		var radialDistance := boundary * sqrt(progress) * rng.randf_range(0.90, 1.0)
		_shardData.append({
			"variant": variant,
			"slot": slot,
			"spawn": lerpf(
					IceStormProfile.HERO_SHARD_SPAWN_START_FRACTION,
					IceStormProfile.HERO_SHARD_SPAWN_END_FRACTION,
					progress),
			"start": Vector3(
				cos(angle) * radialDistance,
				rng.randf_range(
						snowCeiling * IceStormProfile.HERO_SHARD_MIN_HEIGHT_FRACTION,
						snowCeiling * IceStormProfile.HERO_SHARD_MAX_HEIGHT_FRACTION),
				sin(angle) * radialDistance),
			"size": rng.randf_range(
				IceStormProfile.HERO_SHARD_MIN_SIZE_U,
				IceStormProfile.HERO_SHARD_MAX_SIZE_U),
			"turns": rng.randf_range(
				IceStormProfile.HERO_SHARD_MIN_TURNS_PER_LIFETIME,
				IceStormProfile.HERO_SHARD_MAX_TURNS_PER_LIFETIME),
			"angle": angle,
			"drift": rng.randf_range(
				IceStormProfile.HERO_SHARD_MIN_DRIFT_U,
				IceStormProfile.HERO_SHARD_MAX_DRIFT_U),
			"blue": rng.randf() < IceStormProfile.HERO_SHARD_BLUE_CHANCE,
		})
	_updateFlurryUniforms()


func _updateVisuals(normalizedTime: float) -> void:
	if _groundMaterial == null:
		return
	var charge := _exponentialRise(normalizedTime, 0.0)
	var canopyReveal := _exponentialRise(
			normalizedTime, IceStormProfile.CANOPY_REVEAL_START_FRACTION)
	var chargeAccent := 1.0 - 0.45 * _smoothstep(
			IceStormProfile.CHARGE_END_FRACTION,
			IceStormProfile.CANOPY_REVEAL_END_FRACTION,
			normalizedTime)
	var settle := _exponentialSettle(normalizedTime)
	var squallProgress := _smoothstep(
			IceStormProfile.SQUALL_START_FRACTION,
			IceStormProfile.SQUALL_FULL_FRACTION,
			normalizedTime)
	var groundRecess := 1.0 - IceStormProfile.GROUND_SQUALL_RECESS_FRACTION * squallProgress
	var frostRecess := 1.0 - IceStormProfile.FROST_SQUALL_RECESS_FRACTION * squallProgress
	var pulse := _pulseAccent() if bool(_layerVisibility[LAYER_PULSE_ACCENTS]) else 0.0
	var pulseBrightness := lerpf(1.0, IceStormProfile.PULSE_BRIGHTNESS_MULTIPLIER, pulse)
	var steppedTime := floorf(
			normalizedTime * _totalDuration * IceStormProfile.TEMPORAL_SAMPLE_RATE_HZ
			) / IceStormProfile.TEMPORAL_SAMPLE_RATE_HZ
	var driftDistance := (
			float(_footprintRadius * 2 + 1)
			* IceStormProfile.CANOPY_DRIFT_DISTANCE_FRACTION)

	_setMaterialOpacity(
			_groundMaterial,
			IceStormProfile.GROUND_WASH_COLOR,
			charge * groundRecess * settle)
	_setMaterialOpacity(
			_frostVeinMaterial,
			IceStormProfile.VEIN_COLOR,
			charge * chargeAccent * frostRecess * settle)
	_frostVeinMaterial.emission_energy_multiplier = pulseBrightness

	for index: int in range(_canopyNodes.size()):
		var phase := _canopyPhases[index]
		var breath := 1.0 + sin(steppedTime * TAU + phase) * IceStormProfile.CANOPY_SCALE_BREATH_FRACTION
		var basePosition := _canopyBasePositions[index]
		_canopyNodes[index].position = basePosition + Vector3(
				sin(steppedTime * TAU + phase) * driftDistance,
				0.0,
				cos(steppedTime * TAU * 0.75 + phase) * driftDistance * 0.35)
		_canopyNodes[index].scale = Vector3.ONE * breath
		var canopyRecess := 1.0 - IceStormProfile.CANOPY_SQUALL_RECESS_FRACTION * _smoothstep(
				IceStormProfile.SQUALL_START_FRACTION,
				IceStormProfile.SQUALL_FULL_FRACTION,
				normalizedTime)
		var canopyFade := canopyReveal * canopyRecess * settle
		# Larger-index quads are the larger ones (see the size ramp in
		# `_updateFootprintGeometry`), so they carry more of the edge tint —
		# index 0 stays pure core color, the largest quad leans toward the edge
		# color, giving the canopy a core-to-edge falloff instead of one flat tint.
		var edgeAmount := float(index) / float(maxi(_canopyNodes.size() - 1, 1))
		var canopyColor := IceStormProfile.CANOPY_CORE_COLOR.lerp(
				IceStormProfile.CANOPY_EDGE_COLOR, edgeAmount)
		_setMaterialOpacity(_canopyMaterials[index], canopyColor, canopyFade)
		_canopyMaterials[index].emission_energy_multiplier = pulseBrightness

	_updateHeroShards(normalizedTime)
	_updateFlurryUniforms()


func _updateHeroShards(normalizedTime: float) -> void:
	var snowCeiling := _snowCeiling()
	for shard: Dictionary in _shardData:
		var variant: int = shard["variant"]
		var slot: int = shard["slot"]
		var shardNode := _shardNodes[variant]
		var life := _shardLife(shard, normalizedTime)
		if life < 0.0:
			_hideShardInstance(shardNode, slot)
			continue
		var start: Vector3 = shard["start"]
		var gust := IceStormProfile.GUST_DIRECTION_XZ.normalized()
		var position := start + Vector3(
				gust.x * float(shard["drift"]) * life,
				-snowCeiling * IceStormProfile.HERO_SHARD_DOWN_DISTANCE_FRACTION * life,
				gust.y * float(shard["drift"]) * life)
		var angle := float(shard["angle"]) + life * float(shard["turns"]) * TAU
		angle = snappedf(angle, TAU / IceStormProfile.GUST_HEADING_STEPS)
		position.x = snappedf(position.x, IceStormProfile.POSITION_QUANTUM_U)
		position.y = snappedf(position.y, IceStormProfile.POSITION_QUANTUM_U)
		position.z = snappedf(position.z, IceStormProfile.POSITION_QUANTUM_U)
		var size: float = shard["size"]
		var basis := Basis(Vector3.FORWARD, angle).scaled(Vector3(size, size, 1.0))
		shardNode.multimesh.set_instance_transform(slot, Transform3D(basis, position))
		var color := (
				IceStormProfile.SHARD_BLUE_COLOR
				if bool(shard["blue"])
				else IceStormProfile.SHARD_WHITE_COLOR)
		var fade := _smoothstep(0.0, 0.10, life) * (1.0 - _smoothstep(0.72, 1.0, life))
		color.a *= fade
		shardNode.multimesh.set_instance_color(slot, color)


func _shardLife(shard: Dictionary, normalizedTime: float) -> float:
	var spawn: float = shard["spawn"]
	var lifetimeFraction := IceStormProfile.HERO_SHARD_LIFETIME_FRACTION
	if normalizedTime < spawn or normalizedTime >= spawn + lifetimeFraction:
		return -1.0
	return (normalizedTime - spawn) / lifetimeFraction


func _hideShardInstance(shardNode: MultiMeshInstance3D, slot: int) -> void:
	shardNode.multimesh.set_instance_transform(
			slot, Transform3D(Basis.IDENTITY.scaled(Vector3(0.001, 0.001, 0.001)), Vector3.ZERO))
	shardNode.multimesh.set_instance_color(slot, Color(1.0, 1.0, 1.0, 0.0))


func _setMaterialOpacity(
		material: StandardMaterial3D,
		baseColor: Color,
		visibility: float) -> void:
	var color := baseColor
	color.a *= clampf(visibility * _intensityScale, 0.0, 1.0)
	material.albedo_color = color
	# `VfxTextures._createMaterial` bakes `emission` once from the material's
	# original construction-time color and never revisits it, so a caller that
	# varies `baseColor` per call (the canopy's core-to-edge lerp) would
	# otherwise see the tint only in the unlit albedo, not in the additive glow
	# that actually reads as brightness. Every existing caller passes the same
	# constant color every frame, so this is a no-op for them.
	material.emission = Color(baseColor.r, baseColor.g, baseColor.b, 1.0)


func _pulseAccent() -> float:
	var interval := (
			IceStormProfile.REFERENCE_PULSE_INTERVAL_SECONDS
			if _mode == MODE_REFERENCE
			else IceStormProfile.BATTLE_PULSE_INTERVAL_SECONDS)
	var phase := fposmod(_elapsedTime, interval) / interval
	return 1.0 - _smoothstep(0.0, IceStormProfile.PULSE_ACCENT_FRACTION, phase)


func _restartFlurryAt(elapsed: float) -> void:
	if _flurry == null:
		return
	_updateFlurryUniforms()
	_flurry.speed_scale = 0.0
	_flurry.use_fixed_seed = true
	_flurry.seed = _activeSeed
	_flurry.emitting = true
	_flurry.restart(true)
	if elapsed > 0.0:
		_flurry.request_particles_process(minf(elapsed, _totalDuration))
	if _finished:
		_flurry.emitting = false
	_flurry.speed_scale = _playbackScale if _playing else 0.0


func _updateFlurryUniforms() -> void:
	if _flurryShaderMaterial == null:
		return
	var diameter := float(_footprintRadius * 2 + 1)
	var snowCeiling := _snowCeiling()
	var heightScale := snowCeiling / IceStormProfile.REFERENCE_STORM_HEIGHT_U
	var interval := (
			IceStormProfile.REFERENCE_PULSE_INTERVAL_SECONDS
			if _mode == MODE_REFERENCE
			else IceStormProfile.BATTLE_PULSE_INTERVAL_SECONDS)
	_flurryShaderMaterial.set_shader_parameter("playback_time", _elapsedTime)
	_flurryShaderMaterial.set_shader_parameter("total_duration", _totalDuration)
	_flurryShaderMaterial.set_shader_parameter("footprint_width", diameter)
	_flurryShaderMaterial.set_shader_parameter("particle_count", float(_flurry.amount))
	_flurryShaderMaterial.set_shader_parameter("storm_height", snowCeiling)
	_flurryShaderMaterial.set_shader_parameter("lateral_speed", IceStormProfile.FLAKE_LATERAL_SPEED_U_PER_SECOND)
	_flurryShaderMaterial.set_shader_parameter(
			"min_down_speed",
			IceStormProfile.FLAKE_MIN_DOWN_SPEED_U_PER_SECOND * heightScale)
	_flurryShaderMaterial.set_shader_parameter(
			"max_down_speed",
			IceStormProfile.FLAKE_MAX_DOWN_SPEED_U_PER_SECOND * heightScale)
	_flurryShaderMaterial.set_shader_parameter("min_scale", IceStormProfile.FLAKE_MIN_SIZE_U)
	_flurryShaderMaterial.set_shader_parameter("max_scale", IceStormProfile.FLAKE_MAX_SIZE_U)
	_flurryShaderMaterial.set_shader_parameter("gust_direction", IceStormProfile.GUST_DIRECTION_XZ)
	_flurryShaderMaterial.set_shader_parameter("gust_band_period", IceStormProfile.GUST_BAND_PERIOD_SECONDS)
	_flurryShaderMaterial.set_shader_parameter("gust_band_width", IceStormProfile.GUST_BAND_WIDTH_FRACTION)
	_flurryShaderMaterial.set_shader_parameter("pulse_interval", interval)
	_flurryShaderMaterial.set_shader_parameter("pulse_window_fraction", IceStormProfile.PULSE_ACCENT_FRACTION)
	_flurryShaderMaterial.set_shader_parameter("squall_start_fraction", IceStormProfile.SQUALL_START_FRACTION)
	_flurryShaderMaterial.set_shader_parameter(
			"energy_half_life_fraction",
			IceStormProfile.ENERGY_RISE_HALF_LIFE_FRACTION)
	_flurryShaderMaterial.set_shader_parameter("settle_start_fraction", IceStormProfile.SETTLE_START_FRACTION)
	_flurryShaderMaterial.set_shader_parameter(
			"settle_half_life_fraction",
			IceStormProfile.SETTLE_HALF_LIFE_FRACTION)
	_flurryShaderMaterial.set_shader_parameter("temporal_sample_rate", IceStormProfile.TEMPORAL_SAMPLE_RATE_HZ)
	_flurryShaderMaterial.set_shader_parameter("position_quantum", IceStormProfile.POSITION_QUANTUM_U)
	_flurryShaderMaterial.set_shader_parameter("heading_steps", IceStormProfile.GUST_HEADING_STEPS)
	_flurryShaderMaterial.set_shader_parameter("golden_angle", IceStormProfile.GOLDEN_ANGLE_RADIANS)
	_flurryShaderMaterial.set_shader_parameter(
			"golden_angle_jitter_fraction",
			IceStormProfile.GOLDEN_ANGLE_JITTER_FRACTION)
	_flurryShaderMaterial.set_shader_parameter("gust_min_density", IceStormProfile.GUST_MIN_DENSITY)
	_flurryShaderMaterial.set_shader_parameter("snow_tiny_weight", IceStormProfile.SNOW_TINY_WEIGHT)
	_flurryShaderMaterial.set_shader_parameter("snow_small_weight", IceStormProfile.SNOW_SMALL_WEIGHT)
	_flurryShaderMaterial.set_shader_parameter("snow_medium_weight", IceStormProfile.SNOW_MEDIUM_WEIGHT)
	_flurryShaderMaterial.set_shader_parameter("intensity_scale", _intensityScale)
	_flurryShaderMaterial.set_shader_parameter("gust_enabled", 1.0 if bool(_layerVisibility[LAYER_GUST]) else 0.0)
	_flurryShaderMaterial.set_shader_parameter(
			"pulse_enabled",
			1.0 if bool(_layerVisibility[LAYER_PULSE_ACCENTS]) else 0.0)
	_flurryShaderMaterial.set_shader_parameter("vfx_seed", float(_activeSeed))
	_flurryShaderMaterial.set_shader_parameter(
			"diamond_shape", 1.0 if _isDiamondShape(_areaShape) else 0.0)
	_flurryShaderMaterial.set_shader_parameter("flake_color", IceStormProfile.FLAKE_COLOR)


func _scaledFlurryCount() -> int:
	return clampi(
			roundi(float(IceStormProfile.FLURRY_REFERENCE_AMOUNT) * _populationScale()),
			IceStormProfile.FLURRY_MIN_AMOUNT,
			IceStormProfile.MAX_LIVE_PARTICLES)


func _scaledShardCount() -> int:
	return clampi(
			roundi(float(IceStormProfile.HERO_SHARD_REFERENCE_COUNT) * _populationScale()),
			IceStormProfile.HERO_SHARD_MIN_COUNT,
			IceStormProfile.HERO_SHARD_MAX_COUNT)


func _populationScale() -> float:
	var tileCount := 1.0 + 2.0 * float(_footprintRadius * (_footprintRadius + 1))
	return sqrt(tileCount / IceStormProfile.REFERENCE_DIAMOND_TILE_COUNT)


func _stormHeight() -> float:
	var radiusScale := pow(
			(float(_footprintRadius) + 0.5)
			/ (float(IceStormProfile.REFERENCE_CARRIER_RADIUS_TILES) + 0.5),
			IceStormProfile.STORM_HEIGHT_RADIUS_EXPONENT)
	return IceStormProfile.REFERENCE_STORM_HEIGHT_U * clampf(
			radiusScale,
			IceStormProfile.MIN_STORM_HEIGHT_SCALE,
			IceStormProfile.MAX_STORM_HEIGHT_SCALE)


func _snowCeiling() -> float:
	return _stormHeight()


func _canopyHeight(index: int) -> float:
	return _snowCeiling() * (
			IceStormProfile.CANOPY_HEIGHT_BASE_FRACTION
			+ float(index) * IceStormProfile.CANOPY_HEIGHT_STEP_FRACTION)


func _cloudTopHeight() -> float:
	var largestIndex := maxi(IceStormProfile.CANOPY_QUAD_COUNT - 1, 0)
	var canopyHeight := _canopyHeight(largestIndex)
	return (
			_snowCeiling()
			+ canopyHeight * (
					IceStormProfile.CANOPY_CENTER_ABOVE_SNOW_FRACTION
					+ IceStormProfile.CANOPY_VERTICAL_JITTER_FRACTION
					+ 0.5))


func _exponentialRise(normalizedTime: float, startFraction: float) -> float:
	if normalizedTime <= startFraction:
		return 0.0
	var elapsed := normalizedTime - startFraction
	return 1.0 - exp(
			-log(2.0) * elapsed
			/ maxf(IceStormProfile.ENERGY_RISE_HALF_LIFE_FRACTION, 0.001))


func _exponentialSettle(normalizedTime: float) -> float:
	if normalizedTime <= IceStormProfile.SETTLE_START_FRACTION:
		return 1.0
	return exp(
			-log(2.0)
			* (normalizedTime - IceStormProfile.SETTLE_START_FRACTION)
			/ maxf(IceStormProfile.SETTLE_HALF_LIFE_FRACTION, 0.001))


static func _smoothstep(edge0: float, edge1: float, value: float) -> float:
	if edge1 <= edge0:
		return 1.0 if value >= edge1 else 0.0
	var amount := clampf((value - edge0) / (edge1 - edge0), 0.0, 1.0)
	return amount * amount * (3.0 - 2.0 * amount)


## Mirrors `CombatResolver._spellAffectedPositions`'s own shape match: only
## `cross` and `line` are special-cased there, and everything else — including
## `circle` and any unrecognized value — falls through to `ShapeCaster.getCircle`,
## which is a Manhattan diamond, not a Euclidean circle. `cross`/`line` carriers
## keep the legacy square flurry field and disc wash; no carrier uses either
## with this profile today (tracked in `BACKLOG_LONGTERM.md`).
static func _isDiamondShape(areaShape: String) -> bool:
	return areaShape != "cross" and areaShape != "line"


static func _countNodes(node: Node) -> int:
	var count := 1
	for child: Node in node.get_children():
		count += _countNodes(child)
	return count
