extends SceneTree

const BattleSetupConfigScript = preload("res://src/battle_sim/BattleSetupConfig.gd")
const BattleSetupFactoryScript = preload("res://src/battle_sim/BattleSetupFactory.gd")
const BattleSimulatorScript = preload("res://src/battle_sim/BattleSimulator.gd")
const BattleStateScript = preload("res://src/battle_sim/BattleState.gd")
const BattleEventsScript = preload("res://src/battle_sim/BattleEvents.gd")
const MovementResolverScript = preload("res://src/battle_sim/MovementResolver.gd")
const CombatResolverScript = preload("res://src/battle_sim/CombatResolver.gd")
const MonsterFactoryScript = preload("res://src/factories/MonsterFactory.gd")
const SpellScript = preload("res://src/entities/Spell.gd")
const HexGridScript = preload("res://src/board/HexGrid.gd")
const ThreatMapScript = preload("res://src/algorithms/ThreatMap.gd")
const PartyDeliberationScript = preload("res://src/entity_ai/PartyCommandDeliberation.gd")

const SCENARIO_PATH := "res://data/battle/scenarios/technical_hxb_contract_player_cpu.json"
const WORKLOAD_PATH := "res://scripts/hex_battle/fixtures/ai/workloads.json"

var failures: Array[String] = []
var workload: Dictionary = {}


func _init() -> void:
	workload = _loadWorkload()
	_checkRoleWeights()
	_checkPartyProposals(false)
	_checkPartyProposals(true)
	_checkPartyExhaustion()
	_checkStaleProposal()
	_checkThreatGeometry()
	_checkAreaThreats()
	_checkNoLegacySpatialBranches()
	if not failures.is_empty():
		for failure: String in failures:
			printerr("HXB_AI_FAILURE: %s" % failure)
		quit(1)
		return
	print("HXB_AI_OK")
	quit(0)


func _require(condition: bool, message: String) -> void:
	if not condition:
		failures.append(message)


func _loadWorkload() -> Dictionary:
	var file := FileAccess.open(WORKLOAD_PATH, FileAccess.READ)
	_require(file != null, "AI workload fixture could not be opened")
	if file == null:
		return {}
	var parsed = JSON.parse_string(file.get_as_text())
	_require(parsed is Dictionary, "AI workload fixture is not an object")
	return parsed if parsed is Dictionary else {}


func _simulator(stress: bool = false) -> BattleSimulator:
	var config = BattleSetupConfigScript.new()
	config.scenarioPath = SCENARIO_PATH
	config.seed = 4242
	var stateResult := BattleSetupFactoryScript.createHexState(config)
	_require(stateResult["success"], "hex setup failed: %s" % stateResult.get("error", ""))
	if not stateResult["success"]:
		return null
	var simulator: BattleSimulator = BattleSimulatorScript.new(config.seed)
	simulator.configureHexState(stateResult["state"], stateResult["scenario"], config.serialize())
	var priorityLevels := {10: 10, 11: 9, 20: 99, 21: 98}
	for partyID in simulator.state.parties:
		var party = simulator.state.parties[partyID]
		var commander: Monster = simulator.state.getMonster(party.commanderID)
		commander.level = int(priorityLevels[partyID])
	for monsterID in [100, 101, 102, 103]:
		var target: Monster = simulator.state.getMonster(monsterID)
		target.max_hitpoints = 9999
		target.hitpoints = 9999
	if stress:
		var copies := int(workload.get("stress_spell_copies", 4))
		for memberID in [200, 201]:
			var actor: Monster = simulator.state.getMonster(memberID)
			actor.move = int(workload.get("stress_move", 8))
			var originalSets := actor.spellSets.duplicate(true)
			for _copy in range(copies - 1):
				actor.spellSets.append_array(originalSets.duplicate(true))
	simulator.startBattle()
	var opened := simulator.startNextPartyActivation("probe")
	_require(opened["success"] and opened["party_id"] == 20,
		"CPU party 20 was not first in the probe")
	return simulator


func _checkRoleWeights() -> void:
	var simulator := _simulator()
	if simulator == null:
		return
	var expected := {
		"SupportBrain": [45, 180, 8, 0, 4],
		"BerserkBrain": [135, 35, 0, 4, 12],
		"MageBrain": [125, 70, 4, 1, 8],
		"TacticalBrain": [100, 100, 3, 1, 6],
	}
	for monsterID in simulator.brains:
		var brain = simulator.brains[monsterID]
		var role: String = str(brain.get_script().resource_path.get_file().get_basename())
		var weights: Dictionary = brain._evaluationWeights()
		var values := [weights["damage"], weights["utility"], weights["threat"],
			weights["distance"], weights["wait_penalty"]]
		_require(expected.has(role) and values == expected[role],
			"role weights changed for %s" % role)


func _checkPartyProposals(stress: bool) -> void:
	var simulator := _simulator(stress)
	if simulator == null:
		return
	var before := BattleSimulatorScript._canonicalJSON(simulator.state.serialize_state())
	var referenceKey := ""
	var referenceCandidates := -1
	var referenceWork := -1
	var elapsedUsec := 0
	for sliceValue in workload.get("slice_sizes", [1, 3, 17, 64]):
		var started := Time.get_ticks_usec()
		var deliberation = PartyDeliberationScript.new(simulator)
		var proposal = deliberation.run(int(sliceValue))
		elapsedUsec = Time.get_ticks_usec() - started
		_require(proposal != null, "party deliberation returned no proposal")
		if proposal == null:
			continue
		var key := "%d:%s" % [proposal.actor_id,
			BattleSimulatorScript._canonicalJSON(proposal.command.to_dictionary())]
		if referenceKey.is_empty():
			referenceKey = key
			referenceCandidates = proposal.candidate_count
			referenceWork = proposal.work_slice_count
		else:
			_require(key == referenceKey,
				"slice size %d changed actor/command" % int(sliceValue))
			_require(proposal.candidate_count == referenceCandidates,
				"slice size changed candidate count")
			_require(proposal.work_slice_count == referenceWork,
				"slice size changed deterministic work count")
		_require(proposal.isCurrent(simulator.state), "fresh proposal was marked stale")
	var after := BattleSimulatorScript._canonicalJSON(simulator.state.serialize_state())
	_require(before == after, "party planning mutated authoritative state or RNG")
	_require(referenceCandidates >= int(workload.get("minimum_small_candidates", 2)),
		"party planning produced too few candidates")
	print("AI_WORKLOAD %s candidates=%d slices=%d usec=%d" % [
		"stress" if stress else "small", referenceCandidates, referenceWork, elapsedUsec])


func _checkPartyExhaustion() -> void:
	var simulator := _simulator()
	if simulator == null:
		return
	var expected := simulator.eligiblePartyMemberIDs()
	var resolved: Array[int] = []
	while simulator.state.activePartyID == 20:
		var proposal = PartyDeliberationScript.new(simulator).run(7)
		_require(proposal != null, "active CPU party produced no proposal")
		if proposal == null:
			break
		_require(expected.has(proposal.actor_id) and not resolved.has(proposal.actor_id),
			"party planner selected an ineligible or spent member")
		var selection := simulator.selectPartyMember(proposal.actor_id, "cpu_probe")
		_require(selection["success"], "canonical member selection rejected CPU proposal")
		if not selection["success"]:
			break
		var validation := simulator.validateCommand(proposal.actor_id, proposal.command)
		_require(validation.success,
			"CPU proposal failed canonical validation: %s" % validation.reason)
		if not validation.success:
			break
		var outcome := simulator.executeCommand(
			proposal.actor_id, proposal.command, "cpu_probe")
		_require(outcome.success, "canonical runtime rejected validated CPU proposal")
		resolved.append(proposal.actor_id)
	resolved.sort()
	expected.sort()
	_require(resolved == expected,
		"eligible CPU members did not all act/pass: %s vs %s" % [resolved, expected])


func _checkStaleProposal() -> void:
	var simulator := _simulator(true)
	if simulator == null:
		return
	var deliberation = PartyDeliberationScript.new(simulator)
	_require(not deliberation.stepSlices(1), "stress deliberation finished before stale check")
	simulator.state.add_event("probe_revision", -1, -1)
	_require(deliberation.stepSlices(1), "state change did not stop deliberation")
	_require(deliberation.isStale(), "changed state revision was not detected")
	_require(deliberation.result() == null, "stale deliberation exposed a proposal")
	var restarted = PartyDeliberationScript.new(simulator).run(11)
	_require(restarted != null and restarted.isCurrent(simulator.state),
		"discard/restart did not produce a current proposal")


func _threatHarness() -> Dictionary:
	var state: BattleState = BattleStateScript.new(17)
	state.setup_board(Vector2i(9, 7))
	var events = BattleEventsScript.new()
	var movement = MovementResolverScript.new(state, events)
	var combat = CombatResolverScript.new(state, events)
	var enemy: Monster = MonsterFactoryScript.createMonster("Gigasaurus", 500, 1)
	enemy.move = 0
	enemy.spellSets.clear()
	state.addMonster(enemy, Vector2i(4, 3), 2)
	return {"state": state, "movement": movement, "combat": combat, "enemy": enemy}


func _checkThreatGeometry() -> void:
	var harness := _threatHarness()
	for center in [Vector2i(4, 3), Vector2i(3, 3)]:
		harness["state"].moveMonsterTo(500, center)
		var bounds := ThreatMapScript.beginMap(harness["state"])
		var threat := ThreatMapScript.threatFor(
			harness["state"], bounds, 500, harness["movement"], harness["combat"])
		var neighbours := HexGridScript.neighbours(center)
		_require(neighbours.size() == 6, "hex lattice did not return six approaches")
		for neighbor in neighbours:
			_require(int(threat.get(neighbor, 0)) == harness["enemy"].atk,
				"parity %d omitted melee approach %s" % [center.x & 1, neighbor])


func _checkAreaThreats() -> void:
	var harness := _threatHarness()
	var spell = SpellScript.new({
		"NAME": "Probe Area",
		"DAMAGE": 12,
		"RANGE": 1,
		"MIN_RANGE": 1,
		"TARGET_TYPE": "area",
		"RADIUS": 1,
		"AREA_SHAPE": "circle",
		"CAN_TARGET_EMPTY": true,
	})
	harness["enemy"].spellSets = [[spell]]
	var victim: Monster = MonsterFactoryScript.createMonster("Smoke Cloud", 501, 1)
	var center := Vector2i(5, 3)
	var victimPos := Vector2i(6, 3)
	harness["state"].addMonster(victim, victimPos, 1)
	var bounds := ThreatMapScript.beginMap(harness["state"])
	var threat := ThreatMapScript.threatFor(
		harness["state"], bounds, 500, harness["movement"], harness["combat"])
	_require(int(threat.get(center, 0)) > 0, "area center was not threatened")
	_require(int(threat.get(victimPos, 0)) > 0,
		"unit in an affected area cell was not assessed")
	_require(HexGridScript.distance(Vector2i(4, 3), victimPos) == 2,
		"area probe did not cover a cell beyond direct range")


func _checkNoLegacySpatialBranches() -> void:
	for path in [
		"res://src/entity_ai/EntityBrain.gd",
		"res://src/entity_ai/BerserkBrain.gd",
		"res://src/entity_ai/MageBrain.gd",
		"res://src/entity_ai/SupportBrain.gd",
		"res://src/entity_ai/TacticalBrain.gd",
		"res://src/algorithms/ThreatMap.gd",
	]:
		var file := FileAccess.open(path, FileAccess.READ)
		var text := file.get_as_text() if file != null else ""
		_require(text.find("_evaluateTile") == -1,
			"legacy _evaluateTile branch remains in %s" % path)
		_require(text.find("abs(pos.x -") == -1,
			"square distance remains in %s" % path)
