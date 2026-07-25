## Canonical headless battle orchestrator.
## AI and player controllers submit the same validated command dictionaries.

class_name BattleSimulator

const CombatResolverScript = preload("res://src/battle_sim/CombatResolver.gd")
const PassiveSkillResolverScript = preload("res://src/battle_sim/PassiveSkillResolver.gd")
const MapFactoryScript = preload("res://src/factories/MapFactory.gd")
const BattleStateSerializerScript = preload("res://src/battle_sim/BattleStateSerializer.gd")

var state: BattleState
var events: BattleEvents
var turnManager: TurnManager
var movementResolver: MovementResolver
var combatResolver: CombatResolver
var passiveSkillResolver: PassiveSkillResolver
var visualAdapter: IBattleVisualAdapter

var brains: Dictionary = {}
var initialStateSnapshot: Dictionary = {}
var setupSnapshot: Dictionary = {}


func _init(seedValue: int = 0) -> void:
	events = BattleEvents.new()
	state = BattleState.new(seedValue)
	turnManager = TurnManager.new(state, events)
	movementResolver = MovementResolver.new(state, events)
	combatResolver = CombatResolverScript.new(state, events)
	passiveSkillResolver = PassiveSkillResolverScript.new(state, events)
	combatResolver.passiveSkillResolver = passiveSkillResolver


func setVisualAdapter(adapter: IBattleVisualAdapter) -> void:
	if visualAdapter != null and visualAdapter != adapter:
		visualAdapter.disconnectFromEvents()
	visualAdapter = adapter
	adapter.connectToEvents(events)


func setSeed(seedValue: int) -> void:
	state.setSeed(seedValue)


func setSetupSnapshot(setupData: Dictionary) -> void:
	setupSnapshot = setupData.duplicate(true)


func loadMap(mapName: String) -> void:
	var map = MapFactoryScript.createMap(mapName)
	state.setup_board(map.boardSize)
	MapFactoryScript.applyMapToState(map, state)


func spawnMonster(referenceName: String, team: int, pos: Vector2i) -> Monster:
	var monster = MonsterFactory.createMonster(referenceName, state.allocateMonsterID())
	var reference = MonsterReferences.getReference(referenceName)
	var brainClass = _resolveBrainClass(reference.get("BRAIN", "TacticalBrain"))

	assert(state.withinBounds(pos), "Spawning monster out of bounds at %s" % str(pos))
	assert(state.isWalkable(pos), "Spawning monster on blocked tile at %s" % str(pos))
	assert(not state.isOccupied(pos), "Spawning monster on occupied tile at %s" % str(pos))

	var brain = brainClass.new(state, movementResolver, combatResolver)
	monster.brain = brain
	brains[monster.uniqueID] = brain
	state.addMonster(monster, pos, team)

	var stats = {
		"hp": monster.hitpoints,
		"atk": monster.atk,
		"def": monster.def,
		"spd": monster.speed,
		"move": monster.move
	}
	events.monster_spawned.emit(monster.uniqueID, monster.name, team, pos, stats)
	return monster


func _resolveBrainClass(name: String):
	match name:
		"BerserkBrain": return load("res://src/entity_ai/BerserkBrain.gd")
		"MageBrain": return load("res://src/entity_ai/MageBrain.gd")
		"SupportBrain": return load("res://src/entity_ai/SupportBrain.gd")
		_: return load("res://src/entity_ai/TacticalBrain.gd")


func validateCommand(monsterID: int, command: Dictionary) -> Dictionary:
	if state.currentMonsterID != monsterID:
		return {"success": false, "reason": "not_current_turn"}
	var mon = state.getMonster(monsterID)
	if mon == null or not mon.is_alive():
		return {"success": false, "reason": "invalid_monster"}

	var normalizedPath: Array = []
	for stepValue in command.get("move_path", []):
		var step = stepValue
		if stepValue is Dictionary:
			step = Vector2i(int(stepValue.get("x", 0)), int(stepValue.get("y", 0)))
		if not step is Vector2i:
			return {"success": false, "reason": "invalid_path_coordinate"}
		normalizedPath.append(step)

	var moveValidation = movementResolver.validateMovePath(monsterID, normalizedPath)
	if not moveValidation["success"]:
		return moveValidation
	var futurePos: Vector2i = moveValidation["destination"]

	var action: String = command.get("action", "wait")
	if action not in ["wait", "attack", "spell"]:
		return {"success": false, "reason": "invalid_action"}
	var targetID: int = int(command.get("target_id", -1))
	var spellSetIndex: int = int(command.get("spell_set_index", 0))
	var spellIndex: int = int(command.get("spell_index", 0))

	if action == "attack":
		if not combatResolver.getBasicAttackTargetsFrom(monsterID, futurePos).has(targetID):
			return {"success": false, "reason": "invalid_attack_target"}
	elif action == "spell":
		if spellSetIndex < 0 or spellIndex < 0:
			return {"success": false, "reason": "invalid_spell"}
		var targets = combatResolver.getSpellTargetsFrom(
			monsterID, spellSetIndex, spellIndex, futurePos
		)
		if not targets.has(targetID):
			return {"success": false, "reason": "invalid_spell_target"}

	return {
		"success": true,
		"command": {
			"move_path": normalizedPath,
			"action": action,
			"target_id": targetID,
			"spell_set_index": spellSetIndex,
			"spell_index": spellIndex
		}
	}


func executeCommand(monsterID: int, command: Dictionary, source: String = "cpu") -> Dictionary:
	var validation = validateCommand(monsterID, command)
	if not validation["success"]:
		state.add_event("command_rejected", monsterID, int(command.get("target_id", -1)), {
			"source": source,
			"reason": validation.get("reason", "invalid_command")
		})
		return validation

	var normalized: Dictionary = validation["command"]
	state.add_event("command", monsterID, normalized["target_id"], {
		"source": source,
		"command": normalized.duplicate(true)
	})

	if state.hasEffect(monsterID, "petrify"):
		events.monster_skipped_turn.emit(monsterID, "petrify")
		passiveSkillResolver.fireEvent(PassiveSkillResolver.ON_TURN_END, monsterID)
		return {
			"success": true,
			"resolved": false,
			"acted": false,
			"skipped": true,
			"command": normalized,
			"actionResult": {"success": false, "reason": "petrify"}
		}

	var acted = false
	var path: Array = normalized["move_path"]
	if not path.is_empty():
		events.movement_targeted.emit(monsterID, path.back())
		acted = movementResolver.executeMove(monsterID, path) or acted

	var action: String = normalized["action"]
	var targetID: int = normalized["target_id"]
	var actionResult: Dictionary = {"success": true}
	if action in ["attack", "spell"]:
		events.action_targeted.emit(monsterID, targetID, action)

	if action == "attack":
		actionResult = combatResolver.executeBasicAttack(monsterID, targetID)
		acted = actionResult.get("success", false) or acted
	elif action == "spell":
		actionResult = combatResolver.executeCastSpell(
			monsterID,
			targetID,
			normalized["spell_set_index"],
			normalized["spell_index"]
		)
		acted = actionResult.get("success", false) or acted

	passiveSkillResolver.fireEvent(PassiveSkillResolver.ON_TURN_END, monsterID)
	return {
		"success": true,
		"resolved": actionResult.get("success", true),
		"acted": acted,
		"command": normalized,
		"actionResult": actionResult
	}


func executeTurn(monsterID: int) -> bool:
	var mon = state.getMonster(monsterID)
	if mon == null or not mon.is_alive():
		return false
	if state.hasEffect(monsterID, "petrify"):
		return executeCommand(monsterID, {"move_path": [], "action": "wait"}, "cpu").get("acted", false)

	var brain = brains.get(monsterID)
	if brain == null:
		return false
	var decision = brain.decideTurn(monsterID)
	state.add_event("decision", monsterID, decision.get("target_id", -1), decision.duplicate(true))
	var result = executeCommand(monsterID, decision, "cpu")
	if not result.get("success", false):
		push_error("AI command rejected for monster %d: %s" % [monsterID, result.get("reason", "unknown")])
		result = executeCommand(monsterID, {"move_path": [], "action": "wait"}, "cpu_fallback")
	return result.get("acted", false)


func createReplaySnapshot() -> Dictionary:
	var brainClasses = {}
	for monsterID in brains:
		var brain = brains[monsterID]
		brainClasses[str(monsterID)] = brain.get_script().resource_path.get_file().get_basename()

	var commands: Array = []
	for event in state.history:
		if event.get("type", "") == "command":
			commands.append(BattleStateSerializerScript.jsonSafe(event))

	return {
		"version": 2,
		"seed": state.battleSeed,
		"setup": setupSnapshot.duplicate(true),
		"initialState": initialStateSnapshot if not initialStateSnapshot.is_empty() else state.serialize_state(),
		"currentState": state.serialize_state(),
		"turnOrder": turnManager.turnOrder.duplicate(),
		"brainClasses": brainClasses,
		"commands": commands
	}


func restoreReplaySnapshot(snapshot: Dictionary) -> Dictionary:
	if not snapshot.has("currentState"):
		return {"success": false, "reason": "missing_current_state"}

	if visualAdapter != null:
		visualAdapter.disconnectFromEvents()
	visualAdapter = null
	state = BattleStateSerializerScript.deserialize(snapshot["currentState"])
	events = BattleEvents.new()
	turnManager = TurnManager.new(state, events)
	movementResolver = MovementResolver.new(state, events)
	combatResolver = CombatResolverScript.new(state, events)
	passiveSkillResolver = PassiveSkillResolverScript.new(state, events)
	combatResolver.passiveSkillResolver = passiveSkillResolver
	turnManager.turnOrder.clear()
	for monsterID in snapshot.get("turnOrder", []):
		turnManager.turnOrder.append(int(monsterID))
	initialStateSnapshot = snapshot.get("initialState", {}).duplicate(true)
	setupSnapshot = snapshot.get("setup", {}).duplicate(true)
	brains.clear()

	var brainClasses: Dictionary = snapshot.get("brainClasses", {})
	for monsterID in state.monsters:
		var brainName: String = brainClasses.get(str(monsterID), "TacticalBrain")
		var brainClass = _resolveBrainClass(brainName)
		var brain = brainClass.new(state, movementResolver, combatResolver)
		state.monsters[monsterID].brain = brain
		brains[monsterID] = brain

	return {"success": true}


func emitRestoredBattle() -> void:
	for monsterID in state.monsters:
		var monster = state.monsters[monsterID]
		if not monster.is_alive():
			continue
		var stats = {
			"hp": monster.hitpoints,
			"atk": monster.atk,
			"def": monster.def,
			"spd": monster.speed,
			"move": monster.move
		}
		events.monster_spawned.emit(
			monsterID,
			monster.name,
			monster.team,
			state.getMonsterPosition(monsterID),
			stats
		)
	var monsterList = state.getAliveMonsterIDs()
	events.battle_started.emit(state.boardSize, monsterList)

func startBattle() -> void:
	if initialStateSnapshot.is_empty():
		initialStateSnapshot = state.serialize_state()
	var monsterList = []
	for id in state.monsters:
		monsterList.append(id)
	events.battle_started.emit(state.boardSize, monsterList)


func runFullBattle(maxRounds: int = 50) -> int:
	startBattle()
	for _roundIndex in range(maxRounds):
		turnManager.startNewRound()
		var actionsThisRound = 0
		while turnManager.hasNextTurn():
			var monsterID = turnManager.startNextTurn()
			if monsterID == -1:
				break
			if executeTurn(monsterID):
				actionsThisRound += 1
			turnManager.endTurn(monsterID)

			var winner = checkWinCondition()
			if winner != -1:
				events.battle_ended.emit(winner)
				return winner

		events.round_ended.emit(state.roundCount)
		if actionsThisRound == 0:
			break

	var winner = _determineWinnerByNumbers()
	events.battle_ended.emit(winner)
	return winner


func checkWinCondition() -> int:
	var aliveTeams = []
	for team in state.teamRosters:
		if not state.isTeamDefeated(team):
			aliveTeams.append(team)
	if aliveTeams.size() == 1:
		return aliveTeams[0]
	if aliveTeams.is_empty():
		return 0
	return -1


func _determineWinnerByNumbers() -> int:
	var bestTeam = -1
	var bestCount = -1
	for team in state.teamRosters:
		var alive = state.getAliveMonsterIDs(team)
		if alive.size() > bestCount:
			bestCount = alive.size()
			bestTeam = team
	return bestTeam
