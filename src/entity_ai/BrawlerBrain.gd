class_name BrawlerBrain
extends EntityBrain

func decideTurn(monsterID: int) -> Dictionary:
	var myPos = state.getMonsterPosition(monsterID)
	
	var nearestEnemyID = _findNearestEnemy(monsterID)
	if nearestEnemyID == -1:
		return { "move_path": [], "action": "wait", "target_id": -1 }

	var enemyPos = state.getMonsterPosition(nearestEnemyID)
	
	# Brawler logic: always move toward the nearest enemy.
	var movePath = _buildMovePath(monsterID, enemyPos)
	var posAfterMove = myPos if movePath.is_empty() else movePath.back()
	
	var distAfterMove = abs(posAfterMove.x - enemyPos.x) + abs(posAfterMove.y - enemyPos.y)

	# After moving, prioritize offensive spells if available, otherwise melee attack
	var offensiveDecision = _findBestOffensiveSpell(monsterID, posAfterMove)
	
	if distAfterMove == 1:
		# If adjacent, prefer short-range spell (like Ember Strike) over long-range, or just melee
		# Since _findBestOffensiveSpell might pick a long range one, let's just use it if available
		# In a real game, you might want to filter spells by optimal range.
		if offensiveDecision != null:
			return {
				"move_path": movePath,
				"action": "spell",
				"target_id": offensiveDecision.target_id,
				"spell_set_index": offensiveDecision.spell_set_index,
				"spell_index": offensiveDecision.spell_index
			}
		return { "move_path": movePath, "action": "attack", "target_id": nearestEnemyID }
	
	# Not adjacent, but maybe we can hit with a spell
	if offensiveDecision != null:
		return {
			"move_path": movePath,
			"action": "spell",
			"target_id": offensiveDecision.target_id,
			"spell_set_index": offensiveDecision.spell_set_index,
			"spell_index": offensiveDecision.spell_index
		}

	# Move and wait
	return { "move_path": movePath, "action": "wait", "target_id": -1 }
