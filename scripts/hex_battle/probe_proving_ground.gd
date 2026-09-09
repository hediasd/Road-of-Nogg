extends SceneTree

const AStarPathfinderScript = preload("res://src/algorithms/AStarPathfinder.gd")
const HexGridScript = preload("res://src/board/HexGrid.gd")
const LineOfSightScript = preload("res://src/algorithms/LineOfSight.gd")
const BattleSetupConfigScript = preload("res://src/battle_sim/BattleSetupConfig.gd")
const BattleSetupFactoryScript = preload("res://src/battle_sim/BattleSetupFactory.gd")
const BattleSimulatorScript = preload("res://src/battle_sim/BattleSimulator.gd")
const PartyDeliberationScript = preload("res://src/entity_ai/PartyCommandDeliberation.gd")
const BattleMapFactoryScript = preload("res://src/factories/BattleMapFactory.gd")
const BattleScenarioFactoryScript = preload("res://src/factories/BattleScenarioFactory.gd")

const MAP_PATH := "res://data/battle/maps/proving_ground.json"
const AUTHORED_PATH := "res://data/worldmap/authored/proving_ground.json"
const SCENARIO_PATHS := [
	"res://data/battle/scenarios/proving_ground_player_cpu.json",
	"res://data/battle/scenarios/proving_ground_cpu_cpu.json",
]
const MAX_ROUNDS := 30

var failures: Array[String] = []


func _init() -> void:
	var loaded := BattleMapFactoryScript.loadFromPath(MAP_PATH)
	_require(loaded["success"], "proving map did not load: %s" % str(loaded.get("error", "")))
	if loaded["success"]:
		_checkMapVocabulary(loaded["definition"])
	_checkAuthoredDocumentIsFlat()
	for scenarioPath: String in SCENARIO_PATHS:
		_checkScenario(scenarioPath)
	if not failures.is_empty():
		for failure: String in failures:
			printerr("HXB_PROVING_FAILURE: %s" % failure)
		quit(1)
		return
	print("HXB_PROVING_OK")
	quit(0)


func _require(condition: bool, message: String) -> void:
	if not condition:
		failures.append(message)


func _checkMapVocabulary(map) -> void:
	_require(map.boardSize == Vector2i(20, 10), "board dimensions changed")
	_require(map.containsCell(Vector2i(2, 2)) and map.containsCell(Vector2i(3, 2)),
		"both column parities are not playable")
	_require(not map.containsCell(Vector2i(6, 5)), "internal board hole was filled")
	_require(map.containsCell(Vector2i(6, 4)) and map.containsCell(Vector2i(6, 6)),
		"the declared hole is not inside the board")

	for cell: Vector2i in map.validCells():
		_require(map.heightAt(cell) == 0, "non-flat elevation at %s" % cell)

	for y in range(10):
		var cell := Vector2i(10, y)
		_require(map.containsCell(cell), "chokepoint column left the board at %s" % cell)
		if y == 4:
			_require(map.isTraversable(cell), "the one-cell chokepoint is blocked")
		else:
			_require(not map.isTraversable(cell), "chokepoint is wider than one cell at %s" % cell)

	_require(map.terrainAt(Vector2i(12, 4)) == "blocked"
		and map.blocksLineOfSight(Vector2i(12, 4)), "line-of-sight blocker is absent")
	_require(not LineOfSightScript.hasLoS(Vector2i(11, 4), Vector2i(15, 4),
		func(cell: Vector2i) -> bool: return map.blocksLineOfSight(cell)),
		"blocked cell does not break line of sight")

	var shortRoute: Array[Vector2i] = [
		Vector2i(4, 2), Vector2i(5, 1), Vector2i(6, 1),
		Vector2i(7, 1), Vector2i(8, 2), Vector2i(9, 2),
	]
	var detour: Array[Vector2i] = [
		Vector2i(3, 1), Vector2i(3, 0), Vector2i(4, 0), Vector2i(5, 0),
		Vector2i(6, 0), Vector2i(7, 0), Vector2i(8, 0), Vector2i(9, 0),
		Vector2i(9, 1), Vector2i(9, 2),
	]
	var start := Vector2i(3, 2)
	_require(_isRouteTraversable(map, start, shortRoute), "short rough route is malformed")
	_require(_isRouteTraversable(map, start, detour), "clear detour route is malformed")
	var shortCost := _routeCost(map, start, shortRoute)
	var detourCost := _routeCost(map, start, detour)
	_require(shortRoute.size() < detour.size() and shortCost > detourCost,
		"rough band does not make a longer route cheaper (%d/%d vs %d/%d)" % [
			shortRoute.size(), shortCost, detour.size(), detourCost,
		])
	var cheapest: Array = AStarPathfinderScript.findPath(
		start, Vector2i(9, 2),
		func(_from: Vector2i, candidate: Vector2i) -> bool: return map.isTraversable(candidate),
		100,
		func(_from: Vector2i, candidate: Vector2i) -> int: return map.movementCostAt(candidate),
		func(cell: Vector2i) -> bool: return map.isTraversable(cell),
		func(cell: Vector2i) -> bool: return map.isStoppable(cell),
	)
	_require(not cheapest.is_empty() and cheapest.size() > shortRoute.size(),
		"weighted route did not avoid the shorter rough band")
	_require(AStarPathfinderScript.pathCost(cheapest,
		func(_from: Vector2i, candidate: Vector2i) -> int: return map.movementCostAt(candidate), start) < shortCost,
		"weighted route cost did not beat the shorter rough route")

	var deploymentDistance := HexGridScript.distance(Vector2i(2, 2), Vector2i(17, 2))
	_require(deploymentDistance >= 12, "deployment areas are too close: %d" % deploymentDistance)


func _checkAuthoredDocumentIsFlat() -> void:
	var file := FileAccess.open(AUTHORED_PATH, FileAccess.READ)
	_require(file != null, "authored document could not be opened")
	if file == null:
		return
	var parsed = JSON.parse_string(file.get_as_text())
	_require(parsed is Dictionary, "authored document is not a dictionary")
	if not parsed is Dictionary:
		return
	for layerValue in parsed.get("LAYERS", []):
		if layerValue is Dictionary:
			_require(str(layerValue.get("KIND", "")) != "heights",
				"the proving ground must not carry a height layer")


func _isRouteTraversable(map, start: Vector2i, route: Array[Vector2i]) -> bool:
	var previous := start
	for cell: Vector2i in route:
		if not HexGridScript.neighbours(previous).has(cell) or not map.isTraversable(cell):
			return false
		previous = cell
	return true


func _routeCost(map, start: Vector2i, route: Array[Vector2i]) -> int:
	var total := 0
	for cell: Vector2i in route:
		total += map.movementCostAt(cell)
	return total


func _checkScenario(scenarioPath: String) -> void:
	var loaded := BattleScenarioFactoryScript.loadFromPath(scenarioPath)
	_require(loaded["success"], "scenario %s did not load: %s" % [
		scenarioPath, str(loaded.get("error", "")),
	])
	if not loaded["success"]:
		return
	var config = BattleSetupConfigScript.new()
	config.scenarioPath = scenarioPath
	config.seed = int(loaded["scenario"].seed)
	var stateResult := BattleSetupFactoryScript.createHexState(config)
	_require(stateResult["success"], "scenario %s could not build state: %s" % [
		scenarioPath, str(stateResult.get("error", "")),
	])
	if not stateResult["success"]:
		return
	var simulator: BattleSimulator = BattleSimulatorScript.new(config.seed)
	simulator.configureHexState(stateResult["state"], stateResult["scenario"], config.serialize())
	simulator.startBattle()
	var activations := 0
	while simulator.state.battleOutcome == -1 and simulator.state.roundCount <= MAX_ROUNDS:
		var opened := simulator.startNextPartyActivation("proving_probe")
		if not opened["success"]:
			_require(str(opened.get("reason", "")) == "round_complete",
				"scenario %s could not advance: %s" % [scenarioPath, opened.get("reason", "")])
			if str(opened.get("reason", "")) != "round_complete":
				break
			continue
		while simulator.state.activePartyID != -1 and simulator.state.battleOutcome == -1:
			activations += 1
			_require(activations <= 400, "scenario %s exceeded activation safety bound" % scenarioPath)
			if activations > 400:
				break
			var proposal = PartyDeliberationScript.new(simulator).run(64)
			_require(proposal != null, "scenario %s produced no party proposal" % scenarioPath)
			if proposal == null:
				break
			var selection := simulator.selectPartyMember(proposal.actor_id, "proving_probe")
			_require(selection["success"], "scenario %s rejected selected member" % scenarioPath)
			if not selection["success"]:
				break
			var outcome := simulator.executeCommand(proposal.actor_id, proposal.command, "proving_probe")
			_require(outcome.success, "scenario %s rejected its proposal: %s" % [
				scenarioPath, str(outcome.reason),
			])
			if not outcome.success:
				break
	_require(simulator.state.battleOutcome != -1,
		"scenario %s did not reach a result within %d rounds" % [scenarioPath, MAX_ROUNDS])
	_require(simulator.state.roundCount <= MAX_ROUNDS,
		"scenario %s exceeded %d rounds" % [scenarioPath, MAX_ROUNDS])
