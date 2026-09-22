## Canonical headless battle orchestrator.
## AI and player controllers submit the same validated BattleCommand values.

class_name BattleSimulator

const ORDER_MOVE_FIRST := "move_first"

## Version 8 keeps side-turn operation order and uses lossless state snapshots.
## Version 6 was the retired party-activation contract and is never reinterpreted.
const REPLAY_VERSION := 8
const REPLAY_MIN_VERSION := 8
const SQUARE_REPLAY_MAX_VERSION := 5
const PARTY_ACTIVATION_REPLAY_VERSION := 6
const GRID_KIND := "hex_flat"
const COORDINATE_CONVENTION := "odd_q_offset"
const RULESET_ID := "hex_side_turn_v1"

const BattleInvariantsScript = preload("res://src/battle_sim/BattleInvariants.gd")
const CombatResolverScript = preload("res://src/battle_sim/CombatResolver.gd")
const PassiveSkillResolverScript = preload("res://src/battle_sim/PassiveSkillResolver.gd")
const MapFactoryScript = preload("res://src/factories/MapFactory.gd")
const BattleStateSerializerScript = preload("res://src/battle_sim/BattleStateSerializer.gd")
const MonsterReferencesScript = preload("res://src/factories/MonsterReferences.gd")
const SpellReferencesScript = preload("res://src/factories/SpellReferences.gd")
const PassiveSkillReferencesScript = preload("res://src/factories/PassiveSkillReferences.gd")
const PolicyCatalogScript = preload("res://src/entity_ai/PolicyCatalog.gd")
const SideDeliberationScript = preload("res://src/entity_ai/PartyCommandDeliberation.gd")
const TacticalSidePolicyScript = preload("res://src/entity_ai/TacticalSidePolicy.gd")

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
## Which named policy plays this battle's CPU sides. Every caller that opens a
## side decision goes through beginSideDeliberation(), so a run always knows,
## and can say, what chose its moves.
var sidePolicyID: String = PolicyCatalogScript.TACTICAL_SIDE
## Operations survive a timeline restore; only the current rules state rewinds.
var operationLedger: Array[Dictionary] = []
## Exactly one side-start state is retained, until the next side opens.
var sideStartCheckpoint: Dictionary = {}
var _resolutionDepth := 0

## Set by `emitInitialBoard()`, reset on every `configureHexState()`. Lets `startBattle()` skip
## its own `battle_started` emission when the board has already been announced -- see that
## function's own note for why both exist and why emitting twice would otherwise be harmless but
## redundant.
var _initialBoardEmitted := false

## Off by default, because the interactive game pays for it on every step and gains nothing it
## cannot see. The headless runners turn it on: there, a violation is the only way a broken state
## announces itself at all. See `setInvariantChecks()`.
var _invariantChecksEnabled := false
var _invariantViolations: Array[String] = []

func _init(seedValue: int = 0) -> void:
	events = BattleEvents.new()
	state = BattleState.new(seedValue)
	turnManager = TurnManager.new(state, events)
	movementResolver = MovementResolver.new(state, events)
	combatResolver = CombatResolverScript.new(state, events)
	passiveSkillResolver = PassiveSkillResolverScript.new(state, events)
	combatResolver.passiveSkillResolver = passiveSkillResolver


## Checks the battle's invariants after every resolved step (see `BattleInvariants`). A headless
## runner turns this on so a broken state cannot pass for a finished battle; presentation leaves it
## off, since the check costs a full board and roster walk per step.
##
## Enabling it changes nothing a record can see: the check reads, it never emits, mutates or draws
## from the RNG, so corpora stay byte-identical either way.
func setInvariantChecks(enabled: bool) -> void:
	_invariantChecksEnabled = enabled


func invariantChecksEnabled() -> bool:
	return _invariantChecksEnabled


## Every invariant violation seen so far, oldest first, each naming the step that produced it.
## Empty after a battle means every step of it was legal.
func invariantViolations() -> Array[String]:
	return _invariantViolations.duplicate()


## Reports violations without deciding what to do about them: a single battle and a thousand-battle
## championship want different answers, and both live in their runners. The simulator's part is to
## make sure a violation can never pass silently -- it is recorded and it goes to stderr, once per
## step that produced it.
func _checkInvariants(step: String) -> void:
	if not _invariantChecksEnabled:
		return
	var found: Array[String] = BattleInvariantsScript.violations(state)
	for violation: String in found:
		var line := "%s: %s" % [step, violation]
		_invariantViolations.append(line)
		printerr("BATTLE_INVARIANT_VIOLATION: %s" % line)


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
	_initialBoardEmitted = false
	operationLedger.clear()
	sideStartCheckpoint.clear()


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
	## Content identity describes authored definitions, never mutable spell/passive
	## instances. A temporary ability change must not invalidate the build itself.
	var monsters := _sortedDefinitions(MonsterReferencesScript.list)
	var spells := _sortedDefinitions(SpellReferencesScript.list)
	var passives := _sortedDefinitions(PassiveSkillReferencesScript.list)
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


static func _sortedDefinitions(definitions: Array) -> Array:
	var result: Array = definitions.duplicate(true)
	result.sort_custom(func(a, b): return str(a.get("NAME", "")) < str(b.get("NAME", "")))
	return result


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
		"RandomLegalBrain": return load("res://src/entity_ai/RandomLegalBrain.gd")
		"MageBrain": return load("res://src/entity_ai/MageBrain.gd")
		"SupportBrain": return load("res://src/entity_ai/SupportBrain.gd")
		_: return load("res://src/entity_ai/TacticalBrain.gd")


## Replaces the brain of every unit, or of one team's units, with `brainName`.
##
## For headless fuzzing and experiments: a scenario authors a brain per monster, and that is the
## configuration the game ships, so this never edits the scenario. Call it right after
## configureHexState() and before any adapter connects, because rebuilding the runtime replaces the
## event bus the adapters subscribe to.
##
## The corpus records each member's brain from the live object, so an overridden run identifies
## itself without any extra bookkeeping.
func overrideBrains(brainName: String, teamID: int = -1) -> void:
	var overrides: Dictionary = {}
	for monsterID in state.monsters:
		var monster: Monster = state.monsters[monsterID]
		if teamID != -1 and monster.team != teamID:
			continue
		overrides[str(monsterID)] = brainName
	_rebuildRuntimeDependencies(overrides)


## The RNG a side deliberation should draw its actor from, or null when the open side plays a
## policy. Non-null only when every ready unit of the open side is on a fuzzing brain, so a mixed
## run (--brain-team) keeps scoring the side that is still playing properly.
func uniformChoiceRNGForActiveSide() -> RandomNumberGenerator:
	if state.activeSideID == -1:
		return null
	var readyIDs := state.eligibleUnitIDs(state.activeSideID)
	if readyIDs.is_empty():
		return null
	for unitID: int in readyIDs:
		var brain = brains.get(unitID)
		if brain == null or not brain.has_method("playsAtRandom"):
			return null
	# Seeded out of the position rather than taken from state.rng: a deliberation that drew from
	# the battle's own generator would change the state revision and be discarded as stale. See
	# RandomLegalBrain.rngFor().
	var rng := RandomNumberGenerator.new()
	rng.seed = hash([state.battleSeed, state.sideTurnCount, state.totalHistoryCount(), state.activeSideID])
	return rng


func hasSideRuntime() -> bool:
	return not state.parties.is_empty()


func startNextSideTurn(source: String = "system") -> Dictionary:
	if _resolutionDepth > 0:
		return {"success": false, "reason": "operation_in_progress", "side_id": -1}
	if not hasSideRuntime():
		return {"success": false, "reason": "side_runtime_unavailable", "side_id": -1}
	if state.battleOutcome != -1:
		return {"success": false, "reason": "battle_ended", "side_id": -1}
	if state.activeSideID != -1:
		return {"success": false, "reason": "side_turn_in_progress", "side_id": state.activeSideID}

	_synchronizeCommanderWithdrawals()
	_recordBattleOutcomeIfResolved()
	if state.battleOutcome != -1:
		return {"success": false, "reason": "battle_ended", "side_id": -1}
	if state.pendingSideIDs.is_empty():
		if state.roundCount > 0 and not state.sideOrder.is_empty():
			state.add_event("round_end", -1, -1, {"round": state.roundCount})
			events.round_ended.emit(state.roundCount)
		state.roundCount += 1
		state.sideOrder = TurnManager.sideSortedIDs(state)
		state.pendingSideIDs = state.sideOrder.duplicate()
		state.add_event("round_start", -1, -1, {
			"round": state.roundCount,
			"side_order": state.sideOrder.duplicate(),
		})
		events.round_started.emit(state.roundCount, state.sideOrder.duplicate())

	while not state.pendingSideIDs.is_empty():
		var sideID := int(state.pendingSideIDs.pop_front())
		if state.isTeamDefeated(sideID):
			continue
		state.activeSideID = sideID
		state.spentUnitIDs.clear()
		state.pendingUnitTurns.clear()
		state.currentMonsterID = -1
		state.sideTurnCount += 1
		state.turnCount += 1
		state.sideTurnPhase = "awaiting_unit"
		var eligible := state.eligibleUnitIDs(sideID)
		state.add_event("side_turn_start", sideID, -1, {
			"source": source,
			"side_turn": state.sideTurnCount,
			"eligible": eligible.duplicate(),
		})
		if eligible.is_empty():
			_resolutionDepth += 1
			events.side_turn_started.emit(
				sideID, state.roundCount, state.turnCount, eligible.duplicate())
			_resolutionDepth -= 1
			_closeSideTurn("no_eligible_units")
			continue
		_checkInvariants("side_open:%d" % sideID)
		_recordOperation("side_turn_start")
		_captureSideStartCheckpoint()
		_resolutionDepth += 1
		events.side_turn_started.emit(
			sideID, state.roundCount, state.turnCount, eligible.duplicate())
		_resolutionDepth -= 1
		return {"success": true, "reason": "", "side_id": sideID}

	_recordBattleOutcomeIfResolved()
	return {"success": false, "reason": "round_complete", "side_id": -1}


func eligibleSideUnitIDs() -> Array[int]:
	if state.activeSideID == -1:
		return []
	return state.eligibleUnitIDs(state.activeSideID)


func selectUnit(monsterID: int, source: String = "player") -> Dictionary:
	if _resolutionDepth > 0:
		return {"success": false, "reason": "operation_in_progress", "monster_id": -1}
	var rejection := _validateUnitSelection(monsterID)
	if not rejection.is_empty():
		state.add_event("unit_selection_rejected", monsterID, -1, {
			"source": source,
			"side_id": state.activeSideID,
			"reason": rejection,
		})
		return {"success": false, "reason": rejection, "monster_id": -1}
	state.currentMonsterID = monsterID
	state.sideTurnPhase = "unit_selected"
	state.last_turn_start_index[monsterID] = state.history.size()
	state.add_event("unit_selected", monsterID, -1, {
		"source": source,
		"side_id": state.activeSideID,
		"side_turn": state.sideTurnCount,
	})
	_recordOperation("unit_selected")
	_resolutionDepth += 1
	events.unit_selected.emit(state.activeSideID, monsterID)
	_resolutionDepth -= 1
	return {"success": true, "reason": "", "monster_id": monsterID}


func _validateUnitSelection(monsterID: int) -> String:
	if not hasSideRuntime():
		return "side_runtime_unavailable"
	if state.battleOutcome != -1:
		return "battle_ended"
	if state.activeSideID == -1:
		return "no_active_side"
	var monster: Monster = state.getMonster(monsterID)
	if monster == null or not monster.is_alive():
		return "unit_defeated"
	if monster.team != state.activeSideID:
		return "unit_not_on_active_side"
	if state.spentUnitIDs.has(monsterID):
		return "unit_already_spent"
	if state.isMonsterWithdrawn(monsterID) or not state.monsterPositions.has(monsterID):
		return "unit_withdrawn"
	return ""


func endSideTurn(source: String = "player") -> Dictionary:
	if _resolutionDepth > 0:
		return {"success": false, "reason": "operation_in_progress", "consumed": []}
	if not hasSideRuntime() or state.activeSideID == -1:
		return {"success": false, "reason": "no_active_side", "consumed": []}
	var sideID := state.activeSideID
	var remaining := state.eligibleUnitIDs(sideID)
	state.add_event("end_side_requested", sideID, -1, {
		"source": source,
		"remaining": remaining.duplicate(),
	})
	for monsterID: int in remaining:
		var selection := selectUnit(monsterID, "end_side")
		if not selection["success"]:
			return {"success": false, "reason": selection["reason"], "consumed": []}
		var result := executeCommand(monsterID, BattleCommand.wait(), "end_side")
		if not result.success:
			return {"success": false, "reason": result.reason, "consumed": []}
	if state.activeSideID == sideID:
		_closeSideTurn("ended_by_player")
	_checkInvariants("side_end:%d" % sideID)
	return {"success": true, "reason": "", "consumed": remaining}


func _completeUnitAction(monsterID: int) -> void:
	var sideID := state.activeSideID
	turnManager.endUnitAction(monsterID)
	state.spentUnitIDs[monsterID] = true
	state.pendingUnitTurns.erase(monsterID)
	state.currentMonsterID = -1
	state.sideTurnPhase = "awaiting_unit"
	state.add_event("unit_spent", monsterID, -1, {"side_id": sideID})
	events.unit_spent.emit(sideID, monsterID)
	_synchronizeCommanderWithdrawals()
	_recordBattleOutcomeIfResolved()
	if state.battleOutcome != -1:
		if state.activeSideID != -1:
			_closeSideTurn("battle_ended")
		return
	if state.activeSideID != -1 and state.eligibleUnitIDs(state.activeSideID).is_empty():
		_closeSideTurn("units_exhausted")


func _closeSideTurn(reason: String) -> void:
	if state.activeSideID == -1:
		return
	var sideID := state.activeSideID
	state.add_event("side_turn_end", sideID, -1, {
		"reason": reason,
		"spent": _sortedIntKeys(state.spentUnitIDs),
	})
	_resolutionDepth += 1
	events.side_turn_ended.emit(sideID, reason)
	state.activeSideID = -1
	state.currentMonsterID = -1
	state.sideTurnPhase = "idle"
	state.pendingUnitTurns.clear()
	_resolutionDepth -= 1


## Compatibility names kept only until the interactive controller item lands.
## They delegate to side turns and no longer expose party scheduling semantics.
func hasPartyRuntime() -> bool:
	return hasSideRuntime()


func startNextPartyActivation(source: String = "system") -> Dictionary:
	var result := startNextSideTurn(source)
	return {
		"success": result["success"],
		"reason": result["reason"],
		"party_id": result.get("side_id", -1),
		"side_id": result.get("side_id", -1),
	}


func eligiblePartyMemberIDs() -> Array[int]:
	return eligibleSideUnitIDs()


func selectPartyMember(monsterID: int, source: String = "player") -> Dictionary:
	return selectUnit(monsterID, source)


func endPartyActivation(source: String = "player") -> Dictionary:
	return endSideTurn(source)


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
	state.pendingSideIDs.clear()
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
	if hasSideRuntime():
		if state.activeSideID == -1:
			return BattleCommandResult.rejected("no_active_side")
		var activeMonster: Monster = state.getMonster(monsterID)
		if activeMonster == null or activeMonster.team != state.activeSideID:
			return BattleCommandResult.rejected("unit_not_on_active_side")
		if state.spentUnitIDs.has(monsterID):
			return BattleCommandResult.rejected("unit_already_spent")
		if state.isMonsterWithdrawn(monsterID):
			return BattleCommandResult.rejected("unit_withdrawn")
	var mon = state.getMonster(monsterID)
	if mon == null or not mon.is_alive():
		return BattleCommandResult.rejected("invalid_monster")

	var normalizedPath = _normalizePath(command.move_path)
	if normalizedPath == null:
		return BattleCommandResult.rejected("invalid_path_coordinate")
	var pending: Dictionary = state.pendingUnitTurns.get(monsterID, {})
	if bool(pending.get("has_moved", false)) and not normalizedPath.is_empty():
		return BattleCommandResult.rejected("move_already_spent")
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
	if order != ORDER_MOVE_FIRST:
		return BattleCommandResult.rejected("invalid_order")
	if action == "spell" and (bool(pending.get("has_moved", false)) or not normalizedPath.is_empty()):
		return BattleCommandResult.rejected("spell_after_move")
	var actionPos: Vector2i = futurePos

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
## A unit may hold one pending move while another unit is selected. The state
## lives in BattleState so snapshots preserve the exact side-turn interleaving.


func _ensureUnitTurnState(monsterID: int, source: String) -> Dictionary:
	if not state.pendingUnitTurns.has(monsterID):
		state.pendingUnitTurns[monsterID] = {
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
			"source": source,
			"acted": false,
			"skipped": false,
			"action_result": {"success": true}
		}
	return state.pendingUnitTurns[monsterID]


func _guardPhase(monsterID: int) -> Dictionary:
	if state.currentMonsterID != monsterID:
		return {"success": false, "reason": "not_current_turn"}
	if hasSideRuntime() and (
		state.activeSideID == -1
		or state.getMonster(monsterID) == null
		or state.getMonster(monsterID).team != state.activeSideID
		or state.spentUnitIDs.has(monsterID)
		or state.isMonsterWithdrawn(monsterID)
	):
		return {"success": false, "reason": "unit_not_eligible"}
	var mon = state.getMonster(monsterID)
	if mon == null or not mon.is_alive():
		return {"success": false, "reason": "invalid_monster"}
	if state.hasEffect(monsterID, "petrify"):
		return {"success": false, "reason": "petrify"}
	return {"success": true}


func turnPhaseState(monsterID: int) -> Dictionary:
	## What the interactive controller needs to build its menu: which phases are
	## still available, and whether the move can still be taken back.
	var accumulator: Dictionary = state.pendingUnitTurns.get(monsterID, {})
	if accumulator.is_empty():
		return {"has_moved": false, "has_acted": false, "can_undo_move": false}
	var hasMoved: bool = accumulator["has_moved"]
	var hasActed: bool = accumulator["has_acted"]
	return {
		"has_moved": hasMoved,
		"has_acted": hasActed,
		"can_undo_move": hasMoved and not hasActed
	}


func executeMovePhase(monsterID: int, path: Array, source: String = "player") -> Dictionary:
	if _resolutionDepth > 0:
		return {"success": false, "reason": "operation_in_progress"}
	var guard = _guardPhase(monsterID)
	if not guard["success"]:
		return _rejectPhase(monsterID, source, guard["reason"])

	var accumulator = _ensureUnitTurnState(monsterID, source)
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
		_resolutionDepth += 1
		events.movement_targeted.emit(monsterID, normalizedPath.back())
		moved = movementResolver.executeMove(monsterID, normalizedPath)
		_resolutionDepth -= 1

	accumulator["has_moved"] = not normalizedPath.is_empty()
	accumulator["move_path"] = normalizedPath
	accumulator["acted"] = accumulator["acted"] or moved
	if moved:
		state.add_event("move_phase", monsterID, -1, {
			"source": source,
			"path": normalizedPath.duplicate(),
		})
	_checkInvariants("move")
	if moved:
		_recordOperation("move_phase")
	return {
		"success": true,
		"moved": moved,
		"destination": moveValidation["destination"]
	}


func undoMovePhase(monsterID: int) -> Dictionary:
	if _resolutionDepth > 0:
		return {"success": false, "reason": "operation_in_progress"}
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

	var accumulator: Dictionary = state.pendingUnitTurns.get(monsterID, {})
	if accumulator.is_empty() or not accumulator["has_moved"]:
		return {"success": false, "reason": "no_move_to_undo"}
	if accumulator["has_acted"]:
		return {"success": false, "reason": "action_already_resolved"}

	var origin: Vector2i = accumulator["origin"]
	var currentPos = state.getMonsterPosition(monsterID)
	if currentPos != origin:
		if state.isOccupied(origin):
			return {"success": false, "reason": "move_origin_occupied"}
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
	_checkInvariants("undo")
	if currentPos != origin:
		_recordOperation("undo_move")
	return {"success": true, "destination": origin}


func executeActionPhase(
		monsterID: int,
		action: String,
		targetPos: Vector2i = Vector2i(-1, -1),
		spellSetIndex: int = 0,
		spellIndex: int = 0,
		source: String = "player") -> Dictionary:
	if _resolutionDepth > 0:
		return {"success": false, "reason": "operation_in_progress"}
	var guard = _guardPhase(monsterID)
	if not guard["success"]:
		return _rejectPhase(monsterID, source, guard["reason"])
	if action not in ["wait", "attack", "spell"]:
		return _rejectPhase(monsterID, source, "invalid_action")

	var accumulator = _ensureUnitTurnState(monsterID, source)
	if accumulator["has_acted"]:
		return _rejectPhase(monsterID, source, "action_already_spent")
	if action == "spell" and accumulator["has_moved"]:
		return _rejectPhase(monsterID, source, "spell_after_move")
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
	_resolutionDepth += 1
	if action in ["attack", "spell"]:
		events.action_targeted.emit(monsterID, targetPos, targetID, action)
	if action == "attack":
		actionResult = combatResolver.executeBasicAttack(monsterID, targetPos)
	elif action == "spell":
		actionResult = combatResolver.executeCastSpell(
			monsterID, targetPos, spellSetIndex, spellIndex
		)
	_resolutionDepth -= 1

	accumulator["has_acted"] = true
	accumulator["action"] = action
	accumulator["target_id"] = targetID
	accumulator["target_pos"] = targetPos
	accumulator["spell_set_index"] = spellSetIndex
	accumulator["spell_index"] = spellIndex
	accumulator["action_result"] = actionResult
	accumulator["acted"] = accumulator["acted"] or actionResult.get("success", false)
	_checkInvariants("action:%s" % action)
	return {"success": true, "actionResult": actionResult}

func finishTurn(monsterID: int, source: String = "player") -> BattleCommandResult:
	if _resolutionDepth > 0:
		return BattleCommandResult.rejected("operation_in_progress")
	## Spending a unit is its end-of-turn boundary: effects, cooldowns and
	## passives advance here, not when the whole side closes.
	if state.currentMonsterID != monsterID:
		return BattleCommandResult.rejected("not_current_turn")
	var accumulator = _ensureUnitTurnState(monsterID, source)
	if not bool(accumulator.get("has_acted", false)):
		return BattleCommandResult.rejected("action_not_resolved")
	var normalized = BattleCommand.new(
		accumulator["move_path"],
		accumulator["action"],
		accumulator["target_id"],
		accumulator["spell_set_index"],
		accumulator["spell_index"],
		ORDER_MOVE_FIRST,
		accumulator["target_pos"]
	)
	var skipped: bool = accumulator["skipped"]
	var actionResult: Dictionary = accumulator["action_result"]
	var acted: bool = accumulator["acted"]
	var result = BattleCommandResult.accepted(normalized)
	result.resolved = false if skipped else actionResult.get("success", true)
	result.acted = acted
	result.skipped = skipped
	result.action_result = actionResult
	state.add_event("unit_action", monsterID, normalized.target_id, {
		"source": accumulator["source"],
		"action": normalized.action,
		"target_pos": normalized.target_pos,
		"spell_set_index": normalized.spell_set_index,
		"spell_index": normalized.spell_index,
		"result": result.to_dictionary(),
	})
	_resolutionDepth += 1
	passiveSkillResolver.fireEvent(PassiveSkillResolver.ON_TURN_END, monsterID)
	if hasSideRuntime():
		_completeUnitAction(monsterID)
	_resolutionDepth -= 1
	_checkInvariants("unit_finished:%d" % monsterID)
	_recordOperation("unit_action")
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
	if _resolutionDepth > 0:
		return BattleCommandResult.rejected("operation_in_progress")
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
	var accumulator = _ensureUnitTurnState(monsterID, source)
	accumulator["source"] = source

	if state.hasEffect(monsterID, "petrify"):
		events.monster_skipped_turn.emit(monsterID, "petrify")
		accumulator["skipped"] = true
		accumulator["has_acted"] = true
		accumulator["action"] = "wait"
		accumulator["action_result"] = {"success": false, "reason": "petrify"}
		var skippedResult = finishTurn(monsterID, source)
		skippedResult.command = normalized
		return skippedResult

	var action: String = normalized.action
	if not normalized.move_path.is_empty():
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
	var decision: BattleCommand = _sideLegalCommand(deliberation.result())
	state.add_event("decision", monsterID, decision.target_id, decision.to_dictionary())
	var result = executeCommand(monsterID, decision, "cpu")
	if not result.success:
		push_error("AI command rejected for monster %d: %s" % [monsterID, result.reason])
		result = executeCommand(monsterID, BattleCommand.wait(), "cpu_fallback")
	return result.acted


## Opens one whole-side decision under the configured policy. Everything that
## drives a CPU side -- the controller, the headless runners, the probes -- comes
## through here, so switching policies is one field and not a search for every
## place a deliberation was constructed.
##
## Random legal play keeps its own path. It is a fuzzer whose whole point is the
## uniform draw that lives in the legacy deliberation, and scoring random picks
## against each other would not produce random play.
func beginSideDeliberation():
	if _sidePlaysAtRandom():
		return SideDeliberationScript.new(self)
	if sidePolicyID == PolicyCatalogScript.LEGACY_SIDE:
		return SideDeliberationScript.new(self)
	return TacticalSidePolicyScript.new(self, sidePolicyID)


func _sidePlaysAtRandom() -> bool:
	for monsterID in eligibleSideUnitIDs():
		var brain = brains.get(int(monsterID))
		if brain != null and brain.has_method("playsAtRandom") and brain.playsAtRandom():
			return true
	return false


func _sideLegalCommand(decision: BattleCommand) -> BattleCommand:
	## The side-turn boundary cannot execute the retired act-then-move order.
	## Preserve the already-chosen action when it came first; a move-then-cast
	## proposal instead becomes move-and-Wait because magic is pre-move only.
	if decision == null:
		return BattleCommand.wait()
	if decision.order != ORDER_MOVE_FIRST:
		return BattleCommand.new(
			[], decision.action, decision.target_id, decision.spell_set_index,
			decision.spell_index, ORDER_MOVE_FIRST, decision.target_pos)
	if decision.action == "spell" and not decision.move_path.is_empty():
		return BattleCommand.new(decision.move_path, "wait", -1, 0, 0, ORDER_MOVE_FIRST)
	return decision

## Fingerprint excludes diagnostic history but includes sufficient rules memory
## and exact gameplay RNG. Cost follows board, actors and rule-relevant damage.
static func semanticFingerprint(battleState: BattleState) -> String:
	var context := HashingContext.new()
	context.start(HashingContext.HASH_SHA256)
	context.update(_canonicalJSON(
		BattleStateSerializerScript.serializeCore(battleState)).to_utf8_buffer())
	return "sha256:%s" % context.finish().hex_encode()


func _recordOperation(eventType: String) -> void:
	for index in range(state.history.size() - 1, -1, -1):
		var event: Dictionary = state.history[index]
		if str(event.get("type", "")) == eventType:
			var operation: Dictionary = BattleStateSerializerScript.jsonSafe(event)
			operation["fingerprint"] = semanticFingerprint(state)
			operationLedger.append(operation)
			return
	assert(false, "Resolved operation missing from state history: %s" % eventType)


func _captureSideStartCheckpoint() -> void:
	assert(state.activeSideID != -1, "Checkpoint requires an open side turn.")
	sideStartCheckpoint = {
		"side_turn_count": state.sideTurnCount,
		"side_id": state.activeSideID,
		"fingerprint": semanticFingerprint(state),
		"state": state.serialize_state(),
		"ledger_count": operationLedger.size(),
	}


## Technical state replacement, reusable within the current side turn. Costs,
## eligibility and presentation are later gameplay/UI decisions.
func restoreSideTurn() -> Dictionary:
	if _resolutionDepth > 0:
		return {"success": false, "reason": "resolver_in_progress"}
	if sideStartCheckpoint.is_empty():
		return {"success": false, "reason": "missing_side_checkpoint"}
	if int(sideStartCheckpoint.get("side_turn_count", -1)) != state.sideTurnCount:
		return {"success": false, "reason": "checkpoint_expired"}
	var restored: BattleState = BattleStateSerializerScript.deserialize(
		sideStartCheckpoint["state"])
	if restored.contentFingerprint != state.contentFingerprint:
		return {"success": false, "reason": "content_fingerprint_mismatch"}
	if semanticFingerprint(restored) != str(sideStartCheckpoint.get("fingerprint", "")):
		return {"success": false, "reason": "checkpoint_fingerprint_mismatch"}
	var priorGeneration := state.timelineGeneration
	var branchID := operationLedger.size() + 1
	var abandonedCount := maxi(0, operationLedger.size() -
		int(sideStartCheckpoint.get("ledger_count", 0)))
	## Presentation is detached rather than destroyed. The adapter was built
	## against the state object that is about to be replaced, so leaving it
	## connected would feed the new timeline's events to something reading the
	## old board; but deciding what to draw instead is presentation's business,
	## and it is told through `timeline_restored` so it can rebuild once.
	if visualAdapter != null:
		visualAdapter.disconnectFromEvents()
	visualAdapter = null
	## Rebuilding the runtime replaces the event bus, which silently orphans
	## every listener connected to the old one. The announcement therefore has
	## to go out on the bus that still has listeners -- emitted on the new bus it
	## would reach nobody, and presentation would sit there holding a board that
	## no longer exists while hearing nothing further.
	var previousEvents := events
	state = restored
	state.timelineGeneration = priorGeneration + 1
	_rebuildRuntimeDependencies()
	var branchOperation := {
		"type": "side_turn_rewind",
		"actor_id": int(sideStartCheckpoint["side_id"]),
		"data": {
			"side_turn_count": int(sideStartCheckpoint["side_turn_count"]),
			"checkpoint_fingerprint": str(sideStartCheckpoint["fingerprint"]),
			"branch_id": branchID,
			"abandoned_operations": abandonedCount,
		},
		"fingerprint": semanticFingerprint(state),
	}
	operationLedger.append(branchOperation)
	## Announced after the state, resolvers and ledger are all consistent, so a
	## listener that rebuilds on this signal sees a finished restore -- and on
	## the previous bus, because that is where the listeners are. A listener
	## reconnects to `simulator.events`, which is now a different object.
	previousEvents.timeline_restored.emit(state.timelineGeneration, branchID)
	return {"success": true, "branch_id": branchID,
		"generation": state.timelineGeneration}


func createReplaySnapshot() -> Dictionary:
	if not hasPartyRuntime():
		return {
			"success": false,
			"reason": "square_reference_required",
			"detail": "Use the frozen square reference project for square replay files.",
		}
	var brainClasses = {}
	for monsterID in brains:
		var brain = brains[monsterID]
		brainClasses[str(monsterID)] = brain.get_script().resource_path.get_file().get_basename()

	var operations: Array = operationLedger.duplicate(true)
	var commands: Array = []
	for event in operationLedger:
		if event.get("type", "") == "unit_action":
			commands.append(BattleStateSerializerScript.jsonSafe(event))

	return BattleStateSerializerScript.jsonSafe({
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
		"sideStartCheckpoint": sideStartCheckpoint.duplicate(true),
		"commands": commands
	})


func restoreReplaySnapshot(snapshot: Dictionary) -> Dictionary:
	snapshot = BattleStateSerializerScript.restoreJsonSafe(snapshot)
	var nextGeneration := state.timelineGeneration + 1
	var version = int(snapshot.get("version", REPLAY_MIN_VERSION))
	if version <= SQUARE_REPLAY_MAX_VERSION:
		return {
			"success": false,
			"reason": "square_reference_required",
			"detail": "Use the frozen square reference project for square replay files.",
		}
	if version == PARTY_ACTIVATION_REPLAY_VERSION:
		return {"success": false, "reason": "party_activation_replay_unsupported"}
	if version != REPLAY_VERSION:
		return {"success": false, "reason": "unsupported_replay_version", "version": version}
	if not snapshot.has("currentState"):
		return {"success": false, "reason": "missing_current_state"}
	var identityError := _replayIdentityError(snapshot)
	if not identityError.is_empty():
		return {"success": false, "reason": identityError}
	var currentState: Dictionary = snapshot["currentState"]

	if visualAdapter != null:
		visualAdapter.disconnectFromEvents()
	visualAdapter = null
	state = BattleStateSerializerScript.deserialize(currentState)
	state.timelineGeneration = nextGeneration
	if computeContentFingerprint(state) != str(snapshot.get("contentFingerprint", "")):
		return {"success": false, "reason": "content_fingerprint_mismatch"}
	initialStateSnapshot = snapshot.get("initialState", {}).duplicate(true)
	setupSnapshot = snapshot.get("setup", {}).duplicate(true)
	var brainClasses: Dictionary = snapshot.get("brainClasses", {})
	_rebuildRuntimeDependencies(brainClasses)
	operationLedger.assign(snapshot.get("operations", []).duplicate(true))
	sideStartCheckpoint = snapshot.get("sideStartCheckpoint", {}).duplicate(true)

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


## Announces every living monster on the board to whatever is listening, then announces the
## battle itself. FHB-1: this used to have no caller at all -- a hex battle built its state
## directly through `BattleSetupFactory.createHexState()`, which is correct (setup builds a
## state, it does not narrate one), but nothing then told a connected visual adapter what was on
## the board. `HexBattleController.startBattle()` calls this once, right after the adapter
## connects and before the turn loop opens, which is what gives a hex battle its starting models.
##
## Kept under its original name as a thin delegate below for any caller still resolving it by
## that name -- a battle restored from a snapshot re-announces its board the same way a fresh one
## does, so the rename is cosmetic and the behaviour is identical either way.
func emitInitialBoard() -> void:
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
	_initialBoardEmitted = true


func emitRestoredBattle() -> void:
	emitInitialBoard()


func startBattle() -> void:
	if initialStateSnapshot.is_empty():
		initialStateSnapshot = state.serialize_state()
	if _initialBoardEmitted:
		return
	var monsterList = []
	for id in state.monsters:
		monsterList.append(id)
	events.battle_started.emit(state.boardSize, monsterList)


func runFullBattle(maxRounds: int = 50) -> int:
	if hasSideRuntime():
		return _runFullSideBattle(maxRounds)
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


## THE CAP COUNTS WHOLE ROUNDS (FHB-10). A round is the unit in which every surviving party
## activates once, in `partyOrder`, so finishing the round is what gives both sides the same number
## of activations. The loop used to test `roundCount < maxRounds` between activations, which ended
## the battle straight after the first party of the last round: in hexmap seed 14, team 2 acted in
## round 30 and team 1 never did. A turn cap would not be fairer -- parties differ in size and in
## how many members are still standing, so equal turns would mean unequal rounds.
##
## So the last round runs to its end, and only then is the cap checked: nothing active, nobody
## pending, `roundCount` at the cap. Its `round_end` is announced like every earlier one, because
## the round did finish; an elimination mid-round still ends without one.
func _runFullSideBattle(maxRounds: int) -> int:
	startBattle()
	while state.battleOutcome == -1:
		if (
			state.roundCount >= maxRounds
			and state.activeSideID == -1
			and state.pendingSideIDs.is_empty()
		):
			state.add_event("round_end", -1, -1, {"round": state.roundCount})
			events.round_ended.emit(state.roundCount)
			break
		var sideTurn := startNextSideTurn("headless")
		if not sideTurn["success"]:
			if sideTurn["reason"] in ["battle_ended", "round_complete"]:
				continue
			break
		while state.activeSideID != -1 and state.battleOutcome == -1:
			var eligible := eligibleSideUnitIDs()
			if eligible.is_empty():
				_closeSideTurn("no_eligible_units")
				break
			var memberID := int(eligible.front())
			if not selectUnit(memberID, "cpu")["success"]:
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


## The outcome a battle has when no side is left standing alone. Team ids start at 1 (a
## scenario's TEAM_ID must be positive), so 0 is free, and `checkWinCondition()` already answers 0
## when every side falls at once.
const DRAW_TEAM := 0


## The round-cap tally: most monsters still on the board wins, and A TIE IS A DRAW (FHB-10). It
## used to go to whichever team `teamRosters` happened to list first, because only a strictly
## larger count replaced the leader -- a result decided by dictionary order, not by the battle.
func _determineWinnerByNumbers() -> int:
	var bestTeam = DRAW_TEAM
	var bestCount = -1
	var tied := false
	for team in state.teamRosters:
		var count: int = state.getAliveMonsterIDs(team).size()
		if count > bestCount:
			bestCount = count
			bestTeam = team
			tied = false
		elif count == bestCount:
			tied = true
	return DRAW_TEAM if tied else bestTeam
