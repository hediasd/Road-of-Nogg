## What the hex HUD is allowed to know about one unit, as plain data.
##
## READ, NEVER WRITTEN. This is the one place the inspection surfaces reach into `BattleState`;
## the readout, the status sheet and the explanation box render the dictionaries it returns and
## never see a `Monster`. That keeps every control testable without a battle, and keeps the
## question "could the HUD have changed the battle" answerable by reading one file.
##
## THE WORDS ARE MECHANICAL. Effect and spell descriptions are built from the fields the
## simulator actually reads -- `damagePerTurn`, `damage_multiplier`, `atk_bonus` and the like --
## rather than written as flavour, so a description can never claim a rule the battle does not
## apply. An effect the simulator gives no readable field to says only whether it helps or harms.

class_name HexUnitFacts
extends RefCounted

const ElementReferencesScript = preload("res://src/factories/ElementReferences.gd")
const BattleMeshFactoryScript = preload("res://src/presentation/BattleMeshFactory.gd")

## Equipment is not a battle rule yet. The sheet shows this many empty slots so the layout is
## already the one real equipment will fill, without implying any item exists.
const EQUIPMENT_SLOTS := 3

## Stat bonus keys the simulator sums from effects, and the label each reads under.
const EFFECT_BONUS_LABELS := {
	"atk_bonus": "ATK", "def_bonus": "DEF", "spd_bonus": "SPD", "move_bonus": "MOV",
}


## Everything the readout and the sheet show, or an empty dictionary when the unit is gone -- which
## is how a stale selection is noticed.
##
## `display` is the adapter's displayed-state reader. HP, effects and removal are read from what the
## SCREEN has shown, because the simulation runs ahead of playback: without it a readout drops HP
## before the blow that took it has landed. Everything else has no displayed counterpart and is read
## live from state.
static func build(sim: BattleSimulator, monsterID: int, display = null) -> Dictionary:
	if sim == null or sim.state == null:
		return {}
	var monster = sim.state.getMonster(monsterID)
	if monster == null:
		return {}
	if display != null:
		if not str(display.displayedRemovalReason(monsterID)).is_empty():
			return {}
	elif not monster.is_alive():
		return {}

	var elements: Array = []
	for value in monster.elements:
		elements.append(elementFacts(str(value)))

	var hitpoints := int(monster.hitpoints)
	var effectRows: Array = sim.state.getActiveEffects(monsterID)
	if display != null:
		var shownHP := int(display.displayedHitpoints(monsterID))
		if shownHP >= 0:
			hitpoints = shownHP
		effectRows = display.displayedEffects(monsterID)
	var effects: Array = []
	for effect in effectRows:
		if effect is Dictionary:
			effects.append(effectFacts(effect))

	var spells: Array = []
	for setIndex in range(monster.spellSets.size()):
		for spellIndex in range(monster.spellSets[setIndex].size()):
			var spell = monster.spellSets[setIndex][spellIndex]
			spells.append({
				"name": str(spell.name),
				"range": int(spell.range),
				"cooldown_left": int(monster.spell_cooldowns.get(spell.name, 0)),
				"text": spellSummary(spell),
			})

	var passives: Array = []
	for passive in monster.passives:
		if passive == null:
			continue
		passives.append({"name": str(passive.name), "text": passiveSummary(passive)})

	var equipment: Array = []
	for slot in range(EQUIPMENT_SLOTS):
		equipment.append({"slot": slot, "item": ""})

	var party = sim.state.partyForMember(monsterID)

	return {
		"id": monsterID,
		"name": str(monster.name),
		"level": int(monster.level),
		"hp": hitpoints,
		"max_hp": maxi(1, int(monster.max_hitpoints)),
		"team": int(monster.team),
		"elements": elements,
		"race": str(monster.race),
		"family": str(monster.family),
		"species": str(monster.species),
		"stats": {
			"ATK": int(monster.get_effective_atk()),
			"DEF": int(monster.get_effective_def()),
			"SPD": int(monster.speed),
			"MOV": int(monster.move),
			"JMP": int(monster.jump),
			"LUK": int(monster.luck),
		},
		"effects": StatusEffectOrder.sorted(effects),
		"spells": spells,
		"passives": passives,
		"equipment": equipment,
		"commander": party != null and int(party.commanderID) == monsterID,
	}


static func elementFacts(element: String) -> Dictionary:
	return {
		"name": element,
		"code": ElementReferencesScript.code(element) if element != "" else "??",
		"color": BattleMeshFactoryScript.elementColor(element),
	}


## One active effect: its display name, the turns left, whether it harms, and a sentence built from
## what the simulator will actually do with it.
static func effectFacts(effect: Dictionary) -> Dictionary:
	var effectName := str(effect.get("name", ""))
	var turns := int(effect.get("remainingTurns", 0))
	var negative := bool(effect.get("negative", false)) or _knownNegative(effectName)
	var parts: Array[String] = []

	var perTurn := int(effect.get("damagePerTurn", 0))
	if perTurn > 0:
		parts.append("Loses %d HP each turn." % perTurn)
	if effectName == "petrify":
		parts.append("Cannot act.")
	var multiplier := float(effect.get("damage_multiplier", 1.0))
	if not is_equal_approx(multiplier, 1.0):
		if effectName == "guard":
			parts.append("Next hit taken deals x%s damage." % _trimFloat(multiplier))
		elif effectName == "focus":
			parts.append("Next damage dealt is x%s." % _trimFloat(multiplier))
		else:
			parts.append("Damage x%s." % _trimFloat(multiplier))
	for key in EFFECT_BONUS_LABELS:
		var bonus := int(effect.get(key, 0))
		if bonus != 0:
			parts.append("%s %s%d." % [EFFECT_BONUS_LABELS[key], "+" if bonus > 0 else "", bonus])
	if parts.is_empty():
		parts.append("A harmful effect." if negative else "A helpful effect.")
	var source := str(effect.get("sourceSpellName", ""))
	if not source.is_empty():
		parts.append("From %s." % source)

	return {
		"name": effectName,
		"label": displayName(effectName),
		"turns": turns,
		"negative": negative,
		"text": " ".join(parts),
		# Handed back untouched so `StatusBadgeRow` can draw the same effect it always has.
		"raw": effect,
	}


## "spd_debuff" -> "Spd debuff". Mechanical on purpose: naming effects is a content decision.
static func displayName(effectName: String) -> String:
	var spaced := effectName.replace("_", " ").strip_edges()
	if spaced.is_empty():
		return "?"
	return spaced.substr(0, 1).to_upper() + spaced.substr(1)


static func spellSummary(spell) -> String:
	var parts: Array[String] = []
	var element := str(spell.element)
	if element != "none" and element != "":
		parts.append(displayName(element) + ".")
	parts.append("Range %d." % int(spell.range))
	if int(spell.radius) > 0:
		parts.append("Radius %d." % int(spell.radius))
	if bool(spell.heals):
		parts.append("Heals.")
	elif int(spell.damage) > 0:
		parts.append("Power %d." % int(spell.damage))
	if str(spell.inflicts_status) != "":
		parts.append("Inflicts %s." % displayName(str(spell.inflicts_status)).to_lower())
	if str(spell.removes_status) != "":
		parts.append("Cures %s." % displayName(str(spell.removes_status)).to_lower())
	if int(spell.cooldown) > 0:
		parts.append("Cooldown %d." % int(spell.cooldown))
	return " ".join(parts)


static func passiveSummary(passive) -> String:
	var trigger := displayName(str(passive.trigger).to_lower())
	var kind := displayName(str(passive.effect_type))
	if trigger == "?" and kind == "?":
		return ""
	return "%s: %s." % [trigger, kind.to_lower()]


static func _knownNegative(effectName: String) -> bool:
	return effectName in ["burn", "poison", "petrify", "chill", "spd_debuff"]


static func _trimFloat(value: float) -> String:
	var text := "%.2f" % value
	while text.ends_with("0"):
		text = text.substr(0, text.length() - 1)
	if text.ends_with("."):
		text = text.substr(0, text.length() - 1)
	return text


## Effect ordering the badge row already uses, applied to facts rather than raw effects, so the
## readout's list and the icons over the unit agree about what comes first.
class StatusEffectOrder:
	const StatusEffectIconsScript = preload("res://src/presentation/StatusEffectIcons.gd")

	static func sorted(facts: Array) -> Array:
		var raws: Array = []
		for fact in facts:
			raws.append(fact["raw"])
		var order: Array = StatusEffectIconsScript.sorted_effects(raws)
		var result: Array = []
		for raw in order:
			for fact in facts:
				if is_same(fact["raw"], raw) and not result.has(fact):
					result.append(fact)
					break
		return result
