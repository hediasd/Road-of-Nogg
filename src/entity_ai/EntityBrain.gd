## EntityBrain — Base class for entity AI.
## Every entity has a brain instance that decides its actions each turn.
## Subclass this to create different AI behaviors.
## Shared utility methods live here for all subclasses to use.

class_name EntityBrain

const ThreatMap = preload("res://src/algorithms/ThreatMap.gd")
const BrainTargetingScript = preload("res://src/entity_ai/BrainTargeting.gd")
const BattleCommandEvaluatorScript = preload("res://src/entity_ai/BattleCommandEvaluator.gd")

var state: BattleState
var movementResolver: MovementResolver
var combatResolver: CombatResolver
var targeting
var commandEvaluator


func _init(_state: BattleState, _movementResolver: MovementResolver, _combatResolver: CombatResolver) -> void:
	state = _state
	movementResolver = _movementResolver
	combatResolver = _combatResolver
	targeting = BrainTargetingScript.new(state)
	commandEvaluator = BattleCommandEvaluatorScript.new(state, movementResolver, combatResolver)


func decideTurn(monsterID: int) -> Dictionary:
	return commandEvaluator.chooseCommand(monsterID, _evaluationWeights())


func _evaluationWeights() -> Dictionary:
	return {
		"damage": 100,
		"utility": 100,
		"threat": 2,
		"distance": 1,
		"wait_penalty": 5
	}

func _evaluateTile(_monsterID: int, pos: Vector2i) -> Dictionary:
	## Virtual method. Override in subclasses.
	## Must return a dict: { "score": int, "decision": { "action": "wait", "target_id": -1 } }
	return { "score": 0, "decision": { "action": "wait", "target_id": -1 } }


# ─── Shared Query Helpers ─────────────────────────────────────────────────────

func _findNearestEnemy(monsterID: int) -> int:
	return targeting.findNearestEnemy(monsterID)


func _findLowestHPAlly(monsterID: int) -> int:
	return targeting.findLowestHPAlly(monsterID)


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

	var bestResult = null
	var highestScore = -1

	for spellIdx in range(spellSet.size()):
		var spell = spellSet[spellIdx]
		if not mon.can_cast(spell):
			continue
		if spell.heals or spell.targetType != "single":
			continue
		if spell.damage <= 0 and spell.inflicts_status == "" and spell.removes_status == "":
			continue

		for enemyID in state.monsters:
			var enemy = state.monsters[enemyID]
			if enemy.team == mon.team or not enemy.is_alive():
				continue
			var enemyPos = state.getMonsterPosition(enemyID)
			var dist = abs(fromPos.x - enemyPos.x) + abs(fromPos.y - enemyPos.y)
			if dist >= spell.min_range and dist <= spell.range:
				if spell.bypass_los or _checkLoS(fromPos, enemyPos, monsterID, enemyID):
					var score = max(1, mon.atk + spell.damage - enemy.def)
					if spell.inflicts_status != "":
						score += 10
					if score > highestScore:
						highestScore = score
						bestResult = {
							"target_id": enemyID,
							"spell_set_index": 0,
							"spell_index": spellIdx,
							"score": score
						}

	return bestResult


func _findBestSelfBuff(monsterID: int) -> Variant:
	## Finds an unapplied self-buff spell
	var mon = state.getMonster(monsterID)
	if mon.spellSets.is_empty(): return null
	var spellSet = mon.spellSets[0]
	for spellIdx in range(spellSet.size()):
		var spell = spellSet[spellIdx]
		if spell.targetType == "self" and spell.range == 0 and spell.buffs_atk > 0:
			var hasBuff = false
			for effect in state.getActiveEffects(monsterID):
				if effect.name == "atk_buff":
					hasBuff = true
					break
			if not hasBuff:
				return { "action": "spell", "target_id": monsterID, "spell_set_index": 0, "spell_index": spellIdx }
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
		if not mon.can_cast(spell):
			continue
		if not spell.heals and not spell.reverts_damage:
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
			if dist >= spell.min_range and dist <= spell.range and ratio < lowestRatio:
				if spell.bypass_los or _checkLoS(fromPos, allyPos, monsterID, allyID):
					lowestRatio = ratio
					bestTarget = allyID
					bestSpellIdx = spellIdx
					
		# If it's a reverts_damage spell, maybe cast it if someone took damage last turn
		if spell.reverts_damage:
			for enemyID in state.monsters:
				var enemy = state.monsters[enemyID]
				if enemy.team == mon.team or not enemy.is_alive(): continue
				if state.get_events_for_actor_since_last_turn(enemyID, "damage").size() > 0:
					# This enemy dealt damage last turn! We should target them!
					var enemyPos = state.getMonsterPosition(enemyID)
					var dist = abs(fromPos.x - enemyPos.x) + abs(fromPos.y - enemyPos.y)
					if dist >= spell.min_range and dist <= spell.range:
						if spell.bypass_los or _checkLoS(fromPos, enemyPos, monsterID, enemyID):
							# We prioritize this heavily
							lowestRatio = 0.0
							bestTarget = enemyID
							bestSpellIdx = spellIdx
							break

	if bestTarget == -1:
		return null

	return { "target_id": bestTarget, "spell_set_index": 0, "spell_index": bestSpellIdx }


func _checkLoS(fromPos: Vector2i, toPos: Vector2i, selfID: int, targetID: int) -> bool:
	return combatResolver._hasLoS(selfID, fromPos, toPos, targetID)


func _findSafestReachablePosition(monsterID: int, targetPos: Vector2i, retreat: bool = false) -> Vector2i:
	## Among reachable positions, find the safest tile (lowest threat).
	## Ties are broken by minimizing distance to targetPos (or maximizing if retreat).
	var mon = state.getMonster(monsterID)
	var reachable = movementResolver.getReachablePositions(monsterID)
	if reachable.is_empty():
		return state.getMonsterPosition(monsterID)
		
	var threatMap = ThreatMap.generate(state, mon.team)
	var bestPos = reachable[0]
	var bestThreat = threatMap.get(bestPos, 9999)
	var bestDist = abs(bestPos.x - targetPos.x) + abs(bestPos.y - targetPos.y)
	
	for pos in reachable:
		var threat = threatMap.get(pos, 0)
		var dist = abs(pos.x - targetPos.x) + abs(pos.y - targetPos.y)
		
		if threat < bestThreat:
			bestThreat = threat
			bestDist = dist
			bestPos = pos
		elif threat == bestThreat:
			if retreat and dist > bestDist:
				bestDist = dist
				bestPos = pos
			elif not retreat and dist < bestDist:
				bestDist = dist
				bestPos = pos
			
	return bestPos


func _buildMovePath(monsterID: int, targetPos: Vector2i) -> Array:
	## Build a truncated move path toward targetPos within move range.
	var mon = state.getMonster(monsterID)
	var myPos = state.getMonsterPosition(monsterID)
	var path = movementResolver.findPath(myPos, targetPos, 100)
	if path.is_empty():
		return []
		
	if path.back() == targetPos and state.isOccupied(targetPos):
		path.pop_back()
		
	if path.size() > mon.move:
		path = path.slice(0, mon.move)
	return path
