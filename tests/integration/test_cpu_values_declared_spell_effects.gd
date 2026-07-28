## Regression test for P5-1 (AUDIT_REMEDIATION_PLAN.md). Before this fix,
## BattleCommandEvaluator never scored spell.effects, so every EFFECTS-only
## spell (all 25 Level 1 self-spells) contributed zero utility. Two otherwise
## identical buff spells of different strength would tie exactly, and the
## deterministic tie_key (which sorts by ascending spell_index as a late
## component) would then pick whichever happened to have the lower
## spell_index — the WEAKER buff here — regardless of actual value.
extends "res://tests/TestCase.gd"


func describe() -> String:
	return "the CPU prefers a stronger declared spell.effects buff over a weaker one, not just the lower spell index"


func run() -> void:
	var sim = makeSimulator(0, Vector2i(6, 1))
	var actor = sim.spawnMonster("Defaultgon", 1, Vector2i(0, 0))
	sim.spawnMonster("Envoy of Lightning", 2, Vector2i(5, 0))

	var weakBuff = Spell.new({
		"NAME": "Weak Buff", "TARGET_TYPE": "self", "RANGE": 0,
		"EFFECTS": [{"NAME": "atk_buff", "DURATION": 3, "ATK_BONUS": 1}]
	})
	var strongBuff = Spell.new({
		"NAME": "Strong Buff", "TARGET_TYPE": "self", "RANGE": 0,
		"EFFECTS": [{"NAME": "atk_buff", "DURATION": 3, "ATK_BONUS": 6}]
	})
	actor.spellSets = [[weakBuff, strongBuff]]

	sim.state.currentMonsterID = actor.uniqueID
	var evaluator = BattleCommandEvaluator.new(sim.state, sim.movementResolver, sim.combatResolver)
	var command: Dictionary = evaluator.chooseCommand(actor.uniqueID, {})

	assertEqual(command["action"], "spell", "the CPU should cast a spell rather than wait")
	assertEqual(
		command["spell_index"], 1,
		"the CPU should prefer the stronger declared-effect buff (index 1) over the weaker one (index 0)"
	)
