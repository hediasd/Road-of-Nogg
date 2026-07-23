## MageBrain — Ranged AI.
## Values casting spells from maximum range. Avoids getting into melee range (kites).

class_name MageBrain
extends EntityBrain


func _evaluateTile(monsterID: int, pos: Vector2i) -> Dictionary:
	var tile_score = -9999
	var tile_decision = { "action": "wait", "target_id": -1 }
	var mon = state.getMonster(monsterID)
	
	var offensive_score = 0
	
	# 1. Spells (Main priority)
	var buffDecision = _findBestSelfBuff(monsterID)
	if buffDecision != null:
		offensive_score = 60
		tile_decision = buffDecision
	else:
		var spellDecision = _findBestOffensiveSpell(monsterID, pos)
		if spellDecision != null:
			offensive_score = 80 + spellDecision.score
			tile_decision = { 
				"action": "spell", 
				"target_id": spellDecision.target_id, 
				"spell_set_index": spellDecision.spell_set_index, 
				"spell_index": spellDecision.spell_index 
			}
			
	# 2. Melee (Desperation)
	if tile_decision.action == "wait":
		var best_melee_score = -9999
		for enemyID in state.monsters:
			var enemy = state.monsters[enemyID]
			if enemy.team == mon.team or not enemy.is_alive(): continue
			var enemyPos = state.getMonsterPosition(enemyID)
			var dist = abs(pos.x - enemyPos.x) + abs(pos.y - enemyPos.y)
			if dist == 1:
				var dmg = combatResolver.calculateBasicDamage(mon, enemy, true)
				if 30 + dmg > best_melee_score: # Scored much lower than spells
					best_melee_score = 30 + dmg
					offensive_score = best_melee_score
					tile_decision = { "action": "attack", "target_id": enemyID }
					
	# 3. Kiting modifier
	var nearestEnemyID = _findNearestEnemy(monsterID)
	var threatMap = ThreatMap.generate(state, mon.team)
	var threat_at_pos = threatMap.get(pos, 0)
	
	if nearestEnemyID != -1:
		var nearestDist = abs(pos.x - state.getMonsterPosition(nearestEnemyID).x) + abs(pos.y - state.getMonsterPosition(nearestEnemyID).y)
		
		# If we have nothing to do, incentivize moving closer to the nearest enemy
		if tile_decision.action == "wait":
			offensive_score = 30 - nearestDist

		# Mage wants to be at range 3-4. Distance 1 or 2 is heavily penalized.
		if nearestDist <= 2:
			offensive_score -= 40
		elif nearestDist >= 3 and nearestDist <= 4:
			offensive_score += 20 # Ideal spellcasting range
			
	tile_score = offensive_score - (threat_at_pos * 3)
			
	return { "score": tile_score, "decision": tile_decision }
