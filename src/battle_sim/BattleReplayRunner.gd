class_name BattleReplayRunner
extends RefCounted

const BattleSetupConfigScript = preload("res://src/battle_sim/BattleSetupConfig.gd")
const BattleSetupFactoryScript = preload("res://src/battle_sim/BattleSetupFactory.gd")
const BattleSimulatorScript = preload("res://src/battle_sim/BattleSimulator.gd")


static func replay(snapshot: Dictionary) -> Dictionary:
	var version = int(snapshot.get("version", BattleSimulatorScript.REPLAY_MIN_VERSION))
	if version < BattleSimulatorScript.REPLAY_MIN_VERSION or version > BattleSimulatorScript.REPLAY_VERSION:
		return {"success": false, "reason": "unsupported_replay_version", "version": version}
	if snapshot.get("setup", {}).is_empty():
		return {"success": false, "reason": "missing_setup"}

	var config: BattleSetupConfig = BattleSetupConfigScript.fromDictionary(snapshot["setup"])
	var validation := config.validate()
	if not validation.success:
		return {"success": false, "reason": "invalid_setup", "errors": validation.errors}

	var simulator: BattleSimulator = BattleSetupFactoryScript.createSimulator(config)
	if version >= 3:
		var initialState: Dictionary = snapshot.get("initialState", {})
		var recordedRevision = int(initialState.get("mapRevision", simulator.state.mapRevision))
		if recordedRevision != simulator.state.mapRevision:
			return {
				"success": false,
				"reason": "map_revision_mismatch",
				"recorded": recordedRevision,
				"current": simulator.state.mapRevision
			}
	simulator.startBattle()

	for entry in snapshot.get("commands", []):
		if not simulator.turnManager.hasNextTurn():
			simulator.turnManager.startNewRound()
		var actorID = simulator.turnManager.startNextTurn()
		if actorID != int(entry.get("actor_id", -1)):
			return {
				"success": false,
				"reason": "turn_order_mismatch",
				"expected": actorID,
				"recorded": entry.get("actor_id", -1)
			}

		var data: Dictionary = entry.get("data", {})
		var command = BattleCommand.from_dictionary(data.get("command", {}))
		if version < 5:
			command.target_pos = _legacyTargetPosition(simulator, actorID, command)
		var result = simulator.executeCommand(
			actorID, command, data.get("source", "replay")
		)
		if not result.success:
			return {
				"success": false,
				"reason": "command_rejected",
				"detail": result.to_dictionary()
			}
		simulator.state.assertValidOccupancy()
		simulator.turnManager.endTurn(actorID)

	return {"success": true, "simulator": simulator}

static func _legacyTargetPosition(
		simulator,
		actorID: int,
		command: BattleCommand) -> Vector2i:
	## Versions 2-4 identified action centers by occupant. Resolve that occupant
	## immediately before executing each command, after all prior replay movement.
	if command.action == "wait":
		return Vector2i(-1, -1)
	if command.target_id == actorID:
		## The actor targeting itself — every Level 1 "Setup" spell does — is the
		## one case whose center moves with the actor. It must resolve to the tile
		## the action is made from, which for a move-first turn is the
		## destination, not the position the actor is standing on right now.
		return _actionOrigin(simulator, actorID, command)
	var target = simulator.state.getMonster(command.target_id)
	if target == null:
		return Vector2i(-1, -1)
	return simulator.state.getMonsterPosition(command.target_id)


static func _actionOrigin(
		simulator,
		actorID: int,
		command: BattleCommand) -> Vector2i:
	if command.order == BattleSimulatorScript.ORDER_ACT_FIRST:
		return simulator.state.getMonsterPosition(actorID)
	if command.move_path.is_empty():
		return simulator.state.getMonsterPosition(actorID)
	var destination = command.move_path.back()
	if destination is Dictionary:
		destination = Vector2i(int(destination.get("x", 0)), int(destination.get("y", 0)))
	if not destination is Vector2i:
		return simulator.state.getMonsterPosition(actorID)
	return destination
