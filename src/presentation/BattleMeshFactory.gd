## Creates placeholder meshes and materials that can opt into PS1-style vertex
## snapping and affine texture interpolation without changing battle state.

class_name BattleMeshFactory

const RETRO_SURFACE_SHADER = preload("res://assets/shaders/retro_surface.gdshader")
const RETRO_TRANSPARENT_SHADER = preload("res://assets/shaders/retro_surface_transparent.gdshader")
const RETRO_MATERIAL_META := "road_of_nogg_retro_material"

static var vertex_snap_enabled: bool = true
static var affine_mapping_enabled: bool = true
static var snap_resolution := Vector2(320, 240)


static func configureRetro(vertexSnap: bool, affineMapping: bool, resolution: Vector2) -> void:
	vertex_snap_enabled = vertexSnap
	affine_mapping_enabled = affineMapping
	snap_resolution = Vector2(maxf(resolution.x, 2.0), maxf(resolution.y, 2.0))


static func elementColor(element: String) -> Color:
	match element.to_lower():
		"fire": return Color(0.9, 0.2, 0.2)
		"water", "ice": return Color(0.2, 0.7, 0.9)
		"earth", "nature", "wood": return Color(0.2, 0.7, 0.2)
		"electric", "lightning", "thunder": return Color(0.9, 0.9, 0.1)
		"dark", "darkness": return Color(0.4, 0.1, 0.6)
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
	if node is MeshInstance3D:
		_prepareMeshMaterials(node)
	for child in node.get_children():
		prepareNodeMaterials(child)


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
	material.set_shader_parameter("affine_mapping_enabled", affine_mapping_enabled)
	material.set_shader_parameter("snap_resolution", snap_resolution)
