class_name RangedMageBrain
extends EntityBrain

func decideTurn(monsterID: int) -> Dictionary:
	var myPos = state.getMonsterPosition(monsterID)

	var nearestEnemyID = _findNearestEnemy(monsterID)
	if nearestEnemyID == -1:
		return { "move_path": [], "action": "wait", "target_id": -1 }

	var enemyPos = state.getMonsterPosition(nearestEnemyID)
	
	# Pre-move offensive spell check (can we hit from here?)
	var currentSpellDecision = _findBestOffensiveSpell(monsterID, myPos)
	var currentDist = abs(myPos.x - enemyPos.x) + abs(myPos.y - enemyPos.y)

	# If enemies are too close, try to move away
	if currentDist <= 2:
		var retreatPos = _findSafestReachablePosition(monsterID, enemyPos, true)
		var retreatPath = _buildMovePath(monsterID, retreatPos)
		
		var posAfterRetreat = myPos if retreatPath.is_empty() else retreatPath.back()
		var spellDecisionAfterRetreat = _findBestOffensiveSpell(monsterID, posAfterRetreat)

		if spellDecisionAfterRetreat != null:
			return {
				"move_path": retreatPath,
				"action": "spell",
				"target_id": spellDecisionAfterRetreat.target_id,
				"spell_set_index": spellDecisionAfterRetreat.spell_set_index,
				"spell_index": spellDecisionAfterRetreat.spell_index
			}
		
		# If we can't cast after retreating, but we can cast now, cast now (don't retreat)
		if currentSpellDecision != null:
			return {
				"move_path": [],
				"action": "spell",
				"target_id": currentSpellDecision.target_id,
				"spell_set_index": currentSpellDecision.spell_set_index,
				"spell_index": currentSpellDecision.spell_index
			}
		
		# Otherwise just retreat and wait
		return { "move_path": retreatPath, "action": "wait", "target_id": -1 }

	# If we are at a safe distance and can cast, just cast without moving
	if currentSpellDecision != null:
		return {
			"move_path": [],
			"action": "spell",
			"target_id": currentSpellDecision.target_id,
			"spell_set_index": currentSpellDecision.spell_set_index,
			"spell_index": currentSpellDecision.spell_index
		}

	# If we are at a safe distance but CANNOT cast (e.g., out of range), try to move into range while staying safe
	# For simplicity, move toward enemy until in max range.
	var movePath = _buildMovePath(monsterID, enemyPos)
	# Check if we can cast after moving toward enemy
	var posAfterMove = myPos if movePath.is_empty() else movePath.back()
	var spellDecisionAfterMove = _findBestOffensiveSpell(monsterID, posAfterMove)
	if spellDecisionAfterMove != null:
		return {
			"move_path": movePath,
			"action": "spell",
			"target_id": spellDecisionAfterMove.target_id,
			"spell_set_index": spellDecisionAfterMove.spell_set_index,
			"spell_index": spellDecisionAfterMove.spell_index
		}

	# Try melee if close enough, else wait
	var distAfterMove = abs(posAfterMove.x - enemyPos.x) + abs(posAfterMove.y - enemyPos.y)
	if distAfterMove == 1:
		return { "move_path": movePath, "action": "attack", "target_id": nearestEnemyID }

	# Move and wait
	return { "move_path": movePath, "action": "wait", "target_id": -1 }
