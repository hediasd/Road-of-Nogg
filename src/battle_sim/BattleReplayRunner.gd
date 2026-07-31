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

	var config = BattleSetupConfigScript.fromDictionary(snapshot["setup"])
	var validation = config.validate()
	if not validation["success"]:
		return {"success": false, "reason": "invalid_setup", "errors": validation["errors"]}

	var simulator = BattleSetupFactoryScript.createSimulator(config)
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
