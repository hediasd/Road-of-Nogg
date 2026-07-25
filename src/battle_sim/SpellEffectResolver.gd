## SpellEffectResolver — Applies spell damage, healing, buffs, and statuses.
## Pure logic extracted from CombatResolver to keep orchestration focused.

class_name SpellEffectResolver

const RaceReferences = preload("res://src/factories/RaceReferences.gd")

var state: BattleState
var events: BattleEvents


func _init(_state: BattleState, _events: BattleEvents) -> void:
	state = _state
	events = _events


func applySpellEffects(casterID: int, targetID: int, spell: Spell, passiveSkillResolver) -> bool:
	## Applies one spell to one target. Returns true when the target is defeated.
	var caster = state.getMonster(casterID)
	var target = state.getMonster(targetID)
	if target == null or not target.is_alive():
		return false

	if spell.removes_status != "" and state.hasEffect(targetID, spell.removes_status):
		state.removeEffect(targetID, spell.removes_status)
		events.effect_removed.emit(targetID, spell.removes_status)

	if spell.heals:
		var healAmount = calculateHeal(caster, spell)
		var actualHeal = target.heal(healAmount)
		events.monster_healed.emit(casterID, targetID, spell.name, actualHeal, target.hitpoints)
		return false

	if spell.reverts_damage:
		var targetDamageHistory = state.get_events_for_actor_since_last_turn(targetID, "damage")
		for entry in targetDamageHistory:
			var victimID = entry.get("target_id")
			var dmgAmount = entry.get("data", {}).get("damage", 0)
			var victim = state.getMonster(victimID)
			if victim != null and victim.is_alive():
				var actualHeal = victim.heal(dmgAmount)
				events.monster_healed.emit(casterID, victimID, "Ages Ago", actualHeal, victim.hitpoints)
		return false

	var actualDamageLines = []
	for line in spell.damage_lines:
		var element = line.get("element", "none")
		var baseDamage = line.get("damage", 0)
		if baseDamage <= 0:
			continue
		var damage = calculateSpellDamage(caster, target, baseDamage, element, false, passiveSkillResolver)
		var actualDamage = target.take_damage(damage)
		state.add_event("damage", casterID, targetID, {
			"damage": actualDamage,
			"spell": spell.name,
			"element": element
		})
		actualDamageLines.append({ "element": element, "damage": actualDamage })

	events.monster_cast_spell.emit(casterID, targetID, spell.name, actualDamageLines, target.hitpoints)
	_applyStatus(targetID, casterID, spell)
	_applyAttackBuff(targetID, casterID, spell)
	_applySpeedDebuff(targetID, casterID, spell)
	return not target.is_alive()


func calculateSpellDamage(
	caster: Monster,
	target: Monster,
	baseDamage: int,
	element: String = "none",
	isSimulation: bool = false,
	passiveSkillResolver = null
) -> int:
	var raw = max(1, caster.atk + baseDamage - target.def)
	for effect in state.getActiveEffects(caster.uniqueID):
		raw += effect.get("atk_bonus", 0)
	raw = max(1, raw)

	if element != "none":
		var multiplier = RaceReferences.getDamageMultiplier(target.race, element)
		raw = max(1, int(round(float(raw) * multiplier)))

	if passiveSkillResolver != null:
		raw = passiveSkillResolver.applyDamageModifiers(raw, target.uniqueID, isSimulation)

	return max(1, raw)


func calculateHeal(caster: Monster, spell: Spell) -> int:
	var basePower = 0
	if spell.damage_lines.size() > 0:
		basePower = spell.damage_lines[0].get("damage", 0)
	return max(1, caster.atk + basePower)


func _applyStatus(targetID: int, casterID: int, spell: Spell) -> void:
	if spell.inflicts_status == "":
		return
	var duration = _getStatusDuration(spell.inflicts_status)
	var damagePerTurn = _getStatusDamagePerTurn(spell.inflicts_status)
	state.addEffect(targetID, spell.inflicts_status, duration, casterID, spell.name, damagePerTurn)
	events.effect_applied.emit(targetID, spell.inflicts_status, duration, casterID, spell.name)


func _applyAttackBuff(targetID: int, casterID: int, spell: Spell) -> void:
	if spell.buffs_atk <= 0 or spell.buff_duration <= 0:
		return
	state.addEffect(targetID, "atk_buff", spell.buff_duration, casterID, spell.name, 0)
	for effect in state.activeEffects.get(targetID, []):
		if effect["name"] == "atk_buff" and effect.get("atk_bonus", 0) == 0:
			effect["atk_bonus"] = spell.buffs_atk
			break
	events.effect_applied.emit(targetID, "atk_buff", spell.buff_duration, casterID, spell.name)


func _applySpeedDebuff(targetID: int, casterID: int, spell: Spell) -> void:
	if spell.inflicts_status != "spd_debuff":
		return
	var duration = 99
	state.addEffect(targetID, "spd_debuff", duration, casterID, spell.name, 0)
	for effect in state.activeEffects.get(targetID, []):
		if effect["name"] == "spd_debuff" and effect.get("spd_bonus", 0) == 0:
			effect["spd_bonus"] = -2
			break
	events.effect_applied.emit(targetID, "spd_debuff", duration, casterID, spell.name)


func _getStatusDuration(statusName: String) -> int:
	match statusName:
		"burn": return 3
		"poison": return 4
		"petrify": return 2
		_: return 2


func _getStatusDamagePerTurn(statusName: String) -> int:
	match statusName:
		"burn": return 2
		"poison": return 1
		"petrify": return 0
		_: return 1
