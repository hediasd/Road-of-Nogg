## BattleVisualEffects — Selection aura and global material overrides.

class_name BattleVisualEffects

var monsterVisuals: Dictionary
var selectedMonsterID: int = -1
var auraContainer: Node3D


func _init(_monsterVisuals: Dictionary) -> void:
	monsterVisuals = _monsterVisuals


func highlightMonster(monsterID: int) -> void:
	if selectedMonsterID == monsterID:
		return
	selectedMonsterID = monsterID

	if is_instance_valid(auraContainer):
		auraContainer.queue_free()
		auraContainer = null

	if monsterID == -1 or not monsterVisuals.has(monsterID):
		return

	var targetNode = monsterVisuals[monsterID]
	auraContainer = Node3D.new()
	targetNode.add_child(auraContainer)

	var material = ShaderMaterial.new()
	material.shader = load("res://assets/shaders/pixel_aura.gdshader")
	material.set_shader_parameter("aura_color", Color.WHITE)
	material.set_shader_parameter("thickness", 0.04)
	material.set_shader_parameter("pixel_size", 64.0)

	auraContainer.position.y += 0.02
	_buildAuraMeshes(targetNode, auraContainer, material)


func applyGlobalEffect(index: int) -> void:
	var material: Material = null
	match index:
		0: material = null
		1: material = _loadEffectMaterial("res://assets/shaders/effects/01_hologram.gdshader")
		2: material = _loadEffectMaterial("res://assets/shaders/effects/02_ghost.gdshader")
		3: material = _loadEffectMaterial("res://assets/shaders/effects/03_toon.gdshader")
		4: material = _loadEffectMaterial("res://assets/shaders/effects/04_molten.gdshader")
		5: material = _loadEffectMaterial("res://assets/shaders/effects/05_dissolve.gdshader")
		6: material = _loadEffectMaterial("res://assets/shaders/effects/06_matrix.gdshader")
		7: material = _loadEffectMaterial("res://assets/shaders/effects/07_glass.gdshader")
		8: material = _loadEffectMaterial("res://assets/shaders/effects/08_shadow.gdshader")
		9: material = _loadEffectMaterial("res://assets/shaders/effects/09_petrified.gdshader")
		10:
			var standardMaterial = StandardMaterial3D.new()
			standardMaterial.albedo_color = Color(1.0, 0.8, 0.1)
			standardMaterial.metallic = 1.0
			standardMaterial.roughness = 0.15
			material = standardMaterial

	for monsterID in monsterVisuals:
		_overrideMaterialsRecursive(monsterVisuals[monsterID], material)


func _buildAuraMeshes(source: Node, destination: Node3D, material: Material) -> void:
	for child in source.get_children():
		if child == auraContainer:
			continue
		if child is MeshInstance3D:
			var meshInstance = MeshInstance3D.new()
			meshInstance.mesh = child.mesh
			meshInstance.transform = child.transform
			meshInstance.material_override = material
			destination.add_child(meshInstance)
		elif child is Node3D:
			var pivot = Node3D.new()
			pivot.transform = child.transform
			destination.add_child(pivot)
			_buildAuraMeshes(child, pivot, material)


func _loadEffectMaterial(path: String) -> ShaderMaterial:
	var material = ShaderMaterial.new()
	material.shader = load(path)
	return material


func _overrideMaterialsRecursive(node: Node, material: Material) -> void:
	if node == auraContainer:
		return
	if node is MeshInstance3D:
		node.material_override = material
	for child in node.get_children():
		_overrideMaterialsRecursive(child, material)
