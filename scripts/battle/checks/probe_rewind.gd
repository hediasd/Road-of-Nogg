extends SceneTree

const ConfigScript = preload("res://src/battle_sim/BattleSetupConfig.gd")
const SetupScript = preload("res://src/battle_sim/BattleSetupFactory.gd")
const SimulatorScript = preload("res://src/battle_sim/BattleSimulator.gd")
const ReplayScript = preload("res://src/battle_sim/BattleReplayRunner.gd")
const SerializerScript = preload("res://src/battle_sim/BattleStateSerializer.gd")

var failures: Array[String] = []


func _init() -> void:
	var config = ConfigScript.new()
	config.scenarioPath = "res://data/battle/scenarios/technical_hxb_contract_player_cpu.json"
	config.seed = 99173
	var setup: Dictionary = SetupScript.createHexState(config)
	_check(bool(setup.get("success", false)), "setup failed")
	if not bool(setup.get("success", false)):
		_finish()
		return
	var sim: BattleSimulator = SimulatorScript.new(config.seed)
	sim.configureHexState(setup["state"], setup["scenario"], config.serialize())
	sim.startBattle()
	_check(bool(sim.startNextSideTurn("probe").get("success", false)), "side did not open")
	var checkpoint: Dictionary = sim.sideStartCheckpoint.duplicate(true)
	var eligible := sim.eligibleSideUnitIDs()
	var callbackRestoreResults: Array[Dictionary] = []
	sim.events.unit_selected.connect(func(_sideID, _monsterID):
		callbackRestoreResults.append(sim.restoreSideTurn()))
	sim.events.unit_spent.connect(func(_sideID, _monsterID):
		callbackRestoreResults.append(sim.restoreSideTurn()))
	_check(sim.selectUnit(eligible[0], "probe")["success"], "first selection failed")
	_check(sim.executeCommand(eligible[0], BattleCommand.wait(), "probe").success,
		"first command failed")
	_check(callbackRestoreResults.size() == 2 and
		str(callbackRestoreResults[0].get("reason", "")) == "resolver_in_progress" and
		str(callbackRestoreResults[1].get("reason", "")) == "resolver_in_progress",
		"rewind entered a partially resolved operation")
	var allocatedID := sim.state.allocateMonsterID()
	var generation := sim.state.timelineGeneration
	var rewound: Dictionary = sim.restoreSideTurn()
	_check(bool(rewound.get("success", false)), "first rewind failed: %s" % str(rewound))
	_check(sim.state.timelineGeneration == generation + 1,
		"rewind did not advance generation")
	_check(sim.state.nextMonsterID == allocatedID and
		str(sim.state.rng.state) == str(checkpoint["state"]["rngState"]),
		"rewind did not restore allocator or gameplay RNG")
	_check(SimulatorScript.semanticFingerprint(sim.state) == checkpoint["fingerprint"],
		"rewind did not restore checkpoint")
	_check(sim.operationLedger.back()["type"] == "side_turn_rewind",
		"branch operation did not survive outside state")
	_check(sim.selectUnit(eligible[1], "probe")["success"], "branch selection failed")
	_check(sim.executeCommand(eligible[1], BattleCommand.wait(), "probe").success,
		"branch command failed")
	var second := sim.restoreSideTurn()
	_check(bool(second.get("success", false)) and
		sim.state.timelineGeneration == generation + 2, "repeated rewind failed")
	_check(sim.selectUnit(eligible[0], "probe")["success"], "continuation select failed")
	_check(sim.executeCommand(eligible[0], BattleCommand.wait(), "probe").success,
		"continuation command failed")
	var snapshot := sim.createReplaySnapshot()
	var parsed = JSON.parse_string(JSON.stringify(snapshot))
	_check(parsed is Dictionary, "disk envelope parse failed")
	if parsed is Dictionary:
		var replay: Dictionary = ReplayScript.replay(parsed)
		_check(bool(replay.get("success", false)),
			"branched disk replay failed: %s" % str(replay))
		if bool(replay.get("success", false)):
			_check(SimulatorScript.semanticFingerprint(replay["simulator"].state) == \
				SimulatorScript.semanticFingerprint(sim.state),
				"branched replay continuation diverged")
		var tampered: Dictionary = parsed.duplicate(true)
		tampered["operations"][1]["fingerprint"] = "sha256:wrong"
		var rejected := ReplayScript.replay(tampered)
		_check(not bool(rejected.get("success", false)) and
			rejected.get("reason", "") == "operation_divergence" and
			int(rejected.get("operation_index", -1)) == 1,
			"replay did not locate first altered operation")
	_finish()


func _check(condition: bool, message: String) -> void:
	if not condition:
		failures.append(message)


func _finish() -> void:
	if not failures.is_empty():
		for failure in failures:
			printerr("AI_REWIND_FAILURE: %s" % failure)
		quit(1)
		return
	print("AI_REWIND_OK")
	quit(0)
