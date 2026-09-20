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
	##
	## Costs are small non-negative integers bounded by `maxCost`, and every step
	## costs at least one, so a relaxation can only ever move a cell into a
	## strictly later bucket. A bucket is therefore complete before it is opened:
	## sorting it once on its stable (row, column) key reproduces exactly the
	## selection order a repeated scan for the cheapest frontier cell produced,
	## without that scan's quadratic cost or its membership test.
	var costs: Dictionary = {startPos: 0}
	var predecessors: Dictionary = {}
	var buckets: Array = []
	buckets.resize(maxi(0, maxCost) + 1)
	buckets[0] = [startPos] as Array[Vector2i]

	for currentCost in range(buckets.size()):
		var bucket = buckets[currentCost]
		if bucket == null:
			continue
		bucket.sort_custom(_rowMajorLess)
		for current: Vector2i in bucket:
			if int(costs[current]) != currentCost:
				continue
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
				if buckets[newCost] == null:
					buckets[newCost] = [] as Array[Vector2i]
				buckets[newCost].append(neighbor)
		buckets[currentCost] = null

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


static func _rowMajorLess(a: Vector2i, b: Vector2i) -> bool:
	return a.y < b.y or (a.y == b.y and a.x < b.x)
