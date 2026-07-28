## Game-specific movement validation and application.
## Pure logic; all movement consumers share canTraverse().

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
	return BFSFloodFill.getReachable(startPos, getEffectiveMove(monsterID), _canTraverseBound.bind(monsterID))


func findPath(fromPos: Vector2i, toPos: Vector2i, maxSteps: int = 100) -> Array:
	var monster = state.getMonsterAt(fromPos)
	if monster == null:
		return []
	return AStarPathfinder.findPath(
		fromPos,
		toPos,
		_canTraversePath.bind(monster.uniqueID, fromPos, toPos),
		maxSteps
	)


func canTraverse(
		monsterID: int,
		fromPos: Vector2i,
		toPos: Vector2i,
		allowOccupiedDestination: bool = false) -> bool:
	var mon = state.getMonster(monsterID)
	if mon == null or not mon.is_alive():
		return false
	if not state.withinBounds(fromPos) or not state.withinBounds(toPos):
		return false
	if abs(fromPos.x - toPos.x) + abs(fromPos.y - toPos.y) != 1:
		return false
	if not state.isWalkable(toPos):
		return false
	if state.getHeightDifference(fromPos, toPos) > mon.jump:
		return false
	return allowOccupiedDestination or not state.isOccupied(toPos)


func validateMovePath(monsterID: int, path: Array) -> Dictionary:
	var mon = state.getMonster(monsterID)
	if mon == null or not mon.is_alive():
		return {"success": false, "reason": "invalid_monster"}
	if path.size() > getEffectiveMove(monsterID):
		return {"success": false, "reason": "path_exceeds_move"}
	if path.is_empty():
		return {"success": true, "destination": state.getMonsterPosition(monsterID)}

	var previous: Vector2i = state.getMonsterPosition(monsterID)
	var visited: Dictionary = {previous: true}
	for stepValue in path:
		if not stepValue is Vector2i:
			return {"success": false, "reason": "invalid_path_coordinate"}
		var step: Vector2i = stepValue
		if visited.has(step):
			return {"success": false, "reason": "path_loop"}
		if not state.withinBounds(step):
			return {"success": false, "reason": "path_out_of_bounds"}
		if abs(previous.x - step.x) + abs(previous.y - step.y) != 1:
			return {"success": false, "reason": "non_contiguous_path"}
		if not state.isWalkable(step):
			return {"success": false, "reason": "path_blocked"}
		if state.isOccupied(step):
			return {"success": false, "reason": "path_occupied"}
		if state.getHeightDifference(previous, step) > mon.jump:
			return {"success": false, "reason": "height_exceeds_jump"}
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


func getEffectiveMove(monsterID: int) -> int:
	var monster = state.getMonster(monsterID)
	if monster == null:
		return 0
	var bonus = 0
	for effect in state.getActiveEffects(monsterID):
		bonus += int(effect.get("move_bonus", 0))
	return maxi(0, monster.move + bonus)

func _canTraverseBound(current: Vector2i, next: Vector2i, monsterID: int) -> bool:
	return canTraverse(monsterID, current, next)


func _canTraversePath(
		current: Vector2i,
		next: Vector2i,
		monsterID: int,
		_fromPos: Vector2i,
		toPos: Vector2i) -> bool:
	return canTraverse(monsterID, current, next, next == toPos)