## SpellEffectResolver — Applies spell damage, healing, buffs, and statuses.
## Pure logic extracted from CombatResolver to keep orchestration focused.

class_name SpellEffectResolver

const DirectDamageRulesScript = preload("res://src/battle_sim/DirectDamageRules.gd")

const RaceReferences = preload("res://src/factories/RaceReferences.gd")
const StatusEffectReferences = preload("res://src/factories/StatusEffectReferences.gd")
const CRITICAL_DAMAGE_MULTIPLIER := 1.25

var state: BattleState
var events: BattleEvents


func _init(_state: BattleState, _events: BattleEvents) -> void:
	state = _state
	events = _events


func applySpellEffects(casterID: int, targetID: int, spell: Spell, passiveSkillResolver) -> Dictionary:
	## Applies one spell to one target. Returns {"defeated": bool, "damageDealt": bool}.
	## damageDealt tells the caller whether to consume this target's "guard"; the
	## caller consumes the caster's "focus" once after every target is resolved,
	## not per target, so AOE casts strip each effect exactly once (see
	## CombatResolver.executeCastSpell).
	var caster = state.getMonster(casterID)
	var target = state.getMonster(targetID)
	if target == null or not target.is_alive():
		return {"defeated": false, "damageDealt": false}

	if spell.removes_status != "" and state.hasEffect(targetID, spell.removes_status):
		state.removeEffect(targetID, spell.removes_status)
		events.effect_removed.emit(targetID, spell.removes_status)

	var damageDealt = false
	if spell.heals:
		var healAmount = calculateHeal(caster, spell)
		var actualHeal = target.heal(healAmount)
		events.monster_healed.emit(casterID, targetID, spell.name, actualHeal, target.hitpoints)
	elif spell.reverts_damage:
		var targetDamageHistory = state.get_events_for_actor_since_last_turn(targetID, "damage")
		for entry in targetDamageHistory:
			var victimID = entry.get("target_id")
			var dmgAmount = entry.get("data", {}).get("damage", 0)
			var victim = state.getMonster(victimID)
			if victim != null and victim.is_alive():
				var actualHeal = victim.heal(dmgAmount)
				events.monster_healed.emit(casterID, victimID, spell.name, actualHeal, victim.hitpoints)
	else:
		var actualDamageLines = []
		var shouldDecayResonance = false
		var isCritical = _rollCritical(caster)
		for line in spell.damage_lines:
			var element = line.get("element", "none")
			var baseDamage = line.get("damage", 0)
			if baseDamage <= 0:
				continue

			var isWeakness = RaceReferences.getDamageMultiplier(target.race, element) > 1.0
			var damage = calculateSpellDamage(
				caster, target, baseDamage, element, false, passiveSkillResolver,
				Vector2i(-1, -1), isCritical
			)
			var actualDamage = target.take_damage(damage)
			shouldDecayResonance = shouldDecayResonance or isCritical or isWeakness
			state.add_event("damage", casterID, targetID, {
				"damage": actualDamage,
				"spell": spell.name,
				"element": element,
				"critical": isCritical,
				"weakness": isWeakness,
				"elevation_percent": DirectDamageRulesScript.elevationPercent(
					state, casterID, targetID
				)
			})
			actualDamageLines.append({
				"element": element,
				"damage": actualDamage,
				"critical": isCritical,
				"weakness": isWeakness
			})

		damageDealt = not actualDamageLines.is_empty()
		if shouldDecayResonance:
			_decayResonance(targetID)
		events.monster_cast_spell.emit(casterID, targetID, spell.name, actualDamageLines, target.hitpoints)

	## Every payload below is independent of the heal/revert/damage branch above:
	## a healing spell can still inflict a status or grant a buff (e.g. Timeoff).
	_applyStatus(targetID, casterID, spell)
	_applyAttackBuff(targetID, casterID, spell)
	_applyDeclaredEffects(targetID, casterID, spell)
	return {"defeated": not target.is_alive(), "damageDealt": damageDealt}


func calculateSpellDamage(
	caster: Monster,
	target: Monster,
	baseDamage: int,
	element: String = "none",
	isSimulation: bool = false,
	passiveSkillResolver = null,
	casterPos: Vector2i = Vector2i(-1, -1),
	isCritical: bool = false) -> int:
	var attackerBonus = _statBonus(caster.uniqueID, "atk_bonus")
	var defenderBonus = _statBonus(target.uniqueID, "def_bonus")
	var raw = max(1, caster.get_effective_atk() + attackerBonus + baseDamage - target.get_effective_def() - defenderBonus)
	raw = max(1, raw)

	if state.withinBounds(casterPos):
		raw = DirectDamageRulesScript.applyElevationFromPositions(
			state, raw, casterPos, state.getMonsterPosition(target.uniqueID)
		)
	else:
		raw = DirectDamageRulesScript.applyElevation(
			state, raw, caster.uniqueID, target.uniqueID
		)
	if element != "none":
		var multiplier = RaceReferences.getDamageMultiplier(target.race, element)
		raw = max(1, int(round(float(raw) * multiplier)))
	if isCritical:
		raw = max(1, int(round(float(raw) * CRITICAL_DAMAGE_MULTIPLIER)))
	raw = applyDamageEffectMultipliers(raw, caster.uniqueID, target.uniqueID)

	if passiveSkillResolver != null:
		raw = passiveSkillResolver.applyDamageModifiers(raw, target.uniqueID, isSimulation)

	return max(1, raw)


func calculateHeal(caster: Monster, spell: Spell) -> int:
	if spell.heal_amount > 0:
		return spell.heal_amount
	var basePower = 0
	if spell.damage_lines.size() > 0:
		basePower = spell.damage_lines[0].get("damage", 0)
	return max(1, caster.get_effective_atk() + _statBonus(caster.uniqueID, "atk_bonus") + basePower)



func _rollCritical(caster: Monster) -> bool:
	var chance = caster.get_critical_chance()
	return chance > 0.0 and state.rng.randf() < chance

func _decayResonance(targetID: int) -> void:
	var target = state.getMonster(targetID)
	if target == null:
		return
	var change = target.lose_one_resonance_bar()
	if change.is_empty():
		return
	state.add_event("resonance_changed", targetID, targetID, {
		"element": change["element"],
		"old_charge": change["old_charge"],
		"new_charge": change["new_charge"],
		"reason": "critical_or_weakness"
	})
	events.resonance_changed.emit(
		targetID, change["element"], change["old_charge"], change["new_charge"],
		"critical_or_weakness"
	)


func _statBonus(monsterID: int, key: String) -> int:
	var total = 0
	for effect in state.getActiveEffects(monsterID):
		total += int(effect.get(key, 0))
	return total


func _effectMultiplier(monsterID: int, effectName: String) -> float:
	for effect in state.getActiveEffects(monsterID):
		if effect.get("name", "") == effectName:
			return float(effect.get("damage_multiplier", 1.0))
	return 1.0


func applyDamageEffectMultipliers(raw: int, casterID: int, targetID: int) -> int:
	var adjusted = int(round(float(raw) * _effectMultiplier(casterID, "focus")))
	adjusted = int(round(float(adjusted) * _effectMultiplier(targetID, "guard")))
	return max(1, adjusted)


func consumeDamageEffects(casterID: int, targetID: int) -> void:
	## Single-target callers (basic attacks) only ever resolve one target, so
	## consuming both sides together in one action is correct here. AOE spell
	## casts must not use this: see consumeCasterDamageEffects/
	## consumeTargetDamageEffects and the call sites in executeCastSpell.
	consumeCasterDamageEffects(casterID)
	consumeTargetDamageEffects(targetID)


func consumeCasterDamageEffects(casterID: int) -> void:
	if state.hasEffect(casterID, "focus"):
		state.removeEffect(casterID, "focus")
		events.effect_removed.emit(casterID, "focus")


func consumeTargetDamageEffects(targetID: int) -> void:
	if state.hasEffect(targetID, "guard"):
		state.removeEffect(targetID, "guard")
		events.effect_removed.emit(targetID, "guard")


func _applyDeclaredEffects(targetID: int, casterID: int, spell: Spell) -> void:
	for definition in spell.effects:
		var effectName = str(definition.get("NAME", ""))
		if effectName.is_empty():
			continue
		if effectName == "cleanse":
			_cleanseNegativeEffects(targetID)
			continue
		if effectName == "cooldown_reduction":
			_reduceCooldowns(targetID, int(definition.get("VALUE", 1)))
			continue
		var effectData: Dictionary = {}
		for key in definition:
			if key not in ["NAME", "DURATION"]:
				effectData[str(key).to_lower()] = definition[key]
		var duration = maxi(1, int(definition.get("DURATION", 1)))
		state.addEffect(targetID, effectName, duration, casterID, spell.name, 0, effectData)
		events.effect_applied.emit(targetID, effectName, duration, casterID, spell.name)


func _cleanseNegativeEffects(targetID: int) -> void:
	for effect in state.getActiveEffects(targetID).duplicate(true):
		var effectName: String = effect.get("name", "")
		if bool(effect.get("negative", false)) or StatusEffectReferences.isNegative(effectName):
			state.removeEffect(targetID, effectName)
			events.effect_removed.emit(targetID, effectName)


func _reduceCooldowns(targetID: int, amount: int) -> void:
	var target = state.getMonster(targetID)
	if target == null:
		return
	for spellName in target.spell_cooldowns:
		target.spell_cooldowns[spellName] = maxi(0, int(target.spell_cooldowns[spellName]) - maxi(0, amount))

func _applyStatus(targetID: int, casterID: int, spell: Spell) -> void:
	if spell.inflicts_status == "":
		return
	var duration = StatusEffectReferences.getDuration(spell.inflicts_status)
	var damagePerTurn = StatusEffectReferences.getDamagePerTurn(spell.inflicts_status)
	state.addEffect(targetID, spell.inflicts_status, duration, casterID, spell.name, damagePerTurn)
	events.effect_applied.emit(targetID, spell.inflicts_status, duration, casterID, spell.name)


func _applyAttackBuff(targetID: int, casterID: int, spell: Spell) -> void:
	if spell.buffs_atk <= 0 or spell.buff_duration <= 0:
		return
	state.addEffect(
		targetID, "atk_buff", spell.buff_duration, casterID, spell.name, 0,
		{"atk_bonus": spell.buffs_atk}
	)
	events.effect_applied.emit(targetID, "atk_buff", spell.buff_duration, casterID, spell.name)
