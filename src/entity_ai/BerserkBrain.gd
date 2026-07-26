## BerserkBrain — Pure aggressive AI. Charges the nearest enemy every turn.
## Evaluates tiles strictly by offensive output and closing distance. No retreating.

class_name BerserkBrain
extends EntityBrain


func _evaluationWeights() -> Dictionary:
	return {"damage": 135, "utility": 35, "threat": 0, "distance": 4, "wait_penalty": 12}

func _evaluateTile(monsterID: int, pos: Vector2i) -> Dictionary:
	var tile_score = -9999
	var tile_decision = { "action": "wait", "target_id": -1 }
	var mon = state.getMonster(monsterID)
	
	# 1. Check Melee
	var best_melee_score = -9999
	for enemyID in state.monsters:
		var enemy = state.monsters[enemyID]
		if enemy.team == mon.team or not enemy.is_alive(): continue
		var enemyPos = state.getMonsterPosition(enemyID)
		var dist = abs(pos.x - enemyPos.x) + abs(pos.y - enemyPos.y)
		if dist == 1:
			var dmg = combatResolver.calculateBasicDamage(mon, enemy, true)
			if 80 + dmg > best_melee_score:
				best_melee_score = 80 + dmg
				tile_score = best_melee_score
				tile_decision = { "action": "attack", "target_id": enemyID }
				
	# 2. If no melee, check Spell (Buff or Offensive)
	if tile_decision.action == "wait":
		var buffDecision = _findBestSelfBuff(monsterID)
		if buffDecision != null:
			tile_score = 60
			tile_decision = buffDecision
		else:
			var offensiveDecision = _findBestOffensiveSpell(monsterID, pos)
			if offensiveDecision != null:
				tile_score = 50 + offensiveDecision.score
				tile_decision = { 
					"action": "spell", 
					"target_id": offensiveDecision.target_id, 
					"spell_set_index": offensiveDecision.spell_set_index, 
					"spell_index": offensiveDecision.spell_index 
				}
				
	# 3. If nothing, Wait (move towards nearest enemy)
	if tile_decision.action == "wait":
		var nearestEnemyID = _findNearestEnemy(monsterID)
		if nearestEnemyID != -1:
			var nearestDist = abs(pos.x - state.getMonsterPosition(nearestEnemyID).x) + abs(pos.y - state.getMonsterPosition(nearestEnemyID).y)
			tile_score = 20 - nearestDist # prefers getting closer
		else:
			tile_score = 0
			
	return { "score": tile_score, "decision": tile_decision }
