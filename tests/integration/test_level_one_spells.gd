## Ported from run_level_one_check.gd. Exercises the self-centred Level 1
## spell vocabulary: guard/focus consumption, self-radius healing and status
## AOE, and cooldown reduction.
extends "res://tests/TestCase.gd"


func describe() -> String:
	return "Level 1 self-cast spells apply their declared effects correctly"


func run() -> void:
	var sim = makeSimulator(991, Vector2i(5, 5))
	var fire = sim.spawnMonster("Fireblood Lizard", 1, Vector2i(1, 1))
	var dark = sim.spawnMonster("Grid Demon", 2, Vector2i(2, 1))
	_assign_spell(dark, "Anticipate")
	var baseline = sim.combatResolver.calculateBasicDamage(fire, dark)
	if not sim.combatResolver.executeCastSpell(dark.uniqueID, dark.uniqueID, 0, 0)["success"]:
		fail("Anticipate could not self-cast")
		return
	var guarded = sim.combatResolver.executeBasicAttack(fire.uniqueID, dark.uniqueID)
	if guarded["damage"] != int(round(float(baseline) * 0.75)) or sim.state.hasEffect(dark.uniqueID, "guard"):
		fail("Guard did not reduce exactly one incoming hit by 25 percent")
		return

	_assign_spell(fire, "Predict")
	baseline = sim.combatResolver.calculateBasicDamage(fire, dark)
	if not sim.combatResolver.executeCastSpell(fire.uniqueID, fire.uniqueID, 0, 0)["success"]:
		fail("Predict could not self-cast")
		return
	var focused = sim.combatResolver.executeBasicAttack(fire.uniqueID, dark.uniqueID)
	if focused["damage"] != int(round(float(baseline) * 1.25)) or sim.state.hasEffect(fire.uniqueID, "focus"):
		fail("Focus did not increase exactly one outgoing hit by 25 percent")
		return

	var wood = sim.spawnMonster("Walker of the Woods", 1, Vector2i(1, 3))
	var ally = sim.spawnMonster("Lilypad Tender", 1, Vector2i(2, 3))
	wood.hitpoints -= 4
	ally.hitpoints -= 4
	_assign_spell(wood, "Gather")
	if not sim.combatResolver.executeCastSpell(wood.uniqueID, wood.uniqueID, 0, 0)["success"]:
		fail("Gather could not self-cast")
		return
	if wood.hitpoints != wood.max_hitpoints - 2 or ally.hitpoints != ally.max_hitpoints - 2:
		fail("Gather did not heal allies in its self-centred radius")
		return

	var ice = sim.spawnMonster("Polar Weather Wizard", 1, Vector2i(3, 3))
	var chillTarget = sim.spawnMonster("Night Hunter Panther", 2, Vector2i(3, 2))
	_assign_spell(ice, "Chill")
	if not sim.combatResolver.executeCastSpell(ice.uniqueID, ice.uniqueID, 0, 0)["success"]:
		fail("Chill could not self-cast")
		return
	if not sim.state.hasEffect(chillTarget.uniqueID, "chill"):
		fail("Chill did not affect an enemy in its self-centred radius")
		return

	var steel = sim.spawnMonster("Kickatoo", 1, Vector2i(4, 4))
	steel.spell_cooldowns["Ages Ago"] = 3
	_assign_spell(steel, "Iterate")
	if not sim.combatResolver.executeCastSpell(steel.uniqueID, steel.uniqueID, 0, 0)["success"]:
		fail("Iterate could not self-cast")
		return
	if steel.spell_cooldowns["Ages Ago"] != 2:
		fail("Iterate did not reduce cooldowns by one")
		return


func _assign_spell(monster: Monster, spell_name: String) -> void:
	monster.spellSets = [[SpellFactory.createSpell(spell_name)]]
