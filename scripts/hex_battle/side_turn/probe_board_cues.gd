extends SceneTree

const AdapterScript = preload("res://src/presentation/battle/HexBattleVisualAdapter.gd")
const ScreenCuesScript = preload(
	"res://src/presentation/battle/ui/side_turn/SideTurnScreenCues.gd")
const BattleSetupConfigScript = preload("res://src/battle_sim/BattleSetupConfig.gd")
const BattleSetupFactoryScript = preload("res://src/battle_sim/BattleSetupFactory.gd")
const BattleScenarioFactoryScript = preload("res://src/factories/BattleScenarioFactory.gd")
const BattleSimulatorScript = preload("res://src/battle_sim/BattleSimulator.gd")

const SCENARIO := "res://data/battle/scenarios/technical_hxb_contract_cpu_cpu.json"

var failures: Array[String] = []
var _world: Node3D
var _adapter
var _cues


func _init() -> void:
	_world = Node3D.new()
	root.add_child(_world)
	process_frame.connect(_run, CONNECT_ONE_SHOT)


func _run() -> void:
	var loaded := BattleScenarioFactoryScript.loadFromPath(SCENARIO)
	_require(bool(loaded.get("success", false)), "scenario did not load")
	if failures.is_empty():
		var config := BattleSetupConfigScript.new()
		config.scenarioPath = SCENARIO
		config.seed = 20260916
		var built := BattleSetupFactoryScript.createHexState(config)
		_require(bool(built.get("success", false)), "state did not build")
		if bool(built.get("success", false)):
			_checkWorldCues(loaded["scenario"], built["state"])
			_checkScreenCues()
	_finish()


func _checkWorldCues(scenario, state) -> void:
	var sim = BattleSimulatorScript.new(20260916)
	sim.configureHexState(state, scenario, {"scenarioPath": SCENARIO})
	_adapter = AdapterScript.new(_world, scenario.battleMap, sim.state)
	_adapter.connectToEvents(sim.events)
	sim.emitInitialBoard()
	var ids: Array = _adapter.shownModelIDs()
	_require(ids.size() >= 2, "fixture did not render enough unit models")
	if ids.size() < 2:
		return
	var spentID := int(ids[0])
	var targetID := int(ids[1])
	var model: Node3D = _adapter.modelFor(spentID)
	var mesh := _firstUnitMesh(model)
	var authoredMaterial: Material = mesh.material_override if mesh != null else null
	_adapter.setUnitSpent(spentID, true)
	_require(_adapter.isUnitSpent(spentID), "spent state was not retained")
	_require(mesh != null and mesh.material_overlay != null, "spent unit received no overlay")
	_require(mesh == null or mesh.material_override == authoredMaterial,
		"spent treatment replaced the unit's authored material")
	_adapter.setHoveredUnit(spentID)
	_require(mesh != null and mesh.material_overlay is ShaderMaterial,
		"hover did not temporarily replace the spent overlay with its outline")
	_adapter.setHoveredUnit(-1)
	_require(mesh != null and mesh.material_overlay is StandardMaterial3D,
		"leaving hover did not restore the spent overlay")
	_adapter.setUnitSpent(spentID, false)
	_require(mesh == null or mesh.material_overlay == null,
		"clearing spent did not restore the original presentation")

	_adapter.setTargetedUnit(targetID)
	_require(_adapter.targetedUnit() == targetID, "sword target was not retained")
	var targetModel: Node3D = _adapter.modelFor(targetID)
	_require(targetModel.get_node_or_null("TargetSword") != null,
		"sword marker was not parented to its target model")
	_adapter.setTargetedUnit(-1)
	_require(_adapter.targetedUnit() == -1, "sword target did not clear")

	var region: Array = scenario.battleMap.validCells().slice(0, 7)
	_adapter.show_movement_options(region)
	_require(_adapter.layerCellCount(AdapterScript.LAYER_REACH) == region.size(),
		"reachable region lost its logical cell count")
	_require((_adapter._layers[AdapterScript.LAYER_REACH] as Array).size() == 1,
		"reachable cells were not consolidated into one region mesh")


func _checkScreenCues() -> void:
	_cues = ScreenCuesScript.new()
	root.add_child(_cues)
	_cues.setProjector(func(world: Vector3): return Vector2(400.0 + world.x, 100.0 + world.z))
	_cues.showTurnBanner(true)
	_cues.showActionArc(Vector3.ZERO, {
		"magic": false, "item": true, "status": true, "wait": true,
	}, ["magic"], true)
	_require(_cues.actionArcFlipped(), "arc did not flip below a unit near the top edge")
	_cues.setAiming(true)
	_require(_cues._arc.modulate.a < 0.5, "aiming did not fade the action arc")
	var forecast := {
		"available": true, "minimum": 12, "maximum": 18,
		"critical_chance": 0.1, "exact": false,
		"target_hitpoints": 15, "possibly_lethal": true,
	}
	_cues.showForecasts([
		{"monster_id": 1, "name": "One", "world_anchor": Vector3.ZERO,
			"forecast": forecast},
		{"monster_id": 2, "name": "Two", "world_anchor": Vector3.ONE,
			"forecast": forecast},
	])
	_require(_cues.previewCount() == 2, "multiple forecast boxes were not retained")
	_cues.setReadyCount(2)
	_cues._endButton._onPressed()
	_require(_cues.endTurnConfirming(), "End turn did not ask before skipping ready units")


func _firstUnitMesh(model: Node3D) -> MeshInstance3D:
	if model == null:
		return null
	for node in model.find_children("*", "MeshInstance3D", true, false):
		var mesh := node as MeshInstance3D
		if not _adapter._isUnitChrome(mesh, model):
			return mesh
	return null


func _require(condition: bool, message: String) -> void:
	if not condition:
		failures.append(message)


func _finish() -> void:
	if _adapter != null:
		_adapter.dispose()
	if not failures.is_empty():
		for failure: String in failures:
			printerr("STB_BOARD_CUES_FAILURE: %s" % failure)
		quit(1)
		return
	print("STB_BOARD_CUES_OK")
	quit(0)
