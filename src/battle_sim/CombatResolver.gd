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
		if targetMon != null and targetMon.team != mon.team and targetMon.is_alive():
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

	if passiveSkillResolver != null:
		passiveSkillResolver.fireOnTargeted(targetID, attackerID)
		if not attacker.is_alive():
			return { "success": false, "reason": "attacker_died_to_passive" }
		if not target.is_alive():
			return { "success": true, "damage": 0, "targetHP": 0, "defeated": true }

	# Calculate and apply damage
	var damage = calculateBasicDamage(attacker, target)
	var actualDamage = target.take_damage(damage)

	state.add_event("damage", attackerID, targetID, { "damage": actualDamage, "type": "physical" })
	
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


func calculateBasicDamage(attacker: Monster, target: Monster, is_simulation: bool = false) -> int:
	var raw = max(1, attacker.atk - target.def)
	## Apply atk_bonus from active buffs
	for effect in state.getActiveEffects(attacker.uniqueID):
		raw += effect.get("atk_bonus", 0)
	raw = max(1, raw)
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
		if not spell.bypass_los and not _hasLoS(monsterID, fromPos, candidatePos, candidateID):
			continue
		targets.append(candidateID)

	return targets


func _hasLoS(casterID: int, fromPos: Vector2i, toPos: Vector2i, targetID: int) -> bool:
	## Returns true if there is clear LoS between fromPos and toPos.
	## Other monsters (not caster, not target) block line of sight, as do TERRAIN_OBSTACLE.
	return LineOfSight.hasLoS(fromPos, toPos, func(p: Vector2i) -> bool:
		if not state.withinBounds(p):
			return true  # Out-of-bounds blocks LoS
		if state.isLoSBlocked(p):
			return true  # Trees/Walls block LoS
		var occupantID = state.board.at(p)
		return occupantID != 0 and occupantID != casterID and occupantID != targetID
	)


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

	var actualTargets = []
	if spell.targetType == "self":
		# Self-cast: always targets the caster only, no range or LoS needed
		actualTargets.append(casterID)
	elif spell.targetType == "area":
		var affectedTiles = []
		match spell.area_shape:
			"cross": affectedTiles = ShapeCaster.getCross(centerPos, spell.radius)
			"line":  affectedTiles = ShapeCaster.getLine(casterPos, centerPos, spell.radius)
			"circle", _: affectedTiles = ShapeCaster.getCircle(centerPos, spell.radius)
		for p in affectedTiles:
			if not state.withinBounds(p): continue
			var otherID = state.board.at(p)
			if otherID != 0:
				# Friendly fire rules: heals only allies, damage/debuffs only enemies
				var isAlly = state.getMonster(otherID).team == caster.team
				if spell.heals and not isAlly: continue
				if not spell.heals and isAlly: continue
				actualTargets.append(otherID)
	else:
		actualTargets.append(targetID)

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

	for tID in actualTargets:
		_applySpellEffects(casterID, tID, spell)

	caster.record_cast(spell)

	return { "success": true, "targetsHit": actualTargets.size(), "spellName": spell.name }


func _applySpellEffects(casterID: int, targetID: int, spell: Spell) -> void:
	if spellEffectResolver.applySpellEffects(casterID, targetID, spell, passiveSkillResolver):
		_handleDefeat(targetID, casterID)

func calculateSpellDamage(caster: Monster, target: Monster, base_damage: int, element: String = "none", is_simulation: bool = false) -> int:
	return spellEffectResolver.calculateSpellDamage(
		caster,
		target,
		base_damage,
		element,
		is_simulation,
		passiveSkillResolver
	)

func calculateHeal(caster: Monster, spell: Spell) -> int:
	return spellEffectResolver.calculateHeal(caster, spell)

# --- Status effect damage ticks --- MOVED to PassiveSkillResolver.fireEvent(ON_TURN_END)
# CombatResolver no longer owns executeStatusEffectDamage().
# BattleSimulator.executeTurn() calls passiveSkillResolver.fireEvent(ON_TURN_END, monsterID) instead.


# --- Internal helpers ---

func _handleDefeat(defeatedID: int, killerID: int) -> void:
	## Fire ON_DEATH passives BEFORE removing from state (so Snowfall can read positions).
	if passiveSkillResolver != null:
		passiveSkillResolver.fireEvent(PassiveSkillResolver.ON_DEATH, defeatedID)
	## Only emit defeated + remove if still in state (ON_DEATH aoe may have already cleared it)
	if state.monsters.has(defeatedID) and not state.getMonster(defeatedID).is_alive():
		events.monster_defeated.emit(defeatedID, killerID)
		state.removeMonster(defeatedID)
