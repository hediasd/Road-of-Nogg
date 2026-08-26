## Debug-only polygonal technique-charge aura playback.
##
## Authored fresh under docs/VFX_DESIGN.md's isolation rule. Solar Storm is a
## process reference only: this effect owns its mesh construction, materials,
## texture, profile, and lifecycle implementation.

class_name TechniqueChargeAuraEffect
extends "res://src/presentation/effects/VfxPlayback.gd"

const _AURA_SHADER = preload(
	"res://assets/shaders/effects/technique_charge_aura.gdshader"
)
const _AURA_MASK = preload(
	"res://assets/vfx/technique_charge_aura/aura_panel.png"
)

const LAYER_GROUND := "ground_circle"
const LAYER_WALL := "polygonal_wall"

var _groundInstance: MeshInstance3D
var _wallInstance: MeshInstance3D
var _groundMaterial: ShaderMaterial
var _wallMaterial: ShaderMaterial
var _elapsedTime := 0.0
var _playbackScale := 1.0
var _playing := false
var _finished := true
var _disposed := false
var _autoDispose := false


static func createPlayback(
		parent: Node3D,
		world_position: Vector3,
		_element_color: Color,
		overrides: Dictionary = {}) -> TechniqueChargeAuraEffect:
	var playback := TechniqueChargeAuraEffect.new()
	playback.name = "TechniqueChargeAuraEffect"
	playback.position = world_position
	parent.add_child(playback)
	playback.set_tunable_overrides(overrides)
	playback._buildOwnedLayers()
	return playback


func configure_cast_context(context: VfxCastContext) -> void:
	if context == null:
		return
	context.assert_valid()
	position = context.source_world_position


func play(_seed: int, mode: String) -> void:
	assert(not _disposed, "Cannot play a disposed TechniqueChargeAuraEffect.")
	assert(mode == MODE_REFERENCE or mode == MODE_BATTLE, "Unknown VFX playback mode.")
	_elapsedTime = 0.0
	_finished = false
	_playing = true
	_applyVisibility(1.0)
	set_process(true)


func set_playback_scale(scale: float) -> void:
	_playbackScale = maxf(scale, 0.0)


func seek_normalized(time: float) -> void:
	if _disposed:
		return
	var normalized_time := clampf(time, 0.0, 1.0)
	_elapsedTime = normalized_time * TechniqueChargeAuraProfile.DURATION_SECONDS
	_finished = normalized_time >= 1.0
	_playing = not _finished
	_applyVisibility(0.0 if _finished else 1.0)


func skip_to_settle() -> void:
	seek_normalized(TechniqueChargeAuraProfile.SETTLE_NORMALIZED_TIME)


func get_normalized_time() -> float:
	return clampf(
		_elapsedTime / TechniqueChargeAuraProfile.DURATION_SECONDS,
		0.0,
		1.0
	)


func get_elapsed_time() -> float:
	return _elapsedTime


func get_total_duration() -> float:
	return TechniqueChargeAuraProfile.DURATION_SECONDS


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
	if is_inside_tree() or get_parent() != null:
		queue_free()
	else:
		call_deferred("free")


func get_layer_names() -> Array[String]:
	return [LAYER_GROUND, LAYER_WALL]


func set_layer_visible(layer_name: String, visible: bool) -> void:
	match layer_name:
		LAYER_GROUND:
			if _groundInstance != null:
				_groundInstance.visible = visible
		LAYER_WALL:
			if _wallInstance != null:
				_wallInstance.visible = visible
		_:
			push_warning("Unknown TechniqueChargeAuraEffect layer: %s" % layer_name)


func get_live_particle_count() -> int:
	return 0


func get_live_instance_count() -> int:
	if _disposed or _finished:
		return 0
	var count := 0
	for instance: MeshInstance3D in [_groundInstance, _wallInstance]:
		if instance != null and instance.visible:
			count += 1
	return count


func get_live_draw_call_count() -> int:
	return get_live_instance_count()


func get_live_node_count() -> int:
	if _disposed:
		return 0
	return 1 + get_child_count()


func is_particle_seek_exact() -> bool:
	return true


func _process(delta: float) -> void:
	if _disposed or not _playing:
		return
	_elapsedTime += delta * _playbackScale
	if _elapsedTime < TechniqueChargeAuraProfile.DURATION_SECONDS:
		return
	_elapsedTime = TechniqueChargeAuraProfile.DURATION_SECONDS
	_playing = false
	_finished = true
	_applyVisibility(0.0)
	if _autoDispose:
		dispose()


func _buildOwnedLayers() -> void:
	_groundMaterial = _createOwnedMaterial(1)
	_groundMaterial.render_priority = TechniqueChargeAuraProfile.GROUND_RENDER_PRIORITY
	_groundMaterial.set_shader_parameter(
		"opacity", TechniqueChargeAuraProfile.GROUND_OPACITY
	)
	_groundMaterial.set_shader_parameter(
		"emission_energy", TechniqueChargeAuraProfile.GROUND_EMISSION_ENERGY
	)
	_groundMaterial.set_shader_parameter(
		"ground_inner_radius", TechniqueChargeAuraProfile.GROUND_INNER_RADIUS_UV
	)
	_groundMaterial.set_shader_parameter(
		"ground_outer_radius", TechniqueChargeAuraProfile.GROUND_OUTER_RADIUS_UV
	)
	_groundMaterial.set_shader_parameter(
		"ground_edge_softness", TechniqueChargeAuraProfile.GROUND_EDGE_SOFTNESS_UV
	)
	_groundMaterial.set_shader_parameter(
		"ground_fill_alpha", TechniqueChargeAuraProfile.GROUND_FILL_ALPHA
	)

	var ground_mesh := PlaneMesh.new()
	ground_mesh.size = Vector2.ONE * TechniqueChargeAuraProfile.GROUND_DIAMETER_U
	_groundInstance = MeshInstance3D.new()
	_groundInstance.name = "GroundCircle"
	_groundInstance.mesh = ground_mesh
	_groundInstance.position.y = TechniqueChargeAuraProfile.GROUND_HEIGHT_U
	_groundInstance.material_override = _groundMaterial
	_groundInstance.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(_groundInstance)

	_wallMaterial = _createOwnedMaterial(0)
	_wallMaterial.render_priority = TechniqueChargeAuraProfile.WALL_RENDER_PRIORITY
	_wallMaterial.set_shader_parameter(
		"opacity", TechniqueChargeAuraProfile.WALL_OPACITY
	)
	_wallMaterial.set_shader_parameter(
		"emission_energy", TechniqueChargeAuraProfile.WALL_EMISSION_ENERGY
	)

	_wallInstance = MeshInstance3D.new()
	_wallInstance.name = "PolygonalWall"
	_wallInstance.mesh = _createRepeatedFaceWall(
		TechniqueChargeAuraProfile.WALL_SIDES,
		TechniqueChargeAuraProfile.WALL_RADIUS_U,
		TechniqueChargeAuraProfile.WALL_HEIGHT_U
	)
	_wallInstance.material_override = _wallMaterial
	_wallInstance.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(_wallInstance)

	assert(
		get_child_count() + 1 <= TechniqueChargeAuraProfile.MAX_EFFECT_NODES,
		"Technique charge aura exceeded its authored node ceiling."
	)
	assert(
		2 <= TechniqueChargeAuraProfile.MAX_GEOMETRY_INSTANCES,
		"Technique charge aura exceeded its authored geometry ceiling."
	)
	assert(
		2 <= TechniqueChargeAuraProfile.MAX_DRAW_CALLS,
		"Technique charge aura exceeded its authored draw-call ceiling."
	)


func _createOwnedMaterial(layer_kind: int) -> ShaderMaterial:
	var material := ShaderMaterial.new()
	material.shader = _AURA_SHADER
	material.set_shader_parameter("aura_mask", _AURA_MASK)
	material.set_shader_parameter("aura_color", TechniqueChargeAuraProfile.AURA_COLOR)
	material.set_shader_parameter("layer_kind", layer_kind)
	material.set_shader_parameter("lifecycle_visibility", 1.0)
	return material


func _applyVisibility(visibility: float) -> void:
	for material: ShaderMaterial in [_groundMaterial, _wallMaterial]:
		if material != null:
			material.set_shader_parameter("lifecycle_visibility", visibility)


static func _createRepeatedFaceWall(sides: int, radius: float, height: float) -> ArrayMesh:
	assert(sides >= 3, "Technique charge aura wall needs at least three sides.")
	assert(radius > 0.0 and height > 0.0, "Aura wall dimensions must be positive.")
	var vertices := PackedVector3Array()
	var normals := PackedVector3Array()
	var uvs := PackedVector2Array()
	var indices := PackedInt32Array()

	for side: int in range(sides):
		var angle_a := TAU * float(side) / float(sides)
		var angle_b := TAU * float(side + 1) / float(sides)
		var point_a := Vector3(cos(angle_a) * radius, 0.0, sin(angle_a) * radius)
		var point_b := Vector3(cos(angle_b) * radius, 0.0, sin(angle_b) * radius)
		var outward_angle := (angle_a + angle_b) * 0.5
		var outward := Vector3(cos(outward_angle), 0.0, sin(outward_angle))
		var base := vertices.size()

		vertices.append_array(PackedVector3Array([
			point_a,
			point_b,
			point_a + Vector3.UP * height,
			point_b + Vector3.UP * height,
		]))
		normals.append_array(PackedVector3Array([outward, outward, outward, outward]))
		uvs.append_array(PackedVector2Array([
			Vector2(0.0, 1.0),
			Vector2(1.0, 1.0),
			Vector2(0.0, 0.0),
			Vector2(1.0, 0.0),
		]))
		indices.append_array(PackedInt32Array([
			base,
			base + 3,
			base + 2,
			base,
			base + 1,
			base + 3,
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
