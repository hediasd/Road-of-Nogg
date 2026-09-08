class_name BattleReplayRunner
extends RefCounted

const BattleSetupConfigScript = preload("res://src/battle_sim/BattleSetupConfig.gd")
const BattleSetupFactoryScript = preload("res://src/battle_sim/BattleSetupFactory.gd")
const BattleSimulatorScript = preload("res://src/battle_sim/BattleSimulator.gd")
const BattleStateSerializerScript = preload("res://src/battle_sim/BattleStateSerializer.gd")


static func replay(snapshot: Dictionary) -> Dictionary:
	var identityError := _identityError(snapshot)
	if not identityError.is_empty():
		return {"success": false, "reason": identityError}
	var setupValue = snapshot.get("setup", {})
	if not setupValue is Dictionary or setupValue.is_empty():
		return {"success": false, "reason": "missing_setup"}
	var config: BattleSetupConfig = BattleSetupConfigScript.fromDictionary(setupValue)
	if not config.isHexScenario():
		return _squareReferenceRequired()
	var validation := config.validate()
	if not validation.success:
		return {"success": false, "reason": "invalid_setup", "errors": validation.errors}
	var stateResult := BattleSetupFactoryScript.createHexState(config)
	if not stateResult["success"]:
		return {"success": false, "reason": "invalid_setup_state", "detail": stateResult["error"]}
	var scenario: BattleScenario = stateResult["scenario"]
	var identityDetail := _scenarioIdentityError(snapshot, scenario)
	if not identityDetail.is_empty():
		return {"success": false, "reason": identityDetail}

	var catalogSimulator := BattleSimulatorScript.new(config.seed)
	catalogSimulator.configureHexState(stateResult["state"], scenario, config.serialize())
	if catalogSimulator.state.contentFingerprint != str(snapshot.get("contentFingerprint", "")):
		return {"success": false, "reason": "content_fingerprint_mismatch"}

	var initialValue = snapshot.get("initialState", {})
	if not initialValue is Dictionary or initialValue.is_empty():
		return {"success": false, "reason": "missing_initial_state"}
	if int(initialValue.get("currentMonsterID", -1)) != -1:
		return {"success": false, "reason": "partial_turn_snapshot_unsupported"}
	var initialIdentityError := _embeddedIdentityError(initialValue, snapshot)
	if not initialIdentityError.is_empty():
		return {"success": false, "reason": initialIdentityError}

	var simulator: BattleSimulator = BattleSimulatorScript.new(config.seed)
	var initialState: BattleState = BattleStateSerializerScript.deserialize(initialValue)
	simulator.configureHexState(initialState, scenario, config.serialize())
	if simulator.state.contentFingerprint != str(snapshot.get("contentFingerprint", "")):
		return {"success": false, "reason": "initial_content_fingerprint_mismatch"}
	simulator.initialStateSnapshot = initialValue.duplicate(true)
	simulator.startBattle()

	for operationValue in snapshot.get("operations", []):
		if not operationValue is Dictionary:
			return {"success": false, "reason": "invalid_replay_operation"}
		var operation: Dictionary = operationValue
		var type := str(operation.get("type", ""))
		var data: Dictionary = operation.get("data", {})
		match type:
			"party_activation_start":
				var activation := simulator.startNextPartyActivation(str(data.get("source", "replay")))
				if not activation["success"] or int(activation["party_id"]) != int(operation.get("actor_id", -1)):
					return {
						"success": false,
						"reason": "party_order_mismatch",
						"expected": operation.get("actor_id", -1),
						"actual": activation,
					}
			"member_selected":
				var selection := simulator.selectPartyMember(
					int(operation.get("actor_id", -1)), str(data.get("source", "replay")))
				if not selection["success"]:
					return {"success": false, "reason": "member_selection_rejected", "detail": selection}
			"command":
				var actorID := int(operation.get("actor_id", -1))
				var command := BattleCommand.from_dictionary(data.get("command", {}))
				var result := simulator.executeCommand(actorID, command, str(data.get("source", "replay")))
				if not result.success:
					return {"success": false, "reason": "command_rejected", "detail": result.to_dictionary()}
				var expectedResult = data.get("result", {})
				if expectedResult is Dictionary and not expectedResult.is_empty():
					# BOTH SIDES MUST BE NORMALISED THE SAME WAY. The expected result came out of
					# the snapshot, where `createReplaySnapshot` had already put every event
					# through `jsonSafe` -- so its `Vector2i`s are `{x, y}` dictionaries. A live
					# `to_dictionary()` still holds real `Vector2i` values, which canonicalise as
					# "(1, 2)" rather than as a dictionary. Comparing the two raw made every
					# command carrying a position -- every move, attack and targeted spell --
					# report `command_outcome_mismatch` on a replay that had in fact reproduced
					# the battle exactly. Only wait commands compared equal, which is why the
					# HXB-6 probe, whose replay coverage is waits, never saw it.
					if not _same(
						expectedResult, BattleStateSerializerScript.jsonSafe(result.to_dictionary())
					):
						return {
							"success": false,
							"reason": "command_outcome_mismatch",
							"expected": expectedResult,
							"actual": result.to_dictionary(),
						}
			_:
				return {"success": false, "reason": "unsupported_replay_operation", "type": type}
		simulator.state.assertValidOccupancy()

	var currentValue = snapshot.get("currentState", {})
	if not currentValue is Dictionary:
		return {"success": false, "reason": "missing_current_state"}
	if int(currentValue.get("currentMonsterID", -1)) != -1:
		return {"success": false, "reason": "partial_turn_snapshot_unsupported"}
	var actualState := simulator.state.serialize_state()
	if not _same(_outcomeProjection(currentValue), _outcomeProjection(actualState)):
		return {
			"success": false,
			"reason": "state_outcome_mismatch",
			"expectedFingerprint": _fingerprint(_outcomeProjection(currentValue)),
			"actualFingerprint": _fingerprint(_outcomeProjection(actualState)),
			# The state it actually produced, so a caller can diff the two rather than compare
			# two hashes that differ and say nothing about where. Returned on this path for the
			# same reason the success path returns it.
			"simulator": simulator,
			"actualState": actualState,
		}
	return {"success": true, "simulator": simulator}


static func _identityError(snapshot: Dictionary) -> String:
	var version := int(snapshot.get("version", 0))
	if version > 0 and version <= BattleSimulatorScript.SQUARE_REPLAY_MAX_VERSION:
		return "square_reference_required"
	if version != BattleSimulatorScript.REPLAY_VERSION:
		return "unsupported_replay_version"
	if str(snapshot.get("gridKind", "")) != BattleSimulatorScript.GRID_KIND:
		return "grid_kind_mismatch"
	if str(snapshot.get("coordinateConvention", "")) != BattleSimulatorScript.COORDINATE_CONVENTION:
		return "coordinate_convention_mismatch"
	if str(snapshot.get("rulesetID", "")) != BattleSimulatorScript.RULESET_ID:
		return "ruleset_mismatch"
	if str(snapshot.get("contentFingerprint", "")).is_empty():
		return "missing_content_fingerprint"
	var currentValue = snapshot.get("currentState", {})
	if currentValue is Dictionary:
		return _embeddedIdentityError(currentValue, snapshot)
	return "missing_current_state"


static func _embeddedIdentityError(stateData: Dictionary, snapshot: Dictionary) -> String:
	for pair in [
		["gridKind", "grid_kind_mismatch"],
		["coordinateConvention", "coordinate_convention_mismatch"],
		["rulesetID", "ruleset_mismatch"],
		["contentFingerprint", "content_fingerprint_mismatch"],
	]:
		if str(stateData.get(pair[0], "")) != str(snapshot.get(pair[0], "")):
			return pair[1]
	return ""


static func _scenarioIdentityError(snapshot: Dictionary, scenario: BattleScenario) -> String:
	if str(snapshot.get("scenarioID", "")) != scenario.scenarioID:
		return "scenario_id_mismatch"
	if int(snapshot.get("scenarioRevision", 0)) != scenario.revision:
		return "scenario_revision_mismatch"
	if str(snapshot.get("mapID", "")) != scenario.mapID:
		return "map_id_mismatch"
	if int(snapshot.get("mapRevision", 0)) != scenario.mapRevision:
		return "map_revision_mismatch"
	if str(snapshot.get("mapSourceFingerprint", "")) != scenario.sourceFingerprint:
		return "map_fingerprint_mismatch"
	return ""


## The comparable part of a serialized state: what the battle DID, with the bookkeeping that
## depends on how it was driven removed.
##
## `lastTurnStartIndex` is dropped for the same reason `history` is filtered. It is an index into
## the UNFILTERED history, and a live run records events a replay never re-emits -- so the indices
## sit at a constant offset from each other while describing the identical battle. Filtering the
## history and then comparing a pointer into the unfiltered version is self-contradictory, and it
## made every replay of a brain-driven battle fail `state_outcome_mismatch` with every command,
## every event and every monster in agreement. What the index is FOR -- which events an actor has
## seen since its last turn -- is already covered by the filtered history it points into.
static func _outcomeProjection(serializedState: Dictionary) -> Dictionary:
	var projection := serializedState.duplicate(true)
	projection.erase("lastTurnStartIndex")
	var outcomes: Array = []
	for eventValue in projection.get("history", []):
		if not eventValue is Dictionary:
			continue
		var type := str(eventValue.get("type", ""))
		if type in [
			"round_start", "round_end", "party_activation_start",
			"party_activation_end", "member_selected", "turn_start", "command",
			"member_spent", "damage", "attack_miss", "spell_cast",
			"resonance_changed", "party_withdrawn", "battle_end",
		]:
			outcomes.append(eventValue)
	projection["history"] = outcomes
	return projection


static func _same(a, b) -> bool:
	return BattleSimulatorScript._canonicalJSON(a) == BattleSimulatorScript._canonicalJSON(b)


static func _fingerprint(value) -> String:
	var context := HashingContext.new()
	context.start(HashingContext.HASH_SHA256)
	context.update(BattleSimulatorScript._canonicalJSON(value).to_utf8_buffer())
	return "sha256:%s" % context.finish().hex_encode()


static func _squareReferenceRequired() -> Dictionary:
	return {
		"success": false,
		"reason": "square_reference_required",
		"detail": "Use the frozen square reference project for square replay files.",
	}
