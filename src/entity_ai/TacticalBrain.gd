## TacticalBrain — Balanced AI.
## Values attacking and spells, but uses ThreatMap to avoid danger,
## especially when HP is low.

class_name TacticalBrain
extends EntityBrain


func _evaluationWeights() -> Dictionary:
	return {"damage": 100, "utility": 100, "threat": 3, "distance": 1, "wait_penalty": 6}

func _evaluateTile(monsterID: int, pos: Vector2i) -> Dictionary:
	var tile_score = -9999
	var tile_decision = { "action": "wait", "target_id": -1 }
	var mon = state.getMonster(monsterID)
	
	# Evaluate base offensive value
	var offensive_score = -9999
	
	# 1. Check Melee
	for enemyID in state.monsters:
		var enemy = state.monsters[enemyID]
		if enemy.team == mon.team or not enemy.is_alive(): continue
		var enemyPos = state.getMonsterPosition(enemyID)
		var dist = abs(pos.x - enemyPos.x) + abs(pos.y - enemyPos.y)
		if dist == 1:
			var dmg = combatResolver.calculateBasicDamage(mon, enemy, true)
			if 80 + dmg > offensive_score:
				offensive_score = 80 + dmg
				tile_decision = { "action": "attack", "target_id": enemyID }
				
	# 2. Check Spells
	if tile_decision.action == "wait":
		var buffDecision = _findBestSelfBuff(monsterID)
		if buffDecision != null:
			offensive_score = 60
			tile_decision = buffDecision
		else:
			var spellDecision = _findBestOffensiveSpell(monsterID, pos)
			if spellDecision != null:
				offensive_score = 50 + spellDecision.score
				tile_decision = { 
					"action": "spell", 
					"target_id": spellDecision.target_id, 
					"spell_set_index": spellDecision.spell_set_index, 
					"spell_index": spellDecision.spell_index 
				}
				
	# 3. Wait (Closing distance)
	if tile_decision.action == "wait":
		var nearestEnemyID = _findNearestEnemy(monsterID)
		if nearestEnemyID != -1:
			var nearestDist = abs(pos.x - state.getMonsterPosition(nearestEnemyID).x) + abs(pos.y - state.getMonsterPosition(nearestEnemyID).y)
			offensive_score = 30 - nearestDist
		else:
			offensive_score = 0
			
	# Tactical Modification: Threat Map penalty
	var threatMap = ThreatMap.generate(state, mon.team)
	var threat_at_pos = threatMap.get(pos, 0)
	
	var hp_ratio = float(mon.hitpoints) / float(mon.max_hitpoints)
	
	# If HP is low, threat penalty is massive. If healthy, it's minor.
	var threat_penalty = threat_at_pos * 2
	if hp_ratio < 0.35:
		threat_penalty = threat_at_pos * 8
		
	tile_score = offensive_score - threat_penalty
			
	return { "score": tile_score, "decision": tile_decision }
