extends SceneTree

const BattleReplayRunnerScript = preload("res://src/battle_sim/BattleReplayRunner.gd")
const BattleSetupConfigScript = preload("res://src/battle_sim/BattleSetupConfig.gd")
const BattleSetupFactoryScript = preload("res://src/battle_sim/BattleSetupFactory.gd")
const BattleSimulatorScript = preload("res://src/battle_sim/BattleSimulator.gd")

const SCENARIO_PATH := "res://data/battle/scenarios/technical_hxb_contract_player_cpu.json"

var failures: Array[String] = []


func _init() -> void:
	var simulator := _simulator()
	if simulator != null:
		_checkReplayAndContinuation(simulator)
	if not failures.is_empty():
		for failure: String in failures:
			printerr("HXB_REPLAY_FAILURE: %s" % failure)
		quit(1)
		return
	print("HXB_REPLAY_OK")
	quit(0)


func _require(condition: bool, message: String) -> void:
	if not condition:
		failures.append(message)


func _simulator() -> BattleSimulator:
	var config = BattleSetupConfigScript.new()
	config.scenarioPath = SCENARIO_PATH
	config.seed = 99173
	var stateResult := BattleSetupFactoryScript.createHexState(config)
	_require(stateResult["success"], "hex setup failed: %s" % stateResult.get("error", ""))
	if not stateResult["success"]:
		return null
	var simulator: BattleSimulator = BattleSimulatorScript.new(config.seed)
	simulator.configureHexState(stateResult["state"], stateResult["scenario"], config.serialize())
	return simulator


func _checkReplayAndContinuation(simulator: BattleSimulator) -> void:
	simulator.startBattle()
	var opening := simulator.startNextPartyActivation("probe")
	_require(opening["success"], "first party activation failed")
	if not opening["success"]:
		return
	var selectedID := int(simulator.eligiblePartyMemberIDs().back())
	_require(simulator.selectPartyMember(selectedID, "probe")["success"],
		"explicit out-of-order member selection failed")
	var commandResult := simulator.executeCommand(selectedID, BattleCommand.wait(), "probe")
	_require(commandResult.success, "selected member wait failed")
	var snapshot := simulator.createReplaySnapshot()
	_require(snapshot.get("success", false), "activation-boundary snapshot failed")
	if not snapshot.get("success", false):
		return
	_require(snapshot["version"] == 6, "hex replay did not use version 6")
	_require(snapshot["gridKind"] == "hex_flat" and snapshot["coordinateConvention"] == "odd_q_offset",
		"hex topology identity was not recorded")
	_require(snapshot["rulesetID"] == "hex_party_activation_v1",
		"ruleset identity was not recorded")
	_require(str(snapshot["contentFingerprint"]).begins_with("sha256:"),
		"content fingerprint was not recorded")
	_require(snapshot["operations"].filter(func(entry):
		return entry.get("type", "") == "member_selected").size() == 1,
		"member selection was not explicit in replay operations")

	var replayed := BattleReplayRunnerScript.replay(snapshot)
	_require(replayed["success"], "replay failed: %s" % replayed.get("reason", ""))
	if replayed["success"]:
		_require(_same(snapshot["currentState"], replayed["simulator"].state.serialize_state()),
			"replay did not reproduce the activation-boundary state and events")

	var restored := BattleSimulatorScript.new()
	var restoreResult := restored.restoreReplaySnapshot(snapshot)
	_require(restoreResult["success"], "activation-boundary restore failed: %s" % restoreResult.get("reason", ""))
	if restoreResult["success"]:
		_continueOnce(simulator)
		_continueOnce(restored)
		var originalRandom := simulator.state.rng.randi()
		var restoredRandom := restored.state.rng.randi()
		var originalID := simulator.state.allocateMonsterID()
		var restoredID := restored.state.allocateMonsterID()
		_require(originalRandom == restoredRandom, "restored RNG diverged on continuation")
		_require(originalID == restoredID, "restored ID allocation diverged on continuation")
		_require(_same(simulator.state.serialize_state(), restored.state.serialize_state()),
			"restored activation continuation diverged")

	var partial := _simulator()
	if partial != null:
		partial.startBattle()
		partial.startNextPartyActivation("probe")
		var partialID := int(partial.eligiblePartyMemberIDs().front())
		partial.selectPartyMember(partialID, "probe")
		var partialSnapshot := partial.createReplaySnapshot()
		_require(not partialSnapshot.get("success", true) and
			partialSnapshot.get("reason", "") == "partial_turn_snapshot_unsupported",
			"mid-turn capture was not rejected explicitly")

	_expectReplayFailure({"version": 5}, "square_reference_required", "square replay")
	var wrongGrid: Dictionary = snapshot.duplicate(true)
	wrongGrid["gridKind"] = "square"
	_expectReplayFailure(wrongGrid, "grid_kind_mismatch", "wrong grid")
	var wrongRuleset: Dictionary = snapshot.duplicate(true)
	wrongRuleset["rulesetID"] = "hex_future_rules"
	_expectReplayFailure(wrongRuleset, "ruleset_mismatch", "wrong ruleset")
	var wrongMap: Dictionary = snapshot.duplicate(true)
	wrongMap["mapRevision"] = int(snapshot["mapRevision"]) + 1
	_expectReplayFailure(wrongMap, "map_revision_mismatch", "wrong map revision")
	var wrongContent: Dictionary = snapshot.duplicate(true)
	var fakeFingerprint := "sha256:%s" % "0".repeat(64)
	wrongContent["contentFingerprint"] = fakeFingerprint
	wrongContent["initialState"]["contentFingerprint"] = fakeFingerprint
	wrongContent["currentState"]["contentFingerprint"] = fakeFingerprint
	_expectReplayFailure(wrongContent, "content_fingerprint_mismatch", "wrong content")
	var wrongOutcome: Dictionary = snapshot.duplicate(true)
	wrongOutcome["currentState"]["turnCount"] = int(snapshot["currentState"]["turnCount"]) + 1
	_expectReplayFailure(wrongOutcome, "state_outcome_mismatch", "wrong final outcome")

	var partialRestore: Dictionary = snapshot.duplicate(true)
	partialRestore["currentState"]["currentMonsterID"] = selectedID
	var partialRestoreResult := BattleSimulatorScript.new().restoreReplaySnapshot(partialRestore)
	_require(not partialRestoreResult["success"] and
		partialRestoreResult["reason"] == "partial_turn_snapshot_unsupported",
		"unsupported partial restore was accepted")


func _continueOnce(simulator: BattleSimulator) -> void:
	if simulator.state.activePartyID == -1:
		var opened := simulator.startNextPartyActivation("continuation")
		_require(opened["success"], "continuation could not open a party")
		if not opened["success"]:
			return
	var eligible := simulator.eligiblePartyMemberIDs()
	_require(not eligible.is_empty(), "continuation had no eligible member")
	if eligible.is_empty():
		return
	var memberID := int(eligible.front())
	_require(simulator.selectPartyMember(memberID, "continuation")["success"],
		"continuation member selection failed")
	_require(simulator.executeCommand(memberID, BattleCommand.wait(), "continuation").success,
		"continuation command failed")


func _expectReplayFailure(snapshot: Dictionary, reason: String, label: String) -> void:
	var result := BattleReplayRunnerScript.replay(snapshot)
	_require(not result.get("success", false) and result.get("reason", "") == reason,
		"%s returned %s instead of %s" % [label, result.get("reason", ""), reason])


func _same(a, b) -> bool:
	return BattleSimulatorScript._canonicalJSON(a) == BattleSimulatorScript._canonicalJSON(b)
