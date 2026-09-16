extends SceneTree

const BattleSetupConfigScript = preload("res://src/battle_sim/BattleSetupConfig.gd")
const BattleSetupFactoryScript = preload("res://src/battle_sim/BattleSetupFactory.gd")
const BattleSimulatorScript = preload("res://src/battle_sim/BattleSimulator.gd")

const SCENARIO_PATH := "res://data/battle/scenarios/technical_hxb_contract_player_cpu.json"

var failures: Array[String] = []


func _init() -> void:
	_checkRules()
	_checkDeterminism()
	if not failures.is_empty():
		for failure: String in failures:
			printerr("SIDE_TURN_RULES_FAILURE: %s" % failure)
		quit(1)
		return
	print("SIDE_TURN_RULES_OK")
	quit(0)


func _require(condition: bool, message: String) -> void:
	if not condition:
		failures.append(message)


func _simulator(seed: int = 4242) -> BattleSimulator:
	var config = BattleSetupConfigScript.new()
	config.scenarioPath = SCENARIO_PATH
	config.seed = seed
	var stateResult := BattleSetupFactoryScript.createHexState(config)
	_require(stateResult["success"], "hex setup failed: %s" % stateResult.get("error", ""))
	if not stateResult["success"]:
		return null
	var simulator: BattleSimulator = BattleSimulatorScript.new(seed)
	simulator.configureHexState(stateResult["state"], stateResult["scenario"], config.serialize())
	simulator.startBattle()
	return simulator


func _checkRules() -> void:
	var simulator := _simulator()
	if simulator == null:
		return
	var opened := simulator.startNextSideTurn("probe")
	_require(opened["success"] and opened["side_id"] == 1,
		"side order was not deterministic ascending team ID")
	_require(simulator.state.sideOrder == [1, 2], "round side order changed")
	var units := simulator.eligibleSideUnitIDs()
	_require(units.size() >= 2, "probe side needs at least two units")
	if units.size() < 2:
		return
	var first := int(units[0])
	var second := int(units[1])
	_require(simulator.selectUnit(first, "probe")["success"], "first unit selection failed")
	var reachable: Array = simulator.movementResolver.getReachablePositions(first)
	var origin := simulator.state.getMonsterPosition(first)
	var destination := origin
	for cell in reachable:
		if cell != origin:
			destination = cell
			break
	_require(destination != origin, "probe unit had no move destination")
	if destination != origin:
		var path := simulator.movementResolver.findPath(origin, destination, 100)
		var moved := simulator.executeMovePhase(first, path, "probe")
		_require(moved["success"] and simulator.state.getMonsterPosition(first) == destination,
			"move-only phase failed")
		_require(not simulator.state.spentUnitIDs.has(first), "moving alone spent the unit")
		var castAfterMove := simulator.executeActionPhase(first, "spell", destination, 0, 0, "probe")
		_require(not castAfterMove["success"] and castAfterMove["reason"] == "spell_after_move",
			"casting after moving was not refused")

	_require(simulator.selectUnit(second, "probe")["success"], "free unit switch failed")
	_require(simulator.selectUnit(first, "probe")["success"], "returning to moved unit failed")
	if destination != origin:
		var undone := simulator.undoMovePhase(first)
		_require(undone["success"] and simulator.state.getMonsterPosition(first) == origin,
			"pending move did not undo")

	var acted := simulator.executeCommand(first, BattleCommand.wait(), "probe")
	_require(acted.success and simulator.state.spentUnitIDs.has(first), "Wait did not spend the unit")
	var spentSelection := simulator.selectUnit(first, "probe")
	_require(not spentSelection["success"] and spentSelection["reason"] == "unit_already_spent",
		"spent unit could be selected")
	var moveAfterAct := simulator.executeMovePhase(first, [], "probe")
	_require(not moveAfterAct["success"], "unit moved after acting")
	var undoAfterAct := simulator.undoMovePhase(first)
	_require(not undoAfterAct["success"], "move undo remained available after acting")

	var remainingBefore := simulator.eligibleSideUnitIDs()
	var ended := simulator.endSideTurn("probe")
	_require(ended["success"] and ended["consumed"] == remainingBefore,
		"End turn did not spend every ready unit in ID order")
	_require(simulator.state.activeSideID == -1, "End turn left the side active")

	opened = simulator.startNextSideTurn("probe")
	_require(opened["success"] and opened["side_id"] == 2, "enemy side did not open")
	var enemyUnits := simulator.eligibleSideUnitIDs()
	for enemyID: int in enemyUnits:
		_require(simulator.selectUnit(enemyID, "probe")["success"], "enemy unit selection failed")
		_require(simulator.executeCommand(enemyID, BattleCommand.wait(), "probe").success,
			"enemy wait failed")
	_require(simulator.state.activeSideID == -1,
		"spending the final unit did not end the side turn automatically")


func _checkDeterminism() -> void:
	var first := _deterministicHistory(771)
	var second := _deterministicHistory(771)
	_require(BattleSimulatorScript._canonicalJSON(first) == BattleSimulatorScript._canonicalJSON(second),
		"equal seeds produced different side-turn histories")


func _deterministicHistory(seed: int) -> Array:
	var simulator := _simulator(seed)
	if simulator == null:
		return []
	for _sideIndex in range(2):
		var opened := simulator.startNextSideTurn("determinism")
		if not opened["success"]:
			break
		for monsterID: int in simulator.eligibleSideUnitIDs():
			if simulator.state.activeSideID == -1:
				break
			simulator.selectUnit(monsterID, "determinism")
			simulator.executeCommand(monsterID, BattleCommand.wait(), "determinism")
	return simulator.state.history.duplicate(true)
