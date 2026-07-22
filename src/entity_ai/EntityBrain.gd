## EntityBrain — Base class for entity AI.
## Every entity has a brain instance that decides its actions each turn.
## Subclass this to create different AI behaviors.
## Shared utility methods live here for all subclasses to use.

class_name EntityBrain

var state: BattleState
var movementResolver: MovementResolver
var combatResolver: CombatResolver


func _init(_state: BattleState, _movementResolver: MovementResolver, _combatResolver: CombatResolver) -> void:
	state = _state
	movementResolver = _movementResolver
	combatResolver = _combatResolver


func decideTurn(monsterID: int) -> Dictionary:
	## Override this in subclasses.
	## Returns a turn decision dictionary:
	## {
	##   "move_path": Array[Vector2i]  — path to move along (can be empty for no move)
	##   "action": String              — "attack", "spell", "wait"
	##   "target_id": int              — target monster ID (for attack/spell)
	##   "spell_set_index": int        — (for spell action only)
	##   "spell_index": int            — (for spell action only)
	## }
	return { "move_path": [], "action": "wait", "target_id": -1 }


# ─── Shared Query Helpers ─────────────────────────────────────────────────────

func _findNearestEnemy(monsterID: int) -> int:
	## Find the closest living enemy by Manhattan distance.
	var mon = state.getMonster(monsterID)
	var myPos = state.getMonsterPosition(monsterID)
	var nearestID = -1
	var nearestDist = 9999

	for enemyID in state.monsters:
		var enemy = state.monsters[enemyID]
		if enemy.team == mon.team or not enemy.is_alive():
			continue
		var enemyPos = state.getMonsterPosition(enemyID)
		var dist = abs(myPos.x - enemyPos.x) + abs(myPos.y - enemyPos.y)
		if dist < nearestDist:
			nearestDist = dist
			nearestID = enemyID

	return nearestID


func _findLowestHPAlly(monsterID: int) -> int:
	## Find the living ally (including self) with the lowest HP percentage.
	var mon = state.getMonster(monsterID)
	var lowestID = -1
	var lowestRatio = 1.1  # Above 100%

	for allyID in state.monsters:
		var ally = state.monsters[allyID]
		if ally.team != mon.team or not ally.is_alive():
			continue
		var ratio = float(ally.hitpoints) / float(ally.max_hitpoints)
		if ratio < lowestRatio:
			lowestRatio = ratio
			lowestID = allyID

	return lowestID


func _findReachablePositionClosestTo(monsterID: int, targetPos: Vector2i) -> Vector2i:
	## Among reachable positions, find the one closest to targetPos.
	var reachable = movementResolver.getReachablePositions(monsterID)
	if reachable.is_empty():
		return state.getMonsterPosition(monsterID)

	var bestPos = reachable[0]
	var bestDist = abs(bestPos.x - targetPos.x) + abs(bestPos.y - targetPos.y)

	for pos in reachable:
		var dist = abs(pos.x - targetPos.x) + abs(pos.y - targetPos.y)
		if dist < bestDist:
			bestDist = dist
			bestPos = pos

	return bestPos


func _findReachablePositionFarthestFrom(monsterID: int, avoidPos: Vector2i, minDist: int = 2) -> Vector2i:
	## Among reachable positions, find the farthest from avoidPos, at least minDist away.
	var reachable = movementResolver.getReachablePositions(monsterID)
	var myPos = state.getMonsterPosition(monsterID)
	if reachable.is_empty():
		return myPos

	var bestPos = myPos
	var bestDist = abs(myPos.x - avoidPos.x) + abs(myPos.y - avoidPos.y)

	for pos in reachable:
		var dist = abs(pos.x - avoidPos.x) + abs(pos.y - avoidPos.y)
		if dist > bestDist and dist >= minDist:
			bestDist = dist
			bestPos = pos

	return bestPos


func _findBestOffensiveSpell(monsterID: int, fromPos: Vector2i) -> Variant:
	## Find the best damaging spell reachable from fromPos (LoS-aware).
	## Returns { target_id, spell_set_index, spell_index } or null.
	var mon = state.getMonster(monsterID)
	if mon.spellSets.is_empty():
		return null

	var spellSet = mon.spellSets[0]

	for spellIdx in range(spellSet.size()):
		var spell = spellSet[spellIdx]
		if spell.heals or spell.range <= 0:
			continue
		if spell.damage <= 0 and spell.inflicts_status == "" and spell.removes_status == "":
			continue

		for enemyID in state.monsters:
			var enemy = state.monsters[enemyID]
			if enemy.team == mon.team or not enemy.is_alive():
				continue
			var enemyPos = state.getMonsterPosition(enemyID)
			var dist = abs(fromPos.x - enemyPos.x) + abs(fromPos.y - enemyPos.y)
			if dist <= spell.range:
				if spell.bypass_los or _checkLoS(fromPos, enemyPos, monsterID, enemyID):
					return { "target_id": enemyID, "spell_set_index": 0, "spell_index": spellIdx }

	return null


func _findBestHealSpell(monsterID: int, fromPos: Vector2i, hpThreshold: float = 0.75) -> Variant:
	## Find the best heal spell and lowest-HP ally below hpThreshold in range.
	## Returns { target_id, spell_set_index, spell_index } or null.
	var mon = state.getMonster(monsterID)
	if mon.spellSets.is_empty():
		return null

	var spellSet = mon.spellSets[0]
	var bestTarget = -1
	var lowestRatio = hpThreshold
	var bestSpellIdx = -1

	for spellIdx in range(spellSet.size()):
		var spell = spellSet[spellIdx]
		if not spell.heals:
			continue

		for allyID in state.monsters:
			var ally = state.monsters[allyID]
			if ally.team != mon.team or not ally.is_alive():
				continue
			var ratio = float(ally.hitpoints) / float(ally.max_hitpoints)
			if ratio >= hpThreshold:
				continue
			var allyPos = state.getMonsterPosition(allyID)
			var dist = abs(fromPos.x - allyPos.x) + abs(fromPos.y - allyPos.y)
			if dist <= spell.range and ratio < lowestRatio:
				if spell.bypass_los or _checkLoS(fromPos, allyPos, monsterID, allyID):
					lowestRatio = ratio
					bestTarget = allyID
					bestSpellIdx = spellIdx

	if bestTarget == -1:
		return null

	return { "target_id": bestTarget, "spell_set_index": 0, "spell_index": bestSpellIdx }


func _checkLoS(fromPos: Vector2i, toPos: Vector2i, selfID: int, targetID: int) -> bool:
	## LoS check using Bresenham raycast. Other monsters block sight.
	return LineOfSight.hasLoS(fromPos, toPos, func(p: Vector2i) -> bool:
		if not state.withinBounds(p):
			return true
		var id = state.board.at(p)
		return id != 0 and id != selfID and id != targetID
	)


func _buildMovePath(monsterID: int, targetPos: Vector2i) -> Array:
	## Build a truncated move path toward targetPos within move range.
	var mon = state.getMonster(monsterID)
	var myPos = state.getMonsterPosition(monsterID)
	var bestMoveTarget = _findReachablePositionClosestTo(monsterID, targetPos)
	var path = movementResolver.findPath(myPos, bestMoveTarget, mon.move)
	if path.size() > mon.move:
		path = path.slice(0, mon.move)
	return path
