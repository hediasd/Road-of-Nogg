## What the docked card shows while the player aims: one target's matchup, or the list of units an
## area spell would hit.
##
## Built here, in the battle layer, because it needs the adapter's forecasts (the same numbers the
## in-world preview boxes print) and the simulator's resolvers; the card in `ui/` only draws the
## Dictionary this returns. Every number is a forecast or a rule lookup, never a guess:
##
## - damage and crit from `forecastAttack` / `forecastSpell`;
## - healing from `CombatResolver.calculateHeal`;
## - weakness and resistance from `RaceReferences.getDamageMultiplier`, the only source of them;
## - the threat line from `DangerQuery.reply`: the most that enemy could deal to the acting unit on
##   the tile it stands on, over one enemy turn. A bound for that one enemy, not a prediction.
##
## The threat query is the expensive part, so it is cached on (target, actor, tile, side turn).

extends RefCounted

const RaceReferencesScript = preload("res://content/RaceReferences.gd")
const DecisionContextScript = preload("res://ai/DecisionContext.gd")
const DangerQueryScript = preload("res://ai/DangerQuery.gd")
const HexUnitFactsScript = preload("res://ui/HexUnitFacts.gd")
const HexBattleHudScript = preload("res://battle/HexBattleHud.gd")
const HexBattleMemberInputScript = preload("res://battle/HexBattleMemberInput.gd")

const KIND_SINGLE := "single"
const KIND_AREA := "area"
const MATCHUP_WEAK := "weak"
const MATCHUP_RESIST := "resist"
const MATCHUP_NEUTRAL := "neutral"
const MATCHUP_NONE := "none"
## Race multipliers touch damage only, so a heal or a damage-free spell prints no matchup line.
const MATCHUP_QUIET := "quiet"
## Rows the area list has room for before it folds the rest into "+N more".
const AREA_ROWS := 4

var _threatCache: Dictionary = {}


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
		return _area(sim, adapter, actor, actorID, model, spell, affected, viewerPartyID)
	var targetID := int(model.get("target_id", -1))
	if targetID == -1 and affected.size() == 1:
		targetID = int(affected[0])
	var target = sim.state.getMonster(targetID)
	if target == null or not target.is_alive():
		return {}
	var result := _single(sim, adapter, actor, actorID, model, spell, target, targetID, viewerPartyID)
	return result


func _single(sim, adapter, actor, actorID: int, model: Dictionary, spell, target, targetID: int,
		viewerPartyID: int) -> Dictionary:
	var hp := int(target.hitpoints)
	var facts := {
		"kind": KIND_SINGLE,
		"action": str(spell.name) if spell != null else "Attack",
		"elements": _actionElements(spell),
		"target_id": targetID,
		"target_name": str(target.name),
		"target_level": int(target.level),
		"allegiance": HexUnitFactsScript.allegianceFor(sim, target, viewerPartyID),
		"commander": _isCommander(sim, targetID),
		"hp": hp,
		"max_hp": maxi(1, int(target.max_hitpoints)),
		"hp_after": hp,
		"heal": 0,
		"damage_min": 0,
		"damage_max": 0,
		"crit_chance": 0.0,
		"lethal": false,
		"possibly_lethal": false,
		"reactive": false,
		"effect_text": "",
		"legal": bool(model.get("legal", false)),
		"reason": HexBattleHudScript.reasonText(str(model.get("reason", ""))),
		"matchup": _matchup(target, spell),
		"threat": -1,
		"threat_lethal": false,
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
		facts["reactive"] = bool(forecast.get("reactive_risk", false))
		facts["hp_after"] = maxi(0, hp - int(facts["damage_min"]))
	elif spell != null and (bool(spell.heals) or int(spell.heal_amount) > 0):
		var amount := int(sim.combatResolver.calculateHeal(actor, spell))
		facts["heal"] = amount
		facts["hp_after"] = mini(int(facts["max_hp"]), hp + amount)
		facts["matchup"] = {"kind": MATCHUP_QUIET}
	elif spell != null:
		facts["effect_text"] = HexUnitFactsScript.spellSummary(spell)
		facts["matchup"] = {"kind": MATCHUP_QUIET}
	if int(target.team) != int(actor.team):
		var threat := _threat(sim, targetID, actorID)
		facts["threat"] = threat
		facts["threat_lethal"] = threat >= int(actor.hitpoints) and threat > 0
	return facts


func _area(sim, adapter, actor, actorID: int, model: Dictionary, spell, affected: Array,
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
			"matchup": _matchup(unit, spell),
		})
	# Allies first: friendly fire is the thing an area aim most needs to say.
	var allies := rows.filter(func(row: Dictionary) -> bool:
		return str(row["allegiance"]) == HexUnitFactsScript.ALLEGIANCE_ALLY)
	var others := rows.filter(func(row: Dictionary) -> bool:
		return str(row["allegiance"]) != HexUnitFactsScript.ALLEGIANCE_ALLY)
	return {
		"kind": KIND_AREA,
		"action": str(spell.name),
		"elements": _actionElements(spell),
		"legal": bool(model.get("legal", false)),
		"reason": HexBattleHudScript.reasonText(str(model.get("reason", ""))),
		"allies_hit": allies.size(),
		"targets": allies + others,
	}


## Weak, resisted or neutral for the action's elements against the target's race. A spell with
## several elements reads as weak if any element is, then resisted if any is. A basic attack has no
## element, so race does not touch it.
func _matchup(target, spell) -> Dictionary:
	var elements := _actionElements(spell)
	if elements.is_empty():
		return {"kind": MATCHUP_NONE, "element": "", "percent": 0}
	var weak := ""
	var resisted := ""
	for element in elements:
		var multiplier := float(RaceReferencesScript.getDamageMultiplier(str(target.race), element))
		if multiplier > 1.0 and weak.is_empty():
			weak = element
		elif multiplier < 1.0 and resisted.is_empty():
			resisted = element
	if not weak.is_empty():
		return {"kind": MATCHUP_WEAK, "element": weak, "percent": _percent(target, weak)}
	if not resisted.is_empty():
		return {"kind": MATCHUP_RESIST, "element": resisted, "percent": _percent(target, resisted)}
	return {"kind": MATCHUP_NEUTRAL, "element": elements[0], "percent": 0}


func _percent(target, element: String) -> int:
	return roundi((float(RaceReferencesScript.getDamageMultiplier(str(target.race), element)) - 1.0) * 100.0)


func _actionElements(spell) -> Array[String]:
	var elements: Array[String] = []
	if spell == null:
		return elements
	for element in spell.getElements():
		var name := str(element)
		if name != "none" and not name.is_empty() and not elements.has(name):
			elements.append(name)
	return elements


## The most `enemyID` could deal to the acting unit where it stands, over one enemy turn.
func _threat(sim, enemyID: int, actorID: int) -> int:
	var tile: Vector2i = sim.state.getMonsterPosition(actorID)
	var key := "%d|%d|%s|%d|%d" % [enemyID, actorID, str(tile), int(sim.state.sideTurnCount),
		int(sim.state.getMonster(actorID).hitpoints)]
	if _threatCache.has(key):
		return int(_threatCache[key])
	var context = DecisionContextScript.forSimulator(sim)
	var assessment = DangerQueryScript.reply(context, enemyID, tile)
	var value := int(assessment.value) if assessment != null else -1
	if _threatCache.size() > 64:
		_threatCache.clear()
	_threatCache[key] = value
	return value


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


func _isCommander(sim, monsterID: int) -> bool:
	var party = sim.state.partyForMember(monsterID)
	return party != null and int(party.commanderID) == monsterID
