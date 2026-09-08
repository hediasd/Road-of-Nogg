## Pure, deterministic weighted A* over the shared flat-top hex lattice.

class_name AStarPathfinder

const HexGridScript = preload("res://src/board/HexGrid.gd")


static func findPath(
		fromPos: Vector2i,
		toPos: Vector2i,
		canEnter: Callable,
		maxCost: int = 200,
		getTraversalCost: Callable = Callable(),
		canPass: Callable = Callable(),
		canStop: Callable = Callable(),
		terminatesMovement: Callable = Callable(),
		minimumTraversalCost: int = 1) -> Array[Vector2i]:
	## Returns a path excluding the start and including the destination.
	##
	## `canEnter(current, next)` controls edge entry. `canPass(cell)` controls
	## whether a reached cell may be expanded, while `canStop(cell)` controls
	## whether it may be the destination. A terminating cell may be entered and
	## stopped on but never expanded. The separate decisions keep terrain and
	## control-zone rules out of this graph implementation.
	if fromPos == toPos or maxCost < 0:
		return []

	var openSet: Array[Dictionary] = []
	var closedSet: Dictionary = {}
	var cameFrom: Dictionary = {}
	var gScore: Dictionary = {fromPos: 0}
	var sequence := 0
	openSet.append({
		"pos": fromPos,
		"g": 0,
		"f": HexGridScript.distance(fromPos, toPos) * maxi(0, minimumTraversalCost),
		"sequence": sequence,
	})

	while not openSet.is_empty():
		var currentIndex := _bestOpenIndex(openSet)
		var current: Dictionary = openSet[currentIndex]
		openSet.remove_at(currentIndex)
		var currentPos: Vector2i = current["pos"]
		if closedSet.has(currentPos):
			continue
		closedSet[currentPos] = true

		if currentPos == toPos:
			if not canStop.is_valid() or bool(canStop.call(currentPos)):
				return _reconstructPath(cameFrom, toPos)
			return []
		if int(current["g"]) >= maxCost:
			continue
		if currentPos != fromPos:
			if canPass.is_valid() and not bool(canPass.call(currentPos)):
				continue
			if terminatesMovement.is_valid() and bool(terminatesMovement.call(currentPos)):
				continue

		for neighbor: Vector2i in HexGridScript.neighbours(currentPos):
			if closedSet.has(neighbor) or not bool(canEnter.call(currentPos, neighbor)):
				continue
			var stepCost := 1
			if getTraversalCost.is_valid():
				stepCost = int(getTraversalCost.call(currentPos, neighbor))
			if stepCost <= 0:
				continue
			var tentativeCost: int = int(current["g"]) + stepCost
			if tentativeCost > maxCost:
				continue
			if gScore.has(neighbor) and tentativeCost >= int(gScore[neighbor]):
				continue

			cameFrom[neighbor] = currentPos
			gScore[neighbor] = tentativeCost
			sequence += 1
			openSet.append({
				"pos": neighbor,
				"g": tentativeCost,
				"f": tentativeCost + HexGridScript.distance(neighbor, toPos) * maxi(0, minimumTraversalCost),
				"sequence": sequence,
			})

	return []


static func pathCost(path: Array, getTraversalCost: Callable, fromPos: Vector2i) -> int:
	var total := 0
	var previous := fromPos
	for value in path:
		if not value is Vector2i:
			return -1
		var cell: Vector2i = value
		var stepCost := 1 if not getTraversalCost.is_valid() else int(
			getTraversalCost.call(previous, cell))
		if stepCost <= 0:
			return -1
		total += stepCost
		previous = cell
	return total


static func _bestOpenIndex(openSet: Array[Dictionary]) -> int:
	var best := 0
	for index in range(1, openSet.size()):
		var candidate: Dictionary = openSet[index]
		var incumbent: Dictionary = openSet[best]
		if int(candidate["f"]) < int(incumbent["f"]):
			best = index
		elif int(candidate["f"]) == int(incumbent["f"]):
			if int(candidate["g"]) < int(incumbent["g"]):
				best = index
			elif int(candidate["g"]) == int(incumbent["g"]):
				var a: Vector2i = candidate["pos"]
				var b: Vector2i = incumbent["pos"]
				if a.y < b.y or (a.y == b.y and a.x < b.x):
					best = index
				elif a == b and int(candidate["sequence"]) < int(incumbent["sequence"]):
					best = index
	return best


static func _reconstructPath(cameFrom: Dictionary, current: Vector2i) -> Array[Vector2i]:
	var path: Array[Vector2i] = [current]
	while cameFrom.has(current):
		current = cameFrom[current]
		path.push_front(current)
	if not path.is_empty():
		path.pop_front()
	return path
