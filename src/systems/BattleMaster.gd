## LEGACY ROLLBACK RUNTIME: gameplay authority belongs to BattleSimulator.
## Preserve this Node-driven path only until the canonical presentation
## controller reaches launch and visual parity. Do not add new gameplay here.

extends Node

var battleSample
var battleBoard

@export var gameBoardLogic:GameBoardLogic
@export var gameBoardThinker:GameBoardThinker
@export var gameBoardVisual:GameBoardVisual

var monsterFactory
var monsterList = []

var turnOrder = []
var turnCount: int = 0
var roundCount: int = 0

func _ready() -> void:

	battleSample = BattleSample.new()
	battleBoard = BattleBoard.new(battleSample.get("boardSize"))

	gameBoardLogic = GameBoardLogic.new(battleBoard)
	gameBoardThinker = GameBoardThinker.new(battleBoard)
	#gameBoardVisual = GameBoardVisual.new()

	add_child(gameBoardLogic)
	add_child(gameBoardThinker)
	#add_child(gameBoardVisual)

	spawnMonstersFromList(battleSample.get("monsterTeamCoordinatesList"))


	pass

# Called every frame. 'delta' is the elapsed time since the previous frame.
func _process(delta: float) -> void:

	if(turnCount < 12):
		if(turnOrder.is_empty()):
			print("STARTING %s ROUND ---------------- " % (roundCount+1))

		var currentTurnMonster = turnWheel()
		var turnDecision = gameBoardThinker.think(currentTurnMonster)

		print("TURN %s - It's %s [#%s] turn! " % [turnCount, currentTurnMonster.get("name"), currentTurnMonster.get("uniqueID")])
		print("%s [#%s] is at %s and wants to move to %s" % [currentTurnMonster.get("name"), currentTurnMonster.get("uniqueID"), turnDecision["MOVE"].front(), turnDecision["MOVE"].back()])

		runTurnDecision(turnDecision)

	pass

func runTurnDecision(turnDecision: Dictionary):

	gameBoardLogic.runTurnDecision(turnDecision)
	gameBoardVisual.runTurnDecision(turnDecision)

	pass

func spawnMonstersFromList(referenceList):
	for referenceKey in referenceList:
		spawnMonster(referenceKey["NAME"], referenceKey["TEAM"], referenceKey["POS"])
	pass


func spawnMonster(referenceName, referenceTeam, referencePos):

	var newMonster = MonsterFactory.createMonster(referenceName)
	monsterList.append(newMonster)

	gameBoardLogic.spawnMonster(newMonster, referencePos)
	gameBoardVisual.spawnMonster(newMonster, referencePos)

	print("%s [#%s] has spawned at %s" % [newMonster.get("name"), newMonster.get("uniqueID"), newMonster.get("position")])

	pass


func turnWheel():

	turnCount += 1
	if(turnOrder.is_empty()):
		roundCount += 1
		turnOrder = monsterList.duplicate()
		turnSortBySpeed()

	return turnOrder.pop_front()


func turnSortBySpeed():
	turnOrder.sort_custom(func(a, b): return a.speed > b.speed)
