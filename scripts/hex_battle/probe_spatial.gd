extends SceneTree

const AStarPathfinderScript = preload("res://src/algorithms/AStarPathfinder.gd")
const BFSFloodFillScript = preload("res://src/algorithms/BFSFloodFill.gd")
const HexGridScript = preload("res://src/board/HexGrid.gd")
const HexReachabilityScript = preload("res://src/algorithms/HexReachability.gd")
const LineOfSightScript = preload("res://src/algorithms/LineOfSight.gd")
const ShapeCasterScript = preload("res://src/algorithms/ShapeCaster.gd")
const BattleEventsScript = preload("res://src/battle_sim/BattleEvents.gd")
const BattleSetupConfigScript = preload("res://src/battle_sim/BattleSetupConfig.gd")
const BattleSetupFactoryScript = preload("res://src/battle_sim/BattleSetupFactory.gd")
const CombatResolverScript = preload("res://src/battle_sim/CombatResolver.gd")
const MovementResolverScript = preload("res://src/battle_sim/MovementResolver.gd")
const PassiveSkillResolverScript = preload("res://src/battle_sim/PassiveSkillResolver.gd")
const PassiveSkillScript = preload("res://src/entities/PassiveSkill.gd")
const SpellScript = preload("res://src/entities/Spell.gd")

const SCENARIO_PATH := "res://data/battle/scenarios/technical_hxb_contract_player_cpu.json"
const GRAPH_PATH := "res://scripts/hex_battle/fixtures/spatial/weighted_graph.json"

var failures: Array[String] = []


func _init() -> void:
	_checkWeightedAlgorithms()
	_checkShapes()
	_checkLineOfSight()
	_checkMovementBoundary()
	_checkCombatBoundary()
	_checkPassiveAreas()
	_checkNoSquareFallback()
	if not failures.is_empty():
		for failure: String in failures:
			printerr("HXB_SPATIAL_FAILURE: %s" % failure)
		quit(1)
		return
	print("HXB_SPATIAL_OK")
	quit(0)


func _require(condition: bool, message: String) -> void:
	if not condition:
		failures.append(message)


func _checkWeightedAlgorithms() -> void:
	var graph := _loadGraph()
	if graph.is_empty():
		return
	var cells: Array[Vector2i] = graph["cells"]
	var costs: Dictionary = graph["costs"]
	var lookup: Dictionary = {}
	for cell: Vector2i in cells:
		lookup[cell] = true

	for start: Vector2i in cells:
		for target: Vector2i in cells:
			if start == target:
				continue
			var oracleCost := _exhaustiveCost(start, target, lookup, costs)
			var path := AStarPathfinderScript.findPath(
				start,
				target,
				func(_current: Vector2i, next: Vector2i) -> bool: return lookup.has(next),
				100,
				func(_current: Vector2i, next: Vector2i) -> int: return int(costs[next]),
				Callable(),
				Callable(),
				Callable(),
				1
			)
			var actualCost := -1 if path.is_empty() else AStarPathfinderScript.pathCost(
				path, func(_current: Vector2i, next: Vector2i) -> int: return int(costs[next]), start)
			_require(actualCost == oracleCost,
				"A* cost %d differed from oracle %d for %s -> %s" %
				[actualCost, oracleCost, start, target])

	var reach := HexReachabilityScript.calculate(
		Vector2i(0, 2),
		5,
		func(_current: Vector2i, next: Vector2i) -> bool: return lookup.has(next),
		func(_cell: Vector2i) -> bool: return true,
		func(_cell: Vector2i) -> bool: return true,
		func(_current: Vector2i, next: Vector2i) -> int: return int(costs[next]),
		func(_cell: Vector2i) -> bool: return false
	)
	for cell: Vector2i in cells:
		var oracleCost := _exhaustiveCost(Vector2i(0, 2), cell, lookup, costs)
		var shouldReach := cell != Vector2i(0, 2) and oracleCost >= 0 and oracleCost <= 5
		_require(reach["positions"].has(cell) == shouldReach,
			"weighted reachability disagreed with oracle at %s" % cell)
		if shouldReach:
			_require(int(reach["costs"][cell]) == oracleCost,
				"weighted reach cost disagreed at %s" % cell)

	var bfs := BFSFloodFillScript.getReachable(
		Vector2i(2, 2), 1, func(_a: Vector2i, _b: Vector2i) -> bool: return true)
	_require(bfs.size() == 6, "uniform BFS did not use six hex neighbours")
	for neighbor: Vector2i in HexGridScript.neighbours(Vector2i(2, 2)):
		_require(bfs.has(neighbor), "uniform BFS omitted hex neighbour %s" % neighbor)


func _loadGraph() -> Dictionary:
	var file := FileAccess.open(GRAPH_PATH, FileAccess.READ)
	if file == null:
		failures.append("weighted graph fixture could not be opened")
		return {}
	var parsed = JSON.parse_string(file.get_as_text())
	if not parsed is Dictionary:
		failures.append("weighted graph fixture is not a dictionary")
		return {}
	var size := Vector2i(int(parsed["size"][0]), int(parsed["size"][1]))
	var blocked: Dictionary = {}
	for pair in parsed["blocked"]:
		blocked[Vector2i(int(pair[0]), int(pair[1]))] = true
	var cells: Array[Vector2i] = []
	var costs: Dictionary = {}
	for y in range(size.y):
		for x in range(size.x):
			var cell := Vector2i(x, y)
			if blocked.has(cell):
				continue
			cells.append(cell)
			costs[cell] = 1
	for entry in parsed["costs"]:
		var pair = entry["cell"]
		costs[Vector2i(int(pair[0]), int(pair[1]))] = int(entry["cost"])
	return {"cells": cells, "costs": costs}


func _exhaustiveCost(
		start: Vector2i, target: Vector2i, lookup: Dictionary, costs: Dictionary) -> int:
	var best: Dictionary = {start: 0}
	var frontier: Array[Vector2i] = [start]
	while not frontier.is_empty():
		var current: Vector2i = frontier.pop_front()
		for neighbor: Vector2i in HexGridScript.neighbours(current):
			if not lookup.has(neighbor):
				continue
			var candidate := int(best[current]) + int(costs[neighbor])
			if best.has(neighbor) and int(best[neighbor]) <= candidate:
				continue
			best[neighbor] = candidate
			frontier.append(neighbor)
	return int(best[target]) if best.has(target) else -1


func _checkShapes() -> void:
	for center in [Vector2i(2, 2), Vector2i(3, 2)]:
		_require(ShapeCasterScript.getCircle(center, 2).size() == 19,
			"radius-two disc count changed at parity %d" % (center.x & 1))
		var cross: Array[Vector2i] = ShapeCasterScript.getCross(center, 2)
		_require(cross.size() == 13, "radius-two cross did not contain six rays")
		_require(cross.has(center), "cross omitted its center")
		for cell: Vector2i in cross:
			var axialDelta := HexGridScript.offsetToAxial(cell) - HexGridScript.offsetToAxial(center)
			_require(cell == center or _isAxialRay(axialDelta),
				"cross contained off-axis cell %s" % cell)
	var line := ShapeCasterScript.getLine(Vector2i(2, 2), Vector2i(4, 3), 3)
	_require(line.size() == 3 and not line.has(Vector2i(2, 2)),
		"line did not exclude caster or preserve length")
	for index in range(line.size()):
		_require(HexGridScript.distance(Vector2i(2, 2), line[index]) == index + 1,
			"line did not follow one axial ray")


func _isAxialRay(delta: Vector2i) -> bool:
	if delta == Vector2i.ZERO:
		return true
	for direction: Vector2i in HexGridScript.AXIAL_NEIGHBOURS:
		for scale in range(1, 8):
			if delta == direction * scale:
				return true
	return false


func _checkLineOfSight() -> void:
	var rays := [
		[Vector2i(0, 0), Vector2i(6, 3)],
		[Vector2i(0, 1), Vector2i(6, 1)],
		[Vector2i(1, 0), Vector2i(5, 4)],
		[Vector2i(0, 3), Vector2i(6, 0)],
	]
	for ray in rays:
		var forward: Array[Vector2i] = LineOfSightScript.supercoverCells(ray[0], ray[1])
		var reverse: Array[Vector2i] = LineOfSightScript.supercoverCells(ray[1], ray[0])
		forward.sort_custom(_rowMajorLess)
		reverse.sort_custom(_rowMajorLess)
		_require(forward == reverse, "supercover was asymmetric for %s -> %s" % ray)
		_require(forward.has(ray[0]) and forward.has(ray[1]), "supercover omitted endpoint")
		var blockers := forward.filter(func(cell: Vector2i) -> bool:
			return cell != ray[0] and cell != ray[1])
		for blocker: Vector2i in blockers:
			_require(not LineOfSightScript.hasLoS(ray[0], ray[1],
				func(cell: Vector2i) -> bool: return cell == blocker),
				"touched cell %s did not block forward LoS" % blocker)
			_require(not LineOfSightScript.hasLoS(ray[1], ray[0],
				func(cell: Vector2i) -> bool: return cell == blocker),
				"touched cell %s did not block reverse LoS" % blocker)
		_require(LineOfSightScript.hasLoS(ray[0], ray[1],
			func(cell: Vector2i) -> bool: return cell == ray[0] or cell == ray[1]),
			"LoS tested a source or target endpoint")
	_require(LineOfSightScript.supercoverCells(Vector2i(0, 1), Vector2i(6, 1)).size() > 7,
		"edge-aligned supercover did not include both seam sides")
	var highBlocker := Vector2i(2, 1)
	_require(not LineOfSightScript.hasHeightAwareLoS(
		Vector2i(0, 0), Vector2i(4, 2), 1.0, 5.0,
		func(cell: Vector2i) -> float: return 10.0 if cell == highBlocker else -INF),
		"height-aware LoS ignored a touched tall blocker")
	_require(LineOfSightScript.hasHeightAwareLoS(
		Vector2i(0, 0), Vector2i(4, 2), 5.0, 5.0,
		func(_cell: Vector2i) -> float: return 0.0),
		"low terrain blocked a level elevated ray")


func _checkMovementBoundary() -> void:
	var state = _freshState()
	if state == null:
		return
	_placeOnly(state, [103, 200], [Vector2i(1, 3), Vector2i(5, 3)])
	var actor = state.getMonster(103)
	actor.move = 10
	actor.jump = 3
	var resolver = MovementResolverScript.new(state, BattleEventsScript.new())
	var cheapPath: Array = resolver.findPath(Vector2i(1, 3), Vector2i(4, 4), 10)
	_require(not cheapPath.is_empty(), "weighted A* found no route around costly terrain")
	var cheapValidation := resolver.validateMovePath(103, cheapPath)
	_require(cheapValidation["success"] and int(cheapValidation["cost"]) == 3,
		"weighted A* did not choose the cost-three route")
	var reachability: Dictionary = resolver.getReachability(103)
	for destination: Vector2i in reachability["positions"]:
		var previewPath: Array = resolver.findPath(Vector2i(1, 3), destination, 10)
		var authoritative := resolver.validateMovePath(103, previewPath)
		_require(authoritative["success"] and
			int(authoritative["cost"]) == int(reachability["costs"][destination]),
			"movement preview and validation disagreed at %s" % destination)

	actor.move = 3
	var costlyValidation := resolver.validateMovePath(
		103, [Vector2i(2, 3), Vector2i(3, 3)])
	_require(not costlyValidation["success"] and costlyValidation["reason"] == "path_exceeds_move",
		"command validation used path length instead of traversal cost")
	actor.move = 10
	var terminated := resolver.validateMovePath(103, [
		Vector2i(2, 4), Vector2i(3, 4), Vector2i(4, 4), Vector2i(5, 4)])
	_require(not terminated["success"] and terminated["reason"] == "movement_terminated",
		"hostile zone of control did not terminate movement")
	var hole := resolver.validateMovePath(103, [Vector2i(2, 3), Vector2i(3, 2)])
	_require(not hole["success"], "masked map hole accepted movement")
	actor.jump = 0
	var height := resolver.validateMovePath(103, [Vector2i(2, 3)])
	_require(not height["success"] and height["reason"] == "height_exceeds_jump",
		"height edge ignored JUMP")
	actor.jump = 3
	var occupied := resolver.validateMovePath(103, [
		Vector2i(2, 4), Vector2i(3, 4), Vector2i(4, 4), Vector2i(5, 3)])
	_require(not occupied["success"], "occupied endpoint accepted movement")


func _checkCombatBoundary() -> void:
	var state = _freshState()
	if state == null:
		return
	_placeOnly(state, [100, 200], [Vector2i(2, 2), Vector2i(2, 1)])
	var caster = state.getMonster(100)
	var resolver = CombatResolverScript.new(state, BattleEventsScript.new())
	var basic: Array = resolver.getBasicAttackTargetPositionsFrom(100, Vector2i(2, 2))
	var expectedBasic: Array[Vector2i] = []
	for cell: Vector2i in HexGridScript.neighbours(Vector2i(2, 2)):
		if state.containsCell(cell) and state.getHeightDifference(Vector2i(2, 2), cell) <= 1:
			expectedBasic.append(cell)
	_require(_sameCells(basic, expectedBasic), "basic attack did not expose six-neighbour hex targets")
	_require(resolver.getProjectedOccupantID(100, Vector2i(2, 3), Vector2i(2, 2)) == 0,
		"projected move did not vacate the authoritative origin")
	_require(resolver.getProjectedOccupantID(100, Vector2i(2, 3), Vector2i(2, 3)) == 100,
		"projected move did not occupy its destination")

	var ringSpell = SpellScript.new({
		"NAME": "probe_ring", "MIN_RANGE": 2, "RANGE": 2,
		"MAX_HEIGHT_DELTA": 8, "TARGET_TYPE": "single", "CAN_TARGET_EMPTY": false,
		"BYPASS_LOS": true,
	})
	caster.spellSets = [[ringSpell]]
	var ring: Array = resolver.getSpellTargetPositionsFrom(100, 0, 0, Vector2i(2, 2), true)
	var expectedRing: Array[Vector2i] = []
	for cell: Vector2i in HexGridScript.disc(Vector2i(2, 2), 2):
		if state.containsCell(cell) and HexGridScript.distance(Vector2i(2, 2), cell) == 2:
			expectedRing.append(cell)
	_require(_sameCells(ring, expectedRing), "minimum range did not cut a complete hex ring")
	var emptyCenter: Vector2i = expectedRing.filter(
		func(cell: Vector2i) -> bool: return not state.isOccupied(cell))[0]
	_require(not resolver.canSpellTargetPositionFrom(100, 0, 0, Vector2i(2, 2), emptyCenter),
		"uncastable empty center became authoritative")
	_require(resolver.canSpellTargetPositionFrom(100, 0, 0, Vector2i(2, 2), emptyCenter, true),
		"preview could not expose an empty center footprint")

	var areaSpell = SpellScript.new({
		"NAME": "probe_area", "MIN_RANGE": 0, "RANGE": 4,
		"MAX_HEIGHT_DELTA": 8, "TARGET_TYPE": "area", "RADIUS": 2,
		"AREA_SHAPE": "circle", "CAN_TARGET_EMPTY": true, "BYPASS_LOS": true,
	})
	caster.spellSets = [[areaSpell]]
	var center := Vector2i(0, 0)
	var affected: Array = resolver.getSpellAffectedPositionsFrom(100, 0, 0, Vector2i(2, 2), center)
	var expectedArea: Array[Vector2i] = []
	for cell: Vector2i in HexGridScript.disc(center, 2):
		if state.containsCell(cell):
			expectedArea.append(cell)
	_require(_sameCells(affected, expectedArea), "border-clipped area differed from authoritative disc")
	_require(not affected.has(Vector2i(3, 2)), "area footprint included a masked map hole")


func _checkPassiveAreas() -> void:
	var state = _freshState()
	if state == null:
		return
	var center := Vector2i(1, 2)
	var cells: Array[Vector2i] = [center]
	cells.append_array(HexGridScript.neighbours(center))
	var ids := [100, 101, 102, 103, 200, 201, 202]
	_placeOnly(state, ids, cells)
	var source = state.getMonster(100)
	source.passives = [PassiveSkillScript.new({
		"NAME": "probe_aura", "TRIGGER": "ON_DEATH", "EFFECT_TYPE": "aoe_damage",
		"VALUE": 1, "ELEMENT": "none", "RADIUS": 1,
	})]
	var events = BattleEventsScript.new()
	var hitCount := [0]
	events.passive_aoe_damage.connect(func(_a, _b, _c, _d, _e, _f): hitCount[0] += 1)
	PassiveSkillResolverScript.new(state, events).fireEvent("ON_DEATH", 100)
	_require(hitCount[0] == 6, "radius-one passive aura did not affect all six occupied neighbours")


func _checkNoSquareFallback() -> void:
	var paths := [
		"res://src/algorithms/AStarPathfinder.gd",
		"res://src/algorithms/BFSFloodFill.gd",
		"res://src/algorithms/HexReachability.gd",
		"res://src/algorithms/ShapeCaster.gd",
		"res://src/battle_sim/MovementResolver.gd",
		"res://src/battle_sim/CombatResolver.gd",
	]
	for path: String in paths:
		var source := FileAccess.get_file_as_string(path)
		_require(not source.contains("Manhattan") and not source.contains("Cardinal grid") and
			not source.contains("const DIRECTIONS"), "square-grid fallback remained in %s" % path)


func _freshState():
	var config = BattleSetupConfigScript.new()
	config.scenarioPath = SCENARIO_PATH
	var result := BattleSetupFactoryScript.createHexState(config)
	_require(result["success"], "could not construct spatial fixture state: %s" % result.get("error", ""))
	return result.get("state") if result["success"] else null


func _placeOnly(state, ids: Array, cells: Array) -> void:
	for value in state.monsterPositions.keys().duplicate():
		state.removeMonster(int(value))
	for index in range(ids.size()):
		var monsterID: int = ids[index]
		var cell: Vector2i = cells[index]
		state.monsterPositions[monsterID] = cell
		state.monsters[monsterID].position = cell
		state.board.set_at(monsterID, cell)
	state.assertValidOccupancy()


func _sameCells(a: Array, b: Array) -> bool:
	var aCopy := a.duplicate()
	var bCopy := b.duplicate()
	aCopy.sort_custom(_rowMajorLess)
	bCopy.sort_custom(_rowMajorLess)
	return aCopy == bCopy


func _rowMajorLess(a: Vector2i, b: Vector2i) -> bool:
	return a.y < b.y or (a.y == b.y and a.x < b.x)
