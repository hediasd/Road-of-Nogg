extends SceneTree

## HPR-1: the adapter must use each authoritative monster's element list when
## creating its model. The direct factory is the oracle: this probe compares
## the full model material/split-bound signature, one model per ID, and the
## position seated by the adapter rather than only checking child counts.

const BattleMapDefinitionScript = preload("res://src/entities/BattleMapDefinition.gd")
const BattleStateScript = preload("res://src/battle_sim/BattleState.gd")
const HexBattleVisualAdapterScript = preload(
	"res://src/presentation/battle/HexBattleVisualAdapter.gd")
const MonsterFactoryScript = preload("res://src/factories/MonsterFactory.gd")
const MonsterModelFactoryScript = preload("res://src/presentation/MonsterModelFactory.gd")
const NoggThemeScript = preload("res://src/presentation/theme/NoggTheme.gd")

const FIXTURES := [
	{"id": 4101, "name": "Smoke Cloud", "team": 1, "pos": Vector2i(0, 0), "elements": []},
	{"id": 4102, "name": "Healer Mage", "team": 2, "pos": Vector2i(1, 0), "elements": ["fire"]},
	{"id": 4103, "name": "Mage Dragon", "team": 1, "pos": Vector2i(2, 0), "elements": ["water", "wind"]},
]

var failures: Array[String] = []
var _root: Node3D


func _init() -> void:
	_root = Node3D.new()
	root.add_child(_root)
	process_frame.connect(_run, CONNECT_ONE_SHOT)


func _run() -> void:
	_checkAuthoritativeElements()
	_checkNullStateFallback()
	_checkWholeModelDiagonal()
	_root.queue_free()
	await process_frame
	if not failures.is_empty():
		for failure: String in failures:
			printerr("HPR_UNIT_COLORS_FAILURE: %s" % failure)
		quit(1)
		return
	print("HPR_UNIT_COLORS_OK")
	quit(0)


func _checkAuthoritativeElements() -> void:
	var map: BattleMapDefinition = _buildMap()
	var state: BattleState = BattleStateScript.new(7)
	state.setBattleMap(map)
	for fixture: Dictionary in FIXTURES:
		var monster: Monster = MonsterFactoryScript.createMonster(
			str(fixture["name"]), int(fixture["id"]), 1)
		monster.elements = (fixture["elements"] as Array).duplicate()
		state.addMonster(monster, fixture["pos"] as Vector2i, int(fixture["team"]))

	var adapter: HexBattleVisualAdapter = HexBattleVisualAdapterScript.new(_root, map, state)
	for fixture: Dictionary in FIXTURES:
		adapter._on_monster_spawned(
			int(fixture["id"]), str(fixture["name"]), int(fixture["team"]),
			fixture["pos"] as Vector2i, {})

	var seenModels: Dictionary = {}
	for fixture: Dictionary in FIXTURES:
		var id: int = int(fixture["id"])
		var actual: Node3D = adapter.modelFor(id)
		_require(actual != null, "adapter created no model for ID %d" % id)
		if actual == null:
			continue
		_require(not seenModels.has(actual), "ID %d reused another model" % id)
		seenModels[actual] = true
		_require(actual.position.is_equal_approx(adapter.worldPositionOf(fixture["pos"] as Vector2i)),
			"ID %d model position diverged from its cell" % id)
		var expected := MonsterModelFactoryScript.build(
			str(fixture["name"]), NoggThemeScript.team_color(int(fixture["team"])),
			fixture["elements"] as Array)
		_require(_modelSignature(actual) == _modelSignature(expected),
			"ID %d materials or split bounds diverged from direct factory input %s" % [
				id, fixture["elements"]
			])
		expected.free()
	_require(seenModels.size() == FIXTURES.size(),
		"adapter built %d distinct models for %d IDs" % [seenModels.size(), FIXTURES.size()])
	adapter.dispose()


func _checkNullStateFallback() -> void:
	var map: BattleMapDefinition = _buildMap()
	var adapter: HexBattleVisualAdapter = HexBattleVisualAdapterScript.new(_root, map, null)
	var id := 4199
	var pos := Vector2i(0, 1)
	adapter._on_monster_spawned(id, "Smoke Cloud", 2, pos, {})
	var actual: Node3D = adapter.modelFor(id)
	var expected := MonsterModelFactoryScript.build("Smoke Cloud", NoggThemeScript.team_color(2), [])
	_require(actual != null, "null-state fallback created no model")
	if actual != null:
		_require(actual.position.is_equal_approx(adapter.worldPositionOf(pos)),
			"null-state fallback did not preserve cell position")
		_require(_modelSignature(actual) == _modelSignature(expected),
			"null-state fallback did not use neutral factory input")
	expected.free()
	adapter.dispose()


func _checkWholeModelDiagonal() -> void:
	var model := MonsterModelFactoryScript.build(
		"Smoke Cloud", NoggThemeScript.team_color(1), ["fire", "water"])
	var body := model.get_child(1) as Node3D
	_require(body != null, "dual-element model has no body")
	if body == null:
		model.free()
		return
	var materials: Array[ShaderMaterial] = []
	_checkSplitTransforms(body, Transform3D.IDENTITY, materials)
	_require(materials.size() > 1,
		"dual-element fixture did not exercise a multi-part body")
	model.free()


func _checkSplitTransforms(
		node: Node, fromBody: Transform3D, materials: Array[ShaderMaterial]) -> void:
	for child: Node in node.get_children():
		var childNode := child as Node3D
		if childNode == null:
			continue
		var bodyTransform := fromBody * childNode.transform
		var mesh := childNode as MeshInstance3D
		if mesh != null:
			var material := mesh.material_override as ShaderMaterial
			_require(material != null and material.get_shader_parameter("split_color") == true,
				"dual-element body part is not using its split material")
			if material != null:
				_require(not materials.has(material),
					"two body parts still share one mutable split transform")
				materials.append(material)
				_require((material.get_shader_parameter("split_model_origin") as Vector3)
					.is_equal_approx(bodyTransform.origin),
					"body part split origin is not in whole-model space")
				_require((material.get_shader_parameter("split_model_basis_x") as Vector3)
					.is_equal_approx(bodyTransform.basis.x),
					"body part split X basis is not in whole-model space")
				_require((material.get_shader_parameter("split_model_basis_y") as Vector3)
					.is_equal_approx(bodyTransform.basis.y),
					"body part split Y basis is not in whole-model space")
				_require((material.get_shader_parameter("split_model_basis_z") as Vector3)
					.is_equal_approx(bodyTransform.basis.z),
					"body part split Z basis is not in whole-model space")
		_checkSplitTransforms(childNode, bodyTransform, materials)


func _buildMap() -> BattleMapDefinition:
	var map: BattleMapDefinition = BattleMapDefinitionScript.new()
	map.boardSize = Vector2i(3, 2)
	map.cellWidth = 2.0
	map.cellHeight = 2.0
	map.heightStep = 0.5
	map.terrainDefinitions = {
		"plain": {"traversable": true, "stoppable": true, "movement_cost": 1},
	}
	var cells: Array[Vector2i] = []
	var cellData := {}
	for y in range(2):
		for x in range(3):
			var cell := Vector2i(x, y)
			cells.append(cell)
			cellData[cell] = {"terrain": "plain", "height": 0}
	map.configureCells(cells, cellData)
	return map


func _modelSignature(model: Node3D) -> Array:
	var signature: Array = []
	_collectMaterialSignature(model, signature)
	return signature


func _collectMaterialSignature(node: Node, signature: Array) -> void:
	if node is MeshInstance3D:
		var mesh := node as MeshInstance3D
		var material := mesh.material_override as ShaderMaterial
		if material != null:
			signature.append({
				"albedo": material.get_shader_parameter("albedo_color"),
				"color_b": material.get_shader_parameter("color_b"),
				"split": material.get_shader_parameter("split_color"),
				"bounds_min": material.get_shader_parameter("split_bounds_min"),
				"bounds_size": material.get_shader_parameter("split_bounds_size"),
			})
	for child: Node in node.get_children():
		_collectMaterialSignature(child, signature)


func _require(condition: bool, message: String) -> void:
	if not condition:
		failures.append(message)
