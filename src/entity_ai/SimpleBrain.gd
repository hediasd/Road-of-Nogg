## SimpleBrain — A generic fallback AI for unspecified monsters.
## 1. Finds the nearest enemy.
## 2. Moves toward it.
## 3. Attacks with the first valid spell, or melee.

class_name SimpleBrain
extends EntityBrain


func decideTurn(monsterID: int) -> Dictionary:
	var myPos = state.getMonsterPosition(monsterID)

	var nearestEnemyID = _findNearestEnemy(monsterID)
	if nearestEnemyID == -1:
		return { "move_path": [], "action": "wait", "target_id": -1 }

	var enemyPos = state.getMonsterPosition(nearestEnemyID)
	var movePath = _buildMovePath(monsterID, enemyPos)
	var posAfterMove = myPos if movePath.is_empty() else movePath.back()
	
	var distAfterMove = abs(posAfterMove.x - enemyPos.x) + abs(posAfterMove.y - enemyPos.y)

	var offensiveDecision = _findBestOffensiveSpell(monsterID, posAfterMove)
	if offensiveDecision != null:
		return {
			"move_path": movePath,
			"action": "spell",
			"target_id": offensiveDecision.target_id,
			"spell_set_index": offensiveDecision.spell_set_index,
			"spell_index": offensiveDecision.spell_index
		}

	if distAfterMove == 1:
		return { "move_path": movePath, "action": "attack", "target_id": nearestEnemyID }

	return { "move_path": movePath, "action": "wait", "target_id": -1 }
