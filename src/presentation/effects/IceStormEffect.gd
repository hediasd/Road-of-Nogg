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
## MEASURED acceptance cap from S1/S2 (see `IceStormProfile`'s provenance
## rule): hero silhouettes remain individually countable at this count. This
## constant, together with the `spawn` schedule in `_configureSeed()` below,
## is the authoritative shard count and timing — no separate rate constant
## drives it, so there is nothing else to keep in sync when tuning either.
const _SHARD_COUNT := 8
const _SHARDS_PER_VARIANT := 2

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
		_elementColor: Color) -> IceStormEffect:
	var playback := IceStormEffect.new()
	playback.name = "IceStormEffect"
	playback.position = worldPosition
	parent.add_child(playback)
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
	var density := 1.0 - _smoothstep(0.84, 0.95, get_normalized_time())
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
	_frostVeins.position = Vector3(0.0, IceStormProfile.STORM_VOLUME_HEIGHT_U * 0.48, -0.35)
	add_child(_frostVeins)


func _buildCanopy() -> void:
	for index: int in range(IceStormProfile.CANOPY_QUAD_COUNT):
		var canopy := MeshInstance3D.new()
		canopy.name = "Canopy%d" % index
		var mesh := QuadMesh.new()
		canopy.mesh = mesh
		var material := VfxTextures.canopyMaterial().duplicate() as StandardMaterial3D
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
	_flurry.amount = IceStormProfile.FLURRY_PARTICLE_AMOUNT
	_flurry.lifetime = 1.0
	_flurry.preprocess = 1.0
	_flurry.randomness = 0.0
	_flurry.fixed_fps = 30
	_flurry.interpolate = true
	_flurry.fract_delta = true
	_flurry.local_coords = true
	_flurry.use_fixed_seed = true
	_flurry.visibility_aabb = AABB(Vector3(-3.0, -0.2, -3.0), Vector3(6.0, 4.2, 6.0))
	_flurryShaderMaterial = ShaderMaterial.new()
	_flurryShaderMaterial.shader = _FLURRY_SHADER
	_flurry.process_material = _flurryShaderMaterial
	var drawMesh := QuadMesh.new()
	drawMesh.size = Vector2.ONE
	var drawMaterial := VfxTextures.flurryMaterial().duplicate() as StandardMaterial3D
	drawMaterial.billboard_mode = BaseMaterial3D.BILLBOARD_ENABLED
	drawMesh.material = drawMaterial
	_flurry.draw_pass_1 = drawMesh
	add_child(_flurry)


func _buildHeroShards() -> void:
	for variant: int in range(4):
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
		multiMesh.instance_count = _SHARDS_PER_VARIANT
		multiMesh.mesh = quad
		shardNode.multimesh = multiMesh
		_shardNodes.append(shardNode)
		add_child(shardNode)
		for slot: int in range(_SHARDS_PER_VARIANT):
			_hideShardInstance(shardNode, slot)


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
	_frostVeinMesh.size = Vector2(diameter, IceStormProfile.STORM_VOLUME_HEIGHT_U)
	for index: int in range(_canopyMeshes.size()):
		_canopyMeshes[index].size = Vector2(
				diameter * IceStormProfile.CANOPY_WIDTH_SCALE,
				diameter * (0.34 + float(index) * 0.035))
	_flurry.visibility_aabb = AABB(
			Vector3(-diameter * 0.6, -0.2, -diameter * 0.6),
			Vector3(diameter * 1.2, IceStormProfile.STORM_VOLUME_HEIGHT_U + 0.4, diameter * 1.2))
	_updateFlurryUniforms()


func _configureSeed(seed: int) -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = seed
	var diameter := float(_footprintRadius * 2 + 1)
	for index: int in range(_canopyNodes.size()):
		_canopyBasePositions[index] = Vector3(
				rng.randf_range(-diameter * 0.16, diameter * 0.16),
				rng.randf_range(
						IceStormProfile.CANOPY_MIN_HEIGHT_U,
						IceStormProfile.CANOPY_MAX_HEIGHT_U),
				rng.randf_range(-diameter * 0.10, diameter * 0.10))
		_canopyPhases[index] = rng.randf_range(0.0, TAU)

	_shardData.clear()
	for index: int in range(_SHARD_COUNT):
		var variant := index % 4
		var slot := index / 4
		_shardData.append({
			"variant": variant,
			"slot": slot,
			"spawn": 0.05 + float(index) * 0.075,
			"start": Vector3(
				rng.randf_range(-diameter * 0.44, diameter * 0.44),
				rng.randf_range(2.9, IceStormProfile.STORM_VOLUME_HEIGHT_U),
				rng.randf_range(-diameter * 0.44, diameter * 0.44)),
			"size": rng.randf_range(
				IceStormProfile.HERO_SHARD_MIN_SIZE_U,
				IceStormProfile.HERO_SHARD_MAX_SIZE_U),
			"turns": rng.randf_range(
				IceStormProfile.HERO_SHARD_MIN_TURNS_PER_LIFETIME,
				IceStormProfile.HERO_SHARD_MAX_TURNS_PER_LIFETIME),
			"angle": rng.randf_range(0.0, TAU),
			"drift": rng.randf_range(0.70, 1.25),
			"blue": rng.randf() < 0.35,
		})
	_updateFlurryUniforms()


func _updateVisuals(normalizedTime: float) -> void:
	if _groundMaterial == null:
		return
	var onset := _smoothstep(0.0, IceStormProfile.ONSET_FRACTION, normalizedTime)
	var pulse := _pulseAccent() if bool(_layerVisibility[LAYER_PULSE_ACCENTS]) else 0.0
	var pulseBrightness := lerpf(1.0, IceStormProfile.PULSE_BRIGHTNESS_MULTIPLIER, pulse)

	_setMaterialOpacity(
			_groundMaterial,
			IceStormProfile.GROUND_WASH_COLOR,
			onset * (1.0 - _smoothstep(0.82, 0.92, normalizedTime)))
	_setMaterialOpacity(
			_frostVeinMaterial,
			IceStormProfile.VEIN_COLOR,
			onset * (1.0 - _smoothstep(0.86, 0.96, normalizedTime)))
	_frostVeinMaterial.emission_energy_multiplier = pulseBrightness

	for index: int in range(_canopyNodes.size()):
		var phase := _canopyPhases[index]
		var breath := 1.0 + sin(normalizedTime * TAU + phase) * IceStormProfile.CANOPY_SCALE_BREATH_FRACTION
		var basePosition := _canopyBasePositions[index]
		_canopyNodes[index].position = basePosition + Vector3(
				sin(normalizedTime * TAU + phase) * IceStormProfile.CANOPY_DRIFT_DISTANCE_U,
				0.0,
				cos(normalizedTime * TAU * 0.7 + phase) * IceStormProfile.CANOPY_DRIFT_DISTANCE_U * 0.35)
		_canopyNodes[index].scale = Vector3.ONE * breath
		var canopyFade := onset * (1.0 - _smoothstep(0.91, 1.0, normalizedTime))
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
				-3.2 * life,
				gust.y * float(shard["drift"]) * life)
		var angle := float(shard["angle"]) + life * float(shard["turns"]) * TAU
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
	var interval := (
			IceStormProfile.REFERENCE_PULSE_INTERVAL_SECONDS
			if _mode == MODE_REFERENCE
			else IceStormProfile.BATTLE_PULSE_INTERVAL_SECONDS)
	_flurryShaderMaterial.set_shader_parameter("playback_time", _elapsedTime)
	_flurryShaderMaterial.set_shader_parameter("total_duration", _totalDuration)
	_flurryShaderMaterial.set_shader_parameter("footprint_width", diameter)
	_flurryShaderMaterial.set_shader_parameter("storm_height", IceStormProfile.STORM_VOLUME_HEIGHT_U)
	_flurryShaderMaterial.set_shader_parameter("lateral_speed", IceStormProfile.FLAKE_LATERAL_SPEED_U_PER_SECOND)
	_flurryShaderMaterial.set_shader_parameter("min_down_speed", IceStormProfile.FLAKE_MIN_DOWN_SPEED_U_PER_SECOND)
	_flurryShaderMaterial.set_shader_parameter("max_down_speed", IceStormProfile.FLAKE_MAX_DOWN_SPEED_U_PER_SECOND)
	_flurryShaderMaterial.set_shader_parameter("min_scale", IceStormProfile.FLAKE_MIN_SIZE_U)
	_flurryShaderMaterial.set_shader_parameter("max_scale", IceStormProfile.FLAKE_MAX_SIZE_U)
	_flurryShaderMaterial.set_shader_parameter("gust_direction", IceStormProfile.GUST_DIRECTION_XZ)
	_flurryShaderMaterial.set_shader_parameter("gust_band_period", IceStormProfile.GUST_BAND_PERIOD_SECONDS)
	_flurryShaderMaterial.set_shader_parameter("gust_band_width", IceStormProfile.GUST_BAND_WIDTH_FRACTION)
	_flurryShaderMaterial.set_shader_parameter("pulse_interval", interval)
	_flurryShaderMaterial.set_shader_parameter("pulse_window_fraction", IceStormProfile.PULSE_ACCENT_FRACTION)
	_flurryShaderMaterial.set_shader_parameter("onset_fraction", IceStormProfile.ONSET_FRACTION)
	_flurryShaderMaterial.set_shader_parameter("intensity_scale", _intensityScale)
	_flurryShaderMaterial.set_shader_parameter("gust_enabled", 1.0 if bool(_layerVisibility[LAYER_GUST]) else 0.0)
	_flurryShaderMaterial.set_shader_parameter(
			"pulse_enabled",
			1.0 if bool(_layerVisibility[LAYER_PULSE_ACCENTS]) else 0.0)
	_flurryShaderMaterial.set_shader_parameter("vfx_seed", float(_activeSeed))
	_flurryShaderMaterial.set_shader_parameter(
			"diamond_shape", 1.0 if _isDiamondShape(_areaShape) else 0.0)
	_flurryShaderMaterial.set_shader_parameter("flake_color", IceStormProfile.FLAKE_COLOR)


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