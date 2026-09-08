## Deterministic weighted reachability over the shared flat-top hex lattice.

class_name HexReachability

const HexGridScript = preload("res://src/board/HexGrid.gd")


static func calculate(
		startPos: Vector2i,
		maxCost: int,
		canEnter: Callable,
		canPass: Callable,
		canStop: Callable,
		getTraversalCost: Callable,
		terminatesMovement: Callable) -> Dictionary:
	## Returns stable reachable positions plus cheapest costs and predecessors.
	## Positions exclude `startPos`; callers that offer "stay" add it explicitly.
	var costs: Dictionary = {startPos: 0}
	var predecessors: Dictionary = {}
	var frontier: Array[Vector2i] = [startPos]

	while not frontier.is_empty():
		var currentIndex := _lowestCostIndex(frontier, costs)
		var current: Vector2i = frontier[currentIndex]
		frontier.remove_at(currentIndex)
		var currentCost: int = costs[current]
		if currentCost >= maxCost:
			continue
		if current != startPos and (
				not bool(canPass.call(current)) or bool(terminatesMovement.call(current))):
			continue

		for neighbor: Vector2i in HexGridScript.neighbours(current):
			if not bool(canEnter.call(current, neighbor)):
				continue
			var stepCost := int(getTraversalCost.call(current, neighbor))
			if stepCost <= 0:
				continue
			var newCost := currentCost + stepCost
			if newCost > maxCost:
				continue
			if costs.has(neighbor) and int(costs[neighbor]) <= newCost:
				continue
			costs[neighbor] = newCost
			predecessors[neighbor] = current
			if not frontier.has(neighbor):
				frontier.append(neighbor)

	var positions: Array[Vector2i] = []
	for value in costs:
		var cell: Vector2i = value
		if cell != startPos and bool(canStop.call(cell)):
			positions.append(cell)
	positions.sort_custom(func(a: Vector2i, b: Vector2i) -> bool:
		var aCost: int = costs[a]
		var bCost: int = costs[b]
		if aCost != bCost:
			return aCost < bCost
		return a.y < b.y or (a.y == b.y and a.x < b.x)
	)
	return {"positions": positions, "costs": costs, "predecessors": predecessors}


static func pathTo(result: Dictionary, startPos: Vector2i, destination: Vector2i) -> Array[Vector2i]:
	if destination == startPos or not result.get("costs", {}).has(destination):
		return []
	var predecessors: Dictionary = result.get("predecessors", {})
	var current := destination
	var path: Array[Vector2i] = [current]
	while current != startPos:
		if not predecessors.has(current):
			return []
		current = predecessors[current]
		path.push_front(current)
	path.pop_front()
	return path


static func _lowestCostIndex(frontier: Array[Vector2i], costs: Dictionary) -> int:
	var best := 0
	for index in range(1, frontier.size()):
		var candidate := frontier[index]
		var incumbent := frontier[best]
		var candidateCost: int = costs[candidate]
		var incumbentCost: int = costs[incumbent]
		if candidateCost < incumbentCost or (
				candidateCost == incumbentCost and (
					candidate.y < incumbent.y or (
						candidate.y == incumbent.y and candidate.x < incumbent.x))):
			best = index
	return best
