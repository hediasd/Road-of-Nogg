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


func getBasicAttackTargetsFrom(monsterID: int, fromPos: Vector2i) -> Array:
	var mon = state.getMonster(monsterID)
	if mon == null or not mon.is_alive():
		return []

	var targets = []
	for direction in DIRECTIONS:
		var neighbor = fromPos + direction
		if not state.withinBounds(neighbor):
			continue
		var targetMon = state.getMonsterAt(neighbor)
		if (
			targetMon != null
			and targetMon.team != mon.team
			and targetMon.is_alive()
			and state.getHeightDifference(fromPos, neighbor) <= 1
		):
			targets.append(targetMon.uniqueID)
	return targets


func executeBasicAttack(attackerID: int, targetID: int) -> Dictionary:
	## Executes a basic melee attack. Returns result dict.
	var attacker = state.getMonster(attackerID)
	var target = state.getMonster(targetID)

	if attacker == null or target == null:
		return { "success": false, "reason": "invalid_monster" }
	if not attacker.is_alive() or not target.is_alive():
		return { "success": false, "reason": "dead_monster" }
	if attacker.team == target.team:
		return { "success": false, "reason": "invalid_target" }

	# Validate range (must be adjacent)
	var attackerPos = state.getMonsterPosition(attackerID)
	var targetPos = state.getMonsterPosition(targetID)
	var distance = abs(attackerPos.x - targetPos.x) + abs(attackerPos.y - targetPos.y)

	if distance > 1:
		return { "success": false, "reason": "out_of_range" }
	if state.getHeightDifference(attackerPos, targetPos) > 1:
		return { "success": false, "reason": "height_out_of_range" }

	if passiveSkillResolver != null:
		passiveSkillResolver.fireOnTargeted(targetID, attackerID)
		if not attacker.is_alive():
			return { "success": false, "reason": "attacker_died_to_passive" }
		if not target.is_alive():
			return { "success": true, "damage": 0, "targetHP": 0, "defeated": true }

	# Calculate and apply damage
	var damage = calculateBasicDamage(attacker, target)
	var actualDamage = target.take_damage(damage)
	if actualDamage > 0:
		spellEffectResolver.consumeDamageEffects(attackerID, targetID)

	state.add_event("damage", attackerID, targetID, {
		"damage": actualDamage,
		"type": "physical",
		"elevation_percent": getElevationPercent(attackerID, targetID)
	})
	
	events.monster_attacked.emit(attackerID, targetID, actualDamage, target.hitpoints)

	var result = {
		"success": true,
		"damage": actualDamage,
		"targetHP": target.hitpoints,
		"defeated": not target.is_alive()
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
		monsterID,
		spellSetIndex,
		spellIndex,
		state.getMonsterPosition(monsterID)
	)


func getSpellTargetsFrom(
		monsterID: int,
		spellSetIndex: int,
		spellIndex: int,
		fromPos: Vector2i) -> Array:
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
		return [monsterID]

	var targets = []
	for candidateID in state.monsters:
		var candidate = state.monsters[candidateID]
		if not candidate.is_alive():
			continue

		var isAlly = candidate.team == mon.team
		if spell.heals and not isAlly:
			continue
		if not spell.heals and isAlly:
			continue

		var candidatePos = state.getMonsterPosition(candidateID)
		var distance = abs(fromPos.x - candidatePos.x) + abs(fromPos.y - candidatePos.y)
		if distance < spell.min_range or distance > spell.range:
			continue
		if state.getHeightDifference(fromPos, candidatePos) > spell.max_height_delta:
			continue
		if not spell.bypass_los and not _hasLoS(monsterID, fromPos, candidatePos, candidateID):
			continue
		targets.append(candidateID)

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

func canBasicAttackPositionFrom(monsterID: int, fromPos: Vector2i, targetPos: Vector2i) -> bool:
	return (
		state.withinBounds(targetPos)
		and abs(fromPos.x - targetPos.x) + abs(fromPos.y - targetPos.y) == 1
		and state.getHeightDifference(fromPos, targetPos) <= 1
	)


func canSpellReachPositionFrom(
		monsterID: int,
		spellSetIndex: int,
		spellIndex: int,
		fromPos: Vector2i,
		targetPos: Vector2i) -> bool:
	var mon = state.getMonster(monsterID)
	if mon == null or spellSetIndex < 0 or spellSetIndex >= mon.spellSets.size():
		return false
	if spellIndex < 0 or spellIndex >= mon.spellSets[spellSetIndex].size():
		return false
	var spell = mon.spellSets[spellSetIndex][spellIndex]
	if not mon.can_cast(spell):
		return false
	var distance = abs(fromPos.x - targetPos.x) + abs(fromPos.y - targetPos.y)
	if distance < spell.min_range or distance > spell.range:
		return false
	if state.getHeightDifference(fromPos, targetPos) > spell.max_height_delta:
		return false
	if spell.bypass_los:
		return true
	## Pass the real occupant of targetPos, matching getSpellTargetsFrom(), so a
	## target's own tile is never treated as its own LoS blocker.
	var targetOccupantID = state.board.at(targetPos)
	return _hasLoS(monsterID, fromPos, targetPos, targetOccupantID)


func getSpellAffectedTargetsFrom(
		casterID: int,
		spellSetIndex: int,
		spellIndex: int,
		fromPos: Vector2i,
		centerTargetID: int) -> Array:
	if not getSpellTargetsFrom(casterID, spellSetIndex, spellIndex, fromPos).has(centerTargetID):
		return []
	var caster = state.getMonster(casterID)
	if caster == null:
		return []
	var spell = caster.spellSets[spellSetIndex][spellIndex]
	var result: Array = []
	for pos in getSpellAffectedPositionsFrom(
			casterID, spellSetIndex, spellIndex, fromPos, centerTargetID):
		var otherID = state.board.at(pos)
		if otherID == 0:
			continue
		var isAlly = state.getMonster(otherID).team == caster.team
		if spell.targetType == "self":
			if spell.aoe_targets == "allies" and isAlly:
				result.append(otherID)
			elif spell.aoe_targets == "enemies" and not isAlly:
				result.append(otherID)
			elif spell.aoe_targets == "all" or (spell.aoe_targets == "self" and otherID == casterID):
				result.append(otherID)
		elif (spell.heals and isAlly) or (not spell.heals and not isAlly):
			result.append(otherID)
	return result


func getSpellAffectedPositionsFrom(
		casterID: int,
		spellSetIndex: int,
		spellIndex: int,
		fromPos: Vector2i,
		centerTargetID: int) -> Array:
	## Read-only shape query shared by resolution, AI scoring, and presentation
	## previews. The center remains an occupied legal target by command contract.
	if not getSpellTargetsFrom(casterID, spellSetIndex, spellIndex, fromPos).has(centerTargetID):
		return []
	var caster = state.getMonster(casterID)
	if caster == null:
		return []
	var spell = caster.spellSets[spellSetIndex][spellIndex]
	var centerPos = (
		state.getMonsterPosition(casterID)
		if spell.targetType == "self" else
		state.getMonsterPosition(centerTargetID)
	)
	var affectedTiles: Array
	if (spell.targetType == "self" and spell.self_radius <= 0) or (
			spell.targetType != "area" and spell.self_radius <= 0):
		affectedTiles = [centerPos]
	else:
		var radius = spell.self_radius if spell.targetType == "self" else spell.radius
		match spell.area_shape:
			"cross": affectedTiles = ShapeCaster.getCross(centerPos, radius)
			"line": affectedTiles = ShapeCaster.getLine(fromPos, centerPos, radius)
			"circle", _: affectedTiles = ShapeCaster.getCircle(centerPos, radius)
	return affectedTiles.filter(func(pos: Vector2i) -> bool: return state.withinBounds(pos))

func executeCastSpell(casterID: int, targetID: int, spellSetIndex: int, spellIndex: int) -> Dictionary:
	## Casts a spell. Routes to heal or damage logic based on spell.heals. Supports AOE.
	var caster = state.getMonster(casterID)
	var centerTarget = state.getMonster(targetID)

	if caster == null or centerTarget == null:
		return { "success": false, "reason": "invalid_monster" }
	if not caster.is_alive() or not centerTarget.is_alive():
		return { "success": false, "reason": "dead_monster" }
	if spellSetIndex < 0 or spellSetIndex >= caster.spellSets.size():
		return { "success": false, "reason": "invalid_spell_set" }
	if spellIndex < 0 or spellIndex >= caster.spellSets[spellSetIndex].size():
		return { "success": false, "reason": "invalid_spell" }

	var spell = caster.spellSets[spellSetIndex][spellIndex]
	if not caster.can_cast(spell):
		return { "success": false, "reason": "unavailable_spell" }
	if not getSpellTargets(casterID, spellSetIndex, spellIndex).has(targetID):
		return { "success": false, "reason": "invalid_target" }

	# Validate range to center
	var casterPos = state.getMonsterPosition(casterID)
	var centerPos = state.getMonsterPosition(targetID)
	var distance = abs(casterPos.x - centerPos.x) + abs(casterPos.y - centerPos.y)

	if distance < spell.min_range or distance > spell.range:
		return { "success": false, "reason": "out_of_range" }

	var actualTargets = getSpellAffectedTargetsFrom(
		casterID, spellSetIndex, spellIndex, casterPos, targetID
	)
	if actualTargets.is_empty():
		return { "success": false, "reason": "no_valid_targets" }

	if passiveSkillResolver != null:
		# Fire targeted for all valid targets (some could die, attacker could die)
		for tID in actualTargets:
			var t = state.getMonster(tID)
			if t != null and t.is_alive():
				passiveSkillResolver.fireOnTargeted(tID, casterID)
		
		if not caster.is_alive():
			return { "success": false, "reason": "caster_died_to_passive" }

	## "focus" (caster) is consumed once for the whole cast, regardless of how
	## many targets an AOE hits. "guard" (defender) is consumed once per target
	## that actually took damage. Consuming both per-target would let a single
	## AOE cast strip the caster's focus once per affected target.
	var casterDealtDamage = false
	for tID in actualTargets:
		if _applySpellEffects(casterID, tID, spell):
			casterDealtDamage = true
	if casterDealtDamage:
		spellEffectResolver.consumeCasterDamageEffects(casterID)

	var resonanceElement = spell.resonance_element
	var oldCharge = caster.get_resonance(resonanceElement)
	caster.record_cast(spell)
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

	return { "success": true, "targetsHit": actualTargets.size(), "spellName": spell.name }


func _applySpellEffects(casterID: int, targetID: int, spell: Spell) -> bool:
	## Returns true when this target actually took damage, so the caller can
	## decide whether the caster's "focus" effect should be consumed.
	var result = spellEffectResolver.applySpellEffects(casterID, targetID, spell, passiveSkillResolver)
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
