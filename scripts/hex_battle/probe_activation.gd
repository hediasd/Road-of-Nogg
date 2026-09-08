extends SceneTree

const BattleSetupConfigScript = preload("res://src/battle_sim/BattleSetupConfig.gd")
const BattleSetupFactoryScript = preload("res://src/battle_sim/BattleSetupFactory.gd")
const BattleSimulatorScript = preload("res://src/battle_sim/BattleSimulator.gd")

const SCENARIO_PATH := "res://data/battle/scenarios/technical_hxb_contract_player_cpu.json"

var failures: Array[String] = []


func _init() -> void:
	_checkActivationLifecycle()
	_checkAtomicIncrementalEquivalence()
	_checkSimultaneousCommanderLoss()
	if not failures.is_empty():
		for failure: String in failures:
			printerr("HXB_ACTIVATION_FAILURE: %s" % failure)
		quit(1)
		return
	print("HXB_ACTIVATION_OK")
	quit(0)


func _require(condition: bool, message: String) -> void:
	if not condition:
		failures.append(message)


func _simulator() -> BattleSimulator:
	var config = BattleSetupConfigScript.new()
	config.scenarioPath = SCENARIO_PATH
	config.seed = 4242
	var stateResult := BattleSetupFactoryScript.createHexState(config)
	_require(stateResult["success"], "hex setup failed: %s" % stateResult.get("error", ""))
	if not stateResult["success"]:
		return null
	var simulator: BattleSimulator = BattleSimulatorScript.new(config.seed)
	simulator.configureHexState(stateResult["state"], stateResult["scenario"], config.serialize())
	return simulator


func _forcePartyOrder(simulator: BattleSimulator) -> void:
	var priorities := {
		10: [5, 10],
		11: [5, 10],
		20: [4, 99],
		21: [3, 99],
	}
	for partyID in priorities:
		var commanderID: int = simulator.state.parties[partyID].commanderID
		var commander: Monster = simulator.state.getMonster(commanderID)
		commander.level = priorities[partyID][0]
		commander.speed = priorities[partyID][1]


func _checkActivationLifecycle() -> void:
	var simulator := _simulator()
	if simulator == null:
		return
	_forcePartyOrder(simulator)
	simulator.startBattle()
	var activationEnds: Array[int] = []
	simulator.events.party_activation_ended.connect(
		func(partyID: int, _reason: String): activationEnds.append(partyID))

	var opened := simulator.startNextPartyActivation("probe")
	_require(opened["success"] and opened["party_id"] == 10,
		"party ordering did not use level, speed, then party ID")
	_require(simulator.state.partyOrder == [10, 11, 20, 21],
		"round party order changed: %s" % simulator.state.partyOrder)
	var invalid := simulator.selectPartyMember(102, "probe")
	_require(not invalid["success"] and invalid["reason"] == "member_not_in_active_party",
		"foreign member selection was not rejected")

	simulator.state.addEffect(100, "probe_clock", 2)
	simulator.state.getMonster(100).spell_cooldowns["probe"] = 2
	simulator.state.addEffect(101, "petrify", 2)
	_require(simulator.selectPartyMember(101, "probe")["success"], "eligible member 101 was rejected")
	var skipped := simulator.executeCommand(101, BattleCommand.wait(), "probe")
	_require(skipped.success and skipped.skipped and not skipped.resolved,
		"petrified member was not recorded as an accepted skip")
	_require(simulator.state.getActiveEffects(100)[0]["remainingTurns"] == 2,
		"another member's effect clock advanced")
	_require(simulator.state.getMonster(100).spell_cooldowns["probe"] == 2,
		"another member's cooldown advanced")
	var spent := simulator.selectPartyMember(101, "probe")
	_require(not spent["success"] and spent["reason"] == "member_already_spent",
		"spent member could act twice")
	_require(simulator.selectPartyMember(100, "probe")["success"], "member 100 was not selectable")
	var waited := simulator.executeCommand(100, BattleCommand.wait(), "probe")
	_require(waited.success and waited.resolved, "wait did not resolve")
	_require(simulator.state.getActiveEffects(100)[0]["remainingTurns"] == 1,
		"acting member's effect did not tick exactly once")
	_require(simulator.state.getMonster(100).spell_cooldowns["probe"] == 1,
		"acting member's cooldown did not tick exactly once")
	_require(simulator.state.activePartyID == -1 and activationEnds == [10],
		"exhausted party did not close exactly once")

	opened = simulator.startNextPartyActivation("probe")
	_require(opened["success"] and opened["party_id"] == 11, "second party did not open")
	simulator.state.addEffect(102, "probe_clock", 2)
	simulator.state.addEffect(103, "probe_clock", 2)
	var ended := simulator.endPartyActivation("probe")
	_require(ended["success"] and ended["consumed"] == [102, 103],
		"End Party did not wait remaining members in deterministic ID order")
	_require(simulator.state.getActiveEffects(102)[0]["remainingTurns"] == 1,
		"End Party did not tick member 102 exactly once")
	_require(simulator.state.getActiveEffects(103)[0]["remainingTurns"] == 1,
		"End Party did not tick member 103 exactly once")

	var commander20: Monster = simulator.state.getMonster(200)
	commander20.hitpoints = 0
	simulator.passiveSkillResolver.handleDefeat(200, 100)
	opened = simulator.startNextPartyActivation("probe")
	_require(opened["success"] and opened["party_id"] == 21,
		"party with a defeated commander was not skipped")
	_require(simulator.state.isPartyWithdrawn(20), "commander loss before activation did not withdraw party")
	_require(simulator.state.isMonsterWithdrawn(201) and simulator.state.getMonster(201).is_alive(),
		"surviving member was killed instead of withdrawn")

	simulator.state.addEffect(202, "probe_lethal", 2, 100, "", 9999)
	_require(simulator.selectPartyMember(202, "probe")["success"], "commander 202 was not selectable")
	var lethalWait := simulator.executeCommand(202, BattleCommand.wait(), "probe")
	_require(lethalWait.success, "commander's accepted wait was rejected during resolution")
	_require(simulator.state.isPartyWithdrawn(21), "commander loss after acting did not withdraw party")
	_require(simulator.state.isMonsterWithdrawn(203) and simulator.state.getMonster(203).is_alive(),
		"commander loss did not withdraw its survivor")
	_require(simulator.state.battleOutcome == 1, "last enemy commander loss did not award Team 1")
	_require(simulator.startNextPartyActivation("probe")["reason"] == "battle_ended",
		"battle outcome left a schedulable party")
	var lethalCommands := simulator.state.history.filter(func(event):
		return event.get("type", "") == "command" and event.get("actor_id", -1) == 202)
	_require(lethalCommands.size() == 1 and lethalCommands[0]["data"].has("result"),
		"accepted command outcome was not recorded exactly once")


func _checkAtomicIncrementalEquivalence() -> void:
	var atomic := _simulator()
	var incremental := _simulator()
	if atomic == null or incremental == null:
		return
	_forcePartyOrder(atomic)
	_forcePartyOrder(incremental)
	for simulator in [atomic, incremental]:
		simulator.startBattle()
		simulator.startNextPartyActivation("equivalence")
		simulator.selectPartyMember(100, "equivalence")
	var atomicResult := atomic.executeCommand(100, BattleCommand.wait(), "equivalence")
	var moveResult := incremental.executeMovePhase(100, [], "equivalence")
	var actionResult := incremental.executeActionPhase(100, "wait", Vector2i(-1, -1), 0, 0, "equivalence")
	var incrementalResult := incremental.finishTurn(100, "equivalence")
	_require(moveResult["success"] and actionResult["success"], "incremental wait phases failed")
	_require(BattleSimulatorScript._canonicalJSON(atomicResult.to_dictionary()) ==
		BattleSimulatorScript._canonicalJSON(incrementalResult.to_dictionary()),
		"atomic and incremental results differ")
	_require(BattleSimulatorScript._canonicalJSON(atomic.state.serialize_state()) ==
		BattleSimulatorScript._canonicalJSON(incremental.state.serialize_state()),
		"atomic and incremental state/events differ")


func _checkSimultaneousCommanderLoss() -> void:
	var simulator := _simulator()
	if simulator == null:
		return
	for partyID in simulator.state.parties:
		var commanderID: int = simulator.state.parties[partyID].commanderID
		simulator.state.getMonster(commanderID).hitpoints = 0
		simulator.passiveSkillResolver.handleDefeat(commanderID, -1)
	simulator.startBattle()
	var opened := simulator.startNextPartyActivation("probe")
	_require(not opened["success"] and opened["reason"] == "battle_ended",
		"simultaneous last-commander loss did not stop scheduling")
	_require(simulator.state.battleOutcome == 0, "simultaneous last-commander loss was not a draw")
