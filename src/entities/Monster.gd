class_name Monster

const MonsterStatCalculatorScript = preload("res://src/battle_sim/MonsterStatCalculator.gd")

var uniqueID: int
var name: String = "Dump"

var hitpoints: int = 1
var max_hitpoints: int = 1
var move: int = 1
var atk: int = 1
var def: int = 1
var speed: int = 1
var luck: int = 0
var level: int = 1
var jump: int = 1
var base_hitpoints: int = 1
var base_atk: int = 1
var base_def: int = 1
var hp_growth: int = 0
var atk_growth: int = 0
var def_growth: int = 0

var team: int
var position: Vector2i
var spellSets = []
var elements: Array = []  # Array of String
var race: String = "none"
var family: String = "none"
var species: String = "none"
var ascends_from: String = ""

var passives: Array = []  # Array of PassiveSkill instances
var brain  # EntityBrain instance — assigned by BattleSimulator

var spell_cooldowns: Dictionary = {} # Maps spell name (String) to remaining turns (int)
var resonance_bars: Dictionary = {} # element -> charge from 0 through 3
static func get_or_default(dict: Dictionary, key: String, default_value = 1):
	return dict[key] if dict.has(key) else default_value

func _init(parameterDictionary, _uniqueID) -> void:

	uniqueID = _uniqueID

	name = get_or_default(parameterDictionary, "NAME", "Dump")
	level = maxi(1, int(get_or_default(parameterDictionary, "LEVEL", 1)))
	jump = maxi(0, int(get_or_default(parameterDictionary, "JUMP", 1)))
	base_hitpoints = int(get_or_default(parameterDictionary, "BASE_HP", get_or_default(parameterDictionary, "HP", 1)))
	base_atk = int(get_or_default(parameterDictionary, "BASE_ATK", get_or_default(parameterDictionary, "ATK", 1)))
	base_def = int(get_or_default(parameterDictionary, "BASE_DEF", get_or_default(parameterDictionary, "DEF", 1)))
	hp_growth = maxi(0, int(get_or_default(parameterDictionary, "HP_GROWTH", 0)))
	atk_growth = maxi(0, int(get_or_default(parameterDictionary, "ATK_GROWTH", 0)))
	def_growth = maxi(0, int(get_or_default(parameterDictionary, "DEF_GROWTH", 0)))
	var derivedStats = MonsterStatCalculatorScript.deriveFromReference(parameterDictionary, level)
	hitpoints = derivedStats["hp"]
	max_hitpoints = hitpoints
	move = get_or_default(parameterDictionary, "MOVE", 1)
	atk = derivedStats["atk"]
	def = derivedStats["def"]
	speed = get_or_default(parameterDictionary, "SPD", 1)
	luck = maxi(0, int(get_or_default(parameterDictionary, "LUCK", 0)))
	elements = get_or_default(parameterDictionary, "ELEMENTS", [])
	race = get_or_default(parameterDictionary, "RACE", "none")
	family = get_or_default(parameterDictionary, "FAMILY", "none")
	species = get_or_default(parameterDictionary, "SPECIES", name)
	ascends_from = get_or_default(parameterDictionary, "ASCENDS_FROM", "")

	for element in elements:
		resonance_bars[str(element)] = 0

	var refSpellSetsList = get_or_default(parameterDictionary, "SPELLS", [])

	for refSpellSet in refSpellSetsList:
		var newSpellSet = []
		for spellName in refSpellSet:
			var newSpell = SpellFactory.createSpell(spellName)
			newSpellSet.append(newSpell)
		spellSets.append(newSpellSet)

	# Load passive skills
	var refPassivesList = get_or_default(parameterDictionary, "PASSIVES", [])
	for passiveName in refPassivesList:
		var newPassive = PassiveSkillFactory.createPassive(passiveName)
		if newPassive != null:
			passives.append(newPassive)

	pass

func _to_string():
	return name

func setPosition(newPosition: Vector2i):
	position = newPosition
	pass


func is_alive() -> bool:
	return hitpoints > 0


func take_damage(damage: int) -> int:
	var old = hitpoints
	hitpoints = max(0, hitpoints - damage)
	return old - hitpoints

func heal(amount: int) -> int:
	var old = hitpoints
	hitpoints = min(max_hitpoints, hitpoints + amount)
	return hitpoints - old

func can_cast(spell: Spell) -> bool:
	if spell_cooldowns.has(spell.name) and spell_cooldowns[spell.name] > 0:
		return false

	var required_elements = {}
	if spell.element != "none":
		required_elements[spell.element] = true
	for line in spell.damage_lines:
		if line.has("element") and line["element"] != "none":
			required_elements[line["element"]] = true

	for req in required_elements.keys():
		if not elements.has(req):
			return false
	if spell.sequence_level == 4:
		return get_resonance(spell.resonance_element) == 3
	return true


func get_critical_chance() -> float:
	return clampf(float(luck) * 0.01, 0.0, 0.15)

func tick_cooldowns() -> void:
	for spell_name in spell_cooldowns.keys():
		if spell_cooldowns[spell_name] > 0:
			spell_cooldowns[spell_name] -= 1

func record_cast(spell: Spell) -> void:
	if spell.cooldown > 0:
		spell_cooldowns[spell.name] = spell.cooldown
	if spell.sequence_level <= 0 or spell.resonance_element == "none":
		return
	var current = get_resonance(spell.resonance_element)
	if spell.sequence_level == 4:
		resonance_bars[spell.resonance_element] = 0
	elif spell.sequence_level == current + 1:
		resonance_bars[spell.resonance_element] = mini(3, current + 1)


func get_resonance(element: String) -> int:
	return clampi(int(resonance_bars.get(element, 0)), 0, 3)


func would_advance_resonance(spell: Spell) -> bool:
	return (
		spell.sequence_level >= 1
		and spell.sequence_level <= 3
		and spell.sequence_level == get_resonance(spell.resonance_element) + 1
	)


func get_resonance_bonus_percent() -> int:
	var highest_bar = 0
	for element in resonance_bars:
		highest_bar = maxi(highest_bar, get_resonance(element))
	return highest_bar * 10


func get_effective_atk() -> int:
	return _apply_resonance_bonus(atk)


func get_effective_def() -> int:
	return _apply_resonance_bonus(def)


func lose_one_resonance_bar() -> Dictionary:
	var selected_element = ""
	var selected_charge = 0
	var sorted_elements: Array = resonance_bars.keys()
	sorted_elements.sort()
	for element in sorted_elements:
		var charge = get_resonance(str(element))
		if charge > selected_charge:
			selected_element = str(element)
			selected_charge = charge
	if selected_element.is_empty():
		return {}
	resonance_bars[selected_element] = selected_charge - 1
	return {
		"element": selected_element,
		"old_charge": selected_charge,
		"new_charge": selected_charge - 1
	}


func _apply_resonance_bonus(value: int) -> int:
	return int(round(float(value) * (1.0 + float(get_resonance_bonus_percent()) / 100.0)))

func serialize() -> Dictionary:
	var serializedSpellSets = []
	for spellSet in spellSets:
		var serializedSpellSet = []
		for spell in spellSet:
			serializedSpellSet.append(spell.name)
		serializedSpellSets.append(serializedSpellSet)

	var serializedPassives = []
	for passive in passives:
		serializedPassives.append(passive.name)

	return {
		"uniqueID": uniqueID,
		"name": name,
		"team": team,
		"position": {"x": position.x, "y": position.y},
		"hitpoints": hitpoints,
		"max_hitpoints": max_hitpoints,
		"move": move,
		"atk": atk,
		"def": def,
		"speed": speed,
		"luck": luck,
		"level": level,
		"jump": jump,
		"base_hitpoints": base_hitpoints,
		"base_atk": base_atk,
		"base_def": base_def,
		"hp_growth": hp_growth,
		"atk_growth": atk_growth,
		"def_growth": def_growth,
		"elements": elements.duplicate(),
		"race": race,
		"family": family,
		"species": species,
		"ascendsFrom": ascends_from,

		"resonanceBars": resonance_bars.duplicate(true),
		"spellSets": serializedSpellSets,
		"spellCooldowns": spell_cooldowns.duplicate(true),
		"passives": serializedPassives,
		"brainClass": brain.get_script().resource_path.get_file().get_basename() if brain != null else ""
	}
