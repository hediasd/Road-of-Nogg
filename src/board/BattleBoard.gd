class_name BattleBoard

var heightBoardMatrix: Matrix
var monsterBoardMatrix: Matrix
var naturalObstacleBoardMatrix: Matrix
var walkableBoardMatrix: Matrix

func _init(boardSize : Vector2i) -> void:

	heightBoardMatrix = Matrix.new(boardSize[0], boardSize[1])
	monsterBoardMatrix = Matrix.new(boardSize[0], boardSize[1])
	naturalObstacleBoardMatrix = Matrix.new(boardSize[0], boardSize[1])
	walkableBoardMatrix = Matrix.new(boardSize[0], boardSize[1])

	## DEBUGGING CONTENTS
	#for x in range(boardMatrix.get("max_x")):
	#	for y in range(boardMatrix.get("max_y")):
	#		var a = boardMatrix.get_value(x, y)
	#		print(str(x) + " " + str(y) + " value:" + str(a))

	pass


func setMonster(mon : Monster, referencePos):
	var monID = mon.get("uniqueID")
	setMonsterID(monID, referencePos)
	pass
func setMonsterID(monID : int, referencePos):
	monsterBoardMatrix.set_at(monID, referencePos)
	pass

func whereIs(mon : Monster):
	var monID = mon.get("uniqueID")
	for x in range(0, monsterBoardMatrix.get("max_x")):
		for y in range(0, monsterBoardMatrix.get("max_y")):
			if(monsterBoardMatrix.at_xy(x, y) == mon.get("uniqueID")):
				return Vector2i(x, y)
	print("MON NOT FOUND ", mon)
	return null


func heightAt(pos : Vector2i):
	return heightBoardMatrix.at(pos)
func monsterAt(pos : Vector2i):
	return monsterBoardMatrix.at(pos)

func withinBounds(pos : Vector2i) -> bool:
	return (pos[0] >= 0
			and pos[0] < walkableBoardMatrix.get("max_x")
			and pos[1] >= 0
			and pos[1] < walkableBoardMatrix.get("max_y"))

func isOccupied(pos : Vector2i):
	return monsterBoardMatrix.at(pos) != 0

func isWalkable(pos : Vector2i):
	return walkableBoardMatrix.at(pos) == 0
