## Pure A* pathfinding algorithm for 2D grid navigation.
## Fully stateless — accepts a callable for walkability checks.
## Decoupled from all game state; usable by any system.

class_name AStarPathfinder

# Cardinal grid directions (4-directional movement)
const DIRECTIONS: Array[Vector2i] = [
	Vector2i(-1, 0), Vector2i(1, 0),
	Vector2i(0, -1), Vector2i(0, 1)
]


static func findPath(
		fromPos: Vector2i,
		toPos: Vector2i,
		isPassable: Callable,
		maxSteps: int = 200) -> Array[Vector2i]:
	## A* pathfinding. Returns path as Array[Vector2i] excluding start, including destination.
	## isPassable: func(pos: Vector2i) -> bool
	## Returns empty array if no path found or fromPos == toPos.

	if fromPos == toPos:
		return []

	var openSet: Array = []
	var closedSet: Dictionary = {}
	var cameFrom: Dictionary = {}
	var gScore: Dictionary = {}

	gScore[fromPos] = 0
	openSet.append({ "pos": fromPos, "g": 0, "f": _heuristic(fromPos, toPos) })

	while not openSet.is_empty():
		# Find lowest-f node (linear scan — suitable for small grids)
		var currentIdx = 0
		for i in range(1, openSet.size()):
			if openSet[i]["f"] < openSet[currentIdx]["f"]:
				currentIdx = i

		var current = openSet[currentIdx]
		var currentPos: Vector2i = current["pos"]

		if currentPos == toPos:
			return _reconstructPath(cameFrom, toPos)

		openSet.remove_at(currentIdx)
		closedSet[currentPos] = true

		if current["g"] >= maxSteps:
			continue

		for dir in DIRECTIONS:
			var neighbor: Vector2i = currentPos + dir

			if closedSet.has(neighbor):
				continue
			if not isPassable.call(neighbor):
				continue

			var tentativeG: int = current["g"] + 1

			if gScore.has(neighbor) and tentativeG >= gScore[neighbor]:
				continue

			cameFrom[neighbor] = currentPos
			gScore[neighbor] = tentativeG
			var f: int = tentativeG + _heuristic(neighbor, toPos)

			var found = false
			for entry in openSet:
				if entry["pos"] == neighbor:
					entry["g"] = tentativeG
					entry["f"] = f
					found = true
					break
			if not found:
				openSet.append({ "pos": neighbor, "g": tentativeG, "f": f })

	return []  # No path found


static func _heuristic(a: Vector2i, b: Vector2i) -> int:
	## Manhattan distance heuristic for 4-directional grids.
	return abs(a.x - b.x) + abs(a.y - b.y)


static func _reconstructPath(cameFrom: Dictionary, current: Vector2i) -> Array[Vector2i]:
	var path: Array[Vector2i] = [current]
	while cameFrom.has(current):
		current = cameFrom[current]
		path.push_front(current)
	# Remove the starting position
	if not path.is_empty():
		path.pop_front()
	return path
