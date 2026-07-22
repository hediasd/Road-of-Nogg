## MovementResolver — Game-specific movement application layer.
## Delegates pure algorithms to AStarPathfinder and BFSFloodFill.
## Handles game rules: occupancy validation, move range, and event emission.
## Pure logic, no Node dependency.

class_name MovementResolver

const BFSFloodFill = preload("res://src/algorithms/BFSFloodFill.gd")
const AStarPathfinder = preload("res://src/algorithms/AStarPathfinder.gd")

var state: BattleState
var events: BattleEvents


func _init(_state: BattleState, _events: BattleEvents) -> void:
	state = _state
	events = _events


# --- Reachable positions (BFS, respects move range and occupancy) ---

func getReachablePositions(monsterID: int) -> Array:
	## Returns all grid positions this monster can move to within its move range.
	var mon = state.getMonster(monsterID)
	if mon == null:
		return []
	var startPos = state.getMonsterPosition(monsterID)
	return BFSFloodFill.getReachable(startPos, mon.move, _isPassableForMonster.bind(monsterID))


# --- A* pathfinding ---

func findPath(fromPos: Vector2i, toPos: Vector2i, maxSteps: int = 100) -> Array:
	## A* path from fromPos to toPos, excluding start, including destination.
	## Returns empty array if no path found.
	return AStarPathfinder.findPath(fromPos, toPos, _isPassableForPath.bind(fromPos, toPos), maxSteps)


# --- Execute movement ---

func executeMove(monsterID: int, path: Array) -> bool:
	## Validates and executes a movement along the given path.
	## Returns true if the move was successful.
	if path.is_empty():
		return false

	var mon = state.getMonster(monsterID)
	if mon == null or not mon.is_alive():
		return false

	if path.size() > mon.move:
		return false

	var destination: Vector2i = path.back()
	if state.isOccupied(destination):
		return false

	state.moveMonsterTo(monsterID, destination)
	events.monster_moved.emit(monsterID, path)
	return true


# --- Passability callbacks (passed to pure algorithm classes) ---

func _isPassableForMonster(pos: Vector2i, _monsterID: int) -> bool:
	## Used by BFS: a tile is passable if it's in-bounds, walkable, and unoccupied.
	if not state.withinBounds(pos):
		return false
	if not state.isWalkable(pos):
		return false
	if state.isOccupied(pos):
		return false
	return true


func _isPassableForPath(pos: Vector2i, fromPos: Vector2i, toPos: Vector2i) -> bool:
	## Used by A*: allows moving to occupied tiles only if it's the source or destination.
	if not state.withinBounds(pos):
		return false
	if not state.isWalkable(pos):
		return false
	if state.isOccupied(pos) and pos != fromPos and pos != toPos:
		return false
	return true
