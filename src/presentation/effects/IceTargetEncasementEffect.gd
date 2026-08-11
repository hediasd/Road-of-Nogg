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
}
var _chunkRecords: Array[Dictionary] = []
var _intactTransforms: Array[Transform3D] = []
var _brokenTransforms: Array[Transform3D] = []
var _drawCallCount := 0


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
	_applyStaticHold()
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
	_applyStaticHold()
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
	return 0 if _disposed else _chunkRecords.size()


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
	_buildLayerNodes()
	var random := RandomNumberGenerator.new()
	random.seed = seed
	_buildChunkRecords(bodyBounds, random)
	_buildChunkInstances()
	_buildCore(bodyBounds)
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
	var kinds := [
		IceChunkMeshFactory.Kind.BLOCK,
		IceChunkMeshFactory.Kind.WEDGE,
		IceChunkMeshFactory.Kind.CRYSTAL,
	]

	for faceIndex in range(2):
		var layerName := LAYER_SHELL_REAR if faceIndex == 0 else LAYER_SHELL_FRONT
		var zSign := -1.0 if faceIndex == 0 else 1.0
		for row in range(2):
			for column in range(2):
				var index := row * 2 + column
				_appendChunk(
					layerName,
					kinds[(index + faceIndex) % kinds.size()],
					center + Vector3(
						(float(column) - 0.5) * width * 0.48,
						(float(row) - 0.5) * height * 0.48,
						zSign * (depth * 0.5 + thickness * 0.18)
					),
					Vector3(width * 0.60, height * 0.60, thickness),
					Vector3(0.0, 0.0, (float(index) - 1.5) * 0.045),
					center,
					jitterAmplitude,
					random
				)

	for sideIndex in range(2):
		var xSign := -1.0 if sideIndex == 0 else 1.0
		for row in range(2):
			var index := sideIndex * 2 + row
			_appendChunk(
				LAYER_SHELL_SIDES,
				kinds[(index + 1) % kinds.size()],
				center + Vector3(
					xSign * (width * 0.5 + thickness * 0.18),
					(float(row) - 0.5) * height * 0.48,
					(float(row) - 0.5) * depth * 0.14
				),
				Vector3(thickness, height * 0.61, depth * 0.84),
				Vector3(0.0, xSign * 0.08, xSign * (float(row) - 0.5) * 0.07),
				center,
				jitterAmplitude,
				random
			)

	for capIndex in range(3):
		_appendChunk(
			LAYER_SHELL_CAP,
			kinds[(capIndex + 2) % kinds.size()],
			center + Vector3(
				(float(capIndex) - 1.0) * width * 0.31,
				height * 0.5 + thickness * 0.18,
				(float(capIndex % 2) - 0.5) * depth * 0.10
			),
			Vector3(width * 0.45, thickness, depth * 0.84),
			Vector3(0.0, (float(capIndex) - 1.0) * 0.10, 0.04),
			center,
			jitterAmplitude,
			random
		)


func _appendChunk(
		layerName: String,
		kind: int,
		basePosition: Vector3,
		baseScale: Vector3,
		baseRotation: Vector3,
		bodyCenter: Vector3,
		jitterAmplitude: float,
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
		"kind": kind,
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
			var records: Array[Dictionary] = []
			for record: Dictionary in _chunkRecords:
				if record["layer"] == layerName and int(record["kind"]) == kind:
					records.append(record)
			if records.is_empty():
				continue
			var multiMesh := MultiMesh.new()
			multiMesh.transform_format = MultiMesh.TRANSFORM_3D
			multiMesh.mesh = IceChunkMeshFactoryScript.create(kind)
			multiMesh.instance_count = records.size()
			for index in range(records.size()):
				multiMesh.set_instance_transform(index, records[index]["intact"])
			var instance := MultiMeshInstance3D.new()
			instance.name = "%s_chunks" % IceChunkMeshFactoryScript.kindName(kind)
			instance.multimesh = multiMesh
			instance.material_override = _createLayerMaterial(layerName)
			instance.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
			(_layerNodes[layerName] as Node3D).add_child(instance)
			_drawCallCount += 1


func _buildCore(bounds: AABB) -> void:
	var core := MeshInstance3D.new()
	core.name = "EncasementCore"
	var coreMesh := SphereMesh.new()
	coreMesh.radius = 0.5
	coreMesh.height = 1.0
	coreMesh.radial_segments = 8
	coreMesh.rings = 4
	core.mesh = coreMesh
	core.position = bounds.get_center()
	core.scale = bounds.size * IceTargetEncasementProfile.CORE_SCALE_FRACTION
	core.material_override = _createLayerMaterial(LAYER_ICE_CORE)
	core.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	(_layerNodes[LAYER_ICE_CORE] as Node3D).add_child(core)
	_drawCallCount += 1


func _createLayerMaterial(layerName: String) -> ShaderMaterial:
	var material := ShaderMaterial.new()
	material.shader = _ICE_SHADER
	var color := IceTargetEncasementProfile.SIDE_COLOR
	match layerName:
		LAYER_SHELL_REAR:
			color = IceTargetEncasementProfile.REAR_COLOR
		LAYER_SHELL_FRONT:
			color = IceTargetEncasementProfile.FRONT_COLOR
		LAYER_SHELL_CAP:
			color = IceTargetEncasementProfile.CAP_COLOR
		LAYER_ICE_CORE:
			color = IceTargetEncasementProfile.CORE_COLOR
	material.set_shader_parameter("base_color", color)
	material.set_shader_parameter("shadow_color", IceTargetEncasementProfile.SHADOW_COLOR)
	material.set_shader_parameter("emission_strength", 0.18 if layerName == LAYER_ICE_CORE else 0.08)
	material.render_priority = int(IceTargetEncasementProfile.LAYER_RENDER_PRIORITIES[layerName])
	return material


func _applyStaticHold() -> void:
	for layerName: String in get_layer_names():
		var layer := _layerNodes.get(layerName) as Node3D
		if layer != null:
			layer.visible = bool(_layerVisibility[layerName])


func _countNodes(node: Node) -> int:
	var total := 1
	for child: Node in node.get_children():
		total += _countNodes(child)
	return total
