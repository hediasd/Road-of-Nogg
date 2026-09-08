## Canonical headless battle orchestrator.
## AI and player controllers submit the same validated BattleCommand values.

class_name BattleSimulator

## Which of the two turn phases resolved first. Recorded on every command so a
## replay resolves them in the order they actually happened.
const ORDER_MOVE_FIRST := "move_first"
const ORDER_ACT_FIRST := "act_first"

## Version 6 is the first active-project replay contract for the hex party
## rules. Square versions remain in the frozen reference project and receive a
## directed rejection here instead of being reinterpreted.
const REPLAY_VERSION := 6
const REPLAY_MIN_VERSION := 6
const SQUARE_REPLAY_MAX_VERSION := 5
const GRID_KIND := "hex_flat"
const COORDINATE_CONVENTION := "odd_q_offset"
const RULESET_ID := "hex_party_activation_v1"

const CombatResolverScript = preload("res://src/battle_sim/CombatResolver.gd")
const PassiveSkillResolverScript = preload("res://src/battle_sim/PassiveSkillResolver.gd")
const MapFactoryScript = preload("res://src/factories/MapFactory.gd")
const BattleStateSerializerScript = preload("res://src/battle_sim/BattleStateSerializer.gd")
const MonsterReferencesScript = preload("res://src/factories/MonsterReferences.gd")
const SpellReferencesScript = preload("res://src/factories/SpellReferences.gd")
const PassiveSkillReferencesScript = preload("res://src/factories/PassiveSkillReferences.gd")

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


## Installs the validated HXB setup state into the one canonical simulator.
## BattleSetupFactory deliberately remains the setup-data boundary; this method
## owns runtime wiring, scheduling identity, and content fingerprinting.
func configureHexState(
		newState: BattleState,
		scenario: BattleScenario,
		setupData: Dictionary = {}) -> void:
	assert(newState != null and scenario != null, "Hex state and scenario are required.")
	assert(not newState.parties.is_empty(), "Hex state must contain parties.")
	state = newState
	state.gridKind = GRID_KIND
	state.coordinateConvention = COORDINATE_CONVENTION
	state.rulesetID = RULESET_ID
	state.scenarioID = scenario.scenarioID
	state.scenarioRevision = scenario.revision
	state.scenarioPath = str(setupData.get("scenarioPath", ""))
	_rebuildRuntimeDependencies()
	state.contentFingerprint = computeContentFingerprint(state)
	setupSnapshot = setupData.duplicate(true)
	initialStateSnapshot = {}
	_turnAccumulator = {}


func _rebuildRuntimeDependencies(brainClasses: Dictionary = {}) -> void:
	events = BattleEvents.new()
	turnManager = TurnManager.new(state, events)
	movementResolver = MovementResolver.new(state, events)
	combatResolver = CombatResolverScript.new(state, events)
	passiveSkillResolver = PassiveSkillResolverScript.new(state, events)
	combatResolver.passiveSkillResolver = passiveSkillResolver
	brains.clear()
	for monsterID in state.monsters:
		var monster: Monster = state.monsters[monsterID]
		var brainName := str(brainClasses.get(str(monsterID), ""))
		if brainName.is_empty():
			brainName = str(MonsterReferencesScript.getReference(monster.name).get(
				"BRAIN", "TacticalBrain"))
		var brainClass = _resolveBrainClass(brainName)
		var brain = brainClass.new(state, movementResolver, combatResolver)
		monster.brain = brain
		brains[monsterID] = brain


static func computeContentFingerprint(battleState: BattleState) -> String:
	var monsterIDs: Array = battleState.monsters.keys()
	monsterIDs.sort()
	var monsters: Array = []
	var spellNames: Dictionary = {}
	var passiveNames: Dictionary = {}
	for monsterID in monsterIDs:
		var monster: Monster = battleState.monsters[monsterID]
		monsters.append({
			"id": int(monsterID),
			"reference": MonsterReferencesScript.getReference(monster.name).duplicate(true),
		})
		for spellSet in monster.spellSets:
			for spell in spellSet:
				spellNames[spell.name] = true
		for passive in monster.passives:
			passiveNames[passive.name] = true
	var sortedSpellNames: Array = spellNames.keys()
	sortedSpellNames.sort()
	var spells: Array = []
	for spellName in sortedSpellNames:
		spells.append(SpellReferencesScript.getReference(str(spellName)).duplicate(true))
	var sortedPassiveNames: Array = passiveNames.keys()
	sortedPassiveNames.sort()
	var passives: Array = []
	for passiveName in sortedPassiveNames:
		passives.append(PassiveSkillReferencesScript.getReference(str(passiveName)).duplicate(true))
	var partyIDs: Array = battleState.parties.keys()
	partyIDs.sort()
	var parties: Array = []
	for partyID in partyIDs:
		var party: BattleParty = battleState.parties[partyID]
		parties.append(party.toDictionary())
	var content := {
		"ruleset": RULESET_ID,
		"map": battleState.battleMap.toDictionary() if battleState.battleMap != null else {},
		"parties": parties,
		"monsters": monsters,
		"spells": spells,
		"passives": passives,
	}
	var context := HashingContext.new()
	context.start(HashingContext.HASH_SHA256)
	context.update(_canonicalJSON(BattleStateSerializerScript.jsonSafe(content)).to_utf8_buffer())
	return "sha256:%s" % context.finish().hex_encode()


static func _canonicalJSON(value) -> String:
	if value is Dictionary:
		var keys: Array = value.keys()
		keys.sort_custom(func(a, b): return str(a) < str(b))
		var fields: Array[String] = []
		for key in keys:
			fields.append("%s:%s" % [JSON.stringify(str(key)), _canonicalJSON(value[key])])
		return "{%s}" % ",".join(fields)
	if value is Array:
		var items: Array[String] = []
		for item in value:
			items.append(_canonicalJSON(item))
		return "[%s]" % ",".join(items)
	return JSON.stringify(value)


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


func hasPartyRuntime() -> bool:
	return not state.parties.is_empty()


func startNextPartyActivation(source: String = "system") -> Dictionary:
	if not hasPartyRuntime():
		return {"success": false, "reason": "party_runtime_unavailable", "party_id": -1}
	if state.battleOutcome != -1:
		return {"success": false, "reason": "battle_ended", "party_id": -1}
	if state.currentMonsterID != -1 or not _turnAccumulator.is_empty():
		return {"success": false, "reason": "member_turn_in_progress", "party_id": -1}
	if state.activePartyID != -1:
		return {"success": false, "reason": "party_activation_in_progress", "party_id": state.activePartyID}

	_synchronizeCommanderWithdrawals()
	_recordBattleOutcomeIfResolved()
	if state.battleOutcome != -1:
		return {"success": false, "reason": "battle_ended", "party_id": -1}
	if state.pendingPartyIDs.is_empty():
		if state.roundCount > 0 and not state.partyOrder.is_empty():
			state.add_event("round_end", -1, -1, {"round": state.roundCount})
			events.round_ended.emit(state.roundCount)
		state.roundCount += 1
		var surviving: Array[int] = []
		for partyID in state.parties:
			if state.isPartySurviving(int(partyID)):
				surviving.append(int(partyID))
		state.partyOrder = TurnManager.partySortedIDs(state, surviving)
		state.pendingPartyIDs = state.partyOrder.duplicate()
		state.add_event("round_start", -1, -1, {
			"round": state.roundCount,
			"party_order": state.partyOrder.duplicate(),
		})
		events.round_started.emit(state.roundCount, state.partyOrder.duplicate())

	while not state.pendingPartyIDs.is_empty():
		var partyID := int(state.pendingPartyIDs.pop_front())
		if not state.isPartySurviving(partyID):
			continue
		state.activePartyID = partyID
		state.spentMemberIDs.clear()
		state.activationCount += 1
		state.activationPhase = "awaiting_member"
		var eligible := state.eligibleMemberIDs(partyID)
		state.add_event("party_activation_start", partyID, -1, {
			"source": source,
			"activation": state.activationCount,
			"eligible": eligible.duplicate(),
		})
		events.party_activation_started.emit(
			partyID, state.roundCount, state.activationCount, eligible.duplicate())
		if eligible.is_empty():
			_closePartyActivation("no_eligible_members")
			continue
		return {"success": true, "reason": "", "party_id": partyID}

	_recordBattleOutcomeIfResolved()
	return {"success": false, "reason": "round_complete", "party_id": -1}


func eligiblePartyMemberIDs() -> Array[int]:
	if state.activePartyID == -1 or state.currentMonsterID != -1:
		return []
	return state.eligibleMemberIDs(state.activePartyID)


func selectPartyMember(monsterID: int, source: String = "player") -> Dictionary:
	var rejection := _validatePartyMemberSelection(monsterID)
	if not rejection.is_empty():
		state.add_event("member_selection_rejected", monsterID, -1, {
			"source": source,
			"party_id": state.activePartyID,
			"reason": rejection,
		})
		return {"success": false, "reason": rejection, "monster_id": -1}
	state.currentMonsterID = monsterID
	state.turnCount += 1
	state.activationPhase = "member_turn"
	state.last_turn_start_index[monsterID] = state.history.size()
	state.add_event("member_selected", monsterID, -1, {
		"source": source,
		"party_id": state.activePartyID,
		"activation": state.activationCount,
	})
	state.add_event("turn_start", monsterID, -1, {
		"round": state.roundCount,
		"turn": state.turnCount,
		"party_id": state.activePartyID,
	})
	events.party_member_selected.emit(state.activePartyID, monsterID)
	events.turn_started.emit(monsterID, state.roundCount, state.turnCount)
	return {"success": true, "reason": "", "monster_id": monsterID}


func _validatePartyMemberSelection(monsterID: int) -> String:
	if not hasPartyRuntime():
		return "party_runtime_unavailable"
	if state.battleOutcome != -1:
		return "battle_ended"
	if state.activePartyID == -1:
		return "no_active_party"
	if state.currentMonsterID != -1 or not _turnAccumulator.is_empty():
		return "member_turn_in_progress"
	if int(state.monsterPartyIDs.get(monsterID, -1)) != state.activePartyID:
		return "member_not_in_active_party"
	if state.spentMemberIDs.has(monsterID):
		return "member_already_spent"
	var monster: Monster = state.getMonster(monsterID)
	if monster == null or not monster.is_alive():
		return "member_defeated"
	if state.isMonsterWithdrawn(monsterID) or not state.monsterPositions.has(monsterID):
		return "member_withdrawn"
	return ""


func endPartyActivation(source: String = "player") -> Dictionary:
	if not hasPartyRuntime() or state.activePartyID == -1:
		return {"success": false, "reason": "no_active_party", "consumed": []}
	if state.currentMonsterID != -1 or not _turnAccumulator.is_empty():
		return {"success": false, "reason": "member_turn_in_progress", "consumed": []}
	var partyID := state.activePartyID
	var remaining := state.eligibleMemberIDs(partyID)
	remaining.sort()
	state.add_event("end_party_requested", partyID, -1, {
		"source": source,
		"remaining": remaining.duplicate(),
	})
	for memberID: int in remaining:
		var selection := selectPartyMember(memberID, "end_party")
		if not selection["success"]:
			return {"success": false, "reason": selection["reason"], "consumed": []}
		var result := executeCommand(memberID, BattleCommand.wait(), "end_party")
		if not result.success:
			return {"success": false, "reason": result.reason, "consumed": []}
	if state.activePartyID == partyID:
		_closePartyActivation("ended_by_player")
	return {"success": true, "reason": "", "consumed": remaining}


func _completePartyMemberTurn(monsterID: int) -> void:
	var partyID := state.activePartyID
	turnManager.endTurn(monsterID)
	state.spentMemberIDs[monsterID] = true
	state.activationPhase = "awaiting_member"
	state.add_event("member_spent", monsterID, -1, {"party_id": partyID})
	events.party_member_spent.emit(partyID, monsterID)
	_synchronizeCommanderWithdrawals()
	_recordBattleOutcomeIfResolved()
	if state.battleOutcome != -1:
		if state.activePartyID != -1:
			_closePartyActivation("battle_ended")
		return
	if state.activePartyID != -1 and state.eligibleMemberIDs(state.activePartyID).is_empty():
		_closePartyActivation("members_exhausted")


func _closePartyActivation(reason: String) -> void:
	if state.activePartyID == -1:
		return
	var partyID := state.activePartyID
	state.add_event("party_activation_end", partyID, -1, {
		"reason": reason,
		"spent": _sortedIntKeys(state.spentMemberIDs),
	})
	events.party_activation_ended.emit(partyID, reason)
	state.activePartyID = -1
	state.currentMonsterID = -1
	state.activationPhase = "idle"
	_turnAccumulator = {}


func _synchronizeCommanderWithdrawals() -> void:
	var partyIDs: Array = state.parties.keys()
	partyIDs.sort()
	for partyIDValue in partyIDs:
		var partyID := int(partyIDValue)
		if state.isPartyWithdrawn(partyID):
			continue
		var party: BattleParty = state.parties[partyID]
		var commander: Monster = state.getMonster(party.commanderID)
		if commander == null or not commander.is_alive() or state.isMonsterWithdrawn(party.commanderID):
			_withdrawParty(partyID)


func _withdrawParty(partyID: int) -> void:
	if state.isPartyWithdrawn(partyID):
		return
	var party: BattleParty = state.parties.get(partyID)
	if party == null:
		return
	state.withdrawnPartyIDs[partyID] = true
	var withdrawn: Array[int] = []
	for memberID: int in party.memberIDs:
		var monster: Monster = state.getMonster(memberID)
		if memberID == party.commanderID or monster == null or not monster.is_alive():
			continue
		if not state.isMonsterWithdrawn(memberID):
			state.withdrawMonster(memberID)
			withdrawn.append(memberID)
	state.add_event("party_withdrawn", partyID, -1, {
		"commander_id": party.commanderID,
		"member_ids": withdrawn.duplicate(),
	})
	events.party_withdrawn.emit(partyID, withdrawn.duplicate())


func _recordBattleOutcomeIfResolved() -> void:
	if state.battleOutcome != -1:
		return
	var outcome := checkWinCondition()
	if outcome == -1:
		return
	state.battleOutcome = outcome
	state.pendingPartyIDs.clear()
	state.add_event("battle_end", -1, -1, {"outcome": outcome})
	events.battle_ended.emit(outcome)


static func _sortedIntKeys(values: Dictionary) -> Array[int]:
	var result: Array[int] = []
	for value in values:
		result.append(int(value))
	result.sort()
	return result


func validateCommand(monsterID: int, command: BattleCommand) -> BattleCommandResult:
	if command == null:
		return BattleCommandResult.rejected("missing_command")
	if state.currentMonsterID != monsterID:
		return BattleCommandResult.rejected("not_current_turn")
	if hasPartyRuntime():
		if state.activePartyID == -1:
			return BattleCommandResult.rejected("no_active_party")
		if int(state.monsterPartyIDs.get(monsterID, -1)) != state.activePartyID:
			return BattleCommandResult.rejected("member_not_in_active_party")
		if state.spentMemberIDs.has(monsterID):
			return BattleCommandResult.rejected("member_already_spent")
		if state.isMonsterWithdrawn(monsterID):
			return BattleCommandResult.rejected("member_withdrawn")
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
	if hasPartyRuntime() and (
		state.activePartyID == -1
		or int(state.monsterPartyIDs.get(monsterID, -1)) != state.activePartyID
		or state.spentMemberIDs.has(monsterID)
		or state.isMonsterWithdrawn(monsterID)
	):
		return {"success": false, "reason": "member_not_eligible"}
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
	if state.currentMonsterID != monsterID:
		return BattleCommandResult.rejected("not_current_turn")
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
	var skipped: bool = accumulator["skipped"]
	var actionResult: Dictionary = accumulator["action_result"]
	var acted: bool = accumulator["acted"]
	_turnAccumulator = {}
	var result = BattleCommandResult.accepted(normalized)
	result.resolved = false if skipped else actionResult.get("success", true)
	result.acted = acted
	result.skipped = skipped
	result.action_result = actionResult
	state.add_event("command", monsterID, normalized.target_id, {
		"source": accumulator["source"],
		"command": normalized.to_dictionary(),
		"result": result.to_dictionary(),
	})
	passiveSkillResolver.fireEvent(PassiveSkillResolver.ON_TURN_END, monsterID)
	if hasPartyRuntime():
		_completePartyMemberTurn(monsterID)
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
	if not hasPartyRuntime():
		return {
			"success": false,
			"reason": "square_reference_required",
			"detail": "Use the frozen square reference project for square replay files.",
		}
	if state.currentMonsterID != -1 or not _turnAccumulator.is_empty():
		return {"success": false, "reason": "partial_turn_snapshot_unsupported"}
	var brainClasses = {}
	for monsterID in brains:
		var brain = brains[monsterID]
		brainClasses[str(monsterID)] = brain.get_script().resource_path.get_file().get_basename()

	var operations: Array = []
	var commands: Array = []
	for event in state.history:
		if event.get("type", "") in ["party_activation_start", "member_selected", "command"]:
			operations.append(BattleStateSerializerScript.jsonSafe(event))
		if event.get("type", "") == "command":
			commands.append(BattleStateSerializerScript.jsonSafe(event))

	return {
		"success": true,
		"version": REPLAY_VERSION,
		"gridKind": GRID_KIND,
		"coordinateConvention": COORDINATE_CONVENTION,
		"rulesetID": RULESET_ID,
		"scenarioID": state.scenarioID,
		"scenarioRevision": state.scenarioRevision,
		"mapID": state.mapName,
		"mapRevision": state.mapRevision,
		"mapSourceFingerprint": state.battleMap.sourceFingerprint,
		"contentFingerprint": state.contentFingerprint,
		"seed": state.battleSeed,
		"setup": setupSnapshot.duplicate(true),
		"initialState": initialStateSnapshot if not initialStateSnapshot.is_empty() else state.serialize_state(),
		"currentState": state.serialize_state(),
		"brainClasses": brainClasses,
		"operations": operations,
		"commands": commands
	}


func restoreReplaySnapshot(snapshot: Dictionary) -> Dictionary:
	var version = int(snapshot.get("version", REPLAY_MIN_VERSION))
	if version <= SQUARE_REPLAY_MAX_VERSION:
		return {
			"success": false,
			"reason": "square_reference_required",
			"detail": "Use the frozen square reference project for square replay files.",
		}
	if version != REPLAY_VERSION:
		return {"success": false, "reason": "unsupported_replay_version", "version": version}
	if not snapshot.has("currentState"):
		return {"success": false, "reason": "missing_current_state"}
	var identityError := _replayIdentityError(snapshot)
	if not identityError.is_empty():
		return {"success": false, "reason": identityError}
	var currentState: Dictionary = snapshot["currentState"]
	if int(currentState.get("currentMonsterID", -1)) != -1:
		return {"success": false, "reason": "partial_turn_snapshot_unsupported"}

	if visualAdapter != null:
		visualAdapter.disconnectFromEvents()
	visualAdapter = null
	_turnAccumulator = {}
	state = BattleStateSerializerScript.deserialize(currentState)
	if computeContentFingerprint(state) != str(snapshot.get("contentFingerprint", "")):
		return {"success": false, "reason": "content_fingerprint_mismatch"}
	initialStateSnapshot = snapshot.get("initialState", {}).duplicate(true)
	setupSnapshot = snapshot.get("setup", {}).duplicate(true)
	var brainClasses: Dictionary = snapshot.get("brainClasses", {})
	_rebuildRuntimeDependencies(brainClasses)

	return {"success": true}


func _replayIdentityError(snapshot: Dictionary) -> String:
	if str(snapshot.get("gridKind", "")) != GRID_KIND:
		return "grid_kind_mismatch"
	if str(snapshot.get("coordinateConvention", "")) != COORDINATE_CONVENTION:
		return "coordinate_convention_mismatch"
	if str(snapshot.get("rulesetID", "")) != RULESET_ID:
		return "ruleset_mismatch"
	var currentState = snapshot.get("currentState", {})
	if not currentState is Dictionary:
		return "invalid_current_state"
	for key in ["gridKind", "coordinateConvention", "rulesetID", "contentFingerprint"]:
		if str(currentState.get(key, "")) != str(snapshot.get(key, "")):
			return "%s_mismatch" % _snakeCase(key)
	return ""


static func _snakeCase(value: String) -> String:
	var result := ""
	for character in value:
		if character == character.to_upper() and character != character.to_lower():
			if not result.is_empty():
				result += "_"
			result += character.to_lower()
		else:
			result += character
	return result


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
	if hasPartyRuntime():
		return _runFullPartyBattle(maxRounds)
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


func _runFullPartyBattle(maxRounds: int) -> int:
	startBattle()
	while state.roundCount < maxRounds and state.battleOutcome == -1:
		var activation := startNextPartyActivation("headless")
		if not activation["success"]:
			if activation["reason"] in ["battle_ended", "round_complete"]:
				continue
			break
		while state.activePartyID != -1 and state.battleOutcome == -1:
			var eligible := eligiblePartyMemberIDs()
			if eligible.is_empty():
				_closePartyActivation("no_eligible_members")
				break
			var memberID := int(eligible.front())
			if not selectPartyMember(memberID, "cpu")["success"]:
				break
			if not executeTurn(memberID):
				executeCommand(memberID, BattleCommand.wait(), "cpu_fallback")
	if state.battleOutcome == -1:
		state.battleOutcome = _determineWinnerByNumbers()
		events.battle_ended.emit(state.battleOutcome)
	return state.battleOutcome


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
