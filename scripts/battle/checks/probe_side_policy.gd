extends SceneTree

## The reworked side policy: that it decides the same thing however it is
## sliced, that its decisions do not depend on hidden randomness, that its
## explanation adds up to its score, and that it actually finishes battles.

const BattleSetupConfigScript = preload("res://src/battle_sim/BattleSetupConfig.gd")
const BattleSetupFactoryScript = preload("res://src/battle_sim/BattleSetupFactory.gd")
const BattleSimulatorScript = preload("res://src/battle_sim/BattleSimulator.gd")
const PolicyScript = preload("res://src/entity_ai/TacticalSidePolicy.gd")
const CatalogScript = preload("res://src/entity_ai/PolicyCatalog.gd")
const BandScript = preload("res://src/entity_ai/EngagementBand.gd")
const ContextScript = preload("res://src/entity_ai/DecisionContext.gd")
const EnumeratorScript = preload("res://src/entity_ai/LegalActionEnumerator.gd")
const FilterScript = preload("res://src/entity_ai/CandidateFilter.gd")

const CASES_PATH := "res://scripts/battle/fixtures/ai/policy_cases.json"

var failures: Array[String] = []
var cases: Dictionary = {}


func _init() -> void:
	cases = JSON.parse_string(FileAccess.get_file_as_string(CASES_PATH))
	_checkSliceEquivalence()
	_checkHiddenRandomness()
	_checkTraceAddsUp()
	_checkEngagementBands()
	_checkIdleAttacksDropped()
	_checkPolicyIdentity()
	_checkBattlesFinish()
	if not failures.is_empty():
		for failure: String in failures:
			printerr("AI_SIDE_POLICY_FAILURE: %s" % failure)
		quit(1)
		return
	print("AI_SIDE_POLICY_OK")
	quit(0)


func _require(condition: bool, message: String) -> void:
	if not condition:
		failures.append(message)


func _simulator(seed: int, scenario: String = "") -> BattleSimulator:
	var config = BattleSetupConfigScript.new()
	config.scenarioPath = scenario if not scenario.is_empty() else str(cases["scenario"])
	config.seed = seed
	var setup := BattleSetupFactoryScript.createHexState(config)
	if not bool(setup.get("success", false)):
		failures.append("setup failed: %s" % str(setup.get("error", "")))
		return null
	var simulator: BattleSimulator = BattleSimulatorScript.new(config.seed)
	simulator.configureHexState(setup["state"], setup["scenario"], config.serialize())
	simulator.startBattle()
	if not bool(simulator.startNextSideTurn("probe").get("success", false)):
		failures.append("no side opened")
		return null
	return simulator


func _decision(simulator: BattleSimulator, sliceCount: int) -> Dictionary:
	var policy = PolicyScript.new(simulator)
	var proposal = policy.run(sliceCount)
	return {
		"actor_id": -1 if proposal == null else int(proposal.actor_id),
		"command": null if proposal == null else proposal.command.to_dictionary(),
		"score": 0 if proposal == null else int(proposal.score),
		"trace": policy.trace(),
	}


func _checkSliceEquivalence() -> void:
	## Where the slices fall is a machine detail. It must not be able to change
	## which unit acts or what it does.
	for seedValue in cases["seeds"]:
		var reference: Dictionary = {}
		for sliceCount in [1, 2, 7, 64, 4096]:
			var simulator := _simulator(int(seedValue))
			if simulator == null:
				return
			var decision := _decision(simulator, sliceCount)
			if reference.is_empty():
				reference = decision
				_require(decision["actor_id"] >= 0,
					"the policy proposed nothing at seed %d" % int(seedValue))
				continue
			_require(_same(decision["actor_id"], reference["actor_id"])
				and _same(decision["command"], reference["command"])
				and _same(decision["score"], reference["score"]),
				"a slice size of %d changed the decision at seed %d" %
				[sliceCount, int(seedValue)])


func _checkHiddenRandomness() -> void:
	## The policy reads the board, never the dice. Moving the gameplay RNG on
	## without changing anything a policy may observe must change nothing.
	for seedValue in cases["seeds"]:
		var simulator := _simulator(int(seedValue))
		if simulator == null:
			return
		var before := _decision(simulator, 64)
		var rngBefore = simulator.state.rng.state
		simulator.state.rng.state = 0xDEADBEEF
		var after := _decision(simulator, 64)
		_require(_same(before["command"], after["command"])
			and _same(before["actor_id"], after["actor_id"]),
			"the decision at seed %d moved with the hidden gameplay RNG" % int(seedValue))
		_require(simulator.state.rng.state == 0xDEADBEEF,
			"deliberating advanced the gameplay RNG")
		simulator.state.rng.state = rngBefore


func _checkTraceAddsUp() -> void:
	## An explanation nobody can check is decoration. Every component must sum
	## to the score, and the chosen action must be the best of what was scored.
	var simulator := _simulator(int(cases["seeds"][0]))
	if simulator == null:
		return
	var policy = PolicyScript.new(simulator)
	var proposal = policy.run(64)
	_require(proposal != null, "the policy proposed nothing to explain")
	if proposal == null:
		return
	var trace: Dictionary = policy.trace()
	var chosen: Dictionary = trace["chosen"]
	var total := 0
	for key in chosen["components"]:
		if key == "bound" or key == "feasible":
			continue
		total += int(chosen["components"][key])
	_require(total == int(chosen["score"]),
		"the chosen trace's components summed to %d but the score was %d" %
		[total, int(chosen["score"])])
	_require(int(chosen["score"]) == int(proposal.score),
		"the trace and the proposal disagreed about the score")
	for alternative in trace["alternatives"]:
		_require(int(alternative["score"]) <= int(chosen["score"]),
			"an alternative outscored the chosen action")
	_require(str(trace["horizon"]) == "one_decision_step",
		"the policy did not declare its horizon")
	_require(int(trace["candidates_enumerated"]) >= int(trace["candidates_scored"]),
		"more candidates were scored than enumerated")
	print("AI_SIDE_POLICY trace enumerated=%d scored=%d slices=%d" %
		[int(trace["candidates_enumerated"]), int(trace["candidates_scored"]),
		int(trace["work_slices"])])


func _checkEngagementBands() -> void:
	## A unit's preferred distance comes from its own abilities. A sword wants
	## to be adjacent; something that throws from six hexes does not.
	var simulator := _simulator(int(cases["seeds"][0]))
	if simulator == null:
		return
	var state := simulator.state
	var brawlerID := int(simulator.eligibleSideUnitIDs()[0])
	var brawler: Monster = state.getMonster(brawlerID)
	state.setMonsterAbilities(brawlerID, [[]], brawler.passives)
	var band := BandScript.preferredBand(state, brawlerID)
	_require(not band.is_empty() and int(band["min"]) == 1 and int(band["max"]) == 1,
		"a unit with only a sword did not prefer to be adjacent")
	_require(BandScript.fitValue(band, 1) > BandScript.fitValue(band, 4),
		"being adjacent was not worth more than standing off")
	## The gradient must keep falling with distance rather than flattening, or a
	## unit far from the fight has no reason to walk towards it.
	_require(BandScript.fitValue(band, 8) < BandScript.fitValue(band, 6)
		and BandScript.fitValue(band, 6) < BandScript.fitValue(band, 4),
		"the engagement gradient flattened, leaving distant units nothing to follow")

	var reachSpell := Spell.new({})
	reachSpell.range = 6
	reachSpell.min_range = 2
	reachSpell.damage = 30
	reachSpell.damage_lines = [{"damage": 30, "element": "none"}]
	reachSpell.heals = false
	state.setMonsterAbilities(brawlerID, [[reachSpell]], brawler.passives)
	var reachBand := BandScript.preferredBand(state, brawlerID)
	_require(not reachBand.is_empty() and int(reachBand["max"]) == 6
		and int(reachBand["min"]) == 2,
		"a unit whose damage comes from range did not prefer that range")
	_require(BandScript.fitValue(reachBand, 4) > BandScript.fitValue(reachBand, 1),
		"a ranged unit preferred to stand in melee")


func _checkIdleAttacksDropped() -> void:
	## A swing at an empty tile is the Wait at that destination, spelled in a way
	## a player's own controls cannot express. Spells that catch nobody stay.
	var simulator := _simulator(int(cases["seeds"][0]))
	if simulator == null:
		return
	var context = ContextScript.forSimulator(simulator)
	var actorID := int(simulator.eligibleSideUnitIDs()[0])
	var candidates := EnumeratorScript.forActor(context, actorID)
	var idleAttacks := 0
	for candidate in candidates:
		if candidate.action_class == "attack" and candidate.command.target_id < 0:
			idleAttacks += 1
	_require(idleAttacks > 0, "the fixture offered no empty-tile attack to drop")
	var kept := FilterScript.dropIdleAttacks(candidates)
	var emptySpells := 0
	for candidate in kept:
		_require(not (candidate.action_class == "attack"
			and candidate.command.target_id < 0),
			"an attack on an empty tile survived the filter")
		if candidate.action_class == "spell_empty":
			emptySpells += 1
	_require(emptySpells > 0,
		"the filter removed the empty-centre spell class along with idle attacks")
	context.close()


func _checkPolicyIdentity() -> void:
	_require(CatalogScript.has(CatalogScript.TACTICAL_SIDE),
		"the catalog does not know the policy that plays")
	var simulator := _simulator(int(cases["seeds"][0]))
	if simulator == null:
		return
	_require(simulator.sidePolicyID == CatalogScript.TACTICAL_SIDE,
		"a fresh simulator did not default to the reworked policy")
	_require(simulator.beginSideDeliberation() is TacticalSidePolicy,
		"the simulator did not open the configured policy")
	simulator.sidePolicyID = CatalogScript.LEGACY_SIDE
	_require(not (simulator.beginSideDeliberation() is TacticalSidePolicy),
		"the legacy policy could not be selected for comparison")


func _checkBattlesFinish() -> void:
	## The point of a policy is that battles end. Measured against the shipped
	## one on the same scenario and seeds: both are recorded, and a regression
	## in rounds or survivors is visible here rather than in a play session.
	for seedValue in cases["seeds"]:
		var outcomes: Dictionary = {}
		for policyID in [CatalogScript.LEGACY_SIDE, CatalogScript.TACTICAL_SIDE]:
			outcomes[policyID] = _playOut(int(seedValue), policyID)
		var legacy: Dictionary = outcomes[CatalogScript.LEGACY_SIDE]
		var tactical: Dictionary = outcomes[CatalogScript.TACTICAL_SIDE]
		_require(int(tactical["outcome"]) != -1,
			"the reworked policy did not finish the battle at seed %d in %d rounds" %
			[int(seedValue), int(tactical["rounds"])])
		_require(int(tactical["rounds"]) <= int(cases["max_rounds"]),
			"the reworked policy took %d rounds at seed %d" %
			[int(tactical["rounds"]), int(seedValue)])
		print("AI_SIDE_POLICY seed=%d legacy=%s tactical=%s" %
			[int(seedValue), JSON.stringify(legacy), JSON.stringify(tactical)])


func _playOut(seed: int, policyID: String) -> Dictionary:
	var simulator := _simulator(seed, str(cases["headless_scenario"]))
	if simulator == null:
		return {}
	simulator.sidePolicyID = policyID
	var decisions := 0
	var cap := int(cases["max_rounds"])
	while simulator.state.battleOutcome == -1 and simulator.state.roundCount < cap:
		if simulator.state.activeSideID == -1:
			if not bool(simulator.startNextSideTurn("probe").get("success", false)):
				break
		var proposal = simulator.beginSideDeliberation().run(64)
		if proposal == null:
			simulator.endSideTurn("no_proposal")
			continue
		decisions += 1
		if not bool(simulator.selectUnit(proposal.actor_id, "cpu").get("success", false)):
			simulator.endSideTurn("refused")
			continue
		simulator.executeCommand(proposal.actor_id, proposal.command, "cpu")
	var survivors: Dictionary = {}
	for monsterIDValue in simulator.state.getAliveMonsterIDs():
		var monster: Monster = simulator.state.getMonster(int(monsterIDValue))
		survivors[str(monster.team)] = int(survivors.get(str(monster.team), 0)) + 1
	return {
		"rounds": simulator.state.roundCount,
		"decisions": decisions,
		"outcome": simulator.state.battleOutcome,
		"survivors": survivors,
	}


func _same(a, b) -> bool:
	return JSON.stringify(a, "", true) == JSON.stringify(b, "", true)
