## Authoritative weighted hex movement validation and projected queries.

class_name MovementResolver

const AStarPathfinderScript = preload("res://src/algorithms/AStarPathfinder.gd")
const HexGridScript = preload("res://src/board/HexGrid.gd")
const HexReachabilityScript = preload("res://src/algorithms/HexReachability.gd")

var state: BattleState
var events: BattleEvents


func _init(_state: BattleState, _events: BattleEvents) -> void:
	state = _state
	events = _events


func getReachability(monsterID: int) -> Dictionary:
	var monster = state.getMonster(monsterID)
	if monster == null or not monster.is_alive():
		return {"positions": [], "costs": {}, "predecessors": {}}
	var startPos := state.getMonsterPosition(monsterID)
	return HexReachabilityScript.calculate(
		startPos,
		getEffectiveMove(monsterID),
		_canEnterBound.bind(monsterID),
		_canPassBound.bind(monsterID),
		_canStopBound.bind(monsterID),
		_traversalCost,
		_terminatesMovementBound.bind(monsterID)
	)


func getReachablePositions(monsterID: int) -> Array:
	return getReachability(monsterID)["positions"]


func findPath(fromPos: Vector2i, toPos: Vector2i, maxCost: int = 100) -> Array:
	var monster = state.getMonsterAt(fromPos)
	if monster == null:
		return []
	return AStarPathfinderScript.findPath(
		fromPos,
		toPos,
		_canEnterPath.bind(monster.uniqueID, toPos),
		maxCost,
		_traversalCost,
		_canPassPath.bind(monster.uniqueID, toPos),
		_canStopPath.bind(monster.uniqueID, toPos),
		_terminatesMovementBound.bind(monster.uniqueID),
		_minimumTraversalCost()
	)


func canTraverse(
		monsterID: int,
		fromPos: Vector2i,
		toPos: Vector2i,
		allowOccupiedDestination: bool = false) -> bool:
	if not _canEnterTerrain(monsterID, fromPos, toPos):
		return false
	return allowOccupiedDestination or not state.isOccupied(toPos)


func validateMovePath(monsterID: int, path: Array) -> Dictionary:
	var monster = state.getMonster(monsterID)
	if monster == null or not monster.is_alive():
		return {"success": false, "reason": "invalid_monster"}
	var previous := state.getMonsterPosition(monsterID)
	if path.is_empty():
		return {"success": true, "destination": previous, "cost": 0}

	var visited: Dictionary = {previous: true}
	var totalCost := 0
	var previousTerminated := false
	for index in range(path.size()):
		var stepValue = path[index]
		if not stepValue is Vector2i:
			return {"success": false, "reason": "invalid_path_coordinate"}
		var step: Vector2i = stepValue
		if previousTerminated:
			return {"success": false, "reason": "movement_terminated"}
		if visited.has(step):
			return {"success": false, "reason": "path_loop"}
		if not state.containsCell(step):
			return {"success": false, "reason": "path_out_of_bounds"}
		if not HexGridScript.neighbours(previous).has(step):
			return {"success": false, "reason": "non_contiguous_path"}
		if not _canEnterTerrain(monsterID, previous, step):
			return {"success": false, "reason": _terrainFailureReason(monsterID, previous, step)}
		if state.isOccupied(step):
			return {"success": false, "reason": "path_occupied"}

		totalCost += _traversalCost(previous, step)
		if totalCost > getEffectiveMove(monsterID):
			return {"success": false, "reason": "path_exceeds_move"}
		var finalStep := index == path.size() - 1
		if finalStep and not _canStopTerrain(step):
			return {"success": false, "reason": "destination_not_stoppable"}
		if not finalStep and not _canPassTerrain(step):
			return {"success": false, "reason": "path_not_passable"}

		visited[step] = true
		previous = step
		previousTerminated = _terminatesMovement(monsterID, step)

	return {"success": true, "destination": previous, "cost": totalCost}


func executeMove(monsterID: int, path: Array) -> bool:
	if path.is_empty():
		return false
	var validation := validateMovePath(monsterID, path)
	if not validation["success"]:
		return false
	state.moveMonsterTo(monsterID, validation["destination"])
	state.add_event("move", monsterID, -1, {
		"path": path.duplicate(),
		"cost": validation["cost"],
	})
	events.monster_moved.emit(monsterID, path)
	return true


func getEffectiveMove(monsterID: int) -> int:
	var monster = state.getMonster(monsterID)
	if monster == null:
		return 0
	var bonus := 0
	for effect in state.getActiveEffects(monsterID):
		bonus += int(effect.get("move_bonus", 0))
	return maxi(0, monster.move + bonus)


func _canEnterTerrain(monsterID: int, fromPos: Vector2i, toPos: Vector2i) -> bool:
	var monster = state.getMonster(monsterID)
	if monster == null or not monster.is_alive():
		return false
	if not state.containsCell(fromPos) or not state.containsCell(toPos):
		return false
	if not HexGridScript.neighbours(fromPos).has(toPos):
		return false
	if not state.isWalkable(toPos):
		return false
	if state.getHeightDifference(fromPos, toPos) > monster.jump:
		return false
	return true


func _canPassTerrain(cell: Vector2i) -> bool:
	if state.battleMap == null:
		return state.isWalkable(cell)
	return bool(state.battleMap.terrainDefinitionAt(cell).get("passable", false))


func _canStopTerrain(cell: Vector2i) -> bool:
	if state.battleMap == null:
		return state.isWalkable(cell)
	return state.battleMap.isStoppable(cell)


func _traversalCost(_fromPos: Vector2i, toPos: Vector2i) -> int:
	if not state.containsCell(toPos):
		return 0
	if state.battleMap != null:
		return state.battleMap.movementCostAt(toPos)
	return int(state.movementCostBoard.at(toPos))


func _terminatesMovement(monsterID: int, cell: Vector2i) -> bool:
	if state.battleMap != null and bool(
			state.battleMap.terrainDefinitionAt(cell).get("ends_movement", false)):
		return true
	var monster = state.getMonster(monsterID)
	if monster == null:
		return true
	for neighbor: Vector2i in HexGridScript.neighbours(cell):
		var other = state.getMonsterAt(neighbor)
		if other != null and other.is_alive() and other.team != monster.team:
			return true
	return false


func _minimumTraversalCost() -> int:
	var minimum := 2147483647
	if state.battleMap != null:
		for cell: Vector2i in state.battleMap.validCells():
			var cost := state.battleMap.movementCostAt(cell)
			if cost > 0:
				minimum = mini(minimum, cost)
	else:
		for y in range(state.boardSize.y):
			for x in range(state.boardSize.x):
				var cost := int(state.movementCostBoard.at(Vector2i(x, y)))
				if cost > 0:
					minimum = mini(minimum, cost)
	return 1 if minimum == 2147483647 else minimum


func _terrainFailureReason(monsterID: int, fromPos: Vector2i, toPos: Vector2i) -> String:
	if not state.containsCell(toPos) or not state.isWalkable(toPos):
		return "path_blocked"
	var monster = state.getMonster(monsterID)
	if monster != null and state.getHeightDifference(fromPos, toPos) > monster.jump:
		return "height_exceeds_jump"
	return "non_contiguous_path"


func _canEnterBound(current: Vector2i, next: Vector2i, monsterID: int) -> bool:
	return canTraverse(monsterID, current, next)


func _canPassBound(cell: Vector2i, _monsterID: int) -> bool:
	return not state.isOccupied(cell) and _canPassTerrain(cell)


func _canStopBound(cell: Vector2i, _monsterID: int) -> bool:
	return not state.isOccupied(cell) and _canStopTerrain(cell)


func _terminatesMovementBound(cell: Vector2i, monsterID: int) -> bool:
	return _terminatesMovement(monsterID, cell)


func _canEnterPath(current: Vector2i, next: Vector2i, monsterID: int, destination: Vector2i) -> bool:
	return canTraverse(monsterID, current, next, next == destination)


func _canPassPath(cell: Vector2i, _monsterID: int, destination: Vector2i) -> bool:
	return cell == destination or (not state.isOccupied(cell) and _canPassTerrain(cell))


func _canStopPath(cell: Vector2i, _monsterID: int, destination: Vector2i) -> bool:
	if cell == destination and state.isOccupied(cell):
		return true
	return not state.isOccupied(cell) and _canStopTerrain(cell)
