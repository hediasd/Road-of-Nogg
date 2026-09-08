## CombatResolver — Handles attacks, spells, damage calculation, heal resolution, and status infliction.
## Pure logic, no Node dependency.

class_name CombatResolver

var state: BattleState
var events: BattleEvents
var passiveSkillResolver  # PassiveSkillResolver — injected by BattleSimulator
var spellEffectResolver


func _init(_state: BattleState, _events: BattleEvents) -> void:
	state = _state
	events = _events
	spellEffectResolver = SpellEffectResolverScript.new(state, events)


# --- Basic melee attack ---

const LineOfSight = preload("res://src/algorithms/LineOfSight.gd")
const ShapeCaster = preload("res://src/algorithms/ShapeCaster.gd")
const SpellEffectResolverScript = preload("res://src/battle_sim/SpellEffectResolver.gd")
const DirectDamageRulesScript = preload("res://src/battle_sim/DirectDamageRules.gd")
const DIRECTIONS = [Vector2i(0, -1), Vector2i(0, 1), Vector2i(-1, 0), Vector2i(1, 0)]

func getBasicAttackTargets(monsterID: int) -> Array:
	return getBasicAttackTargetsFrom(monsterID, state.getMonsterPosition(monsterID))


func getBasicAttackTargetPositions(monsterID: int) -> Array:
	return getBasicAttackTargetPositionsFrom(
		monsterID, state.getMonsterPosition(monsterID)
	)


func getBasicAttackTargetPositionsFrom(monsterID: int, fromPos: Vector2i) -> Array:
	var mon = state.getMonster(monsterID)
	if mon == null or not mon.is_alive():
		return []
	var positions: Array = []
	for direction in DIRECTIONS:
		var targetPos = fromPos + direction
		if canBasicAttackPositionFrom(monsterID, fromPos, targetPos):
			positions.append(targetPos)
	return positions


func getBasicAttackTargetsFrom(monsterID: int, fromPos: Vector2i) -> Array:
	## Compatibility query for occupied-target presentation code. The canonical
	## command/evaluator query is getBasicAttackTargetPositionsFrom().
	var targets: Array = []
	for targetPos in getBasicAttackTargetPositionsFrom(monsterID, fromPos):
		var targetID = state.board.at(targetPos)
		if targetID != 0:
			targets.append(targetID)
	return targets


func executeBasicAttack(attackerID: int, targetPos: Vector2i) -> Dictionary:
	var attacker = state.getMonster(attackerID)
	if attacker == null or not attacker.is_alive():
		return {"success": false, "reason": "invalid_monster"}
	var attackerPos = state.getMonsterPosition(attackerID)
	if not canBasicAttackPositionFrom(attackerID, attackerPos, targetPos):
		return {"success": false, "reason": "invalid_target"}

	var targetID = state.board.at(targetPos)
	if targetID == 0:
		state.add_event("attack_miss", attackerID, -1, {"target_pos": targetPos})
		events.monster_attacked.emit(attackerID, targetPos, -1, 0, 0)
		return {
			"success": true,
			"damage": 0,
			"targetHP": 0,
			"defeated": false,
			"target_id": -1,
			"target_pos": targetPos
		}

	var target = state.getMonster(targetID)
	if target == null or not target.is_alive():
		return {"success": false, "reason": "dead_monster"}

	if passiveSkillResolver != null:
		passiveSkillResolver.fireOnTargeted(targetID, attackerID)
		if not attacker.is_alive():
			return {"success": false, "reason": "attacker_died_to_passive"}
		if not target.is_alive():
			return {"success": true, "damage": 0, "targetHP": 0, "defeated": true}

	var damage = calculateBasicDamage(attacker, target)
	var actualDamage = target.take_damage(damage)
	if actualDamage > 0:
		spellEffectResolver.consumeDamageEffects(attackerID, targetID)

	state.add_event("damage", attackerID, targetID, {
		"damage": actualDamage,
		"type": "physical",
		"target_pos": targetPos,
		"elevation_percent": getElevationPercent(attackerID, targetID)
	})
	
	events.monster_attacked.emit(
		attackerID, targetPos, targetID, actualDamage, target.hitpoints
	)

	var result = {
		"success": true,
		"damage": actualDamage,
		"targetHP": target.hitpoints,
		"defeated": not target.is_alive(),
		"target_id": targetID,
		"target_pos": targetPos
	}
	if not target.is_alive():
		_handleDefeat(targetID, attackerID)
	return result

func calculateBasicDamage(
	attacker: Monster,
	target: Monster,
	is_simulation: bool = false,
	attackerPos: Vector2i = Vector2i(-1, -1)) -> int:
	var attackerBonus = 0
	for effect in state.getActiveEffects(attacker.uniqueID):
		attackerBonus += int(effect.get("atk_bonus", 0))
	var defenderBonus = 0
	for effect in state.getActiveEffects(target.uniqueID):
		defenderBonus += int(effect.get("def_bonus", 0))
	var raw = max(1, attacker.get_effective_atk() + attackerBonus - target.get_effective_def() - defenderBonus)
	raw = max(1, raw)
	if state.withinBounds(attackerPos):
		raw = DirectDamageRulesScript.applyElevationFromPositions(
			state, raw, attackerPos, state.getMonsterPosition(target.uniqueID)
		)
	else:
		raw = applyElevationModifier(raw, attacker.uniqueID, target.uniqueID)
	raw = spellEffectResolver.applyDamageEffectMultipliers(raw, attacker.uniqueID, target.uniqueID)
	## Let PassiveSkillResolver apply damage reduction passives on the target
	if passiveSkillResolver != null:
		raw = passiveSkillResolver.applyDamageModifiers(raw, target.uniqueID, is_simulation)

	return raw


# --- Spell casting ---

func getSpellTargets(monsterID: int, spellSetIndex: int, spellIndex: int) -> Array:
	return getSpellTargetsFrom(
		monsterID, spellSetIndex, spellIndex, state.getMonsterPosition(monsterID)
	)


func getSpellTargetPositions(
		monsterID: int,
		spellSetIndex: int,
		spellIndex: int,
		includeUncastableEmpty: bool = false) -> Array:
	return getSpellTargetPositionsFrom(
		monsterID,
		spellSetIndex,
		spellIndex,
		state.getMonsterPosition(monsterID),
		includeUncastableEmpty
	)


func getSpellTargetPositionsFrom(
		monsterID: int,
		spellSetIndex: int,
		spellIndex: int,
		fromPos: Vector2i,
		includeUncastableEmpty: bool = false) -> Array:
	var mon = state.getMonster(monsterID)
	if mon == null or not mon.is_alive():
		return []
	if spellSetIndex < 0 or spellSetIndex >= mon.spellSets.size():
		return []
	if spellIndex < 0 or spellIndex >= mon.spellSets[spellSetIndex].size():
		return []
	var spell = mon.spellSets[spellSetIndex][spellIndex]
	if not mon.can_cast(spell):
		return []
	if spell.targetType == "self":
		return [fromPos]

	## Only tiles within the spell's range can pass, so walk the bounding box of
	## that range rather than the whole board. Row-major order over a sub-rectangle
	## is a subsequence of row-major order over the board, so the returned
	## sequence is identical to a full scan's — which matters, because AI
	## tie-breaking and the player's target cycling both depend on it.
	##
	## The AI asks this once per spell per candidate destination, so a full 16x16
	## scan with the monster/spell/can_cast lookups repeated per tile was costing
	## more than everything else in a CPU turn combined.
	var positions: Array = []
	var minY: int = maxi(0, fromPos.y - spell.range)
	var maxY: int = mini(state.boardSize.y - 1, fromPos.y + spell.range)
	var minX: int = maxi(0, fromPos.x - spell.range)
	var maxX: int = mini(state.boardSize.x - 1, fromPos.x + spell.range)
	for y in range(minY, maxY + 1):
		for x in range(minX, maxX + 1):
			var targetPos = Vector2i(x, y)
			var distance: int = absi(fromPos.x - x) + absi(fromPos.y - y)
			if distance < spell.min_range or distance > spell.range:
				continue
			if _canSpellTargetPositionResolved(
					mon,
					spell,
					fromPos,
					targetPos,
					includeUncastableEmpty):
				positions.append(targetPos)
	return positions


func getSpellTargetsFrom(
		monsterID: int,
		spellSetIndex: int,
		spellIndex: int,
		fromPos: Vector2i) -> Array:
	## Compatibility query for older occupied-target consumers. Current player
	## presentation uses getSpellTargetPositionsFrom(..., true).
	var mon = state.getMonster(monsterID)
	if (
		mon != null
		and spellSetIndex >= 0
		and spellSetIndex < mon.spellSets.size()
		and spellIndex >= 0
		and spellIndex < mon.spellSets[spellSetIndex].size()
		and mon.spellSets[spellSetIndex][spellIndex].targetType == "self"
	):
		return [monsterID] if canSpellTargetPositionFrom(
			monsterID, spellSetIndex, spellIndex, fromPos, fromPos
		) else []
	var targets: Array = []
	for targetPos in getSpellTargetPositionsFrom(
			monsterID, spellSetIndex, spellIndex, fromPos):
		var targetID = state.board.at(targetPos)
		if targetID != 0:
			targets.append(targetID)
	return targets

func _hasLoS(casterID: int, fromPos: Vector2i, toPos: Vector2i, targetID: int) -> bool:
	var sourceEye = float(state.getHeight(fromPos)) + 1.0
	var targetEye = float(state.getHeight(toPos)) + 1.0
	return LineOfSight.hasHeightAwareLoS(
		fromPos,
		toPos,
		sourceEye,
		targetEye,
		func(p: Vector2i) -> float:
			if not state.withinBounds(p):
				return INF
			var blockerTop = float(state.getHeight(p))
			if state.isLoSBlocked(p):
				blockerTop += 2.0
			var occupantID = state.board.at(p)
			if occupantID != 0 and occupantID != casterID and occupantID != targetID:
				blockerTop = maxf(blockerTop, float(state.getHeight(p)) + 2.0)
			return blockerTop
	)

func getProjectedOccupantID(
		monsterID: int,
		fromPos: Vector2i,
		queryPos: Vector2i) -> int:
	## AI and atomic validation query an action before its move phase resolves.
	## Model only the acting unit's already-validated move; no other occupancy can
	## change between the query and execution.
	var currentPos = state.getMonsterPosition(monsterID)
	if currentPos != fromPos:
		if queryPos == currentPos:
			return 0
		if queryPos == fromPos:
			return monsterID
	return state.board.at(queryPos) if state.withinBounds(queryPos) else 0

func canBasicAttackPositionFrom(
		monsterID: int,
		fromPos: Vector2i,
		targetPos: Vector2i) -> bool:
	var attacker = state.getMonster(monsterID)
	if attacker == null or not attacker.is_alive() or not state.withinBounds(targetPos):
		return false
	if abs(fromPos.x - targetPos.x) + abs(fromPos.y - targetPos.y) != 1:
		return false
	if state.getHeightDifference(fromPos, targetPos) > 1:
		return false
	var occupantID = getProjectedOccupantID(monsterID, fromPos, targetPos)
	var occupant = state.getMonster(occupantID)
	return occupant == null or (occupant.is_alive() and occupant.team != attacker.team)


func canSpellReachPositionFrom(
		monsterID: int,
		spellSetIndex: int,
		spellIndex: int,
		fromPos: Vector2i,
		targetPos: Vector2i) -> bool:
	var mon = state.getMonster(monsterID)
	var spell = _resolveSpell(mon, spellSetIndex, spellIndex)
	if spell == null:
		return false
	return _canSpellReachPositionResolved(mon, spell, fromPos, targetPos)


func canSpellTargetPositionFrom(
		monsterID: int,
		spellSetIndex: int,
		spellIndex: int,
		fromPos: Vector2i,
		targetPos: Vector2i,
		includeUncastableEmpty: bool = false) -> bool:
	var mon = state.getMonster(monsterID)
	var spell = _resolveSpell(mon, spellSetIndex, spellIndex)
	if spell == null:
		return false
	return _canSpellTargetPositionResolved(
		mon, spell, fromPos, targetPos, includeUncastableEmpty
	)


func _resolveSpell(mon, spellSetIndex: int, spellIndex: int):
	## Shared precondition check for the caster/spell pair. Hoisting it out of the
	## per-tile loops matters: the AI evaluates hundreds of centers per spell per
	## destination, and none of these checks depend on the center.
	if mon == null or not mon.is_alive():
		return null
	if spellSetIndex < 0 or spellSetIndex >= mon.spellSets.size():
		return null
	if spellIndex < 0 or spellIndex >= mon.spellSets[spellSetIndex].size():
		return null
	var spell = mon.spellSets[spellSetIndex][spellIndex]
	if not mon.can_cast(spell):
		return null
	return spell


func _canSpellReachPositionResolved(
		mon,
		spell: Spell,
		fromPos: Vector2i,
		targetPos: Vector2i) -> bool:
	if not state.withinBounds(targetPos):
		return false
	if spell.targetType == "self":
		return targetPos == fromPos
	var distance = absi(fromPos.x - targetPos.x) + absi(fromPos.y - targetPos.y)
	if distance < spell.min_range or distance > spell.range:
		return false
	if state.getHeightDifference(fromPos, targetPos) > spell.max_height_delta:
		return false
	if spell.bypass_los:
		return true
	var targetOccupantID = getProjectedOccupantID(mon.uniqueID, fromPos, targetPos)
	return _hasLoS(mon.uniqueID, fromPos, targetPos, targetOccupantID)


func _canSpellTargetPositionResolved(
		mon,
		spell: Spell,
		fromPos: Vector2i,
		targetPos: Vector2i,
		includeUncastableEmpty: bool) -> bool:
	if not _canSpellReachPositionResolved(mon, spell, fromPos, targetPos):
		return false
	if spell.targetType == "self":
		return targetPos == fromPos
	var occupantID = getProjectedOccupantID(mon.uniqueID, fromPos, targetPos)
	var occupant = state.getMonster(occupantID)
	if occupant == null:
		return spell.can_target_empty or includeUncastableEmpty
	if not occupant.is_alive():
		return false
	var isAlly = occupant.team == mon.team
	return (spell.heals and isAlly) or (not spell.heals and not isAlly)

func getSpellAffectedTargetsFrom(
		casterID: int,
		spellSetIndex: int,
		spellIndex: int,
		fromPos: Vector2i,
		centerPos: Vector2i,
		includeUncastableEmpty: bool = false) -> Array:
	var caster = state.getMonster(casterID)
	var spell = _resolveSpell(caster, spellSetIndex, spellIndex)
	if spell == null:
		return []
	if not _canSpellTargetPositionResolved(
			caster, spell, fromPos, centerPos, includeUncastableEmpty):
		return []
	var result: Array = []
	## The shape query is called with the center already validated, so it uses the
	## unchecked core. Going back through the public entry point would repeat the
	## whole reach check — including line of sight — for every center the AI scores.
	for pos in _spellAffectedPositions(caster, spell, fromPos, centerPos):
		var otherID = getProjectedOccupantID(casterID, fromPos, pos)
		if otherID == 0:
			continue
		var isAlly = state.getMonster(otherID).team == caster.team
		if spell.targetType == "self":
			if spell.aoe_targets == "allies" and isAlly:
				result.append(otherID)
			elif spell.aoe_targets == "enemies" and not isAlly:
				result.append(otherID)
			elif spell.aoe_targets == "all" or (
					spell.aoe_targets == "self" and otherID == casterID):
				result.append(otherID)
		elif (spell.heals and isAlly) or (not spell.heals and not isAlly):
			result.append(otherID)
	return result


func getSpellAffectedPositionsFrom(
		casterID: int,
		spellSetIndex: int,
		spellIndex: int,
		fromPos: Vector2i,
		centerPos: Vector2i,
		includeUncastableEmpty: bool = false) -> Array:
	## Read-only shape query shared by resolution, AI scoring, and presentation.
	## Presentation may request unconfirmable empty centers for preview only.
	var caster = state.getMonster(casterID)
	var spell = _resolveSpell(caster, spellSetIndex, spellIndex)
	if spell == null:
		return []
	if not _canSpellTargetPositionResolved(
			caster, spell, fromPos, centerPos, includeUncastableEmpty):
		return []
	return _spellAffectedPositions(caster, spell, fromPos, centerPos)


func _spellAffectedPositions(
		caster,
		spell: Spell,
		fromPos: Vector2i,
		centerPos: Vector2i) -> Array:
	## Shape-only core, with the center taken as already validated.
	if spell.targetType == "self":
		centerPos = fromPos
	var affectedTiles: Array
	if (spell.targetType == "self" and spell.self_radius <= 0) or (
			spell.targetType != "area" and spell.self_radius <= 0):
		affectedTiles = [centerPos]
	else:
		var radius := _resolvedSpellRadius(spell)
		match spell.area_shape:
			"cross": affectedTiles = ShapeCaster.getCross(centerPos, radius)
			"line": affectedTiles = ShapeCaster.getLine(fromPos, centerPos, radius)
			"circle", _: affectedTiles = ShapeCaster.getCircle(centerPos, radius)
	return affectedTiles.filter(func(pos: Vector2i) -> bool: return state.withinBounds(pos))


## Mirrors the targeting branch above and is also the sole value emitted to
## presentation. Keeping the calculation here prevents a radius buff from
## affecting gameplay while its VFX silently keeps the catalog default.
static func _resolvedSpellRadius(spell: Spell) -> int:
	if spell.targetType == "self":
		return maxi(spell.self_radius, 0)
	if spell.targetType == "area" or spell.self_radius > 0:
		return maxi(spell.radius, 0)
	return 0


func executeCastSpell(
		casterID: int,
		centerPos: Vector2i,
		spellSetIndex: int,
		spellIndex: int) -> Dictionary:
	var caster = state.getMonster(casterID)
	if caster == null or not caster.is_alive():
		return {"success": false, "reason": "invalid_monster"}
	if spellSetIndex < 0 or spellSetIndex >= caster.spellSets.size():
		return {"success": false, "reason": "invalid_spell_set"}
	if spellIndex < 0 or spellIndex >= caster.spellSets[spellSetIndex].size():
		return {"success": false, "reason": "invalid_spell"}

	var spell = caster.spellSets[spellSetIndex][spellIndex]
	if not caster.can_cast(spell):
		return {"success": false, "reason": "unavailable_spell"}
	var casterPos = state.getMonsterPosition(casterID)
	if not canSpellTargetPositionFrom(
			casterID, spellSetIndex, spellIndex, casterPos, centerPos):
		return {"success": false, "reason": "invalid_target"}

	## An empty center has no occupant. Report it as -1, matching the command's
	## own target_id and the empty-attack path — board.at() answers 0 for an empty
	## tile, which reads as a monster id everywhere else.
	var occupantID = state.board.at(centerPos)
	var targetID = -1 if occupantID == 0 else occupantID
	if spell.targetType == "self":
		targetID = casterID
	var actualTargets = getSpellAffectedTargetsFrom(
		casterID, spellSetIndex, spellIndex, casterPos, centerPos
	)
	events.spell_cast_started.emit(
		casterID,
		centerPos,
		spell.name,
		spell.element,
		actualTargets.size(),
		_resolvedSpellRadius(spell),
		spell.area_shape
	)

	if passiveSkillResolver != null:
		for affectedID in actualTargets:
			var target = state.getMonster(affectedID)
			if target != null and target.is_alive():
				passiveSkillResolver.fireOnTargeted(affectedID, casterID)
		if not caster.is_alive():
			return {"success": false, "reason": "caster_died_to_passive"}

	var casterDealtDamage = false
	for affectedID in actualTargets:
		if _applySpellEffects(casterID, affectedID, spell, centerPos):
			casterDealtDamage = true
	if casterDealtDamage:
		spellEffectResolver.consumeCasterDamageEffects(casterID)

	var resonanceElement = spell.resonance_element
	var oldCharge = caster.get_resonance(resonanceElement)
	caster.record_cast(spell)
	state.add_event("spell_cast", casterID, targetID, {
		"spell": spell.name,
		"target_pos": centerPos,
		"targets_hit": actualTargets.size()
	})
	var newCharge = caster.get_resonance(resonanceElement)
	if newCharge != oldCharge:
		var reason = "ascension_cast" if spell.sequence_level == 4 else "sequence_advanced"
		state.add_event("resonance_changed", casterID, casterID, {
			"element": resonanceElement, "old_charge": oldCharge,
			"new_charge": newCharge, "reason": reason
		})
		events.resonance_changed.emit(
			casterID, resonanceElement, oldCharge, newCharge, reason
		)

	return {
		"success": true,
		"targetsHit": actualTargets.size(),
		"spellName": spell.name,
		"target_id": targetID,
		"target_pos": centerPos
	}

func _applySpellEffects(
		casterID: int,
		targetID: int,
		spell: Spell,
		centerPos: Vector2i) -> bool:
	## Returns true when this target actually took damage, so the caller can
	## decide whether the caster's "focus" effect should be consumed.
	var result = spellEffectResolver.applySpellEffects(
		casterID, targetID, spell, passiveSkillResolver, centerPos
	)
	if result["damageDealt"]:
		spellEffectResolver.consumeTargetDamageEffects(targetID)
	if result["defeated"]:
		_handleDefeat(targetID, casterID)
	return result["damageDealt"]

func calculateSpellDamage(
		caster: Monster,
		target: Monster,
		base_damage: int,
		element: String = "none",
		is_simulation: bool = false,
		casterPos: Vector2i = Vector2i(-1, -1),
		isCritical: bool = false) -> int:
	return spellEffectResolver.calculateSpellDamage(
		caster,
		target,
		base_damage,
		element,
		is_simulation,
		passiveSkillResolver,
		casterPos,
		isCritical
	)

func getElevationPercent(attackerID: int, targetID: int) -> int:
	return DirectDamageRulesScript.elevationPercent(state, attackerID, targetID)


func applyElevationModifier(rawDamage: int, attackerID: int, targetID: int) -> int:
	return DirectDamageRulesScript.applyElevation(state, rawDamage, attackerID, targetID)

func calculateHeal(caster: Monster, spell: Spell) -> int:
	return spellEffectResolver.calculateHeal(caster, spell)

# --- Status effect damage ticks --- MOVED to PassiveSkillResolver.fireEvent(ON_TURN_END)
# CombatResolver no longer owns executeStatusEffectDamage().
# BattleSimulator.executeTurn() calls passiveSkillResolver.fireEvent(ON_TURN_END, monsterID) instead.


# --- Internal helpers ---

func _handleDefeat(defeatedID: int, killerID: int) -> void:
	## PassiveSkillResolver.handleDefeat() is the single defeat path shared by
	## every kill source (direct damage, status ticks, retaliation, AOE chains).
	## passiveSkillResolver can be null only in tests that never resolve a kill.
	if passiveSkillResolver != null:
		passiveSkillResolver.handleDefeat(defeatedID, killerID)
