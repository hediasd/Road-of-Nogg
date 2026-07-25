## Game-specific movement validation and application.
## Pure logic; delegates reachability and pathfinding to stateless algorithms.

class_name MovementResolver

const BFSFloodFill = preload("res://src/algorithms/BFSFloodFill.gd")
const AStarPathfinder = preload("res://src/algorithms/AStarPathfinder.gd")

var state: BattleState
var events: BattleEvents


func _init(_state: BattleState, _events: BattleEvents) -> void:
	state = _state
	events = _events


func getReachablePositions(monsterID: int) -> Array:
	var mon = state.getMonster(monsterID)
	if mon == null:
		return []
	var startPos = state.getMonsterPosition(monsterID)
	return BFSFloodFill.getReachable(startPos, mon.move, _isPassableForMonster.bind(monsterID))


func findPath(fromPos: Vector2i, toPos: Vector2i, maxSteps: int = 100) -> Array:
	return AStarPathfinder.findPath(
		fromPos,
		toPos,
		_isPassableForPath.bind(fromPos, toPos),
		maxSteps
	)


func validateMovePath(monsterID: int, path: Array) -> Dictionary:
	var mon = state.getMonster(monsterID)
	if mon == null or not mon.is_alive():
		return {"success": false, "reason": "invalid_monster"}
	if path.size() > mon.move:
		return {"success": false, "reason": "path_exceeds_move"}
	if path.is_empty():
		return {"success": true, "destination": state.getMonsterPosition(monsterID)}

	var previous: Vector2i = state.getMonsterPosition(monsterID)
	var visited: Dictionary = {previous: true}
	for stepValue in path:
		if not stepValue is Vector2i:
			return {"success": false, "reason": "invalid_path_coordinate"}
		var step: Vector2i = stepValue
		if abs(previous.x - step.x) + abs(previous.y - step.y) != 1:
			return {"success": false, "reason": "non_contiguous_path"}
		if visited.has(step):
			return {"success": false, "reason": "path_loop"}
		if not state.withinBounds(step):
			return {"success": false, "reason": "path_out_of_bounds"}
		if not state.isWalkable(step):
			return {"success": false, "reason": "path_blocked"}
		if state.isOccupied(step):
			return {"success": false, "reason": "path_occupied"}
		visited[step] = true
		previous = step

	return {"success": true, "destination": previous}


func executeMove(monsterID: int, path: Array) -> bool:
	if path.is_empty():
		return false
	var validation = validateMovePath(monsterID, path)
	if not validation["success"]:
		return false

	state.moveMonsterTo(monsterID, validation["destination"])
	state.add_event("move", monsterID, -1, {"path": path.duplicate()})
	events.monster_moved.emit(monsterID, path)
	return true


func _isPassableForMonster(pos: Vector2i, _monsterID: int) -> bool:
	return state.withinBounds(pos) and state.isWalkable(pos) and not state.isOccupied(pos)


func _isPassableForPath(pos: Vector2i, fromPos: Vector2i, toPos: Vector2i) -> bool:
	if not state.withinBounds(pos) or not state.isWalkable(pos):
		return false
	return not state.isOccupied(pos) or pos == fromPos or pos == toPos
