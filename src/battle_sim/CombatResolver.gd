## CombatResolver — Handles attacks, spells, damage calculation, heal resolution, and status infliction.
## Pure logic, no Node dependency.

class_name CombatResolver

var state: BattleState
var events: BattleEvents


func _init(_state: BattleState, _events: BattleEvents) -> void:
	state = _state
	events = _events


# --- Basic melee attack ---

const LineOfSight = preload("res://src/algorithms/LineOfSight.gd")
const DIRECTIONS = [Vector2i(0, -1), Vector2i(0, 1), Vector2i(-1, 0), Vector2i(1, 0)]

func getBasicAttackTargets(monsterID: int) -> Array:
	## Returns monster IDs of enemies adjacent to this monster (range 1).
	var mon = state.getMonster(monsterID)
	if mon == null:
		return []

	var pos = state.getMonsterPosition(monsterID)
	var targets = []

	for dir in DIRECTIONS:
		var neighbor = pos + dir
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

	# Validate range (must be adjacent)
	var attackerPos = state.getMonsterPosition(attackerID)
	var targetPos = state.getMonsterPosition(targetID)
	var distance = abs(attackerPos.x - targetPos.x) + abs(attackerPos.y - targetPos.y)

	if distance > 1:
		return { "success": false, "reason": "out_of_range" }

	# Calculate and apply damage
	var damage = calculateBasicDamage(attacker, target)
	var actualDamage = target.take_damage(damage)

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


func calculateBasicDamage(attacker: Monster, target: Monster) -> int:
	return max(1, attacker.atk - target.def)


# --- Spell casting ---

func getSpellTargets(monsterID: int, spellSetIndex: int, spellIndex: int) -> Array:
	## Returns valid target IDs for the spell, filtered by range AND line-of-sight.
	## Heals target ALLIES; damage spells target ENEMIES.
	var mon = state.getMonster(monsterID)
	if mon == null:
		return []
	if spellSetIndex >= mon.spellSets.size():
		return []
	if spellIndex >= mon.spellSets[spellSetIndex].size():
		return []

	var spell = mon.spellSets[spellSetIndex][spellIndex]
	var pos = state.getMonsterPosition(monsterID)
	var targets = []

	for candidateID in state.monsters:
		var candidate = state.monsters[candidateID]
		if not candidate.is_alive():
			continue

		# Heal spells target allies; damage spells target enemies
		var isAlly = candidate.team == mon.team
		if spell.heals and not isAlly:
			continue
		if not spell.heals and isAlly:
			continue

		var candidatePos = state.getMonsterPosition(candidateID)
		var distance = abs(pos.x - candidatePos.x) + abs(pos.y - candidatePos.y)
		if distance > spell.range:
			continue

		# Line-of-sight check (skipped if spell has bypass_los)
		if not spell.bypass_los and not _hasLoS(monsterID, pos, candidatePos, candidateID):
			continue

		targets.append(candidateID)

	return targets


func _hasLoS(casterID: int, fromPos: Vector2i, toPos: Vector2i, targetID: int) -> bool:
	## Returns true if there is clear LoS between fromPos and toPos.
	## Other monsters (not caster, not target) block line of sight.
	return LineOfSight.hasLoS(fromPos, toPos, func(p: Vector2i) -> bool:
		if not state.withinBounds(p):
			return true  # Out-of-bounds blocks LoS
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
	if spellSetIndex >= caster.spellSets.size():
		return { "success": false, "reason": "invalid_spell_set" }
	if spellIndex >= caster.spellSets[spellSetIndex].size():
		return { "success": false, "reason": "invalid_spell" }

	var spell = caster.spellSets[spellSetIndex][spellIndex]

	# Validate range to center
	var casterPos = state.getMonsterPosition(casterID)
	var centerPos = state.getMonsterPosition(targetID)
	var distance = abs(casterPos.x - centerPos.x) + abs(casterPos.y - centerPos.y)

	if distance > spell.range:
		return { "success": false, "reason": "out_of_range" }

	var actualTargets = []
	if spell.targetType == "area":
		for otherID in state.getAliveMonsterIDs():
			var otherPos = state.getMonsterPosition(otherID)
			var distFromCenter = abs(centerPos.x - otherPos.x) + abs(centerPos.y - otherPos.y)
			if distFromCenter <= spell.radius:
				# Friendly fire rules: heals only allies, damage/debuffs only enemies
				var isAlly = state.getMonster(otherID).team == caster.team
				if spell.heals and not isAlly: continue
				if not spell.heals and isAlly: continue
				actualTargets.append(otherID)
	else:
		actualTargets.append(targetID)

	if actualTargets.is_empty():
		return { "success": false, "reason": "no_valid_targets" }

	for tID in actualTargets:
		_applySpellEffects(casterID, tID, spell)

	return { "success": true, "targetsHit": actualTargets.size(), "spellName": spell.name }


func _applySpellEffects(casterID: int, targetID: int, spell: Spell) -> void:
	var caster = state.getMonster(casterID)
	var target = state.getMonster(targetID)
	if not target.is_alive(): return

	# --- Remove Status ---
	if spell.removes_status != "":
		if state.hasEffect(targetID, spell.removes_status):
			state.removeEffect(targetID, spell.removes_status)
			events.effect_removed.emit(targetID, spell.removes_status)

	# --- Heal path ---
	if spell.heals:
		var healAmount = calculateHeal(caster, spell)
		var actualHeal = target.heal(healAmount)
		events.monster_healed.emit(casterID, targetID, spell.name, actualHeal, target.hitpoints)
		return

	# --- Damage path ---
	var damage = calculateSpellDamage(caster, target, spell)
	var actualDamage = target.take_damage(damage)

	events.monster_cast_spell.emit(casterID, targetID, spell.name, spell.element, actualDamage, target.hitpoints)

	# Apply status if the spell inflicts one
	if spell.inflicts_status != "":
		var statusDuration = _getStatusDuration(spell.inflicts_status)
		var statusDmg = _getStatusDamagePerTurn(spell.inflicts_status)
		state.addEffect(targetID, spell.inflicts_status, statusDuration, casterID, spell.name, statusDmg)
		events.effect_applied.emit(targetID, spell.inflicts_status, statusDuration, casterID, spell.name)

	if not target.is_alive():
		_handleDefeat(targetID, casterID)


func calculateSpellDamage(caster: Monster, target: Monster, spell: Spell) -> int:
	return max(1, caster.atk + spell.damage - target.def)


func calculateHeal(caster: Monster, spell: Spell) -> int:
	## Heal amount scales on caster ATK + spell power (same formula as damage for now).
	return max(1, caster.atk + spell.damage)


# --- Status effect damage ticks ---

func executeStatusEffectDamage(monsterID: int) -> void:
	## Called at end of turn before tickEffects(). Applies per-turn damage from effects like Burn.
	var effects = state.getActiveEffects(monsterID)
	var mon = state.getMonster(monsterID)
	if mon == null or not mon.is_alive():
		return

	for effect in effects:
		var dmg = effect.get("damagePerTurn", 0)
		if dmg <= 0:
			continue
		var actualDamage = mon.take_damage(dmg)
		events.status_damage_dealt.emit(monsterID, effect["name"], actualDamage, mon.hitpoints)
		if not mon.is_alive():
			# Status effect kills — source monster gets credit
			var sourceID = effect.get("sourceMonsterID", -1)
			_handleDefeat(monsterID, sourceID)
			return  # Monster is dead, stop processing


# --- Internal helpers ---

func _handleDefeat(defeatedID: int, killerID: int) -> void:
	events.monster_defeated.emit(defeatedID, killerID)
	state.removeMonster(defeatedID)


func _getStatusDuration(statusName: String) -> int:
	match statusName:
		"burn":    return 3
		"poison":  return 4
		"petrify": return 2
		_:         return 2


func _getStatusDamagePerTurn(statusName: String) -> int:
	match statusName:
		"burn":    return 2
		"poison":  return 1
		"petrify": return 0  # No damage but will prevent action (future)
		_:         return 1
