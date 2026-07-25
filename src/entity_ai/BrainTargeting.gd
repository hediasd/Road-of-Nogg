## BrainTargeting — Shared state queries for entity AI.
## Pure logic extracted from EntityBrain.

class_name BrainTargeting

const LineOfSight = preload("res://src/algorithms/LineOfSight.gd")

var state: BattleState


func _init(_state: BattleState) -> void:
	state = _state


func findNearestEnemy(monsterID: int) -> int:
	var monster = state.getMonster(monsterID)
	var origin = state.getMonsterPosition(monsterID)
	var nearestID = -1
	var nearestDistance = 9999

	for enemyID in state.monsters:
		var enemy = state.monsters[enemyID]
		if enemy.team == monster.team or not enemy.is_alive():
			continue
		var enemyPosition = state.getMonsterPosition(enemyID)
		var distance = abs(origin.x - enemyPosition.x) + abs(origin.y - enemyPosition.y)
		if distance < nearestDistance:
			nearestDistance = distance
			nearestID = enemyID

	return nearestID


func findLowestHPAlly(monsterID: int) -> int:
	var monster = state.getMonster(monsterID)
	var lowestID = -1
	var lowestRatio = 1.1

	for allyID in state.monsters:
		var ally = state.monsters[allyID]
		if ally.team != monster.team or not ally.is_alive():
			continue
		var ratio = float(ally.hitpoints) / float(ally.max_hitpoints)
		if ratio < lowestRatio:
			lowestRatio = ratio
			lowestID = allyID

	return lowestID


func hasLineOfSight(fromPos: Vector2i, toPos: Vector2i, selfID: int, targetID: int) -> bool:
	return LineOfSight.hasLoS(fromPos, toPos, func(position: Vector2i) -> bool:
		if not state.withinBounds(position):
			return true
		if state.isLoSBlocked(position):
			return true
		var occupantID = state.board.at(position)
		return occupantID != 0 and occupantID != selfID and occupantID != targetID
	)
