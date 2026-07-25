extends SceneTree

const BattleSetupConfigScript = preload("res://src/battle_sim/BattleSetupConfig.gd")
const BattleSetupFactoryScript = preload("res://src/battle_sim/BattleSetupFactory.gd")
const BattleSetupPresetsScript = preload("res://src/factories/BattleSetupPresets.gd")
const BattleReplayRunnerScript = preload("res://src/battle_sim/BattleReplayRunner.gd")
const BattleSimulatorScript = preload("res://src/battle_sim/BattleSimulator.gd")
const MapReferencesScript = preload("res://src/factories/MapReferences.gd")
const MonsterVisualRegistryScript = preload("res://src/presentation/MonsterVisualRegistry.gd")


func _init() -> void:
	call_deferred("_run")


func _run() -> void:
	if MapReferencesScript.getNames().size() != 3:
		_fail("map catalog size mismatch")
		return

	var randomA = BattleSetupPresetsScript.getRoster("Random Balanced", 1, 42)
	var randomB = BattleSetupPresetsScript.getRoster("Random Balanced", 1, 42)
	if randomA != randomB or randomA.size() != 4:
		_fail("random balanced preset is not deterministic")
		return

	var setupCount = 0
	for mapName in MapReferencesScript.getNames():
		for presetName in BattleSetupPresetsScript.getPresetNames():
			var mapConfig = _defaultConfig(mapName)
			if presetName == BattleSetupPresetsScript.PRESET_RANDOM_BALANCED:
				mapConfig.team1 = BattleSetupPresetsScript.getRoster(presetName, 1, mapConfig.seed)
				mapConfig.team2 = BattleSetupPresetsScript.getRoster(presetName, 2, mapConfig.seed)
			var validation = mapConfig.validate()
			if not validation["success"]:
				_fail("%s/%s setup invalid: %s" % [mapName, presetName, validation["errors"]])
				return
			var mapSimulator = BattleSetupFactoryScript.createSimulator(mapConfig)
			if mapSimulator.state.getAliveMonsterIDs().size() != 8:
				_fail("%s/%s did not deploy eight monsters" % [mapName, presetName])
				return
			setupCount += 1

	var duplicateConfig = _defaultConfig("Meadow")
	duplicateConfig.team1.assign(["Snowzilla", "Snowzilla", "Snowzilla", "Snowzilla"])
	if not duplicateConfig.validate()["success"]:
		_fail("duplicate monsters should be allowed")
		return

	var actionFailure = _checkValidatedActions()
	if not actionFailure.is_empty():
		_fail(actionFailure)
		return

	var config = _defaultConfig("Meadow")
	config.battleMode = BattleSetupConfigScript.MODE_PLAYER_VS_CPU
	var simulator = BattleSetupFactoryScript.createSimulator(config)
	simulator.startBattle()
	simulator.turnManager.startNewRound()

	var playerID = -1
	while simulator.turnManager.hasNextTurn():
		var actorID = simulator.turnManager.startNextTurn()
		var actor = simulator.state.getMonster(actorID)
		if actor.team == 1:
			playerID = actorID
			break
		simulator.executeTurn(actorID)
		simulator.turnManager.endTurn(actorID)

	if playerID == -1:
		_fail("no Team 1 player turn was reached")
		return

	var startPos = simulator.state.getMonsterPosition(playerID)
	var invalidResult = simulator.executeCommand(playerID, {
		"move_path": [startPos + Vector2i(2, 0)],
		"action": "wait"
	}, "player")
	if invalidResult.get("success", true):
		_fail("non-contiguous player path was accepted")
		return
	if simulator.state.getMonsterPosition(playerID) != startPos:
		_fail("rejected command mutated position")
		return

	var reachable = simulator.movementResolver.getReachablePositions(playerID)
	var path: Array = []
	if not reachable.is_empty():
		path = simulator.movementResolver.findPath(startPos, reachable[0], 100)
	var playerResult = simulator.executeCommand(playerID, {
		"move_path": path,
		"action": "wait",
		"target_id": -1
	}, "player")
	if not playerResult.get("success", false):
		_fail("valid player wait command was rejected: %s" % playerResult)
		return
	simulator.turnManager.endTurn(playerID)

	var snapshot = simulator.createReplaySnapshot()
	if snapshot["setup"].is_empty() or snapshot["commands"].is_empty():
		_fail("replay snapshot omitted setup or commands")
		return
	var sawPlayerCommand = false
	for entry in snapshot["commands"]:
		if entry.get("data", {}).get("source", "") == "player":
			sawPlayerCommand = true
	if not sawPlayerCommand:
		_fail("replay snapshot omitted the player command")
		return

	var replay = BattleReplayRunnerScript.replay(snapshot)
	if not replay.get("success", false):
		_fail("command replay failed: %s" % replay)
		return

	var restored = BattleSimulatorScript.new()
	var restoreResult = restored.restoreReplaySnapshot(snapshot)
	if not restoreResult.get("success", false):
		_fail("snapshot restoration failed")
		return
	if restored.state.serialize_state() != snapshot["currentState"]:
		_fail("restored state differs from saved state")
		return

	var encodedSnapshot = JSON.stringify(snapshot)
	var parsedSnapshot = JSON.parse_string(encodedSnapshot)
	if not parsedSnapshot is Dictionary:
		_fail("replay snapshot is not JSON serializable")
		return
	var jsonReplay = BattleReplayRunnerScript.replay(parsedSnapshot)
	if not jsonReplay.get("success", false):
		_fail("JSON command replay failed: %s" % jsonReplay)
		return
	var jsonRestored = BattleSimulatorScript.new()
	if not jsonRestored.restoreReplaySnapshot(parsedSnapshot).get("success", false):
		_fail("JSON snapshot restoration failed")
		return
	for team in jsonRestored.state.teamRosters:
		for monsterID in jsonRestored.state.teamRosters[team]:
			if typeof(monsterID) != TYPE_INT:
				_fail("JSON roster IDs were not normalized to integers")
				return
	for monsterID in jsonRestored.turnManager.turnOrder:
		if typeof(monsterID) != TYPE_INT:
			_fail("JSON turn-order IDs were not normalized to integers")
			return

	if not MonsterVisualRegistryScript.getRegisteredNames().is_empty():
		_fail("authored visual mappings unexpectedly changed the placeholder roster")
		return
	if MonsterVisualRegistryScript.instantiateVisual("Snowzilla") != null:
		_fail("Snowzilla did not use the restored procedural placeholder")
		return

	_succeed("PLAYABLE_BATTLE_CORE_OK setups=%d commands=%d" % [setupCount, snapshot["commands"].size()])


func _checkValidatedActions() -> String:
	var attackSimulator = BattleSimulatorScript.new(11)
	attackSimulator.loadMap("Meadow")
	var attacker = attackSimulator.spawnMonster("Gigasaurus", 1, Vector2i(5, 5))
	var defender = attackSimulator.spawnMonster("Smoke Cloud", 2, Vector2i(6, 5))
	attackSimulator.state.currentMonsterID = attacker.uniqueID
	var startingHP = defender.hitpoints
	var attackResult = attackSimulator.executeCommand(attacker.uniqueID, {
		"move_path": [], "action": "attack", "target_id": defender.uniqueID
	}, "test")
	if not attackResult.get("success", false) or defender.hitpoints >= startingHP:
		return "validated basic attack did not damage its target"

	var reactionSimulator = BattleSimulatorScript.new(13)
	reactionSimulator.loadMap("Meadow")
	var fragileAttacker = reactionSimulator.spawnMonster("Dump", 1, Vector2i(5, 5))
	var reactiveTarget = reactionSimulator.spawnMonster("Envoy of Lightning", 2, Vector2i(6, 5))
	reactionSimulator.state.currentMonsterID = fragileAttacker.uniqueID
	var reactionResult = reactionSimulator.executeCommand(fragileAttacker.uniqueID, {
		"move_path": [], "action": "attack", "target_id": reactiveTarget.uniqueID
	}, "test")
	if not reactionResult.get("success", false) or reactionResult.get("resolved", true):
		return "accepted command was relabeled when a reactive passive defeated its actor"
	if reactionResult.get("actionResult", {}).get("reason", "") != "attacker_died_to_passive":
		return "reactive command fizzle did not retain its action result"

	var spellSimulator = BattleSimulatorScript.new(12)
	spellSimulator.loadMap("Meadow")
	var caster = spellSimulator.spawnMonster("Mage Dragon", 1, Vector2i(5, 5))
	var spellTarget = spellSimulator.spawnMonster("Smoke Cloud", 2, Vector2i(8, 5))
	spellSimulator.state.currentMonsterID = caster.uniqueID
	startingHP = spellTarget.hitpoints
	var spellResult = spellSimulator.executeCommand(caster.uniqueID, {
		"move_path": [],
		"action": "spell",
		"target_id": spellTarget.uniqueID,
		"spell_set_index": 0,
		"spell_index": 2
	}, "test")
	if not spellResult.get("success", false) or spellTarget.hitpoints >= startingHP:
		return "validated spell command did not damage its target"

	return ""


func _defaultConfig(mapName: String):
	var config = BattleSetupConfigScript.new()
	config.mapName = mapName
	config.seed = 42
	config.team1 = BattleSetupPresetsScript.DEFAULT_TEAM_1.duplicate()
	config.team2 = BattleSetupPresetsScript.DEFAULT_TEAM_2.duplicate()
	return config


func _succeed(message: String) -> void:
	call_deferred("_finish", 0, message)


func _fail(reason: String) -> void:
	push_error("PLAYABLE_BATTLE_CORE_FAILED: %s" % reason)
	call_deferred("_finish", 1, "")


func _finish(exitCode: int, message: String) -> void:
	if not message.is_empty():
		print(message)
	quit(exitCode)