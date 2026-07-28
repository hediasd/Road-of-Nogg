## Creates placeholder meshes and materials that can opt into PS1-style vertex
## snapping and affine texture interpolation without changing battle state.

class_name BattleMeshFactory

const RETRO_SURFACE_SHADER = preload("res://assets/shaders/retro_surface.gdshader")
const RETRO_TRANSPARENT_SHADER = preload("res://assets/shaders/retro_surface_transparent.gdshader")
const RETRO_MATERIAL_META := "road_of_nogg_retro_material"
const TERRAIN_CELL_SIZE := Vector3(1.0, 0.5, 1.0)

static var vertex_snap_enabled: bool = true
static var vertex_snap_strength: float = 1.0
static var affine_mapping_enabled: bool = true
static var snap_resolution := Vector2(320, 240)


static func configureRetro(
		vertexSnap: bool,
		affineMapping: bool,
		resolution: Vector2,
		vertexSnapStrength: float = 1.0) -> void:
	vertex_snap_enabled = vertexSnap
	vertex_snap_strength = clampf(vertexSnapStrength, 0.0, 1.0)
	affine_mapping_enabled = affineMapping
	snap_resolution = Vector2(maxf(resolution.x, 2.0), maxf(resolution.y, 2.0))


static func elementColor(element: String) -> Color:
	match element.to_lower():
		"fire": return Color(0.9, 0.2, 0.2)
		"water": return Color(0.1, 0.4, 0.9)
		"ice": return Color(0.6, 0.9, 0.9)
		"wind": return Color(0.55, 0.9, 0.78)
		"earth": return Color(0.6, 0.4, 0.2)
		"wood": return Color(0.2, 0.7, 0.2)
		"thunder": return Color(0.9, 0.9, 0.1)
		"darkness": return Color(0.4, 0.1, 0.6)
		"light": return Color(0.9, 0.9, 0.8)
		"steel": return Color(0.6, 0.6, 0.75)
		_: return Color(0.5, 0.5, 0.5)


static func createMaterial(
		color: Color,
		transparent: bool = false,
		emissionStrength: float = 0.0,
		texture: Texture2D = null) -> ShaderMaterial:
	var material = ShaderMaterial.new()
	material.shader = RETRO_TRANSPARENT_SHADER if transparent else RETRO_SURFACE_SHADER
	material.set_meta(RETRO_MATERIAL_META, true)
	material.set_shader_parameter("color_a", color)
	material.set_shader_parameter("color_b", color)
	material.set_shader_parameter("split_color", false)
	material.set_shader_parameter("use_albedo_texture", texture != null)
	if texture != null:
		material.set_shader_parameter("albedo_texture", texture)
	material.set_shader_parameter("emission_strength", emissionStrength)
	_updateRetroMaterial(material)
	return material


static func createHalfMaterial(color1: Color, color2: Color) -> ShaderMaterial:
	var material = createMaterial(color1)
	material.set_shader_parameter("color_b", color2)
	material.set_shader_parameter("split_color", true)
	return material


static func createMesh(type: String, color: Color) -> MeshInstance3D:
	var meshInstance = MeshInstance3D.new()
	var transparent = false
	var emissionStrength = 0.0

	match type:
		"cursor":
			meshInstance.mesh = PlaneMesh.new()
			meshInstance.mesh.size = Vector2(1.1, 1.1)
			transparent = true
			emissionStrength = 1.0
		"box":
			meshInstance.mesh = BoxMesh.new()
			meshInstance.mesh.size = Vector3(0.9, 0.4, 0.9)
		"terrain_block":
			meshInstance.mesh = BoxMesh.new()
			meshInstance.mesh.size = TERRAIN_CELL_SIZE
		"plane":
			meshInstance.mesh = PlaneMesh.new()
			meshInstance.mesh.size = Vector2(0.9, 0.9)
			transparent = true
		"cylinder":
			meshInstance.mesh = CylinderMesh.new()
			meshInstance.mesh.height = 1.0
			meshInstance.mesh.top_radius = 0.3
			meshInstance.mesh.bottom_radius = 0.3
		"capsule_base":
			meshInstance.mesh = CylinderMesh.new()
			meshInstance.mesh.height = 0.2
			meshInstance.mesh.top_radius = 0.45
			meshInstance.mesh.bottom_radius = 0.45
		"shape_sphere":
			meshInstance.mesh = SphereMesh.new()
			meshInstance.mesh.radius = 0.4
		"shape_cube":
			meshInstance.mesh = BoxMesh.new()
			meshInstance.mesh.size = Vector3(0.7, 0.7, 0.7)
		"shape_coin":
			meshInstance.mesh = CylinderMesh.new()
			meshInstance.mesh.height = 0.2
			meshInstance.mesh.top_radius = 0.4
			meshInstance.mesh.bottom_radius = 0.4
		"shape_capsule":
			meshInstance.mesh = CapsuleMesh.new()
			meshInstance.mesh.radius = 0.3
			meshInstance.mesh.height = 0.8
		"shape_pyramid":
			meshInstance.mesh = PrismMesh.new()
			meshInstance.mesh.size = Vector3(0.7, 0.8, 0.7)

	meshInstance.material_override = createMaterial(color, transparent, emissionStrength)
	return meshInstance


static func prepareNodeMaterials(node: Node) -> void:
	_prepareNodeMaterialsRecursive(node, Transform3D.IDENTITY, true)


static func configureSplitBounds(node: Node, bounds: AABB) -> void:
	var safeSize = Vector2(maxf(bounds.size.x, 0.0001), maxf(bounds.size.y, 0.0001))
	_configureSplitBoundsRecursive(node, Vector2(bounds.position.x, bounds.position.y), safeSize)


static func _prepareNodeMaterialsRecursive(
		node: Node,
		parentTransform: Transform3D,
		isRoot: bool = false) -> void:
	var modelTransform = parentTransform
	if node is Node3D and not isRoot:
		modelTransform = parentTransform * node.transform
	if node is MeshInstance3D:
		_prepareMeshMaterials(node)
		_setSplitInstanceTransform(node, modelTransform)
	for child in node.get_children():
		_prepareNodeMaterialsRecursive(child, modelTransform)


static func _setSplitInstanceTransform(
		meshInstance: MeshInstance3D,
		modelTransform: Transform3D) -> void:
	if not _meshUsesRetroMaterial(meshInstance):
		return
	meshInstance.set_instance_shader_parameter("split_model_origin", modelTransform.origin)
	meshInstance.set_instance_shader_parameter("split_model_basis_x", modelTransform.basis.x)
	meshInstance.set_instance_shader_parameter("split_model_basis_y", modelTransform.basis.y)
	meshInstance.set_instance_shader_parameter("split_model_basis_z", modelTransform.basis.z)


static func _meshUsesRetroMaterial(meshInstance: MeshInstance3D) -> bool:
	if (
		meshInstance.material_override is ShaderMaterial and
		meshInstance.material_override.has_meta(RETRO_MATERIAL_META)
	):
		return true
	if meshInstance.mesh == null:
		return false
	for surfaceIndex in range(meshInstance.mesh.get_surface_count()):
		var material = meshInstance.get_surface_override_material(surfaceIndex)
		if material is ShaderMaterial and material.has_meta(RETRO_MATERIAL_META):
			return true
	return false


static func _configureSplitBoundsRecursive(
		node: Node,
		boundsMin: Vector2,
		boundsSize: Vector2) -> void:
	if node is MeshInstance3D:
		_configureSplitBoundsForMesh(node, boundsMin, boundsSize)
	for child in node.get_children():
		_configureSplitBoundsRecursive(child, boundsMin, boundsSize)


static func _configureSplitBoundsForMesh(
		meshInstance: MeshInstance3D,
		boundsMin: Vector2,
		boundsSize: Vector2) -> void:
	if meshInstance.material_override is ShaderMaterial:
		_setSplitBoundsOnMaterial(meshInstance.material_override, boundsMin, boundsSize)
	if meshInstance.mesh == null:
		return
	for surfaceIndex in range(meshInstance.mesh.get_surface_count()):
		var material = meshInstance.get_surface_override_material(surfaceIndex)
		if material is ShaderMaterial:
			_setSplitBoundsOnMaterial(material, boundsMin, boundsSize)


static func _setSplitBoundsOnMaterial(
		material: ShaderMaterial,
		boundsMin: Vector2,
		boundsSize: Vector2) -> void:
	if not material.has_meta(RETRO_MATERIAL_META):
		return
	material.set_shader_parameter("split_bounds_min", boundsMin)
	material.set_shader_parameter("split_bounds_size", boundsSize)


static func updateMaterialsRecursive(node: Node) -> void:
	if node is MeshInstance3D:
		_updateMeshMaterials(node)
	for child in node.get_children():
		updateMaterialsRecursive(child)


static func _prepareMeshMaterials(meshInstance: MeshInstance3D) -> void:
	if meshInstance.material_override is StandardMaterial3D:
		meshInstance.material_override = _convertStandardMaterial(meshInstance.material_override)
	elif meshInstance.material_override is ShaderMaterial:
		_updateRetroMaterial(meshInstance.material_override)

	if meshInstance.mesh == null or meshInstance.material_override != null:
		return
	for surfaceIndex in range(meshInstance.mesh.get_surface_count()):
		var activeMaterial = meshInstance.get_active_material(surfaceIndex)
		if activeMaterial is StandardMaterial3D:
			meshInstance.set_surface_override_material(
				surfaceIndex,
				_convertStandardMaterial(activeMaterial)
			)


static func _updateMeshMaterials(meshInstance: MeshInstance3D) -> void:
	if meshInstance.material_override is ShaderMaterial:
		_updateRetroMaterial(meshInstance.material_override)
	if meshInstance.mesh == null:
		return
	for surfaceIndex in range(meshInstance.mesh.get_surface_count()):
		var material = meshInstance.get_surface_override_material(surfaceIndex)
		if material is ShaderMaterial:
			_updateRetroMaterial(material)


static func _convertStandardMaterial(source: StandardMaterial3D) -> ShaderMaterial:
	var transparent = (
		source.transparency != BaseMaterial3D.TRANSPARENCY_DISABLED or
		source.albedo_color.a < 1.0
	)
	var emissionStrength = 1.0 if source.emission_enabled else 0.0
	var converted = createMaterial(
		source.albedo_color,
		transparent,
		emissionStrength,
		source.albedo_texture
	)
	return converted


static func _updateRetroMaterial(material: ShaderMaterial) -> void:
	if not material.has_meta(RETRO_MATERIAL_META):
		return
	material.set_shader_parameter("vertex_snap_enabled", vertex_snap_enabled)
	material.set_shader_parameter("vertex_snap_strength", vertex_snap_strength)
	material.set_shader_parameter("affine_mapping_enabled", affine_mapping_enabled)
	material.set_shader_parameter("snap_resolution", snap_resolution)
