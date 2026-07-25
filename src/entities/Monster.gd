class_name Monster

var uniqueID: int
var name: String = "Dump"

var hitpoints: int = 1
var max_hitpoints: int = 1
var move: int = 1
var atk: int = 1
var def: int = 1
var speed: int = 1

var team: int
var position: Vector2i
var spellSets = []
var elements: Array = []  # Array of String
var race: String = "none"
var passives: Array = []  # Array of PassiveSkill instances
var brain  # EntityBrain instance — assigned by BattleSimulator

var spell_cooldowns: Dictionary = {} # Maps spell name (String) to remaining turns (int)
static func get_or_default(dict: Dictionary, key: String, default_value = 1):
	return dict[key] if dict.has(key) else default_value

func _init(parameterDictionary, _uniqueID) -> void:

	uniqueID = _uniqueID

	name = get_or_default(parameterDictionary, "NAME", "Dump")
	hitpoints = get_or_default(parameterDictionary, "HP", 1)
	max_hitpoints = hitpoints
	move = get_or_default(parameterDictionary, "MOVE", 1)
	atk = get_or_default(parameterDictionary, "ATK", 1)
	def = get_or_default(parameterDictionary, "DEF", 1)
	speed = get_or_default(parameterDictionary, "SPD", 1)
	elements = get_or_default(parameterDictionary, "ELEMENTS", [])
	race = get_or_default(parameterDictionary, "RACE", "none")

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
	return true

func tick_cooldowns() -> void:
	for spell_name in spell_cooldowns.keys():
		if spell_cooldowns[spell_name] > 0:
			spell_cooldowns[spell_name] -= 1

func record_cast(spell: Spell) -> void:
	if spell.cooldown > 0:
		spell_cooldowns[spell.name] = spell.cooldown

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
		"elements": elements.duplicate(),
		"race": race,
		"spellSets": serializedSpellSets,
		"spellCooldowns": spell_cooldowns.duplicate(true),
		"passives": serializedPassives,
		"brainClass": brain.get_script().resource_path.get_file().get_basename() if brain != null else ""
	}
