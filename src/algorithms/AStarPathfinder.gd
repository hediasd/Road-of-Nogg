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

	## The open set is a binary heap ordered by the same total key the previous
	## repeated scan selected on: cheapest estimate, then cheapest cost so far,
	## then storage row and column, then insertion sequence. Entries sharing all
	## of those describe the same cell reached the same way, so heap order and
	## scan order agree while the heap drops the per-pop linear scan.
	var openSet: Array[Dictionary] = []
	var closedSet: Dictionary = {}
	var cameFrom: Dictionary = {}
	var gScore: Dictionary = {fromPos: 0}
	var sequence := 0
	_pushOpen(openSet, {
		"pos": fromPos,
		"g": 0,
		"f": HexGridScript.distance(fromPos, toPos) * maxi(0, minimumTraversalCost),
		"sequence": sequence,
	})

	while not openSet.is_empty():
		var current: Dictionary = _popOpen(openSet)
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
			_pushOpen(openSet, {
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


static func _openPrecedes(candidate: Dictionary, incumbent: Dictionary) -> bool:
	var candidateF := int(candidate["f"])
	var incumbentF := int(incumbent["f"])
	if candidateF != incumbentF:
		return candidateF < incumbentF
	var candidateG := int(candidate["g"])
	var incumbentG := int(incumbent["g"])
	if candidateG != incumbentG:
		return candidateG < incumbentG
	var a: Vector2i = candidate["pos"]
	var b: Vector2i = incumbent["pos"]
	if a.y != b.y:
		return a.y < b.y
	if a.x != b.x:
		return a.x < b.x
	return int(candidate["sequence"]) < int(incumbent["sequence"])


static func _pushOpen(openSet: Array[Dictionary], entry: Dictionary) -> void:
	openSet.append(entry)
	var child := openSet.size() - 1
	while child > 0:
		var parent := (child - 1) >> 1
		if not _openPrecedes(openSet[child], openSet[parent]):
			return
		var swap := openSet[parent]
		openSet[parent] = openSet[child]
		openSet[child] = swap
		child = parent


static func _popOpen(openSet: Array[Dictionary]) -> Dictionary:
	var best: Dictionary = openSet[0]
	var last: Dictionary = openSet.pop_back()
	if openSet.is_empty():
		return best
	openSet[0] = last
	var parent := 0
	while true:
		var left := parent * 2 + 1
		var right := left + 1
		var smallest := parent
		if left < openSet.size() and _openPrecedes(openSet[left], openSet[smallest]):
			smallest = left
		if right < openSet.size() and _openPrecedes(openSet[right], openSet[smallest]):
			smallest = right
		if smallest == parent:
			return best
		var swap := openSet[parent]
		openSet[parent] = openSet[smallest]
		openSet[smallest] = swap
		parent = smallest
	return best


static func _reconstructPath(cameFrom: Dictionary, current: Vector2i) -> Array[Vector2i]:
	var path: Array[Vector2i] = [current]
	while cameFrom.has(current):
		current = cameFrom[current]
		path.push_front(current)
	if not path.is_empty():
		path.pop_front()
	return path
