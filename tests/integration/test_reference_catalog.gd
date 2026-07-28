## Ported from run_reference_catalog_check.gd. Validates every spell, passive,
## race, monster, map, and preset reference for internal consistency. See
## AUDIT_REMEDIATION_PLAN.md P2-3 for the plan to share this logic with
## MonsterReferences.validateAll() instead of duplicating it.
extends "res://tests/TestCase.gd"

const ElementReferencesScript = preload("res://src/factories/ElementReferences.gd")
const MapFactoryScript = preload("res://src/factories/MapFactory.gd")
const MapReferencesScript = preload("res://src/factories/MapReferences.gd")
const MonsterReferencesScript = preload("res://src/factories/MonsterReferences.gd")
const PassiveSkillReferencesScript = preload("res://src/factories/PassiveSkillReferences.gd")
const RaceReferencesScript = preload("res://src/factories/RaceReferences.gd")
const SpellReferencesScript = preload("res://src/factories/SpellReferences.gd")
const BattleSetupPresetsScript = preload("res://src/factories/BattleSetupPresets.gd")
const StatusEffectReferencesScript = preload("res://src/factories/StatusEffectReferences.gd")
const CatalogValidatorScript = preload("res://src/factories/CatalogValidator.gd")

## Meta-effect names intercepted by SpellEffectResolver._applyDeclaredEffects()
## before an actual status effect is ever created (they trigger cleanse/
## cooldown-reduction side logic instead), so they are not, and never will be,
## entries in StatusEffectReferences.
const META_EFFECT_NAMES := ["cleanse", "cooldown_reduction"]

const PASSIVE_IMPLEMENTATIONS := {
	"ON_DAMAGE_TAKEN": ["damage_reduction"],
	"ON_DEATH": ["aoe_damage"],
	"ON_TARGETED": ["retaliate_damage"]
}

var _warningCount: int = 0


func describe() -> String:
	return "every spell/passive/race/monster/map/preset reference is internally consistent (warnings=%d)" % _warningCount


func run() -> void:
	var errors: Array[String] = []
	var warnings: Array[String] = []
	var spells: Dictionary = _named_catalog(SpellReferencesScript.list, "spell", errors)
	var passives: Dictionary = _named_catalog(PassiveSkillReferencesScript.list, "passive", errors)
	var races: Dictionary = _named_catalog(RaceReferencesScript.list, "race", errors)
	var monsters: Dictionary = _named_catalog(MonsterReferencesScript.list, "monster", errors)
	_named_catalog(MapReferencesScript.list, "map", errors)

	var spell_usage: Dictionary = {}
	var passive_usage: Dictionary = {}
	var race_usage: Dictionary = {}
	var element_usage: Dictionary = {}
	_validate_spells(spells, element_usage, errors)
	_validate_passives(passives, element_usage, errors)
	_validate_races(races, errors)

	## Monster-reference validation (race/elements/spell-sets/spell-element
	## compatibility/ASCENDS_FROM) is owned by CatalogValidator so this check
	## and MonsterReferences.validateAll() cannot disagree — see P2-3.
	var monsterValidation: Dictionary = CatalogValidatorScript.validateMonsters(MonsterReferencesScript.list)
	errors.append_array(monsterValidation["errors"])
	_track_monster_usage(monsters, spell_usage, passive_usage, race_usage, element_usage)

	_validate_maps(errors)
	_validate_presets(monsters, errors)
	_warn_unused(spells, passives, races, spell_usage, passive_usage, race_usage, element_usage, warnings)

	## Warnings are informational and stable run to run (they track authoring
	## backlog, not regressions), so listing all of them on every invocation is
	## pure noise in hook output and agent context. The count travels in
	## describe(); pass `verbose` to see the list.
	_warningCount = warnings.size()
	if "verbose" in OS.get_cmdline_user_args():
		for warning in warnings:
			print("REFERENCE_CATALOG_WARNING: %s" % warning)

	for issue in errors:
		fail(issue)


func _named_catalog(entries: Array, label: String, errors: Array[String]) -> Dictionary:
	var result: Dictionary = {}
	for entry in entries:
		if not entry is Dictionary:
			errors.append("%s catalog contains a non-dictionary entry." % label)
			continue
		var name := str(entry.get("NAME", ""))
		if name.is_empty():
			errors.append("%s catalog contains an entry without NAME." % label)
		elif result.has(name):
			errors.append("duplicate %s: %s." % [label, name])
		else:
			result[name] = entry
	return result


func _validate_spells(spells: Dictionary, element_usage: Dictionary, errors: Array[String]) -> void:
	for name in spells:
		var spell: Dictionary = spells[name]
		_validate_element(str(spell.get("ELEMENT", "none")), "%s primary element" % name, errors)
		_validate_spell_schema(name, spell, errors)
		for line in spell.get("DAMAGE_LINES", []):
			if not line is Dictionary:
				errors.append("spell %s has a non-dictionary damage line." % name)
				continue
			_validate_element(str(line.get("element", "none")), "%s damage line" % name, errors)
			_element_used(str(line.get("element", "none")), element_usage)
		_element_used(str(spell.get("ELEMENT", "none")), element_usage)


func _validate_spell_schema(name: String, spell: Dictionary, errors: Array[String]) -> void:
	## The tier contract from docs/GAME_DESIGN.md, enforced mechanically so
	## tiers 2-4 cannot drift the way Level 1's convention never could.
	var tier = int(spell.get("SEQUENCE_LEVEL", 0))
	if tier == 1:
		if spell.get("TARGET_TYPE", "single") != "self" or int(spell.get("RANGE", -1)) != 0:
			errors.append("Level 1 spell %s must target self at range 0." % name)
		if int(spell.get("SELF_RADIUS", 0)) > 0 and spell.get("TARGET_TYPE", "") != "self":
			errors.append("self-centred AOE spell %s must target self." % name)
	elif tier == 2:
		if spell.get("TARGET_TYPE", "single") != "single":
			errors.append("Level 2 spell %s must be single-target." % name)
		if int(spell.get("RANGE", 0)) < 1:
			errors.append("Level 2 spell %s must reach at least range 1." % name)
	elif tier == 3:
		if spell.get("TARGET_TYPE", "single") != "area":
			errors.append("Level 3 spell %s must be an area spell." % name)
		if int(spell.get("COOLDOWN", 0)) < 3:
			errors.append("Level 3 spell %s must carry a cooldown of at least 3." % name)
	elif tier == 4:
		if spell.get("TARGET_TYPE", "single") != "area":
			errors.append("Level 4 spell %s must be an area spell." % name)
		if int(spell.get("RADIUS", 0)) < 2:
			errors.append("Level 4 spell %s must have a radius of at least 2." % name)
		if int(spell.get("COOLDOWN", 0)) < 6:
			errors.append("Level 4 spell %s must carry a cooldown of at least 6." % name)
	for definition in spell.get("EFFECTS", []):
		if not definition is Dictionary:
			errors.append("spell %s has a non-dictionary effect." % name)
			continue
		var effect_name = str(definition.get("NAME", ""))
		if effect_name not in META_EFFECT_NAMES and not StatusEffectReferencesScript.hasReference(effect_name):
			errors.append("spell %s has unsupported effect %s." % [name, effect_name])
	var inflicts := str(spell.get("INFLICTS_STATUS", ""))
	if not inflicts.is_empty() and not StatusEffectReferencesScript.hasReference(inflicts):
		errors.append("spell %s inflicts unknown status %s." % [name, inflicts])
	var removes := str(spell.get("REMOVES_STATUS", ""))
	if not removes.is_empty() and not StatusEffectReferencesScript.hasReference(removes):
		errors.append("spell %s removes unknown status %s." % [name, removes])


func _validate_passives(passives: Dictionary, element_usage: Dictionary, errors: Array[String]) -> void:
	for name in passives:
		var passive: Dictionary = passives[name]
		var trigger := str(passive.get("TRIGGER", ""))
		var effect := str(passive.get("EFFECT_TYPE", ""))
		if not PASSIVE_IMPLEMENTATIONS.has(trigger) or not PASSIVE_IMPLEMENTATIONS[trigger].has(effect):
			errors.append("passive %s uses unimplemented %s/%s." % [name, trigger, effect])
		_validate_element(str(passive.get("ELEMENT", "none")), "%s passive element" % name, errors)
		_element_used(str(passive.get("ELEMENT", "none")), element_usage)


func _validate_races(races: Dictionary, errors: Array[String]) -> void:
	for name in races:
		var resistances = races[name].get("RESISTANCES", {})
		if not resistances is Dictionary:
			errors.append("race %s has non-dictionary RESISTANCES." % name)
			continue
		for element in resistances:
			_validate_element(str(element), "%s resistance" % name, errors)
			if element == "none" or float(resistances[element]) <= 0.0:
				errors.append("race %s has invalid %s resistance." % [name, element])


func _track_monster_usage(monsters: Dictionary, spell_usage: Dictionary, passive_usage: Dictionary, race_usage: Dictionary, element_usage: Dictionary) -> void:
	## Reporting-only: which catalog entries a monster references, for the
	## "unused X" warnings below. Whether those references are actually valid
	## is CatalogValidator's job, not this loop's.
	for name in monsters:
		var monster: Dictionary = monsters[name]
		race_usage[str(monster.get("RACE", ""))] = true
		for element in monster.get("ELEMENTS", []):
			_element_used(str(element), element_usage)
		for spell_set in monster.get("SPELLS", []):
			if not spell_set is Array:
				continue
			for spell_name in spell_set:
				spell_usage[spell_name] = true
		for passive_name in monster.get("PASSIVES", []):
			passive_usage[passive_name] = true


func _validate_maps(errors: Array[String]) -> void:
	for map_reference in MapReferencesScript.list:
		var validation: Dictionary = MapFactoryScript.validateReference(map_reference)
		if not validation.get("success", false):
			errors.append("map %s is invalid: %s." % [map_reference.get("NAME", ""), validation.get("reason", "unknown")])


func _validate_presets(monsters: Dictionary, errors: Array[String]) -> void:
	for team in [1, 2]:
		for monster_name in BattleSetupPresetsScript.getRoster(BattleSetupPresetsScript.PRESET_DEFAULT, team, 0):
			if not monsters.has(monster_name):
				errors.append("default setup references unknown monster %s." % monster_name)


func _warn_unused(spells: Dictionary, passives: Dictionary, races: Dictionary, spell_usage: Dictionary, passive_usage: Dictionary, race_usage: Dictionary, element_usage: Dictionary, warnings: Array[String]) -> void:
	for name in spells:
		if not spell_usage.has(name):
			warnings.append("unused spell %s." % name)
	for name in passives:
		if not passive_usage.has(name):
			warnings.append("unused passive %s." % name)
	for name in races:
		if name != "none" and not race_usage.has(name):
			warnings.append("unused race %s." % name)
	for element in ElementReferencesScript.STANDARD:
		if element != "none" and not element_usage.has(element):
			warnings.append("unused element %s." % element)


func _validate_element(element: String, context: String, errors: Array[String]) -> void:
	if not ElementReferencesScript.isValid(element):
		errors.append("%s references unknown element %s." % [context, element])


func _element_used(element: String, usage: Dictionary) -> void:
	if element != "none":
		usage[element] = true
