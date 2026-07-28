## The P4-3 pilot's payoff test. Before the Wood ladder was authored, every
## tiered spell in the catalog was Level 1, so Resonance could never exceed one
## charge and the +20%/+30% tiers plus Level 4 depletion were unreachable in
## play. This drives a real catalog monster up its real spell set, one cast per
## tier, and asserts the whole ladder executes — not the mechanics in isolation
## (those are unit-tested), but that authored content can actually reach them.
extends "res://tests/TestCase.gd"


func describe() -> String:
	return "Walker of the Woods climbs its authored Wood set 0-1-2-3 and spends the bar on Level 4"


func run() -> void:
	var sim = makeSimulator(0, Vector2i(10, 10))
	var caster = sim.spawnMonster("Walker of the Woods", 1, Vector2i(2, 2))
	var victim = sim.spawnMonster("Brickamount", 2, Vector2i(4, 2))

	var woodSet: Array = []
	for spellSet in caster.spellSets:
		for spell in spellSet:
			if spell.name == "Gather":
				woodSet = spellSet
	assertEqual(woodSet.size(), 4, "the Wood set should hold one spell per Level 1-4")

	## Tier by tier: each cast must be legal at the charge it requires, and must
	## leave the bar one higher than it found it.
	for tier in [1, 2, 3]:
		var spell = woodSet[tier - 1]
		assertEqual(spell.sequence_level, tier, "Wood set index %d should be Level %d" % [tier - 1, tier])
		assertEqual(
			caster.get_resonance("wood"), tier - 1,
			"charge should be %d before the Level %d cast" % [tier - 1, tier]
		)
		assertTrue(caster.can_cast(spell), "%s should be castable at charge %d" % [spell.name, tier - 1])
		caster.record_cast(spell)
		assertEqual(
			caster.get_resonance("wood"), tier,
			"%s should have advanced the wood bar to %d" % [spell.name, tier]
		)

	var ultimate = woodSet[3]
	assertEqual(ultimate.name, "Roses at Summers End", "Level 4 of the Wood set should be the authored ultimate")
	assertEqual(caster.get_resonance("wood"), 3, "three charge should be banked before the Level 4 cast")
	assertTrue(caster.can_cast(ultimate), "the Level 4 spell should be castable at full charge")

	## The +30% tier is only reachable here, so this is the first test in the
	## suite where the top Resonance bonus is exercised on authored content.
	var buffedATK = caster.get_effective_atk()
	caster.record_cast(ultimate)
	assertEqual(caster.get_resonance("wood"), 0, "casting Level 4 should empty the wood bar")
	assertTrue(
		caster.get_effective_atk() < buffedATK,
		"spending the bar should drop the Resonance ATK bonus back off"
	)

	## And it must actually resolve as a spell against a real target, not just
	## satisfy can_cast(): a Level 4 that cannot damage anything is still dead
	## content.
	caster.resonance_bars["wood"] = 3
	caster.spell_cooldowns.clear()
	sim.state.currentMonsterID = caster.uniqueID
	var startingHP = victim.hitpoints
	var targets = sim.combatResolver.getSpellTargets(caster.uniqueID, 1, 3)
	assertTrue(targets.has(victim.uniqueID), "the Level 4 area spell should be able to target a nearby enemy")
	var result = sim.executeCommand(caster.uniqueID, {
		"move_path": [], "action": "spell", "target_id": victim.uniqueID,
		"spell_set_index": 1, "spell_index": 3
	}, "test")
	assertTrue(result.get("success", false), "the Level 4 cast should be accepted by the simulator")
	assertTrue(victim.hitpoints < startingHP, "the Level 4 cast should have damaged its target")
