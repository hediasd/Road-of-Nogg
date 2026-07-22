class_name HealerBrain
extends EntityBrain

func decideTurn(monsterID: int) -> Dictionary:
	var myPos = state.getMonsterPosition(monsterID)
	
	# Priority 1: Check for healing opportunities (hpThreshold 0.6 = 60%)
	# First check if we can heal from our current position
	var healDecision = _findBestHealSpell(monsterID, myPos, 0.6)
	if healDecision != null:
		return {
			"move_path": [],
			"action": "spell",
			"target_id": healDecision.target_id,
			"spell_set_index": healDecision.spell_set_index,
			"spell_index": healDecision.spell_index
		}

	# If no immediate heal target, check if moving helps heal someone
	# Easiest way: find lowest HP ally, move toward them, then check heal again
	var lowHPAllyID = _findLowestHPAlly(monsterID)
	var lowHPAllyPos = state.getMonsterPosition(lowHPAllyID)
	
	var mon = state.getMonster(monsterID)
	var ally = state.getMonster(lowHPAllyID)
	
	if ally != null and float(ally.hitpoints) / float(ally.max_hitpoints) < 0.6:
		var movePath = _buildMovePath(monsterID, lowHPAllyPos)
		var posAfterMove = myPos if movePath.is_empty() else movePath.back()
		
		var healDecisionAfterMove = _findBestHealSpell(monsterID, posAfterMove, 0.6)
		if healDecisionAfterMove != null:
			return {
				"move_path": movePath,
				"action": "spell",
				"target_id": healDecisionAfterMove.target_id,
				"spell_set_index": healDecisionAfterMove.spell_set_index,
				"spell_index": healDecisionAfterMove.spell_index
			}

	# Priority 2: Fallback to attack/spells on nearest enemy
	var nearestEnemyID = _findNearestEnemy(monsterID)
	if nearestEnemyID == -1:
		return { "move_path": [], "action": "wait", "target_id": -1 }

	var enemyPos = state.getMonsterPosition(nearestEnemyID)
	
	# See if we can cast an offensive spell from here
	var offensiveDecision = _findBestOffensiveSpell(monsterID, myPos)
	if offensiveDecision != null:
		return {
			"move_path": [],
			"action": "spell",
			"target_id": offensiveDecision.target_id,
			"spell_set_index": offensiveDecision.spell_set_index,
			"spell_index": offensiveDecision.spell_index
		}

	# Move toward enemy
	var movePathToEnemy = _buildMovePath(monsterID, enemyPos)
	var posAfterMoveToEnemy = myPos if movePathToEnemy.is_empty() else movePathToEnemy.back()
	
	# Try casting again
	var offensiveDecisionAfterMove = _findBestOffensiveSpell(monsterID, posAfterMoveToEnemy)
	if offensiveDecisionAfterMove != null:
		return {
			"move_path": movePathToEnemy,
			"action": "spell",
			"target_id": offensiveDecisionAfterMove.target_id,
			"spell_set_index": offensiveDecisionAfterMove.spell_set_index,
			"spell_index": offensiveDecisionAfterMove.spell_index
		}
	
	# Try melee
	var distAfterMove = abs(posAfterMoveToEnemy.x - enemyPos.x) + abs(posAfterMoveToEnemy.y - enemyPos.y)
	if distAfterMove == 1:
		return { "move_path": movePathToEnemy, "action": "attack", "target_id": nearestEnemyID }

	return { "move_path": movePathToEnemy, "action": "wait", "target_id": -1 }
