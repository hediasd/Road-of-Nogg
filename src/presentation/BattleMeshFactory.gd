## Creates placeholder meshes and materials that can opt into PS1-style vertex
## snapping and affine texture interpolation without changing battle state.

class_name BattleMeshFactory

const RETRO_SURFACE_SHADER = preload("res://assets/shaders/retro_surface.gdshader")
const RETRO_TRANSPARENT_SHADER = preload("res://assets/shaders/retro_surface_transparent.gdshader")
const RETRO_MATERIAL_META := "road_of_nogg_retro_material"
const TERRAIN_CELL_SIZE := Vector3(1.0, 0.5, 1.0)

## Total height every model base occupies, however many ascension layers it is
## split into. Fixed on purpose: a twice-ascended monster reads as a taller
## *stack* without standing any taller, so ascension never changes model height,
## camera framing, or the apparent size of a unit on the board.
const BASE_TOTAL_HEIGHT := 0.2
const BASE_RADIUS := 0.45
## Gap between stacked layers, taken out of each layer's own thickness so the
## total stays BASE_TOTAL_HEIGHT.
const BASE_LAYER_GAP := 0.012
## Bases are deliberately darker and flatter than any creature body so the plate
## never reads as part of the monster.
const BASE_COLOR_DARKEN := 0.34
## The base separates from a matte creature body (roughness 1.0, metallic 0.0)
## by surface finish rather than hue, so the distinction survives any team
## colour: dark and polished, like pewter or oiled bronze, rather than bright.
## Ramped per layer alongside the existing colour lightening so a higher
## ascension tier reads as more refined metal, not only as a taller stack —
## both derived from the same `layerIndex`, no separate state to keep in sync.
const BASE_METALLIC_START := 0.55
const BASE_METALLIC_PER_LAYER := 0.10
const BASE_ROUGHNESS_START := 0.35
const BASE_ROUGHNESS_PER_LAYER := 0.05

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


## `roughness`/`metallic`/`specular`/`rimAmount`/`rimColor` default to exactly
## what `retro_surface.gdshader` itself defaults to, so an ordinary call — one
## that does not know these finish parameters exist — produces a byte-identical
## material to before they existed. Only `createModelBase` overrides them
## today. The transparent shader has no matching uniforms; `set_shader_parameter`
## on a material that does not declare one is a documented no-op, so passing a
## finish through a transparent `createMaterial` call is harmless, not an error.
static func createMaterial(
		color: Color,
		transparent: bool = false,
		emissionStrength: float = 0.0,
		texture: Texture2D = null,
		roughness: float = 1.0,
		metallic: float = 0.0,
		specular: float = 0.25,
		rimAmount: float = 0.0,
		rimColor: Color = Color.WHITE) -> ShaderMaterial:
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
	material.set_shader_parameter("surface_roughness", roughness)
	material.set_shader_parameter("surface_metallic", metallic)
	material.set_shader_parameter("surface_specular", specular)
	material.set_shader_parameter("rim_amount", rimAmount)
	material.set_shader_parameter("rim_color", rimColor)
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


## Builds the model base as a stack of `ascensionTier + 1` layers inside a fixed
## total height, and returns the container to parent at the model's origin.
##
## A basic monster gets one layer and looks exactly as it always has. Each
## further ascension adds a layer and makes every layer proportionally thinner,
## so the stack gains visible strata without gaining height. Footprint, origin,
## and the surface the body sits on are identical at every tier.
static func createModelBase(teamColor: Color, ascensionTier: int) -> Node3D:
	var container := Node3D.new()
	container.name = "ModelBase"
	var layerCount: int = maxi(1, ascensionTier + 1)
	## Single-layer bases keep the original solid plate; only a real stack needs
	## the seam between layers to be readable.
	var gap: float = BASE_LAYER_GAP if layerCount > 1 else 0.0
	## Gaps sit *between* layers, never above the top one, so the stack's top
	## surface lands exactly on BASE_TOTAL_HEIGHT at every tier. Solving
	## `count * height + (count - 1) * gap = BASE_TOTAL_HEIGHT` keeps the body
	## sitting at the same world height whether it has one layer or five.
	var totalGap: float = gap * float(layerCount - 1)
	var layerHeight: float = (BASE_TOTAL_HEIGHT - totalGap) / float(layerCount)

	for layerIndex in range(layerCount):
		var layer := MeshInstance3D.new()
		var mesh := CylinderMesh.new()
		mesh.height = layerHeight
		## Each layer up the stack is slightly narrower, which reads as a plinth
		## rather than a smooth cylinder while the footprint stays put.
		var inset: float = 0.035 * float(layerIndex)
		mesh.top_radius = BASE_RADIUS - inset
		mesh.bottom_radius = BASE_RADIUS - inset
		layer.mesh = mesh
		layer.position.y = float(layerIndex) * (layerHeight + gap) + layerHeight * 0.5
		## Higher layers lighten a little so the tier count is countable at a
		## glance even against a dark board.
		var layerColor: Color = teamColor.darkened(BASE_COLOR_DARKEN).lightened(
			0.12 * float(layerIndex)
		)
		var layerMetallic: float = clampf(
			BASE_METALLIC_START + BASE_METALLIC_PER_LAYER * float(layerIndex), 0.0, 1.0
		)
		var layerRoughness: float = clampf(
			BASE_ROUGHNESS_START - BASE_ROUGHNESS_PER_LAYER * float(layerIndex), 0.05, 1.0
		)
		layer.material_override = createMaterial(
			layerColor, false, 0.0, null, layerRoughness, layerMetallic
		)
		layer.name = "BaseLayer%d" % layerIndex
		container.add_child(layer)

	return container


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


## Sets `dim_amount` on every retro material under `node` — used to mark a
## unit whose turn has spent a phase, mirroring the command menu's own
## treatment of a spent row. Non-retro materials (StandardMaterial3D, none)
## are left alone rather than converted; dimming is presentation on top of
## whatever material a mesh already has, not a material-identity change.
static func setDimAmountRecursive(node: Node, amount: float) -> void:
	if node is MeshInstance3D:
		_setDimAmountForMesh(node, amount)
	for child in node.get_children():
		setDimAmountRecursive(child, amount)


static func _setDimAmountForMesh(meshInstance: MeshInstance3D, amount: float) -> void:
	if meshInstance.material_override is ShaderMaterial:
		_setDimAmountOnMaterial(meshInstance.material_override, amount)
	if meshInstance.mesh == null:
		return
	for surfaceIndex in range(meshInstance.mesh.get_surface_count()):
		var material = meshInstance.get_surface_override_material(surfaceIndex)
		if material is ShaderMaterial:
			_setDimAmountOnMaterial(material, amount)


static func _setDimAmountOnMaterial(material: ShaderMaterial, amount: float) -> void:
	if not material.has_meta(RETRO_MATERIAL_META):
		return
	material.set_shader_parameter("dim_amount", amount)


## Sets screen-door `dither_amount` on every retro material under `node`, used
## to fade back the models the player is not currently choosing between.
## Same traversal and same "tagged materials only" rule as the dim setter.
static func setDitherAmountRecursive(node: Node, amount: float) -> void:
	if node is MeshInstance3D:
		_setShaderParameterForMesh(node, "dither_amount", amount)
	for child in node.get_children():
		setDitherAmountRecursive(child, amount)


## Shared by the dither setter; `dim_amount` keeps its own pair above only
## because they were written first and their call sites are stable.
static func _setShaderParameterForMesh(
		meshInstance: MeshInstance3D, parameter: String, value: Variant) -> void:
	if meshInstance.material_override is ShaderMaterial:
		_setShaderParameterOnMaterial(meshInstance.material_override, parameter, value)
	if meshInstance.mesh == null:
		return
	for surfaceIndex in range(meshInstance.mesh.get_surface_count()):
		var material = meshInstance.get_surface_override_material(surfaceIndex)
		if material is ShaderMaterial:
			_setShaderParameterOnMaterial(material, parameter, value)


static func _setShaderParameterOnMaterial(
		material: ShaderMaterial, parameter: String, value: Variant) -> void:
	if not material.has_meta(RETRO_MATERIAL_META):
		return
	material.set_shader_parameter(parameter, value)


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
