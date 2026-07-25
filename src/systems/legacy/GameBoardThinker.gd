extends Node

class_name GameBoardThinker

var battleBoard
var test = 0

var nextSteps = [
		Vector2i(-1,0), Vector2i(1,0),	Vector2i(0,-1),	Vector2i(0,1)
	]


func _init(_battleBoard) -> void:
	battleBoard = _battleBoard
	pass


func _process(delta: float) -> void:


	pass


func think(currentMon: Monster) -> Dictionary:

	var walkableAmount = currentMon.get("move")
	var currentPos = battleBoard.whereIs(currentMon)
	var reachablePositionsList = reachablePositions(currentPos, walkableAmount)

	#print("currentMon is at ", currentPos, " walkable amount is ", walkableAmount, " and it can go to ", reachablePositionsList)

	var pathToPosition = pathTo(currentPos, reachablePositionsList.back(), walkableAmount)

	var turnDecision = {
		"MOVE": pathToPosition,
		"ACTION": [

		]
	}

	return turnDecision


func reachablePositions(currentPos : Vector2i, walkableAmount : int):

	var reachableCostedList = [[ currentPos ]]
	var reachableList = [ currentPos ]

	for cost in range(1, walkableAmount+1):

		var iterationReachableList = []
		var previousReachableList = reachableCostedList[cost-1]

		for previousPoint in previousReachableList:
			for step in nextSteps:
				var newPoint = previousPoint + step

				if((newPoint not in reachableList)
				and (battleBoard.withinBounds(newPoint))
				and (battleBoard.isWalkable(newPoint))
				and (not battleBoard.isOccupied(newPoint))):
					reachableList.append((newPoint))
					iterationReachableList.append((newPoint))

		reachableCostedList.append(iterationReachableList)

	return reachableList


func pathTo(currentPos: Vector2i, targetPos: Vector2i, walkableAmount : int):

	var currentPath =	[]
	var cheapestPath = []

	for step in nextSteps:
		pathTo_recursion(currentPos+step, targetPos, currentPath, cheapestPath, walkableAmount)

	return cheapestPath

func pathTo_recursion(currentPos: Vector2i, targetPos: Vector2i, previousPath: Array, cheapestPath: Array, maxWalk: int):

	var currentPath = previousPath.duplicate(true)
	currentPath.append(currentPos)

	if(not battleBoard.withinBounds(currentPos)):
		#print(currentPos, " is out of bounds")
		return

	if(currentPath.size() > maxWalk):
		#print(currentPath, " walked too much")
		return

	if(currentPos == targetPos):
		#print(currentPos, " equals target ", targetPos, " with path ", currentPath)
		if((currentPath.size() < cheapestPath.size()) or (cheapestPath.is_empty())):
			cheapestPath.clear()
			cheapestPath.assign(currentPath)
			#print("new cheapest path is ", cheapestPath)
			return

	for step in nextSteps:
		var tentativeNextStep = currentPos+step
		if(currentPath.has(tentativeNextStep) == false):
			var path = pathTo_recursion(tentativeNextStep, targetPos, currentPath, cheapestPath, maxWalk)

	return
