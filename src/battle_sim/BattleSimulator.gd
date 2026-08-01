## Canonical headless battle orchestrator.
## AI and player controllers submit the same validated BattleCommand values.

class_name BattleSimulator

## Which of the two turn phases resolved first. Recorded on every command so a
## replay resolves them in the order they actually happened.
const ORDER_MOVE_FIRST := "move_first"
const ORDER_ACT_FIRST := "act_first"

## Replay version 5 makes target_pos canonical. Versions 2-4 derive it from
## target_id immediately before each legacy command executes.
const REPLAY_VERSION := 5
const REPLAY_MIN_VERSION := 2

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

## Accumulates the phases of the turn currently in progress so that a turn
## resolved incrementally still records exactly one `command` history event, at
## finishTurn(). The interactive player path resolves movement and the action as
## separate steps; CPU brains and replay submit both at once through
## executeCommand(). Both routes land here.
##
## Empty when no turn is being accumulated. `origin` is the position the actor
## occupied when the turn opened, which is what undoMovePhase() restores.
var _turnAccumulator: Dictionary = {}


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


func spawnMonster(referenceName: String, team: int, pos: Vector2i, level: int = 1) -> Monster:
	var monster = MonsterFactory.createMonster(referenceName, state.allocateMonsterID(), level)
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
		"move": monster.move,
		"level": monster.level,
		"jump": monster.jump,
		"height": state.getHeight(pos)
	}
	events.monster_spawned.emit(monster.uniqueID, monster.name, team, pos, stats)
	return monster


func _resolveBrainClass(name: String):
	match name:
		"BerserkBrain": return load("res://src/entity_ai/BerserkBrain.gd")
		"MageBrain": return load("res://src/entity_ai/MageBrain.gd")
		"SupportBrain": return load("res://src/entity_ai/SupportBrain.gd")
		_: return load("res://src/entity_ai/TacticalBrain.gd")


func validateCommand(monsterID: int, command: BattleCommand) -> BattleCommandResult:
	if command == null:
		return BattleCommandResult.rejected("missing_command")
	if state.currentMonsterID != monsterID:
		return BattleCommandResult.rejected("not_current_turn")
	var mon = state.getMonster(monsterID)
	if mon == null or not mon.is_alive():
		return BattleCommandResult.rejected("invalid_monster")

	var normalizedPath = _normalizePath(command.move_path)
	if normalizedPath == null:
		return BattleCommandResult.rejected("invalid_path_coordinate")
	var moveValidation = movementResolver.validateMovePath(monsterID, normalizedPath)
	if not moveValidation["success"]:
		return BattleCommandResult.rejected(moveValidation.get("reason", "invalid_move"))
	var futurePos: Vector2i = moveValidation["destination"]

	var action: String = command.action
	if action not in ["wait", "attack", "spell"]:
		return BattleCommandResult.rejected("invalid_action")
	var targetPos: Vector2i = command.target_pos
	var spellSetIndex: int = command.spell_set_index
	var spellIndex: int = command.spell_index
	var order: String = command.order
	if order not in [ORDER_MOVE_FIRST, ORDER_ACT_FIRST]:
		return BattleCommandResult.rejected("invalid_order")
	var actionPos: Vector2i = (
		state.getMonsterPosition(monsterID) if order == ORDER_ACT_FIRST else futurePos
	)

	if action == "attack":
		if not combatResolver.canBasicAttackPositionFrom(monsterID, actionPos, targetPos):
			return BattleCommandResult.rejected("invalid_attack_target")
	elif action == "spell":
		if spellSetIndex < 0 or spellIndex < 0:
			return BattleCommandResult.rejected("invalid_spell")
		if not combatResolver.canSpellTargetPositionFrom(
				monsterID, spellSetIndex, spellIndex, actionPos, targetPos):
			return BattleCommandResult.rejected("invalid_spell_target")

	var targetID = _targetIDAtActionCenter(
		monsterID, action, spellSetIndex, spellIndex, actionPos, targetPos
	)
	return BattleCommandResult.accepted(BattleCommand.new(
		normalizedPath,
		action,
		targetID,
		spellSetIndex,
		spellIndex,
		order,
		targetPos
	))

## --- Incremental turn execution -------------------------------------------
##
## A turn is made of at most one movement phase and at most one action phase,
## in either order. The interactive player path resolves them one at a time so
## each can animate before the next is chosen; CPU brains and replay submit
## both together through executeCommand(). Either way the turn produces exactly
## one `command` history event, written by finishTurn().


func _ensureTurnAccumulator(monsterID: int, source: String) -> Dictionary:
	if _turnAccumulator.get("monster_id", -1) != monsterID:
		_turnAccumulator = {
			"monster_id": monsterID,
			"origin": state.getMonsterPosition(monsterID),
			"move_path": [],
			"has_moved": false,
			"has_acted": false,
			"action": "wait",
			"target_id": -1,
			"target_pos": Vector2i(-1, -1),
			"spell_set_index": 0,
			"spell_index": 0,
			"order": ORDER_MOVE_FIRST,
			"source": source,
			"acted": false,
			"skipped": false,
			"action_result": {"success": true}
		}
	return _turnAccumulator


func _guardPhase(monsterID: int) -> Dictionary:
	if state.currentMonsterID != monsterID:
		return {"success": false, "reason": "not_current_turn"}
	var mon = state.getMonster(monsterID)
	if mon == null or not mon.is_alive():
		return {"success": false, "reason": "invalid_monster"}
	if state.hasEffect(monsterID, "petrify"):
		return {"success": false, "reason": "petrify"}
	return {"success": true}


func turnPhaseState(monsterID: int) -> Dictionary:
	## What the interactive controller needs to build its menu: which phases are
	## still available, and whether the move can still be taken back.
	var accumulator = _turnAccumulator
	if accumulator.get("monster_id", -1) != monsterID:
		return {"has_moved": false, "has_acted": false, "can_undo_move": false}
	var hasMoved: bool = accumulator["has_moved"]
	var hasActed: bool = accumulator["has_acted"]
	return {
		"has_moved": hasMoved,
		"has_acted": hasActed,
		"can_undo_move": hasMoved and not hasActed
	}


func executeMovePhase(monsterID: int, path: Array, source: String = "player") -> Dictionary:
	var guard = _guardPhase(monsterID)
	if not guard["success"]:
		return _rejectPhase(monsterID, source, guard["reason"])

	var accumulator = _ensureTurnAccumulator(monsterID, source)
	if accumulator["has_moved"]:
		return _rejectPhase(monsterID, source, "move_already_spent")

	var normalizedPath = _normalizePath(path)
	if normalizedPath == null:
		return _rejectPhase(monsterID, source, "invalid_path_coordinate")
	var moveValidation = movementResolver.validateMovePath(monsterID, normalizedPath)
	if not moveValidation["success"]:
		return _rejectPhase(monsterID, source, moveValidation["reason"])

	var moved = false
	if not normalizedPath.is_empty():
		events.movement_targeted.emit(monsterID, normalizedPath.back())
		moved = movementResolver.executeMove(monsterID, normalizedPath)

	if not accumulator["has_acted"]:
		accumulator["order"] = ORDER_MOVE_FIRST
	accumulator["has_moved"] = true
	accumulator["move_path"] = normalizedPath
	accumulator["acted"] = accumulator["acted"] or moved
	return {
		"success": true,
		"moved": moved,
		"destination": moveValidation["destination"]
	}


func undoMovePhase(monsterID: int) -> Dictionary:
	## Rewinds the movement phase to where the turn began. Only legal while the
	## action phase is unspent: an attack or spell is validated against range,
	## line of sight, and elevation from the tile it was made from, so rewinding
	## that tile afterwards would retroactively falsify a resolution that has
	## already dealt damage.
	##
	## Nothing in the game reacts to movement — PassiveSkillResolver triggers on
	## ON_TURN_END, ON_DEATH, ON_DAMAGE_TAKEN, and ON_TARGETED only — so there
	## are no side effects to unwind beyond the position itself.
	var guard = _guardPhase(monsterID)
	if not guard["success"]:
		return {"success": false, "reason": guard["reason"]}

	var accumulator = _turnAccumulator
	if accumulator.get("monster_id", -1) != monsterID or not accumulator["has_moved"]:
		return {"success": false, "reason": "no_move_to_undo"}
	if accumulator["has_acted"]:
		return {"success": false, "reason": "action_already_resolved"}

	var origin: Vector2i = accumulator["origin"]
	var currentPos = state.getMonsterPosition(monsterID)
	if currentPos != origin:
		state.moveMonsterTo(monsterID, origin)
		state.add_event("undo_move", monsterID, -1, {"from": currentPos, "to": origin})
		# Replayed through the ordinary movement event so presentation walks the
		# actor back along the way it came rather than teleporting it.
		var returnPath: Array = accumulator["move_path"].slice(
			0, maxi(accumulator["move_path"].size() - 1, 0)
		)
		returnPath.reverse()
		returnPath.append(origin)
		events.monster_moved.emit(monsterID, returnPath)

	accumulator["has_moved"] = false
	accumulator["move_path"] = []
	accumulator["order"] = ORDER_MOVE_FIRST
	return {"success": true, "destination": origin}


func executeActionPhase(
		monsterID: int,
		action: String,
		targetPos: Vector2i = Vector2i(-1, -1),
		spellSetIndex: int = 0,
		spellIndex: int = 0,
		source: String = "player") -> Dictionary:
	var guard = _guardPhase(monsterID)
	if not guard["success"]:
		return _rejectPhase(monsterID, source, guard["reason"])
	if action not in ["wait", "attack", "spell"]:
		return _rejectPhase(monsterID, source, "invalid_action")

	var accumulator = _ensureTurnAccumulator(monsterID, source)
	if accumulator["has_acted"]:
		return _rejectPhase(monsterID, source, "action_already_spent")
	var fromPos = state.getMonsterPosition(monsterID)
	if action == "attack":
		if not combatResolver.canBasicAttackPositionFrom(monsterID, fromPos, targetPos):
			return _rejectPhase(monsterID, source, "invalid_attack_target")
	elif action == "spell":
		if spellSetIndex < 0 or spellIndex < 0:
			return _rejectPhase(monsterID, source, "invalid_spell")
		if not combatResolver.canSpellTargetPositionFrom(
				monsterID, spellSetIndex, spellIndex, fromPos, targetPos):
			return _rejectPhase(monsterID, source, "invalid_spell_target")

	var targetID = _targetIDAtActionCenter(
		monsterID, action, spellSetIndex, spellIndex, fromPos, targetPos
	)
	var actionResult: Dictionary = {"success": true}
	if action in ["attack", "spell"]:
		events.action_targeted.emit(monsterID, targetPos, targetID, action)
	if action == "attack":
		actionResult = combatResolver.executeBasicAttack(monsterID, targetPos)
	elif action == "spell":
		actionResult = combatResolver.executeCastSpell(
			monsterID, targetPos, spellSetIndex, spellIndex
		)

	if not accumulator["has_moved"]:
		accumulator["order"] = ORDER_ACT_FIRST
	accumulator["has_acted"] = true
	accumulator["action"] = action
	accumulator["target_id"] = targetID
	accumulator["target_pos"] = targetPos
	accumulator["spell_set_index"] = spellSetIndex
	accumulator["spell_index"] = spellIndex
	accumulator["action_result"] = actionResult
	accumulator["acted"] = accumulator["acted"] or actionResult.get("success", false)
	return {"success": true, "actionResult": actionResult}

func finishTurn(monsterID: int, source: String = "player") -> BattleCommandResult:
	## Closes the turn: writes the single aggregate command event and fires the
	## end-of-turn passives exactly once, however many phases actually ran.
	var accumulator = _ensureTurnAccumulator(monsterID, source)
	var normalized = BattleCommand.new(
		accumulator["move_path"],
		accumulator["action"],
		accumulator["target_id"],
		accumulator["spell_set_index"],
		accumulator["spell_index"],
		accumulator["order"],
		accumulator["target_pos"]
	)
	state.add_event("command", monsterID, normalized.target_id, {
		"source": accumulator["source"],
		"command": normalized.to_dictionary()
	})

	var skipped: bool = accumulator["skipped"]
	var actionResult: Dictionary = accumulator["action_result"]
	var acted: bool = accumulator["acted"]
	_turnAccumulator = {}
	passiveSkillResolver.fireEvent(PassiveSkillResolver.ON_TURN_END, monsterID)
	var result = BattleCommandResult.accepted(normalized)
	result.resolved = false if skipped else actionResult.get("success", true)
	result.acted = acted
	result.skipped = skipped
	result.action_result = actionResult
	return result

func _rejectPhase(monsterID: int, source: String, reason: String) -> Dictionary:
	state.add_event("command_rejected", monsterID, -1, {"source": source, "reason": reason})
	return {"success": false, "reason": reason}


func _normalizePath(path):
	## Returns the path as Vector2i steps, or null if any coordinate is unusable.
	var normalizedPath: Array = []
	for stepValue in path:
		var step = stepValue
		if stepValue is Dictionary:
			step = Vector2i(int(stepValue.get("x", 0)), int(stepValue.get("y", 0)))
		if not step is Vector2i:
			return null
		normalizedPath.append(step)
	return normalizedPath


func _targetIDAtActionCenter(
		monsterID: int,
		action: String,
		spellSetIndex: int,
		spellIndex: int,
		actionPos: Vector2i,
		targetPos: Vector2i) -> int:
	if action == "spell":
		var monster = state.getMonster(monsterID)
		if (
			monster != null
			and spellSetIndex >= 0
			and spellSetIndex < monster.spellSets.size()
			and spellIndex >= 0
			and spellIndex < monster.spellSets[spellSetIndex].size()
			and monster.spellSets[spellSetIndex][spellIndex].targetType == "self"
		):
			return monsterID
	if state.withinBounds(targetPos):
		var occupantID = combatResolver.getProjectedOccupantID(
			monsterID, actionPos, targetPos
		)
		return -1 if occupantID == 0 else occupantID
	return -1

func executeCommand(
		monsterID: int,
		command: BattleCommand,
		source: String = "cpu") -> BattleCommandResult:
	## The atomic entry point CPU brains and replay use. Validates the whole turn
	## up front, then resolves it through the same phase calls the interactive
	## path uses, in the order the command records.
	var validation = validateCommand(monsterID, command)
	if not validation.success:
		var rejectedTargetID = command.target_id if command != null else -1
		state.add_event("command_rejected", monsterID, rejectedTargetID, {
			"source": source,
			"reason": validation.reason if not validation.reason.is_empty() else "invalid_command"
		})
		return validation

	var normalized: BattleCommand = validation.command
	var accumulator = _ensureTurnAccumulator(monsterID, source)
	accumulator["source"] = source

	if state.hasEffect(monsterID, "petrify"):
		events.monster_skipped_turn.emit(monsterID, "petrify")
		accumulator["skipped"] = true
		accumulator["action_result"] = {"success": false, "reason": "petrify"}
		var skippedResult = finishTurn(monsterID, source)
		skippedResult.command = normalized
		return skippedResult

	var action: String = normalized.action
	if normalized.order == ORDER_ACT_FIRST:
		executeActionPhase(
			monsterID,
			action,
			normalized.target_pos,
			normalized.spell_set_index,
			normalized.spell_index,
			source
		)
		executeMovePhase(monsterID, normalized.move_path, source)
	else:
		executeMovePhase(monsterID, normalized.move_path, source)
		executeActionPhase(
			monsterID,
			action,
			normalized.target_pos,
			normalized.spell_set_index,
			normalized.spell_index,
			source
		)

	return finishTurn(monsterID, source)

## Resolves a CPU turn start to finish. Deliberation happens inline, so the
## call lasts as long as the decision — fine for headless tools and replay,
## which have no frame to protect. Interactive presentation uses
## beginTurnDeliberation()/applyDeliberatedTurn() instead so a decision can be
## spread across frames; both compose the same two halves, so they resolve a
## turn identically. See docs/ARCHITECTURE.md, "Frame budget: deliberation must
## not block presentation".
func executeTurn(monsterID: int) -> bool:
	if state.hasEffect(monsterID, "petrify"):
		var mon = state.getMonster(monsterID)
		if mon == null or not mon.is_alive():
			return false
		return executeCommand(monsterID, BattleCommand.wait(), "cpu").acted
	var deliberation := beginTurnDeliberation(monsterID)
	if deliberation == null:
		return false
	deliberation.run()
	return applyDeliberatedTurn(monsterID, deliberation)


## Opens a CPU decision without resolving anything. Returns null when the
## monster cannot deliberate at all — dead, or brainless — in which case the
## caller must close the turn itself, exactly as executeTurn()'s `false` return
## already required.
##
## Deliberation is a read-only query, so nothing observable happens between this
## call and applyDeliberatedTurn(). The caller does, however, own the invariant
## that simulation state must not change in that window: the decision is
## computed against the board as it stood here.
func beginTurnDeliberation(monsterID: int) -> CommandDeliberation:
	var mon = state.getMonster(monsterID)
	if mon == null or not mon.is_alive():
		return null
	var brain = brains.get(monsterID)
	if brain == null:
		return null
	return brain.beginDeliberation(monsterID)


## Records and resolves a finished decision. This is the only half that mutates,
## and it must run wherever turn order is owned.
func applyDeliberatedTurn(monsterID: int, deliberation: CommandDeliberation) -> bool:
	var decision: BattleCommand = deliberation.result()
	state.add_event("decision", monsterID, decision.target_id, decision.to_dictionary())
	var result = executeCommand(monsterID, decision, "cpu")
	if not result.success:
		push_error("AI command rejected for monster %d: %s" % [monsterID, result.reason])
		result = executeCommand(monsterID, BattleCommand.wait(), "cpu_fallback")
	return result.acted

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
		"version": REPLAY_VERSION,
		"seed": state.battleSeed,
		"setup": setupSnapshot.duplicate(true),
		"initialState": initialStateSnapshot if not initialStateSnapshot.is_empty() else state.serialize_state(),
		"currentState": state.serialize_state(),
		"turnOrder": turnManager.turnOrder.duplicate(),
		"brainClasses": brainClasses,
		"commands": commands
	}


func restoreReplaySnapshot(snapshot: Dictionary) -> Dictionary:
	var version = int(snapshot.get("version", REPLAY_MIN_VERSION))
	if version < REPLAY_MIN_VERSION or version > REPLAY_VERSION:
		return {"success": false, "reason": "unsupported_replay_version", "version": version}
	if not snapshot.has("currentState"):
		return {"success": false, "reason": "missing_current_state"}

	if visualAdapter != null:
		visualAdapter.disconnectFromEvents()
	visualAdapter = null
	_turnAccumulator = {}
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
			"move": monster.move,
			"level": monster.level,
			"jump": monster.jump,
			"height": state.getHeight(state.getMonsterPosition(monsterID))
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
