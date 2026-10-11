## What the docked card shows while the player aims: one target's matchup, or the list of units an
## area spell would hit.
##
## Built here, in the battle layer, because it needs the adapter's forecasts (the same numbers the
## in-world preview boxes print) and the simulator's resolvers; the card in `ui/` only draws the
## Dictionary this returns. It states what the action does, never what the player should do:
##
## - damage and crit from `forecastAttack` / `forecastSpell`;
## - healing from `CombatResolver.calculateHeal`;
## - the target itself as `HexUnitFacts` (displayed HP and effects, elements, side, captain).
##
## Weakness, resistance, retaliation and what an enemy could do next turn are deliberately left out:
## that depth is the STATUS sheet's, and the strategy is the player's.

extends RefCounted

const HexUnitFactsScript = preload("res://ui/HexUnitFacts.gd")
const HexBattleHudScript = preload("res://battle/HexBattleHud.gd")
const HexBattleMemberInputScript = preload("res://battle/HexBattleMemberInput.gd")

const KIND_SINGLE := "single"
const KIND_AREA := "area"


## `model` is the aim model (or the pointer's attack model). Empty when there is nothing to match up:
## no target and no affected unit, or no acting unit.
func build(sim: BattleSimulator, adapter, actorID: int, model: Dictionary, viewerPartyID: int) -> Dictionary:
	if sim == null or adapter == null or model.is_empty():
		return {}
	var actor = sim.state.getMonster(actorID)
	if actor == null:
		return {}
	var isSpell := str(model.get("kind", "")) == HexBattleMemberInputScript.SPELL_PREFIX
	var spell = _spell(actor, model) if isSpell else null
	if isSpell and spell == null:
		return {}

	var affected := _affectedUnits(sim, model) if isSpell else []
	if isSpell and affected.size() > 1:
		return _area(sim, adapter, actorID, model, spell, affected, viewerPartyID)
	var targetID := int(model.get("target_id", -1))
	if targetID == -1 and affected.size() == 1:
		targetID = int(affected[0])
	var target = sim.state.getMonster(targetID)
	if target == null or not target.is_alive():
		return {}
	return _single(sim, adapter, actor, actorID, model, spell, target, targetID, viewerPartyID)


func _single(sim, adapter, actor, actorID: int, model: Dictionary, spell, target, targetID: int,
		viewerPartyID: int) -> Dictionary:
	var hp := int(target.hitpoints)
	var facts := {
		"kind": KIND_SINGLE,
		"action": str(spell.name) if spell != null else "Attack",
		"target_id": targetID,
		"target": HexUnitFactsScript.build(sim, targetID, adapter, viewerPartyID),
		"hp": hp,
		"max_hp": maxi(1, int(target.max_hitpoints)),
		"hp_after": hp,
		"heal": 0,
		"damage_min": 0,
		"damage_max": 0,
		"crit_chance": 0.0,
		"lethal": false,
		"possibly_lethal": false,
		"effect_text": "",
		"legal": bool(model.get("legal", false)),
		"reason": HexBattleHudScript.reasonText(str(model.get("reason", ""))),
	}
	var cell: Vector2i = sim.state.getMonsterPosition(targetID)
	var forecast: Dictionary
	if spell == null:
		forecast = model.get("forecast", {})
		if forecast.is_empty():
			forecast = adapter.forecastAttack(actorID, cell)
	else:
		forecast = adapter.forecastSpell(actorID, int(model.get("spell_set_index", 0)),
			int(model.get("spell_index", 0)), cell)
	if bool(forecast.get("available", false)):
		facts["damage_min"] = int(forecast.get("minimum", 0))
		facts["damage_max"] = int(forecast.get("maximum", 0))
		facts["crit_chance"] = float(forecast.get("critical_chance", 0.0))
		facts["lethal"] = bool(forecast.get("lethal", false))
		facts["possibly_lethal"] = bool(forecast.get("possibly_lethal", false))
		facts["hp_after"] = maxi(0, hp - int(facts["damage_min"]))
	elif spell != null and (bool(spell.heals) or int(spell.heal_amount) > 0):
		var amount := int(sim.combatResolver.calculateHeal(actor, spell))
		facts["heal"] = amount
		facts["hp_after"] = mini(int(facts["max_hp"]), hp + amount)
	elif spell != null:
		facts["effect_text"] = HexUnitFactsScript.spellSummary(spell)
	return facts


func _area(sim, adapter, actorID: int, model: Dictionary, spell, affected: Array,
		viewerPartyID: int) -> Dictionary:
	var rows: Array = []
	for unitID in affected:
		var unit = sim.state.getMonster(int(unitID))
		if unit == null:
			continue
		var cell: Vector2i = sim.state.getMonsterPosition(int(unitID))
		var forecast: Dictionary = adapter.forecastSpell(actorID, int(model.get("spell_set_index", 0)),
			int(model.get("spell_index", 0)), cell)
		rows.append({
			"name": str(unit.name),
			"allegiance": HexUnitFactsScript.allegianceFor(sim, unit, viewerPartyID),
			"damage": int(forecast.get("minimum", 0)) if bool(forecast.get("available", false)) else 0,
			"lethal": bool(forecast.get("lethal", false)),
		})
	# Allies first: that the spell hits its caster's own side is a fact of the cast, not advice.
	var allies := rows.filter(func(row: Dictionary) -> bool:
		return str(row["allegiance"]) == HexUnitFactsScript.ALLEGIANCE_ALLY)
	var others := rows.filter(func(row: Dictionary) -> bool:
		return str(row["allegiance"]) != HexUnitFactsScript.ALLEGIANCE_ALLY)
	return {
		"kind": KIND_AREA,
		"action": str(spell.name),
		"legal": bool(model.get("legal", false)),
		"reason": HexBattleHudScript.reasonText(str(model.get("reason", ""))),
		"allies_hit": allies.size(),
		"targets": allies + others,
	}


func _affectedUnits(sim, model: Dictionary) -> Array:
	var units: Array = []
	for cellValue in model.get("affected_cells", []):
		var cell: Vector2i = cellValue
		if not sim.state.containsCell(cell):
			continue
		var occupant := int(sim.state.board.at(cell))
		if occupant != 0 and not units.has(occupant):
			units.append(occupant)
	return units


func _spell(actor, model: Dictionary):
	var setIndex := int(model.get("spell_set_index", -1))
	var spellIndex := int(model.get("spell_index", -1))
	if setIndex < 0 or setIndex >= actor.spellSets.size():
		return null
	var spells: Array = actor.spellSets[setIndex]
	if spellIndex < 0 or spellIndex >= spells.size():
		return null
	return spells[spellIndex]
