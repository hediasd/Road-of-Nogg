class_name MeleeBrain
extends EntityBrain

func decideTurn(monsterID: int) -> Dictionary:
	var mon = state.getMonster(monsterID)
	var myPos = state.getMonsterPosition(monsterID)

	# Find nearest enemy
	var nearestEnemyID = _findNearestEnemy(monsterID)
	if nearestEnemyID == -1:
		return { "move_path": [], "action": "wait", "target_id": -1 }

	var enemyPos = state.getMonsterPosition(nearestEnemyID)
	var distToEnemy = abs(myPos.x - enemyPos.x) + abs(myPos.y - enemyPos.y)

	# If already adjacent, attack
	if distToEnemy == 1:
		return { "move_path": [], "action": "attack", "target_id": nearestEnemyID }

	# Otherwise, build path and move closer
	var movePath = _buildMovePath(monsterID, enemyPos)
	var posAfterMove = myPos if movePath.is_empty() else movePath.back()
	
	var distAfterMove = abs(posAfterMove.x - enemyPos.x) + abs(posAfterMove.y - enemyPos.y)

	if distAfterMove == 1:
		return { "move_path": movePath, "action": "attack", "target_id": nearestEnemyID }

	return { "move_path": movePath, "action": "wait", "target_id": -1 }
