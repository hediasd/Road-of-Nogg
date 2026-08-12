## Deterministic low-poly shell built around presentation-supplied body bounds.

class_name IceTargetEncasementEffect
extends "res://src/presentation/effects/VfxPlayback.gd"

const IceChunkMeshFactoryScript = preload(
	"res://src/presentation/effects/IceChunkMeshFactory.gd")
const _ICE_SHADER = preload(
	"res://assets/shaders/effects/ice_target_encasement.gdshader")

const LAYER_SHELL_REAR := "shell_rear"
const LAYER_SHELL_SIDES := "shell_sides"
const LAYER_SHELL_FRONT := "shell_front"
const LAYER_SHELL_CAP := "shell_cap"
const LAYER_ICE_CORE := "ice_core"
const LAYER_DELIVERY_TRAIL := "delivery_trail"
const LAYER_CONTACT_ACCENTS := "contact_accents"
const LAYER_IMPACT_FLASH := "impact_flash"

var _elapsedTime := 0.0
var _totalDuration := IceTargetEncasementProfile.BATTLE_DURATION_SECONDS
var _playbackScale := 1.0
var _activeSeed := 1
var _playing := false
var _finished := true
var _disposed := false
var _autoDispose := false
var _shellBuilt := false
var _context: VfxCastContext
var _layerNodes: Dictionary = {}
var _layerVisibility := {
	LAYER_SHELL_REAR: true,
	LAYER_SHELL_SIDES: true,
	LAYER_SHELL_FRONT: true,
	LAYER_SHELL_CAP: true,
	LAYER_ICE_CORE: true,
	LAYER_DELIVERY_TRAIL: true,
	LAYER_CONTACT_ACCENTS: true,
	LAYER_IMPACT_FLASH: true,
}
var _chunkRecords: Array[Dictionary] = []
var _intactTransforms: Array[Transform3D] = []
var _brokenTransforms: Array[Transform3D] = []
var _drawCallCount := 0
var _bodyCenter := Vector3.ZERO
var _core: MeshInstance3D
var _coreBaseScale := Vector3.ONE
var _trailMultiMesh: MultiMesh
var _trailSource := Vector3.ZERO
var _trailTarget := Vector3.ZERO
var _trailBasis := Basis.IDENTITY
var _contactMultiMesh: MultiMesh
var _contactRecords: Array[Dictionary] = []
var _impactFlash: MeshInstance3D
var _impactFlashMaterial: StandardMaterial3D
var _impactFlashBaseScale := Vector3.ONE


static func createPlayback(
		parent: Node3D,
		worldPosition: Vector3,
		_elementColor: Color) -> IceTargetEncasementEffect:
	var playback := IceTargetEncasementEffect.new()
	playback.name = "IceTargetEncasementEffect"
	playback.position = worldPosition
	parent.add_child(playback)
	return playback


func configure_cast_context(context: VfxCastContext) -> void:
	assert(not _shellBuilt, "Ice encasement context must be configured before play.")
	context.assert_valid()
	_context = context
	if not context.target_world_positions.is_empty():
		position = context.target_world_positions[0]
	else:
		position = context.impact_world_position


func play(seed: int, mode: String) -> void:
	assert(not _disposed, "Cannot play a disposed IceTargetEncasementEffect.")
	assert(mode == MODE_REFERENCE or mode == MODE_BATTLE, "Unknown VFX playback mode.")
	_activeSeed = seed
	_totalDuration = (
		IceTargetEncasementProfile.REFERENCE_DURATION_SECONDS
		if mode == MODE_REFERENCE
		else IceTargetEncasementProfile.BATTLE_DURATION_SECONDS
	)
	if not _shellBuilt:
		_buildShell(seed)
	_elapsedTime = 0.0
	_finished = false
	_playing = true
	_applyTimeline()
	set_process(true)


func set_playback_scale(scale: float) -> void:
	_playbackScale = maxf(scale, 0.0)


func seek_normalized(time: float) -> void:
	if _disposed:
		return
	var normalizedTime := clampf(time, 0.0, 1.0)
	_elapsedTime = normalizedTime * _totalDuration
	_finished = normalizedTime >= 1.0
	_playing = not _finished
	_applyTimeline()
	if _finished:
		_finishPlayback()


func skip_to_settle() -> void:
	seek_normalized(IceTargetEncasementProfile.SETTLE_START_FRACTION)


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
	if is_inside_tree() or get_parent() != null:
		queue_free()
	else:
		free()


func get_layer_names() -> Array[String]:
	return [
		LAYER_SHELL_REAR,
		LAYER_SHELL_SIDES,
		LAYER_SHELL_FRONT,
		LAYER_SHELL_CAP,
		LAYER_ICE_CORE,
		LAYER_DELIVERY_TRAIL,
		LAYER_CONTACT_ACCENTS,
		LAYER_IMPACT_FLASH,
	]


func set_layer_visible(layerName: String, visible: bool) -> void:
	if not _layerVisibility.has(layerName):
		push_warning("Unknown IceTargetEncasementEffect layer: %s" % layerName)
		return
	_layerVisibility[layerName] = visible
	var layer := _layerNodes.get(layerName) as Node3D
	if layer != null:
		layer.visible = visible


func get_live_particle_count() -> int:
	return 0


func get_live_instance_count() -> int:
	return (
		0
		if _disposed or not _shellBuilt
		else IceTargetEncasementProfile.TOTAL_GEOMETRY_INSTANCE_COUNT
	)


func get_live_node_count() -> int:
	return 0 if _disposed else _countNodes(self)


func is_particle_seek_exact() -> bool:
	return true


func get_intact_transforms() -> Array[Transform3D]:
	return _intactTransforms.duplicate()


func get_broken_transforms() -> Array[Transform3D]:
	return _brokenTransforms.duplicate()


func _process(delta: float) -> void:
	if not _playing or _playbackScale <= 0.0:
		return
	_elapsedTime = minf(_elapsedTime + delta * _playbackScale, _totalDuration)
	_applyTimeline()
	if _elapsedTime >= _totalDuration:
		_finishPlayback()


func _finishPlayback() -> void:
	_finished = true
	_playing = false
	set_process(false)
	if _autoDispose and not _disposed:
		call_deferred("dispose")


func _buildShell(seed: int) -> void:
	assert(not _shellBuilt, "Ice encasement shell may only be built once.")
	var bodyBounds := VfxCastContext.DEFAULT_TARGET_BODY_BOUNDS
	if _context != null and not _context.target_body_bounds.is_empty():
		bodyBounds = _context.target_body_bounds[0]
	assert(
		bodyBounds.size.x > 0.0 and bodyBounds.size.y > 0.0 and bodyBounds.size.z > 0.0,
		"Ice encasement requires positive target body bounds."
	)
	_bodyCenter = bodyBounds.get_center()
	_buildLayerNodes()
	var random := RandomNumberGenerator.new()
	random.seed = seed
	_buildChunkRecords(bodyBounds, random)
	_buildChunkInstances()
	_buildCore(bodyBounds)
	_buildDeliveryTrail()
	_buildContactAccents(bodyBounds, random)
	_buildImpactFlash(bodyBounds)
	_shellBuilt = true
	assert(
		_chunkRecords.size() == IceTargetEncasementProfile.CHUNK_COUNT,
		"Ice encasement authored chunk count drifted."
	)
	assert(
		_chunkRecords.size() <= IceTargetEncasementProfile.MAX_CHUNKS,
		"Ice encasement exceeded its chunk ceiling."
	)
	assert(
		IceTargetEncasementProfile.SUPPORTING_INSTANCE_COUNT
		<= IceTargetEncasementProfile.MAX_SUPPORTING_INSTANCES,
		"Ice encasement exceeded its supporting-instance ceiling."
	)
	assert(
		_chunkRecords.size()
		+ _trailMultiMesh.instance_count
		+ _contactMultiMesh.instance_count
		+ 1
		== IceTargetEncasementProfile.TOTAL_GEOMETRY_INSTANCE_COUNT,
		"Ice encasement geometry-instance accounting drifted."
	)
	assert(
		_countNodes(self) <= IceTargetEncasementProfile.MAX_EFFECT_NODES,
		"Ice encasement exceeded its node ceiling."
	)
	assert(
		_drawCallCount <= IceTargetEncasementProfile.MAX_DRAW_CALLS,
		"Ice encasement exceeded its draw-call ceiling."
	)


func _buildLayerNodes() -> void:
	for layerName: String in get_layer_names():
		var layer := Node3D.new()
		layer.name = layerName
		layer.visible = bool(_layerVisibility[layerName])
		add_child(layer)
		_layerNodes[layerName] = layer


func _buildChunkRecords(bounds: AABB, random: RandomNumberGenerator) -> void:
	var center := bounds.get_center()
	var width := bounds.size.x + IceTargetEncasementProfile.SHELL_CLEARANCE_U * 2.0
	var height := bounds.size.y + IceTargetEncasementProfile.SHELL_CLEARANCE_U * 2.0
	var depth := bounds.size.z + IceTargetEncasementProfile.SHELL_CLEARANCE_U * 2.0
	var thickness := maxf(
		IceTargetEncasementProfile.MIN_CHUNK_THICKNESS_U,
		minf(width, depth) * IceTargetEncasementProfile.THICKNESS_BODY_FRACTION
	)
	var jitterAmplitude := maxf(minf(width, minf(height, depth)), 0.4) * (
		IceTargetEncasementProfile.POSITION_JITTER_FRACTION
	)
	for authoredValue: Variant in IceTargetEncasementProfile.HERO_LAYOUT:
		var authored: Dictionary = authoredValue
		var layerName := String(authored["layer"])
		var positionFractions: Vector3 = authored["position"]
		var scaleFractions: Vector3 = authored["scale"]
		var rotation: Vector3 = authored["rotation"]
		var formationWindow: Vector2 = authored["formation"]
		var scale := Vector3.ZERO
		match layerName:
			LAYER_SHELL_REAR, LAYER_SHELL_FRONT:
				scale = Vector3(
					width * scaleFractions.x,
					height * scaleFractions.y,
					thickness * scaleFractions.z)
			LAYER_SHELL_SIDES:
				scale = Vector3(
					thickness * scaleFractions.x,
					height * scaleFractions.y,
					depth * scaleFractions.z)
			LAYER_SHELL_CAP:
				scale = Vector3(
					width * scaleFractions.x,
					thickness * scaleFractions.y,
					depth * scaleFractions.z)
			_:
				assert(false, "Unknown authored ice shell layer: %s" % layerName)
		_appendChunk(
			layerName,
			String(authored["role"]),
			int(authored["kind"]),
			center + Vector3(
				width * positionFractions.x,
				height * positionFractions.y,
				depth * positionFractions.z),
			scale,
			rotation,
			center,
			jitterAmplitude,
			formationWindow.x,
			formationWindow.y,
			random)


func _appendChunk(
		layerName: String,
		roleName: String,
		kind: int,
		basePosition: Vector3,
		baseScale: Vector3,
	baseRotation: Vector3,
	bodyCenter: Vector3,
	jitterAmplitude: float,
	formationStart: float,
	formationEnd: float,
	random: RandomNumberGenerator) -> void:
	var positionJitter := Vector3(
		random.randf_range(-jitterAmplitude, jitterAmplitude),
		random.randf_range(-jitterAmplitude, jitterAmplitude),
		random.randf_range(-jitterAmplitude, jitterAmplitude)
	)
	var rotationJitter := Vector3(
		random.randf_range(-1.0, 1.0),
		random.randf_range(-1.0, 1.0),
		random.randf_range(-1.0, 1.0)
	) * IceTargetEncasementProfile.ROTATION_JITTER_RADIANS
	var scaleJitter := random.randf_range(
		IceTargetEncasementProfile.SCALE_JITTER_MIN,
		IceTargetEncasementProfile.SCALE_JITTER_MAX
	)
	var intactPosition := basePosition + positionJitter
	var intactRotation := baseRotation + rotationJitter
	var intactScale := baseScale * scaleJitter
	var intact := Transform3D(Basis.from_euler(intactRotation).scaled(intactScale), intactPosition)
	var formationPosition := bodyCenter.lerp(
		intactPosition, IceTargetEncasementProfile.FORMATION_INWARD_FRACTION)
	var formationScale := intactScale * IceTargetEncasementProfile.FORMATION_COMPRESSED_SCALE
	var formation := Transform3D(
		Basis.from_euler(intactRotation).scaled(formationScale), formationPosition)
	var outward := intactPosition - bodyCenter
	if outward.length_squared() < 0.001:
		outward = Vector3.UP
	outward = outward.normalized()
	var brokenPosition := intactPosition + outward * random.randf_range(
		IceTargetEncasementProfile.BREAK_DISTANCE_MIN_U,
		IceTargetEncasementProfile.BREAK_DISTANCE_MAX_U
	)
	brokenPosition.y += random.randf_range(
		IceTargetEncasementProfile.BREAK_LIFT_MIN_U,
		IceTargetEncasementProfile.BREAK_LIFT_MAX_U
	)
	var brokenRotation := intactRotation + Vector3(
		random.randf_range(-1.4, 1.4),
		random.randf_range(-1.4, 1.4),
		random.randf_range(-1.4, 1.4)
	)
	var broken := Transform3D(
		Basis.from_euler(brokenRotation).scaled(intactScale * 0.94), brokenPosition
	)
	_chunkRecords.append({
		"layer": layerName,
		"role": roleName,
		"kind": kind,
		"formation": formation,
		"formation_start": formationStart,
		"formation_end": formationEnd,
		"intact": intact,
		"broken": broken,
	})
	_intactTransforms.append(intact)
	_brokenTransforms.append(broken)


func _buildChunkInstances() -> void:
	var kinds := [
		IceChunkMeshFactory.Kind.BLOCK,
		IceChunkMeshFactory.Kind.WEDGE,
		IceChunkMeshFactory.Kind.CRYSTAL,
	]
	for layerName: String in [
		LAYER_SHELL_REAR, LAYER_SHELL_SIDES, LAYER_SHELL_FRONT, LAYER_SHELL_CAP
	]:
		for kind: int in kinds:
			var recordIndices: Array[int] = []
			for recordIndex: int in range(_chunkRecords.size()):
				var record: Dictionary = _chunkRecords[recordIndex]
				if record["layer"] == layerName and int(record["kind"]) == kind:
					recordIndices.append(recordIndex)
			if recordIndices.is_empty():
				continue
			var multiMesh := MultiMesh.new()
			multiMesh.transform_format = MultiMesh.TRANSFORM_3D
			multiMesh.mesh = IceChunkMeshFactoryScript.create(kind)
			multiMesh.instance_count = recordIndices.size()
			for slot: int in range(recordIndices.size()):
				var recordIndex: int = recordIndices[slot]
				var record: Dictionary = _chunkRecords[recordIndex]
				multiMesh.set_instance_transform(slot, record["formation"])
				record["multi_mesh"] = multiMesh
				record["slot"] = slot
			var instance := MultiMeshInstance3D.new()
			instance.name = "%s_chunks" % IceChunkMeshFactoryScript.kindName(kind)
			instance.multimesh = multiMesh
			instance.material_override = _createLayerMaterial(layerName)
			instance.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
			(_layerNodes[layerName] as Node3D).add_child(instance)
			_drawCallCount += 1


func _buildCore(bounds: AABB) -> void:
	_core = MeshInstance3D.new()
	_core.name = "EncasementCore"
	var coreMesh := SphereMesh.new()
	coreMesh.radius = 0.5
	coreMesh.height = 1.0
	coreMesh.radial_segments = 8
	coreMesh.rings = 4
	_core.mesh = coreMesh
	_core.position = bounds.get_center()
	_coreBaseScale = bounds.size * IceTargetEncasementProfile.CORE_SCALE_FRACTION
	_core.scale = _coreBaseScale * IceTargetEncasementProfile.FORMATION_COMPRESSED_SCALE
	_core.material_override = _createLayerMaterial(LAYER_ICE_CORE)
	_core.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	(_layerNodes[LAYER_ICE_CORE] as Node3D).add_child(_core)
	_drawCallCount += 1


func _buildDeliveryTrail() -> void:
	_trailTarget = _bodyCenter
	_trailSource = Vector3(0.0, IceTargetEncasementProfile.TRAIL_SOURCE_HEIGHT_U, 2.5)
	if _context != null:
		_trailSource = to_local(_context.source_world_position)
		_trailSource.y += IceTargetEncasementProfile.TRAIL_SOURCE_HEIGHT_U
	var travelDirection := _trailTarget - _trailSource
	if travelDirection.length_squared() < 0.001:
		travelDirection = Vector3.FORWARD
	var trailUp := Vector3.UP
	if absf(travelDirection.normalized().dot(trailUp)) > 0.98:
		trailUp = Vector3.FORWARD
	_trailBasis = Basis.looking_at(travelDirection.normalized(), trailUp)

	var trailMesh := BoxMesh.new()
	trailMesh.size = Vector3.ONE
	_trailMultiMesh = MultiMesh.new()
	_trailMultiMesh.transform_format = MultiMesh.TRANSFORM_3D
	_trailMultiMesh.mesh = trailMesh
	_trailMultiMesh.instance_count = IceTargetEncasementProfile.TRAIL_INSTANCE_COUNT
	for slot: int in range(IceTargetEncasementProfile.TRAIL_INSTANCE_COUNT):
		_trailMultiMesh.set_instance_transform(
			slot,
			Transform3D(
				_trailBasis.scaled(Vector3.ONE * 0.001),
				_trailSource))
	var trailInstance := MultiMeshInstance3D.new()
	trailInstance.name = "DeliveryTrailSegments"
	trailInstance.multimesh = _trailMultiMesh
	trailInstance.material_override = _createLayerMaterial(LAYER_DELIVERY_TRAIL)
	trailInstance.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	(_layerNodes[LAYER_DELIVERY_TRAIL] as Node3D).add_child(trailInstance)
	_drawCallCount += 1


func _buildContactAccents(bounds: AABB, random: RandomNumberGenerator) -> void:
	var directions: Array[Vector3] = [
		Vector3(-0.85, -0.45, 0.62),
		Vector3(0.72, -0.35, 0.78),
		Vector3(-0.65, 0.05, -0.82),
		Vector3(0.88, 0.12, -0.48),
		Vector3(-0.42, 0.68, 0.72),
		Vector3(0.52, 0.74, 0.50),
		Vector3(-0.72, 0.78, -0.38),
		Vector3(0.65, 0.58, -0.68),
	]
	assert(
		directions.size() == IceTargetEncasementProfile.CONTACT_INSTANCE_COUNT,
		"Ice contact direction count drifted from its instance count."
	)
	var contactSize := clampf(
		minf(bounds.size.x, minf(bounds.size.y, bounds.size.z))
		* IceTargetEncasementProfile.CONTACT_SIZE_BODY_FRACTION,
		IceTargetEncasementProfile.CONTACT_SIZE_MIN_U,
		IceTargetEncasementProfile.CONTACT_SIZE_MAX_U)
	for slot: int in range(directions.size()):
		var direction := directions[slot].normalized()
		var surfaceOffset := Vector3(
			direction.x * bounds.size.x * 0.68,
			direction.y * bounds.size.y * 0.56,
			direction.z * bounds.size.z * 0.68)
		var start := (
			IceTargetEncasementProfile.CONTACT_START_FRACTION
			+ float(slot) * IceTargetEncasementProfile.CONTACT_STAGGER_FRACTION)
		_contactRecords.append({
			"base_position": bounds.get_center() + surfaceOffset,
			"direction": direction,
			"size": contactSize * random.randf_range(0.82, 1.12),
			"start": start,
			"end": start + IceTargetEncasementProfile.CONTACT_DURATION_FRACTION,
		})

	var contactMesh := BoxMesh.new()
	contactMesh.size = Vector3.ONE
	_contactMultiMesh = MultiMesh.new()
	_contactMultiMesh.transform_format = MultiMesh.TRANSFORM_3D
	_contactMultiMesh.mesh = contactMesh
	_contactMultiMesh.instance_count = _contactRecords.size()
	for slot: int in range(_contactRecords.size()):
		var record: Dictionary = _contactRecords[slot]
		_contactMultiMesh.set_instance_transform(
			slot,
			Transform3D(
				Basis.IDENTITY.scaled(Vector3.ONE * 0.001),
				record["base_position"]))
	var contactInstance := MultiMeshInstance3D.new()
	contactInstance.name = "ContactSquares"
	contactInstance.multimesh = _contactMultiMesh
	contactInstance.material_override = _createContactMaterial()
	contactInstance.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	(_layerNodes[LAYER_CONTACT_ACCENTS] as Node3D).add_child(contactInstance)
	_drawCallCount += 1


func _buildImpactFlash(bounds: AABB) -> void:
	_impactFlash = MeshInstance3D.new()
	_impactFlash.name = "ImpactFlash"
	var flashMesh := SphereMesh.new()
	flashMesh.radius = 0.5
	flashMesh.height = 1.0
	flashMesh.radial_segments = 8
	flashMesh.rings = 4
	_impactFlash.mesh = flashMesh
	_impactFlash.position = bounds.get_center()
	_impactFlashBaseScale = bounds.size * IceTargetEncasementProfile.IMPACT_FLASH_SCALE_FRACTION
	_impactFlash.scale = _impactFlashBaseScale * 0.001
	_impactFlashMaterial = StandardMaterial3D.new()
	_impactFlashMaterial.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	_impactFlashMaterial.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	_impactFlashMaterial.cull_mode = BaseMaterial3D.CULL_DISABLED
	_impactFlashMaterial.no_depth_test = true
	_impactFlashMaterial.emission_enabled = true
	_impactFlashMaterial.emission = IceTargetEncasementProfile.IMPACT_FLASH_COLOR
	_impactFlashMaterial.emission_energy_multiplier = 0.7
	_impactFlashMaterial.albedo_color = Color(
		IceTargetEncasementProfile.IMPACT_FLASH_COLOR, 0.0)
	_impactFlashMaterial.render_priority = int(
		IceTargetEncasementProfile.LAYER_RENDER_PRIORITIES[LAYER_IMPACT_FLASH])
	_impactFlash.material_override = _impactFlashMaterial
	_impactFlash.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	(_layerNodes[LAYER_IMPACT_FLASH] as Node3D).add_child(_impactFlash)
	_drawCallCount += 1


func _createLayerMaterial(layerName: String) -> ShaderMaterial:
	var material := ShaderMaterial.new()
	material.shader = _ICE_SHADER
	var color := IceTargetEncasementProfile.SIDE_COLOR
	var opacity := IceTargetEncasementProfile.SIDE_OPACITY
	var emissionStrength := IceTargetEncasementProfile.SHELL_EMISSION_STRENGTH
	match layerName:
		LAYER_SHELL_REAR:
			color = IceTargetEncasementProfile.REAR_COLOR
			opacity = IceTargetEncasementProfile.REAR_OPACITY
		LAYER_SHELL_FRONT:
			color = IceTargetEncasementProfile.FRONT_COLOR
			opacity = IceTargetEncasementProfile.FRONT_OPACITY
		LAYER_SHELL_CAP:
			color = IceTargetEncasementProfile.CAP_COLOR
			opacity = IceTargetEncasementProfile.CAP_OPACITY
		LAYER_ICE_CORE:
			color = IceTargetEncasementProfile.CORE_COLOR
			opacity = IceTargetEncasementProfile.CORE_OPACITY
			emissionStrength = IceTargetEncasementProfile.CORE_EMISSION_STRENGTH
		LAYER_DELIVERY_TRAIL:
			color = IceTargetEncasementProfile.TRAIL_COLOR
			opacity = IceTargetEncasementProfile.TRAIL_OPACITY
			emissionStrength = IceTargetEncasementProfile.TRAIL_EMISSION_STRENGTH
		LAYER_CONTACT_ACCENTS:
			color = IceTargetEncasementProfile.CONTACT_COLOR
	material.set_shader_parameter("base_color", color)
	material.set_shader_parameter("shadow_color", IceTargetEncasementProfile.SHADOW_COLOR)
	material.set_shader_parameter("opacity", opacity)
	material.set_shader_parameter("emission_strength", emissionStrength)
	material.render_priority = int(IceTargetEncasementProfile.LAYER_RENDER_PRIORITIES[layerName])
	return material


func _createContactMaterial() -> StandardMaterial3D:
	var material := StandardMaterial3D.new()
	material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	material.cull_mode = BaseMaterial3D.CULL_DISABLED
	material.albedo_color = IceTargetEncasementProfile.CONTACT_COLOR
	material.emission_enabled = true
	material.emission = IceTargetEncasementProfile.CONTACT_COLOR
	material.emission_energy_multiplier = 0.55
	material.render_priority = int(
		IceTargetEncasementProfile.LAYER_RENDER_PRIORITIES[LAYER_CONTACT_ACCENTS])
	return material


func _applyTimeline() -> void:
	if not _shellBuilt:
		return
	var normalizedTime := get_normalized_time()
	for record: Dictionary in _chunkRecords:
		var multiMesh := record["multi_mesh"] as MultiMesh
		assert(multiMesh != null, "Ice encasement chunk is missing its stable MultiMesh slot.")
		multiMesh.set_instance_transform(
			int(record["slot"]), _chunkTransformAt(record, normalizedTime))
	_applyCoreTimeline(normalizedTime)
	_applyDeliveryTrailTimeline(normalizedTime)
	_applyContactTimeline(normalizedTime)
	_applyImpactFlashTimeline(normalizedTime)
	for layerName: String in get_layer_names():
		var layer := _layerNodes.get(layerName) as Node3D
		if layer != null:
			layer.visible = bool(_layerVisibility[layerName])


func _chunkTransformAt(record: Dictionary, normalizedTime: float) -> Transform3D:
	var formation: Transform3D = record["formation"]
	var intact: Transform3D = record["intact"]
	var broken: Transform3D = record["broken"]
	var formationProgress := _smoothstep01(_windowProgress(
		normalizedTime, float(record["formation_start"]), float(record["formation_end"])))
	if normalizedTime < float(record["formation_end"]):
		return _interpolateTransform(
			formation, intact, formationProgress, formationProgress, formationProgress)
	if normalizedTime <= IceTargetEncasementProfile.COMPLETED_HOLD_END_FRACTION:
		return intact
	if normalizedTime < IceTargetEncasementProfile.FRACTURE_IMPULSE_END_FRACTION:
		var impulseProgress := _windowProgress(
			normalizedTime,
			IceTargetEncasementProfile.FRACTURE_IMPULSE_START_FRACTION,
			IceTargetEncasementProfile.FRACTURE_IMPULSE_END_FRACTION)
		var pathProgress := (
			_easeOutCubic(impulseProgress)
			* IceTargetEncasementProfile.FRACTURE_IMPULSE_PATH_FRACTION
		)
		var impulseTransform := _interpolateTransform(
			intact,
			broken,
			pathProgress,
			_steppedRotationProgress(pathProgress),
			pathProgress)
		var scalePulse := (
			1.0
			+ sin(impulseProgress * PI) * IceTargetEncasementProfile.FRACTURE_SCALE_PULSE
		)
		impulseTransform.basis = impulseTransform.basis.scaled(Vector3.ONE * scalePulse)
		return impulseTransform
	if normalizedTime < IceTargetEncasementProfile.OUTWARD_TUMBLE_END_FRACTION:
		var tumbleProgress := _smoothstep01(_windowProgress(
			normalizedTime,
			IceTargetEncasementProfile.OUTWARD_TUMBLE_START_FRACTION,
			IceTargetEncasementProfile.OUTWARD_TUMBLE_END_FRACTION))
		var pathProgress := lerpf(
			IceTargetEncasementProfile.FRACTURE_IMPULSE_PATH_FRACTION,
			1.0,
			tumbleProgress)
		return _interpolateTransform(
			intact,
			broken,
			pathProgress,
			_steppedRotationProgress(pathProgress),
			pathProgress)
	var settleProgress := _smoothstep01(_windowProgress(
		normalizedTime,
		IceTargetEncasementProfile.SETTLE_START_FRACTION,
		IceTargetEncasementProfile.SETTLE_END_FRACTION))
	var settled := broken
	settled.origin.y -= IceTargetEncasementProfile.SETTLE_DROP_U * settleProgress
	settled.basis = settled.basis.scaled(
		Vector3.ONE * lerpf(1.0, IceTargetEncasementProfile.SETTLE_SCALE_FRACTION, settleProgress))
	return settled


func _applyCoreTimeline(normalizedTime: float) -> void:
	if _core == null:
		return
	var coreFactor := IceTargetEncasementProfile.FORMATION_COMPRESSED_SCALE
	if normalizedTime < IceTargetEncasementProfile.CORE_FORMATION_START_FRACTION:
		coreFactor = IceTargetEncasementProfile.FORMATION_COMPRESSED_SCALE
	elif normalizedTime < IceTargetEncasementProfile.CORE_FORMATION_END_FRACTION:
		coreFactor = lerpf(
			IceTargetEncasementProfile.FORMATION_COMPRESSED_SCALE,
			1.0,
			_smoothstep01(_windowProgress(
				normalizedTime,
				IceTargetEncasementProfile.CORE_FORMATION_START_FRACTION,
				IceTargetEncasementProfile.CORE_FORMATION_END_FRACTION)))
	elif normalizedTime <= IceTargetEncasementProfile.COMPLETED_HOLD_END_FRACTION:
		coreFactor = 1.0
	elif normalizedTime < IceTargetEncasementProfile.FRACTURE_IMPULSE_END_FRACTION:
		var impulseProgress := _windowProgress(
			normalizedTime,
			IceTargetEncasementProfile.FRACTURE_IMPULSE_START_FRACTION,
			IceTargetEncasementProfile.FRACTURE_IMPULSE_END_FRACTION)
		coreFactor = 1.0 + sin(impulseProgress * PI) * 0.14
	elif normalizedTime < IceTargetEncasementProfile.CORE_BREAK_END_FRACTION:
		coreFactor = lerpf(
			1.0,
			IceTargetEncasementProfile.FORMATION_COMPRESSED_SCALE,
			_smoothstep01(_windowProgress(
				normalizedTime,
				IceTargetEncasementProfile.FRACTURE_IMPULSE_END_FRACTION,
				IceTargetEncasementProfile.CORE_BREAK_END_FRACTION)))
	_core.scale = _coreBaseScale * coreFactor
	_core.visible = coreFactor > 0.025


func _applyDeliveryTrailTimeline(normalizedTime: float) -> void:
	if _trailMultiMesh == null:
		return
	var travelProgress := _smoothstep01(_windowProgress(
		normalizedTime,
		IceTargetEncasementProfile.TRAIL_START_FRACTION,
		IceTargetEncasementProfile.TRAIL_IMPACT_FRACTION))
	var visibility := 0.0
	if normalizedTime <= IceTargetEncasementProfile.TRAIL_IMPACT_FRACTION:
		visibility = _smoothstep01(_windowProgress(
			normalizedTime,
			IceTargetEncasementProfile.TRAIL_START_FRACTION,
			IceTargetEncasementProfile.TRAIL_FADE_IN_FRACTION))
	elif normalizedTime < IceTargetEncasementProfile.TRAIL_FADE_END_FRACTION:
		visibility = 1.0 - _smoothstep01(_windowProgress(
			normalizedTime,
			IceTargetEncasementProfile.TRAIL_IMPACT_FRACTION,
			IceTargetEncasementProfile.TRAIL_FADE_END_FRACTION))
	for slot: int in range(IceTargetEncasementProfile.TRAIL_INSTANCE_COUNT):
		var taper := (
			float(slot)
			/ float(maxi(IceTargetEncasementProfile.TRAIL_INSTANCE_COUNT - 1, 1)))
		var segmentProgress := maxf(
			travelProgress
			- float(slot) * IceTargetEncasementProfile.TRAIL_SEGMENT_PROGRESS_SPACING,
			0.0)
		var segmentVisibility := visibility if segmentProgress > 0.0 else 0.0
		var width := lerpf(
			IceTargetEncasementProfile.TRAIL_HEAD_WIDTH_U,
			IceTargetEncasementProfile.TRAIL_TAIL_WIDTH_U,
			taper) * maxf(segmentVisibility, 0.001)
		var length := (
			IceTargetEncasementProfile.TRAIL_SEGMENT_LENGTH_U
			* lerpf(1.0, 0.72, taper)
			* maxf(segmentVisibility, 0.001)
		)
		_trailMultiMesh.set_instance_transform(
			slot,
			Transform3D(
				_trailBasis.scaled(Vector3(width, width, length)),
				_trailSource.lerp(_trailTarget, segmentProgress)))


func _applyContactTimeline(normalizedTime: float) -> void:
	if _contactMultiMesh == null:
		return
	for slot: int in range(_contactRecords.size()):
		var record: Dictionary = _contactRecords[slot]
		var progress := _windowProgress(
			normalizedTime, float(record["start"]), float(record["end"]))
		var visibility := sin(progress * PI)
		if normalizedTime <= float(record["start"]) or normalizedTime >= float(record["end"]):
			visibility = 0.0
		var position: Vector3 = record["base_position"]
		position += (
			(record["direction"] as Vector3)
			* IceTargetEncasementProfile.CONTACT_OUTWARD_DISTANCE_U
			* _easeOutCubic(progress))
		var size := float(record["size"]) * maxf(visibility, 0.001)
		_contactMultiMesh.set_instance_transform(
			slot,
			Transform3D(
				Basis.IDENTITY.scaled(Vector3(size, size, size * 0.22)),
				position))


func _applyImpactFlashTimeline(normalizedTime: float) -> void:
	if _impactFlash == null or _impactFlashMaterial == null:
		return
	var progress := _windowProgress(
		normalizedTime,
		IceTargetEncasementProfile.IMPACT_FLASH_START_FRACTION,
		IceTargetEncasementProfile.IMPACT_FLASH_END_FRACTION)
	var visibility := sin(progress * PI)
	if (
		normalizedTime <= IceTargetEncasementProfile.IMPACT_FLASH_START_FRACTION
		or normalizedTime >= IceTargetEncasementProfile.IMPACT_FLASH_END_FRACTION
	):
		visibility = 0.0
	_impactFlash.scale = _impactFlashBaseScale * maxf(visibility, 0.001)
	var flashColor := IceTargetEncasementProfile.IMPACT_FLASH_COLOR
	flashColor.a = IceTargetEncasementProfile.IMPACT_FLASH_MAX_ALPHA * visibility
	_impactFlashMaterial.albedo_color = flashColor
	_impactFlashMaterial.emission_energy_multiplier = 0.35 + visibility * 0.65
	_impactFlash.visible = visibility > 0.01


func _interpolateTransform(
		from: Transform3D,
		to: Transform3D,
		positionProgress: float,
		rotationProgress: float,
		scaleProgress: float) -> Transform3D:
	var fromRotation := from.basis.orthonormalized().get_rotation_quaternion()
	var toRotation := to.basis.orthonormalized().get_rotation_quaternion()
	var rotation := fromRotation.slerp(toRotation, clampf(rotationProgress, 0.0, 1.0))
	var scale := from.basis.get_scale().lerp(
		to.basis.get_scale(), clampf(scaleProgress, 0.0, 1.0))
	var origin := from.origin.lerp(to.origin, clampf(positionProgress, 0.0, 1.0))
	return Transform3D(Basis(rotation).scaled(scale), origin)


func _steppedRotationProgress(progress: float) -> float:
	var steps := float(IceTargetEncasementProfile.TUMBLE_ROTATION_STEPS)
	return floor(clampf(progress, 0.0, 1.0) * steps) / steps


func _windowProgress(value: float, start: float, end: float) -> float:
	return clampf((value - start) / maxf(end - start, 0.0001), 0.0, 1.0)


func _smoothstep01(value: float) -> float:
	var clamped := clampf(value, 0.0, 1.0)
	return clamped * clamped * (3.0 - 2.0 * clamped)


func _easeOutCubic(value: float) -> float:
	var inverse := 1.0 - clampf(value, 0.0, 1.0)
	return 1.0 - inverse * inverse * inverse


func _countNodes(node: Node) -> int:
	var total := 1
	for child: Node in node.get_children():
		total += _countNodes(child)
	return total
