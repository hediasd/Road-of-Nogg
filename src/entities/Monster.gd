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
var brain  # EntityBrain instance — assigned by BattleSimulator

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

	var refSpellSetsList = get_or_default(parameterDictionary, "SPELLS", [])

	for refSpellSet in refSpellSetsList:
		var newSpellSet = []
		for spellName in refSpellSet:
			var newSpell = SpellFactory.createSpell(spellName)
			newSpellSet.append(newSpell)
		spellSets.append(newSpellSet)

	#if(uniqueID == 100):
	#	for spellSet in spellSets:
	#		for spell in spellSet:
	print(spellSets)

	pass

func _to_string():
	return name

func setPosition(newPosition: Vector2i):
	position = newPosition
	pass


func is_alive() -> bool:
	return hitpoints > 0


func take_damage(amount: int) -> int:
	## Applies damage and returns actual damage dealt.
	var actualDamage = min(amount, hitpoints)
	hitpoints -= actualDamage
	return actualDamage


func heal(amount: int) -> int:
	## Restores HP and returns actual HP restored (capped at max).
	var actualHeal = min(amount, max_hitpoints - hitpoints)
	hitpoints += actualHeal
	return actualHeal
