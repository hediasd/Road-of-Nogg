## Accurate deterministic influence map built from shared movement/combat rules.

class_name ThreatMap


static func generate(
		state: BattleState,
		team: int,
		movementResolver: MovementResolver = null,
		combatResolver: CombatResolver = null) -> Dictionary:
	var map: Dictionary = {}
	for x in range(state.boardSize.x):
		for y in range(state.boardSize.y):
			var pos = Vector2i(x, y)
			if state.isWalkable(pos):
				map[pos] = 0

	if movementResolver == null or combatResolver == null:
		return _generateFallback(state, team, map)
	for enemyID in state.getAliveMonsterIDs():
		var enemy = state.getMonster(enemyID)
		if enemy.team == team:
			continue
		var origin = state.getMonsterPosition(enemyID)
		var destinations: Array = movementResolver.getReachablePositions(enemyID)
		if not destinations.has(origin):
			destinations.append(origin)
		var enemyThreat: Dictionary = {}
		for destination in destinations:
			for direction in [Vector2i.LEFT, Vector2i.RIGHT, Vector2i.UP, Vector2i.DOWN]:
				var meleePos = destination + direction
				if map.has(meleePos) and combatResolver.canBasicAttackPositionFrom(
					enemyID, destination, meleePos
				):
					enemyThreat[meleePos] = maxi(
						int(enemyThreat.get(meleePos, 0)), enemy.atk
					)
			for setIndex in range(enemy.spellSets.size()):
				for spellIndex in range(enemy.spellSets[setIndex].size()):
					var spell = enemy.spellSets[setIndex][spellIndex]
					if spell.heals or spell.damage <= 0 or not enemy.can_cast(spell):
						continue
					for dx in range(-spell.range, spell.range + 1):
						var remaining = spell.range - abs(dx)
						for dy in range(-remaining, remaining + 1):
							var distance = abs(dx) + abs(dy)
							if distance < spell.min_range:
								continue
							var targetPos = destination + Vector2i(dx, dy)
							if not map.has(targetPos):
								continue
							if combatResolver.canSpellReachPositionFrom(
								enemyID, setIndex, spellIndex, destination, targetPos
							):
								enemyThreat[targetPos] = maxi(
									int(enemyThreat.get(targetPos, 0)),
									enemy.atk + spell.damage
								)
		for targetPos in enemyThreat:
			map[targetPos] += enemyThreat[targetPos]
	return map


static func _generateFallback(state: BattleState, team: int, map: Dictionary) -> Dictionary:
	for enemyID in state.getAliveMonsterIDs():
		var enemy = state.getMonster(enemyID)
		if enemy.team == team:
			continue
		var maxRange = 1
		for spellSet in enemy.spellSets:
			for spell in spellSet:
				if not spell.heals:
					maxRange = maxi(maxRange, spell.range)
		var totalRange = enemy.move + maxRange
		var enemyPos = state.getMonsterPosition(enemyID)
		for pos in map:
			if abs(pos.x - enemyPos.x) + abs(pos.y - enemyPos.y) <= totalRange:
				map[pos] += enemy.atk
	return map