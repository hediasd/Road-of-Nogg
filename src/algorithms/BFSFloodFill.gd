## Pure BFS flood-fill for uniform-cost movement on the shared hex lattice.
## Weighted battle movement uses HexReachability; this remains the deliberately
## narrow uniform-edge primitive.

class_name BFSFloodFill

const HexGridScript = preload("res://src/board/HexGrid.gd")


static func getReachable(
		startPos: Vector2i,
		maxRange: int,
		isPassable: Callable,
		excludeStart: bool = true) -> Array[Vector2i]:
	var costMap: Dictionary = {startPos: 0}
	var frontier: Array[Vector2i] = [startPos]
	var reachable: Array[Vector2i] = []

	while not frontier.is_empty():
		var current: Vector2i = frontier.pop_front()
		var currentCost: int = costMap[current]
		if not excludeStart or current != startPos:
			reachable.append(current)
		if currentCost >= maxRange:
			continue
		for neighbor: Vector2i in HexGridScript.neighbours(current):
			var newCost := currentCost + 1
			if not bool(isPassable.call(current, neighbor)):
				continue
			if costMap.has(neighbor) and int(costMap[neighbor]) <= newCost:
				continue
			costMap[neighbor] = newCost
			frontier.append(neighbor)
	return reachable
