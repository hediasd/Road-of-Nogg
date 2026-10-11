## The damage tags an aim draws over the units it touches: one model per unit, for
## `SideTurnScreenCues.showForecasts`.
##
## Built in the battle layer because it needs the adapter's forecasts and the simulator's resolvers;
## the tags in `ui/` only draw what this returns. Every number is a forecast, never a guess:
##
## - damage and crit from `forecastAttack` / `forecastSpell`, the same numbers the attack resolver
##   will use;
## - healing from `CombatResolver.calculateHeal`, which the damage forecast cannot price;
## - an attack touches its target; a spell touches every unit on its resolved cells, allies included.
##
## A spell that neither damages nor heals draws no tag: the prompt line says what it does. An aim the
## rules refuse still gets its tags, marked `legal: false` so the tag dims.

extends RefCounted

const HexBattleMemberInputScript = preload("res://battle/HexBattleMemberInput.gd")

## Above the unit's cell, at roughly head height, where the tag's bottom edge sits.
const HEAD_HEIGHT := 1.2


static func build(sim: BattleSimulator, adapter, actorID: int, model: Dictionary) -> Array:
	var tags: Array = []
	if sim == null or adapter == null or model.is_empty():
		return tags
	var actor = sim.state.getMonster(actorID)
	if actor == null:
		return tags
	var legal := bool(model.get("legal", false))
	if str(model.get("kind", "")) == HexBattleMemberInputScript.SPELL_PREFIX:
		var spell = _spell(actor, model)
		if spell == null:
			return tags
		var heals := bool(spell.heals) or int(spell.heal_amount) > 0
		var touched := _affectedUnits(sim, model)
		# The aim model resolves no cells for a spell whose damage forecast it withholds (a heal),
		# so the unit under the cursor stands in for them.
		var aimed := int(model.get("target_id", -1))
		if touched.is_empty() and aimed != -1 and sim.state.getMonster(aimed) != null:
			touched.append(aimed)
		for unitID in touched:
			var unit = sim.state.getMonster(unitID)
			var cell: Vector2i = sim.state.getMonsterPosition(unitID)
			var tag := _tag(sim, adapter, unitID, unit, legal)
			if heals:
				var amount := int(sim.combatResolver.calculateHeal(actor, spell))
				if amount <= 0:
					continue
				tag["heal"] = amount
				tag["hp_after"] = mini(int(tag["max_hp"]), int(tag["hp"]) + amount)
			else:
				var forecast: Dictionary = adapter.forecastSpell(actorID,
					int(model.get("spell_set_index", 0)), int(model.get("spell_index", 0)), cell)
				if not bool(forecast.get("available", false)):
					continue
				_applyForecast(tag, forecast)
			tags.append(tag)
		return tags
	if str(model.get("kind", "")) != HexBattleMemberInputScript.ATTACK_COMMAND:
		return tags
	var targetID := int(model.get("target_id", -1))
	var target = sim.state.getMonster(targetID)
	if target == null or not target.is_alive():
		return tags
	var attack: Dictionary = model.get("forecast", {})
	if attack.is_empty():
		attack = adapter.forecastAttack(actorID, sim.state.getMonsterPosition(targetID))
	if not bool(attack.get("available", false)):
		return tags
	var tag := _tag(sim, adapter, targetID, target, legal)
	_applyForecast(tag, attack)
	tags.append(tag)
	return tags


static func _tag(sim, adapter, unitID: int, unit, legal: bool) -> Dictionary:
	var hp := int(unit.hitpoints)
	return {
		"monster_id": unitID,
		"world_anchor": adapter.worldPositionOf(sim.state.getMonsterPosition(unitID)) + Vector3.UP * HEAD_HEIGHT,
		"hp": hp,
		"max_hp": maxi(1, int(unit.max_hitpoints)),
		"hp_after": hp,
		"damage": 0,
		"crit_damage": 0,
		"crit_chance": 0.0,
		"lethal": false,
		"possibly_lethal": false,
		"heal": 0,
		"legal": legal,
	}


static func _applyForecast(tag: Dictionary, forecast: Dictionary) -> void:
	tag["damage"] = int(forecast.get("minimum", 0))
	tag["crit_damage"] = int(forecast.get("maximum", 0))
	tag["crit_chance"] = float(forecast.get("critical_chance", 0.0))
	tag["lethal"] = bool(forecast.get("lethal", false))
	tag["possibly_lethal"] = bool(forecast.get("possibly_lethal", false))
	tag["hp_after"] = maxi(0, int(tag["hp"]) - int(tag["damage"]))


static func _affectedUnits(sim, model: Dictionary) -> Array[int]:
	var units: Array[int] = []
	for cellValue in model.get("affected_cells", []):
		var cell: Vector2i = cellValue
		if not sim.state.containsCell(cell):
			continue
		var occupant := int(sim.state.board.at(cell))
		if occupant != 0 and not units.has(occupant):
			var unit = sim.state.getMonster(occupant)
			if unit != null and unit.is_alive():
				units.append(occupant)
	return units


static func _spell(actor, model: Dictionary):
	var setIndex := int(model.get("spell_set_index", -1))
	var spellIndex := int(model.get("spell_index", -1))
	if setIndex < 0 or setIndex >= actor.spellSets.size():
		return null
	var spells: Array = actor.spellSets[setIndex]
	if spellIndex < 0 or spellIndex >= spells.size():
		return null
	return spells[spellIndex]
