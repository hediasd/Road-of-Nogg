extends Node

class_name GameBoardLogic

var battleBoard

func _init(_battleBoard) -> void:
	battleBoard = _battleBoard
	pass

func _process(delta: float) -> void:

	pass


func spawnMonster(newMonster: Monster, referencePos: Vector2i):
	battleBoard.setMonster(newMonster, referencePos)
	pass

func moveMonster(monster, newPosition) -> bool:

	if(battleBoard.monsterAt(newPosition) != 0):
		print(monster, " tried to step on someone at ", newPosition)
		return false

	battleBoard.setMonsterID(0, monster.get("position"))
	battleBoard.setMonster(monster, newPosition)

	monster.setPosition(newPosition)

	return true

func runTurnDecision(runTurnDecision):
	pass
