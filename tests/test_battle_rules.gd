extends GutTest

var sim: BattleSimulator

func before_each():
	sim = BattleSimulator.new()
	sim.state.setup_board(Vector2i(10, 10))


func test_basic_attack_adjacency():
	var m1 = sim.spawnMonster("Envoy of Lightning", 1, Vector2i(1, 1))
	var m2 = sim.spawnMonster("Envoy of Lightning", 2, Vector2i(1, 3)) # Distance 2
	
	# Attack fails because it's out of range
	var result = sim.combatResolver.executeBasicAttack(m1.uniqueID, m2.uniqueID)
	assert_false(result["success"], "Attack should fail if distance is greater than 1")
	assert_eq(result["reason"], "out_of_range", "Failure reason should be out_of_range")
	
	# Move them closer
	sim.state.moveMonsterTo(m2.uniqueID, Vector2i(1, 2))
	var result_success = sim.combatResolver.executeBasicAttack(m1.uniqueID, m2.uniqueID)
	assert_true(result_success["success"], "Attack should succeed when adjacent")


func test_spell_friendly_fire():
	var m1 = sim.spawnMonster("Envoy of Lightning", 1, Vector2i(1, 1)) # Needs a healer
	var ally = sim.spawnMonster("Envoy of Lightning", 1, Vector2i(1, 2))
	var enemy = sim.spawnMonster("Envoy of Lightning", 2, Vector2i(1, 3))
	
	# We need to give them a heal spell and a damage spell explicitly if not present
	var heal_spell = Spell.new({})
	heal_spell.name = "Test Heal"
	heal_spell.heals = true
	heal_spell.range = 5
	heal_spell.targetType = "single"
	
	var damage_spell = Spell.new({})
	damage_spell.name = "Test Damage"
	damage_spell.heals = false
	damage_spell.range = 5
	damage_spell.targetType = "single"
	
	m1.spellSets = [[heal_spell, damage_spell]]
	
	var heal_targets = sim.combatResolver.getSpellTargets(m1.uniqueID, 0, 0)
	var damage_targets = sim.combatResolver.getSpellTargets(m1.uniqueID, 0, 1)
	
	assert_has(heal_targets, ally.uniqueID, "Heal spell should target ally")
	assert_does_not_have(heal_targets, enemy.uniqueID, "Heal spell should not target enemy")
	
	assert_has(damage_targets, enemy.uniqueID, "Damage spell should target enemy")
	assert_does_not_have(damage_targets, ally.uniqueID, "Damage spell should not target ally")


func test_line_of_sight():
	var m1 = sim.spawnMonster("Envoy of Lightning", 1, Vector2i(1, 1))
	var blocker = sim.spawnMonster("Envoy of Lightning", 2, Vector2i(1, 2))
	var target = sim.spawnMonster("Envoy of Lightning", 2, Vector2i(1, 3))
	
	var spell = Spell.new({})
	spell.name = "LoS Spell"
	spell.range = 5
	spell.bypass_los = false
	
	m1.spellSets = [[spell]]
	
	var targets = sim.combatResolver.getSpellTargets(m1.uniqueID, 0, 0)
	assert_does_not_have(targets, target.uniqueID, "Should not be able to target behind blocker without bypass_los")
	assert_has(targets, blocker.uniqueID, "Should be able to target the blocker")
	
	spell.bypass_los = true
	var bypass_targets = sim.combatResolver.getSpellTargets(m1.uniqueID, 0, 0)
	assert_has(bypass_targets, target.uniqueID, "Should target behind blocker with bypass_los")


func test_elemental_multipliers():
	var attacker = sim.spawnMonster("Envoy of Lightning", 1, Vector2i(1, 1))
	var target = sim.spawnMonster("Frostborn", 2, Vector2i(1, 2)) # Frostborn should have element weaknesses
	
	# Assuming RaceReferences is loaded properly and Frostborn is weak to fire
	var RaceReferences = preload("res://src/factories/RaceReferences.gd")
	var fire_multiplier = RaceReferences.getDamageMultiplier(target.race, "fire")
	
	var base_dmg = 10
	var no_element_dmg = sim.combatResolver.calculateSpellDamage(attacker, target, base_dmg, "none")
	var fire_element_dmg = sim.combatResolver.calculateSpellDamage(attacker, target, base_dmg, "fire")
	
	assert_true(fire_multiplier > 1.0, "Frostborn should be weak to fire")
	assert_true(fire_element_dmg > no_element_dmg, "Fire damage should be higher than non-elemental damage due to weakness")

func test_short_battle_no_loop():
	# Use Meadow which has real trees to test pathfinding loop avoidance
	sim.loadMap("Meadow")
	sim.spawnMonster("Envoy of Lightning", 1, Vector2i(2, 6))
	sim.spawnMonster("Gigasaurus", 1, Vector2i(1, 7))
	
	sim.spawnMonster("Smoke Cloud", 2, Vector2i(13, 0))
	sim.spawnMonster("Megidos", 2, Vector2i(14, 1))
	
	sim.setSeed(42)
	
	# Run 5 rounds max
	var winner = sim.runFullBattle(5)
	
	assert_true(sim.state.roundCount <= 6, "Battle should not exceed 5 rounds (+1 for final increment)")
	assert_true(sim.state.turnCount > 0, "At least some turns should have been taken")

