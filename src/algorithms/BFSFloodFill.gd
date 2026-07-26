## Pure BFS flood-fill for reachable-tile enumeration on 2D grids.
## Fully stateless — accepts a callable for passability checks.
## Decoupled from all game state; usable by any system.

class_name BFSFloodFill

const DIRECTIONS: Array[Vector2i] = [
	Vector2i(-1, 0), Vector2i(1, 0),
	Vector2i(0, -1), Vector2i(0, 1)
]


static func getReachable(
		startPos: Vector2i,
		maxRange: int,
		isPassable: Callable,
		excludeStart: bool = true) -> Array[Vector2i]:
	## Returns all positions reachable from startPos within maxRange steps.
	## isPassable: func(current: Vector2i, next: Vector2i) -> bool
	## All tiles cost 1 step (uniform movement cost).

	var costMap: Dictionary = { startPos: 0 }
	var frontier: Array[Vector2i] = [startPos]
	var reachable: Array[Vector2i] = []

	while not frontier.is_empty():
		var current: Vector2i = frontier.pop_front()
		var currentCost: int = costMap[current]

		if not excludeStart or current != startPos:
			reachable.append(current)

		if currentCost >= maxRange:
			continue

		for dir in DIRECTIONS:
			var neighbor: Vector2i = current + dir
			var newCost: int = currentCost + 1

			if not isPassable.call(current, neighbor):
				continue
			if costMap.has(neighbor) and costMap[neighbor] <= newCost:
				continue

			costMap[neighbor] = newCost
			frontier.append(neighbor)

	return reachable
