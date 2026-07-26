## Builds and scores controller-neutral CPU command candidates once per turn.

class_name BattleCommandEvaluator
extends RefCounted

const ThreatMapScript = preload("res://src/algorithms/ThreatMap.gd")

var state: BattleState
var movementResolver: MovementResolver
var combatResolver: CombatResolver


func _init(
		_state: BattleState,
		_movementResolver: MovementResolver,
		_combatResolver: CombatResolver) -> void:
	state = _state
	movementResolver = _movementResolver
	combatResolver = _combatResolver


func chooseCommand(monsterID: int, weights: Dictionary) -> Dictionary:
	var actor = state.getMonster(monsterID)
	var origin = state.getMonsterPosition(monsterID)
	var destinations: Array = movementResolver.getReachablePositions(monsterID)
	if not destinations.has(origin):
		destinations.append(origin)
	destinations.sort_custom(func(a: Vector2i, b: Vector2i) -> bool:
		return a.y < b.y or (a.y == b.y and a.x < b.x)
	)
	var threat = ThreatMapScript.generate(
		state, actor.team, movementResolver, combatResolver
	)
	var enemyPositions: Array[Vector2i] = []
	for candidateID in state.getAliveMonsterIDs():
		if state.getMonster(candidateID).team != actor.team:
			enemyPositions.append(state.getMonsterPosition(candidateID))
	var candidates: Array[Dictionary] = []
	for destination in destinations:
		var path: Array = (
			[] if destination == origin else
			movementResolver.findPath(origin, destination, actor.move)
		)
		if destination != origin and path.is_empty():
			continue
		candidates.append(_candidate(
			actor, path, destination, "wait", -1, 0, 0, threat, weights, enemyPositions
		))
		for targetID in combatResolver.getBasicAttackTargetsFrom(monsterID, destination):
			candidates.append(_candidate(
				actor, path, destination, "attack", targetID, 0, 0,
				threat, weights, enemyPositions
			))
		for spellSetIndex in range(actor.spellSets.size()):
			for spellIndex in range(actor.spellSets[spellSetIndex].size()):
				for targetID in combatResolver.getSpellTargetsFrom(
						monsterID, spellSetIndex, spellIndex, destination):
					candidates.append(_candidate(
						actor, path, destination, "spell", targetID,
						spellSetIndex, spellIndex, threat, weights, enemyPositions
					))

	if candidates.is_empty():
		return {"move_path": [], "action": "wait", "target_id": -1}
	candidates.sort_custom(func(a: Dictionary, b: Dictionary) -> bool:
		if a["score"] != b["score"]:
			return a["score"] > b["score"]
		return a["tie_key"] < b["tie_key"]
	)
	return candidates[0]["command"]


func _candidate(
		actor: Monster,
		path: Array,
		destination: Vector2i,
		action: String,
		targetID: int,
		spellSetIndex: int,
		spellIndex: int,
		threat: Dictionary,
		weights: Dictionary,
		enemyPositions: Array[Vector2i]) -> Dictionary:
	var command = {
		"move_path": path.duplicate(),
		"action": action,
		"target_id": targetID,
		"spell_set_index": spellSetIndex,
		"spell_index": spellIndex
	}
	var defeats = 0
	var defeatedValue = 0
	var expectedDamage = 0
	var utility = 0
	if action == "attack":
		var target = state.getMonster(targetID)
		expectedDamage = combatResolver.calculateBasicDamage(actor, target, true, destination)
		if expectedDamage >= target.hitpoints:
			defeats = 1
			defeatedValue = target.max_hitpoints
	elif action == "spell":
		var spell = actor.spellSets[spellSetIndex][spellIndex]
		var affected = combatResolver.getSpellAffectedTargetsFrom(
			actor.uniqueID, spellSetIndex, spellIndex, destination, targetID
		)
		for affectedID in affected:
			var target = state.getMonster(affectedID)
			if spell.heals:
				utility += mini(
					target.max_hitpoints - target.hitpoints,
					combatResolver.calculateHeal(actor, spell)
				)
				continue
			var targetDamage = 0
			for line in spell.damage_lines:
				var baseDamage = int(line.get("damage", 0))
				if baseDamage <= 0:
					continue
				targetDamage += combatResolver.calculateSpellDamage(
					actor,
					target,
					baseDamage,
					line.get("element", "none"),
					true,
					destination
				)
			expectedDamage += targetDamage
			if targetDamage >= target.hitpoints:
				defeats += 1
				defeatedValue += target.max_hitpoints
		if (
			spell.buffs_atk > 0
			or spell.inflicts_status != ""
			or spell.removes_status != ""
			or spell.reverts_damage
		):
			utility += 10

	var winsBattle = defeats > 0 and defeats >= enemyPositions.size()
	var score = (
		(1_000_000 if winsBattle else 0)
		+ defeats * 100_000
		+ defeatedValue * 1_000
		+ utility * int(weights.get("utility", 100))
		+ expectedDamage * int(weights.get("damage", 100))
		- int(threat.get(destination, 0)) * int(weights.get("threat", 1))
	)
	var nearestEnemyDistance = _nearestEnemyDistance(destination, enemyPositions)
	score -= nearestEnemyDistance * int(weights.get("distance", 1))
	if action == "wait":
		score -= int(weights.get("wait_penalty", 5))
	var tieKey = "%02d:%02d:%s:%08d:%02d:%02d" % [
		destination.y,
		destination.x,
		action,
		maxi(targetID, 0),
		spellSetIndex,
		spellIndex
	]
	return {"score": score, "tie_key": tieKey, "command": command}


func _nearestEnemyDistance(fromPos: Vector2i, enemyPositions: Array[Vector2i]) -> int:
	var result = 999
	for enemyPos in enemyPositions:
		result = mini(
			result,
			abs(fromPos.x - enemyPos.x) + abs(fromPos.y - enemyPos.y)
		)
	return 0 if result == 999 else result
