## SimpleBrain — A generic fallback AI for unspecified monsters.
## 1. Finds the nearest enemy.
## 2. Moves toward it.
## 3. Attacks with the first valid spell, or melee.

class_name SimpleBrain
extends EntityBrain


func decideTurn(monsterID: int) -> Dictionary:
	var myPos = state.getMonsterPosition(monsterID)
	var reachable = movementResolver.getReachablePositions(monsterID)
	if not reachable.has(myPos):
		reachable.append(myPos)
		
	var best_score = -9999
	var best_decision = null
	
	for pos in reachable:
		var tile_decision = null
		var tile_score = -9999
		
		# 1. Check Spell
		var offensiveDecision = _findBestOffensiveSpell(monsterID, pos)
		if offensiveDecision != null:
			tile_score = 100 + offensiveDecision.score
			tile_decision = {
				"action": "spell",
				"target_id": offensiveDecision.target_id,
				"spell_set_index": offensiveDecision.spell_set_index,
				"spell_index": offensiveDecision.spell_index
			}
		else:
			# 2. Check Melee
			var best_melee_score = -9999
			for enemyID in state.monsters:
				var enemy = state.monsters[enemyID]
				if enemy.team == state.getMonster(monsterID).team or not enemy.is_alive():
					continue
				var enemyPos = state.getMonsterPosition(enemyID)
				var dist = abs(pos.x - enemyPos.x) + abs(pos.y - enemyPos.y)
				if dist == 1:
					var dmg = combatResolver.calculateBasicDamage(state.getMonster(monsterID), enemy)
					if 80 + dmg > best_melee_score:
						best_melee_score = 80 + dmg
						tile_score = best_melee_score
						tile_decision = {
							"action": "attack",
							"target_id": enemyID
						}
				
			if tile_decision == null:
				# 3. Fallback to wait, score based on distance to nearest enemy
				var nearestEnemyID = -1
				var nearestDist = 9999
				for enemyID in state.monsters:
					var enemy = state.monsters[enemyID]
					if enemy.team == state.getMonster(monsterID).team or not enemy.is_alive():
						continue
					var enemyPos = state.getMonsterPosition(enemyID)
					var dist = abs(pos.x - enemyPos.x) + abs(pos.y - enemyPos.y)
					if dist < nearestDist:
						nearestDist = dist
						nearestEnemyID = enemyID
				
				if nearestEnemyID != -1:
					tile_score = 50 - nearestDist
					tile_decision = {
						"action": "wait",
						"target_id": -1
					}
				else:
					tile_score = 0
					tile_decision = {
						"action": "wait",
						"target_id": -1
					}
		
		if monsterID == 104:
			print("Oracle evaluates tile ", pos, " score: ", tile_score, " decision: ", tile_decision)
			
		if tile_score > best_score:
			best_score = tile_score
			best_decision = tile_decision
			best_decision["dest_pos"] = pos
			
	if best_decision == null:
		return { "move_path": [], "action": "wait", "target_id": -1 }
		
	var dest_pos = best_decision["dest_pos"]
	var movePath = []
	if dest_pos != myPos:
		movePath = _buildMovePath(monsterID, dest_pos)
		
	var final_decision = {
		"move_path": movePath,
		"action": best_decision.action,
		"target_id": best_decision.target_id
	}
	if best_decision.has("spell_set_index"):
		final_decision["spell_set_index"] = best_decision.spell_set_index
		final_decision["spell_index"] = best_decision.spell_index
		
	return final_decision
