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
		## Which spells actually threaten anything does not depend on the
		## destination, so resolve that once per enemy rather than once per tile.
		## Descending threat value lets the loops below skip a tile as soon as it
		## already carries at least what this spell could contribute — a tile's
		## value is a max, so a cheaper source can never raise it, and the
		## line-of-sight check it would have needed is pure waste.
		var threats: Array = []
		for setIndex in range(enemy.spellSets.size()):
			for spellIndex in range(enemy.spellSets[setIndex].size()):
				var spell = enemy.spellSets[setIndex][spellIndex]
				if spell.heals or spell.damage <= 0 or not enemy.can_cast(spell):
					continue
				threats.append({
					"set_index": setIndex,
					"spell_index": spellIndex,
					"spell": spell,
					"value": enemy.atk + spell.damage
				})
		threats.sort_custom(func(left: Dictionary, right: Dictionary) -> bool:
			if left["value"] != right["value"]:
				return left["value"] > right["value"]
			if left["set_index"] != right["set_index"]:
				return left["set_index"] < right["set_index"]
			return left["spell_index"] < right["spell_index"]
		)

		var enemyThreat: Dictionary = {}
		for destination in destinations:
			for threat in threats:
				var spell: Spell = threat["spell"]
				var value: int = threat["value"]
				for dx in range(-spell.range, spell.range + 1):
					var remaining = spell.range - absi(dx)
					for dy in range(-remaining, remaining + 1):
						var distance = absi(dx) + absi(dy)
						if distance < spell.min_range:
							continue
						var targetPos = destination + Vector2i(dx, dy)
						if not map.has(targetPos):
							continue
						if int(enemyThreat.get(targetPos, 0)) >= value:
							continue
						if combatResolver.canSpellReachPositionFrom(
							enemyID, threat["set_index"], threat["spell_index"],
							destination, targetPos
						):
							enemyThreat[targetPos] = value

		# Melee last: every damaging spell scores strictly above bare ATK, so any
		# tile a spell already reached cannot be raised by a melee threat.
		for destination in destinations:
			for direction in [Vector2i.LEFT, Vector2i.RIGHT, Vector2i.UP, Vector2i.DOWN]:
				var meleePos = destination + direction
				if not map.has(meleePos):
					continue
				if int(enemyThreat.get(meleePos, 0)) >= enemy.atk:
					continue
				if combatResolver.canBasicAttackPositionFrom(
					enemyID, destination, meleePos
				):
					enemyThreat[meleePos] = enemy.atk

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