## BerserkBrain — Pure aggressive AI. Charges the nearest enemy every turn.
## Always moves toward the target. Attacks if adjacent, casts offensive spell if in range.
## Does not retreat and does not heal. Simpler than BrawlerBrain.

class_name BerserkBrain
extends EntityBrain


func decideTurn(monsterID: int) -> Dictionary:
	var myPos = state.getMonsterPosition(monsterID)

	var nearestEnemyID = _findNearestEnemy(monsterID)
	if nearestEnemyID == -1:
		return { "move_path": [], "action": "wait", "target_id": -1 }

	var enemyPos = state.getMonsterPosition(nearestEnemyID)

	# Always move toward the nearest enemy, ignoring threat tiles
	var movePath = _buildMovePath(monsterID, enemyPos)
	var posAfterMove = myPos if movePath.is_empty() else movePath.back()

	var distAfterMove = abs(posAfterMove.x - enemyPos.x) + abs(posAfterMove.y - enemyPos.y)

	# If adjacent, melee attack immediately
	if distAfterMove == 1:
		return { "move_path": movePath, "action": "attack", "target_id": nearestEnemyID }

	# Not adjacent — try a spell (including self-buff like Empower)
	var mon = state.getMonster(monsterID)
	if not mon.spellSets.is_empty():
		var spellSet = mon.spellSets[0]
		for spellIdx in range(spellSet.size()):
			var spell = spellSet[spellIdx]

			# Self-buff spells (range 0, TARGET_TYPE == "self")
			if spell.targetType == "self" and spell.range == 0:
				return {
					"move_path": movePath,
					"action": "spell",
					"target_id": monsterID,
					"spell_set_index": 0,
					"spell_index": spellIdx
				}

			# Offensive spell on an enemy in range
			if spell.heals or spell.damage <= 0:
				continue
			for enemyID in state.monsters:
				var enemy = state.monsters[enemyID]
				if enemy.team == mon.team or not enemy.is_alive():
					continue
				var ePos = state.getMonsterPosition(enemyID)
				var dist = abs(posAfterMove.x - ePos.x) + abs(posAfterMove.y - ePos.y)
				if dist <= spell.range:
					return {
						"move_path": movePath,
						"action": "spell",
						"target_id": enemyID,
						"spell_set_index": 0,
						"spell_index": spellIdx
					}

	# Move and wait if nothing to act on
	return { "move_path": movePath, "action": "wait", "target_id": -1 }
