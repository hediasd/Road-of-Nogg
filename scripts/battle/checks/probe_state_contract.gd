extends SceneTree

const ConfigScript = preload("res://src/battle_sim/BattleSetupConfig.gd")
const SetupScript = preload("res://src/battle_sim/BattleSetupFactory.gd")
const SimulatorScript = preload("res://src/battle_sim/BattleSimulator.gd")
const SerializerScript = preload("res://src/battle_sim/BattleStateSerializer.gd")
const RevisionScript = preload("res://src/entity_ai/StateRevision.gd")
const OutputPathsScript = preload("res://src/presentation/BattleOutputPaths.gd")
const SpellFactoryScript = preload("res://src/factories/SpellFactory.gd")

const FIXTURE := "res://scripts/battle/fixtures/ai/state_contract.json"
const OUTPUT_NAME := "ai_state_contract.json"

var failures: Array[String] = []


func _init() -> void:
	var fixtureValue = JSON.parse_string(FileAccess.get_file_as_string(FIXTURE))
	_check(fixtureValue is Dictionary, "state fixture could not be parsed")
	if not fixtureValue is Dictionary:
		_finish()
		return
	var fixture: Dictionary = fixtureValue
	_check(SerializerScript.compatibilityError({"version": 7, "rngState": 5.0}) != "",
		"ambiguous version 7 disk RNG was silently accepted")
	_check(SerializerScript.compatibilityError({"version": 8, "rngState": 5.0}) != "",
		"numeric version 8 RNG was silently accepted")
	var outputPath: String = OutputPathsScript.pathFor(OutputPathsScript.BATTLES, OUTPUT_NAME)
	if FileAccess.file_exists(outputPath):
		var previousValue = JSON.parse_string(FileAccess.get_file_as_string(outputPath))
		_check(previousValue is Dictionary, "previous process output was invalid JSON")
		if previousValue is Dictionary and int(previousValue.get("probeRevision", 0)) == int(fixture["probe_revision"]):
			_checkRestored(SerializerScript.deserialize(previousValue["state"]), fixture,
				"prior process")

	var config = ConfigScript.new()
	config.scenarioPath = str(fixture["scenario"])
	config.seed = int(fixture["seed"])
	var setup: Dictionary = SetupScript.createHexState(config)
	_check(bool(setup.get("success", false)), "scenario setup failed")
	if not bool(setup.get("success", false)):
		_finish()
		return
	var sim: BattleSimulator = SimulatorScript.new(config.seed)
	sim.configureHexState(setup["state"], setup["scenario"], config.serialize())
	sim.startBattle()
	var opened: Dictionary = sim.startNextSideTurn("probe")
	_check(bool(opened.get("success", false)), "side could not open")
	if not bool(opened.get("success", false)):
		_finish()
		return
	var actorID := -1
	for candidateID in sim.eligibleSideUnitIDs():
		var candidate: Monster = sim.state.getMonster(candidateID)
		if not candidate.spellSets.is_empty() and not candidate.spellSets[0].is_empty():
			actorID = candidateID
			break
	_check(actorID >= 0, "active side has no actor with a spell")
	if actorID < 0:
		_finish()
		return

	var state: BattleState = sim.state
	var actor: Monster = state.getMonster(actorID)
	var firstSpell: Spell = actor.spellSets[0][0]
	var catalogSpell: Spell = SpellFactoryScript.createSpell(firstSpell.name)
	var catalogRange := catalogSpell.range
	var contentBefore := SimulatorScript.computeContentFingerprint(state)
	var revisionBefore := state.mutationRevision
	var tokenBefore := RevisionScript.capture(state)
	var changedSpell := Spell.new({})
	changedSpell.restoreRuntime(firstSpell.serializeRuntime())
	changedSpell.range = catalogRange + 3
	changedSpell.targetType = "self"
	changedSpell.heals = true
	changedSpell.heal_amount = int(fixture["heal_amount"])
	changedSpell.cooldown = 0
	changedSpell.effects = [{"type": "probe_effect", "value": 19}]
	var loadout: Array = []
	for spellSet in actor.spellSets:
		loadout.append(spellSet.duplicate())
	loadout[0][0] = changedSpell
	var runtimePassive := PassiveSkill.new({
		"NAME": "Runtime Probe", "TRIGGER": "PROBE_ONLY",
		"EFFECT_TYPE": "none", "VALUE": 0.25, "ELEMENT": "none", "RADIUS": 2,
	})
	var passives: Array = actor.passives.duplicate()
	passives.append(runtimePassive)
	state.setMonsterAbilities(actorID, loadout, passives)
	_check(SpellFactoryScript.createSpell(firstSpell.name).range == catalogRange,
		"runtime spell edit mutated catalog content")
	_check(SimulatorScript.computeContentFingerprint(state) == contentBefore,
		"runtime spell edit changed catalog identity")
	_check(state.mutationRevision > revisionBefore, "ability mutation did not advance revision")
	_check(RevisionScript.capture(state) != tokenBefore,
		"ability mutation did not invalidate decision token")
	var actorPos: Vector2i = state.getMonsterPosition(actorID)
	state.setMovementCost(actorPos, int(fixture["movement_cost"]))
	state.setHeight(actorPos, 1)
	var terrainPos := Vector2i(-1, -1)
	for candidatePos: Vector2i in state.battleMap.validCells():
		if not state.isOccupied(candidatePos) and int(state.terrainBoard.at(candidatePos)) == BattleState.TERRAIN_CLEAR:
			terrainPos = candidatePos
			break
	_check(terrainPos != Vector2i(-1, -1), "scenario has no free clear terrain cell")
	if terrainPos != Vector2i(-1, -1):
		state.setTerrainState(terrainPos, BattleState.TERRAIN_OBSTACLE)
	state.addEffect(actorID, "runtime_probe", 2)
	actor.hitpoints = maxi(1, actor.max_hitpoints - 20)
	var largeValue := int(str(fixture["large_integer"]))
	state.rng.state = largeValue
	state.nextMonsterID = largeValue
	state.add_event("probe_large_id", largeValue, -1)
	var snapshot := sim.createReplaySnapshot()
	_check(bool(snapshot.get("success", false)), "state snapshot failed")
	if not bool(snapshot.get("success", false)):
		_finish()
		return
	var stateData: Dictionary = snapshot["currentState"]
	_check(int(stateData["version"]) == 8, "state schema is not version 8")
	_check(stateData["rngState"] == str(largeValue), "RNG state is not decimal text")
	_check(stateData["nextMonsterID"] is Dictionary,
		"large allocator value lacks lossless encoding")
	OutputPathsScript.ensureParent(outputPath)
	var file := FileAccess.open(outputPath, FileAccess.WRITE)
	_check(file != null, "could not write state artifact")
	if file == null:
		_finish()
		return
	file.store_string(JSON.stringify({
		"probeRevision": int(fixture["probe_revision"]),
		"state": stateData,
	}, "", true, true))
	file.flush()
	file.close()
	var diskValue = JSON.parse_string(FileAccess.get_file_as_string(outputPath))
	_check(diskValue is Dictionary, "disk snapshot could not be parsed")
	if not diskValue is Dictionary:
		_finish()
		return
	_check(int(diskValue.get("probeRevision", 0)) == int(fixture["probe_revision"]),
		"disk artifact used another fixture revision")
	var restoredState: BattleState = SerializerScript.deserialize(diskValue["state"])
	_checkRestored(restoredState, fixture, "disk round trip")

	var restoredSim: BattleSimulator = SimulatorScript.new()
	snapshot["currentState"] = diskValue["state"]
	var restore: Dictionary = restoredSim.restoreReplaySnapshot(snapshot)
	_check(bool(restore.get("success", false)), "simulator restore rejected runtime state")
	if bool(restore.get("success", false)):
		_check(restoredSim.state.timelineGeneration > state.timelineGeneration,
			"restore did not advance timeline generation")
		_check(RevisionScript.capture(restoredSim.state) != RevisionScript.capture(state),
			"equal restored state accepted an old decision token")
		var stateDifference := _firstDifference(state.serialize_state(),
			restoredSim.state.serialize_state())
		_check(stateDifference.is_empty(),
			"restored simulator changed gameplay state: %s" % stateDifference)
		_castSelfHeal(sim, actorID)
		_castSelfHeal(restoredSim, actorID)
		var continuedDifference := _firstDifference(sim.state.serialize_state(),
			restoredSim.state.serialize_state())
		_check(continuedDifference.is_empty(),
			"live and restored continuation diverged: %s" % continuedDifference)
		_check(sim.state.rng.randi() == restoredSim.state.rng.randi(),
			"next RNG draw diverged")
		_check(sim.state.allocateMonsterID() == restoredSim.state.allocateMonsterID(),
			"next entity ID diverged")
	_checkWithdrawalState(SerializerScript.deserialize(stateData))
	_finish()


func _checkRestored(state: BattleState, fixture: Dictionary, source: String) -> void:
	var largeValue := int(str(fixture["large_integer"]))
	_check(state.rng.state == largeValue, "%s lost RNG state" % source)
	_check(state.nextMonsterID == largeValue, "%s lost allocator" % source)
	_check(not state.history.is_empty() and int(state.history.back().get("actor_id", 0)) == largeValue,
		"%s lost event identity" % source)
	var actorID := -1
	for id in state.monsters:
		var monster: Monster = state.getMonster(id)
		if not monster.spellSets.is_empty() and not monster.spellSets[0].is_empty():
			var effects: Array = monster.spellSets[0][0].effects
			if effects.size() == 1 and str(effects[0].get("type", "")) == "probe_effect" and int(effects[0].get("value", 0)) == 19:
				actorID = id
				break
	_check(actorID >= 0, "%s lost runtime spell" % source)
	if actorID < 0:
		return
	var actor: Monster = state.getMonster(actorID)
	var spell: Spell = actor.spellSets[0][0]
	_check(spell.heals and spell.heal_amount == int(fixture["heal_amount"]),
		"%s lost runtime spell behavior" % source)
	_check(spell.targetType == "self", "%s lost spell target type" % source)
	_check(actor.passives.back().name == "Runtime Probe" and actor.passives.back().radius == 2,
		"%s lost runtime passive" % source)
	var pos: Vector2i = state.getMonsterPosition(actorID)
	_check(int(state.movementCostBoard.at(pos)) == int(fixture["movement_cost"]),
		"%s lost movement cost" % source)
	_check(state.getHeight(pos) == 1, "%s lost height" % source)
	_check(state.hasEffect(actorID, "runtime_probe"), "%s lost status effect" % source)
	var changedTerrain := false
	for cell: Vector2i in state.battleMap.validCells():
		if int(state.battleMap.terrainStateCodeAt(cell)) == BattleState.TERRAIN_CLEAR and int(state.terrainBoard.at(cell)) == BattleState.TERRAIN_OBSTACLE and not state.isOccupied(cell):
			changedTerrain = true
	_check(changedTerrain, "%s lost terrain change" % source)
	state.assertValidOccupancy()


func _checkWithdrawalState(state: BattleState) -> void:
	var partyID := 20
	var commanderID := 200
	_check(state.monsterPositions.has(commanderID), "withdrawal fixture lacks commander")
	if not state.monsterPositions.has(commanderID):
		return
	state.withdrawMonster(commanderID)
	state.withdrawnPartyIDs[partyID] = true
	state.markMutation()
	var restored := SerializerScript.deserialize(state.serialize_state())
	_check(restored.isMonsterWithdrawn(commanderID) and restored.isPartyWithdrawn(partyID),
		"withdrawal state did not survive restoration")
	_check(not restored.monsterPositions.has(commanderID),
		"withdrawn commander reappeared on the board")
	restored.assertValidOccupancy()


func _castSelfHeal(sim: BattleSimulator, actorID: int) -> void:
	_check(bool(sim.selectUnit(actorID, "probe").get("success", false)),
		"continuation could not select actor")
	var command := BattleCommand.new([], "spell", actorID, 0, 0, "move_first",
		sim.state.getMonsterPosition(actorID))
	var result: BattleCommandResult = sim.executeCommand(actorID, command, "probe")
	_check(result.success and result.resolved,
		"runtime self-heal did not resolve through canonical simulator")


func _same(a, b) -> bool:
	return SimulatorScript._canonicalJSON(a) == SimulatorScript._canonicalJSON(b)


func _firstDifference(a, b, path: String = "state") -> String:
	if a is Dictionary and b is Dictionary:
		if a.size() != b.size():
			return "%s key count %d versus %d" % [path, a.size(), b.size()]
		for key in a:
			if not b.has(key):
				return "%s missing key %s" % [path, str(key)]
			var child := _firstDifference(a[key], b[key], "%s.%s" % [path, str(key)])
			if not child.is_empty():
				return child
		return ""
	if a is Array and b is Array:
		if a.size() != b.size():
			return "%s length %d versus %d" % [path, a.size(), b.size()]
		for index in range(a.size()):
			var child := _firstDifference(a[index], b[index], "%s[%d]" % [path, index])
			if not child.is_empty():
				return child
		return ""
	if a is float and b is int or a is int and b is float:
		if float(a) == float(b):
			return ""
	if a == b:
		return ""
	return "%s %s versus %s" % [path, str(a), str(b)]


func _check(condition: bool, message: String) -> void:
	if not condition:
		failures.append(message)


func _finish() -> void:
	if not failures.is_empty():
		for failure in failures:
			printerr("AI_STATE_CONTRACT_FAILURE: %s" % failure)
		quit(1)
		return
	print("AI_STATE_CONTRACT_OK")
	quit(0)
