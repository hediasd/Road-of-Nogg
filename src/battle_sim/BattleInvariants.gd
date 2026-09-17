## What must be true of a battle between two resolved steps.
##
## The simulator calls this after every step that can change state -- a move, an undo, an action, a
## unit finishing, a side opening or closing -- when invariant checks are enabled. It is a pure
## read: it emits no events, touches no RNG and mutates nothing, so a run with checks on records
## exactly what a run with them off records.
##
## Every entry is a rule the rules in `docs/GAME_DESIGN.md` state, not a description of what the
## code currently does. A violation is therefore a bug in the simulator or in the rules doc, never
## something to relax until it passes.
##
## `BattleState.assertValidOccupancy()` covers part of the occupancy family with `assert()`, which
## the release build strips and which stops the process on the first failure. This returns every
## violation it finds, so a single failing run names all of them, and it works in any build.

class_name BattleInvariants
extends RefCounted


## Every invariant this state violates, as readable one-line strings. Empty means the state is
## legal. Order is stable so two runs produce comparable output.
static func violations(state: BattleState) -> Array[String]:
	var found: Array[String] = []
	if state == null:
		found.append("state is null")
		return found
	_checkOccupancy(state, found)
	_checkPlacement(state, found)
	_checkHitpoints(state, found)
	_checkSideBookkeeping(state, found)
	_checkPendingTurns(state, found)
	_checkWithdrawals(state, found)
	_checkEffects(state, found)
	_checkOutcome(state, found)
	return found


## One unit per cell, and the board layer agrees with the position lookup in both directions.
static func _checkOccupancy(state: BattleState, found: Array[String]) -> void:
	var occupants: Dictionary = {}
	for monsterID: int in _sortedIDs(state.monsterPositions):
		var pos: Vector2i = state.monsterPositions[monsterID]
		if not state.containsCell(pos):
			found.append("unit %d stands at %s, which is not a cell of this board" % [monsterID, pos])
			continue
		if occupants.has(pos):
			found.append("units %d and %d share cell %s" % [int(occupants[pos]), monsterID, pos])
		occupants[pos] = monsterID
		var occupant := int(state.board.at(pos))
		if occupant != monsterID:
			found.append("cell %s holds unit %d in the board layer but unit %d by position" % [
				pos, occupant, monsterID])
		if not state.isWalkable(pos):
			found.append("unit %d stands on unwalkable ground at %s" % [monsterID, pos])

	for y in range(state.boardSize.y):
		for x in range(state.boardSize.x):
			var pos := Vector2i(x, y)
			var occupant := int(state.board.at(pos))
			if occupant == 0:
				continue
			if not state.monsterPositions.has(occupant):
				found.append("the board layer holds unit %d at %s, which has no position" % [
					occupant, pos])
			elif state.monsterPositions[occupant] != pos:
				found.append("the board layer holds unit %d at %s while its position is %s" % [
					occupant, pos, state.monsterPositions[occupant]])


## Being on the board and being able to act agree: the living and present hold a cell, the dead and
## the withdrawn hold none. A withdrawn unit is alive but off the board at (-1, -1).
static func _checkPlacement(state: BattleState, found: Array[String]) -> void:
	for monsterID: int in _sortedIDs(state.monsters):
		var monster: Monster = state.monsters[monsterID]
		if monster == null:
			found.append("unit %d is registered as null" % monsterID)
			continue
		var placed: bool = state.monsterPositions.has(monsterID)
		var withdrawn: bool = state.isMonsterWithdrawn(monsterID)
		if withdrawn:
			if placed:
				found.append("withdrawn unit %d still holds cell %s" % [
					monsterID, state.monsterPositions[monsterID]])
			if monster.position != Vector2i(-1, -1):
				found.append("withdrawn unit %d reports position %s instead of (-1, -1)" % [
					monsterID, monster.position])
			continue
		if monster.is_alive() and not placed:
			found.append("living unit %d holds no cell" % monsterID)
		if not monster.is_alive() and placed:
			found.append("defeated unit %d still holds cell %s" % [
				monsterID, state.monsterPositions[monsterID]])
		if placed and monster.position != state.monsterPositions[monsterID]:
			found.append("unit %d reports position %s while the state places it at %s" % [
				monsterID, monster.position, state.monsterPositions[monsterID]])


## Hitpoints stay inside their own range.
static func _checkHitpoints(state: BattleState, found: Array[String]) -> void:
	for monsterID: int in _sortedIDs(state.monsters):
		var monster: Monster = state.monsters[monsterID]
		if monster == null:
			continue
		if monster.max_hitpoints <= 0:
			found.append("unit %d has a maximum of %d hitpoints" % [monsterID, monster.max_hitpoints])
		if monster.hitpoints < 0:
			found.append("unit %d has %d hitpoints" % [monsterID, monster.hitpoints])
		if monster.hitpoints > monster.max_hitpoints:
			found.append("unit %d has %d of %d hitpoints" % [
				monsterID, monster.hitpoints, monster.max_hitpoints])


## Side turns: one side is open at a time, in ascending team order, and it is never a side that has
## already taken its turn this round.
static func _checkSideBookkeeping(state: BattleState, found: Array[String]) -> void:
	if state.sideOrder.is_empty():
		return
	var seen: Dictionary = {}
	var previous := -1
	for sideID: int in state.sideOrder:
		if seen.has(sideID):
			found.append("side %d appears twice in this round's side order" % sideID)
		seen[sideID] = true
		if sideID <= previous:
			found.append("side order %s is not ascending by team id" % [state.sideOrder])
		previous = sideID
	for sideID: int in state.pendingSideIDs:
		if not seen.has(sideID):
			found.append("side %d is pending but not in this round's side order" % sideID)
	if state.activeSideID == -1:
		return
	if not seen.has(state.activeSideID):
		found.append("side %d is active but not in this round's side order" % state.activeSideID)
	if state.pendingSideIDs.has(state.activeSideID):
		found.append("side %d is active and still pending" % state.activeSideID)


## A spent unit is done for this side turn, and only a unit of the open side can be spent or hold a
## half-finished turn.
static func _checkPendingTurns(state: BattleState, found: Array[String]) -> void:
	for monsterID: int in _sortedIDs(state.spentUnitIDs):
		if not state.monsters.has(monsterID):
			found.append("unit %d is spent but not registered in this battle" % monsterID)
			continue
		var monster: Monster = state.monsters[monsterID]
		if monster != null and state.activeSideID != -1 and monster.team != state.activeSideID:
			found.append("unit %d of side %d is spent while side %d is open" % [
				monsterID, monster.team, state.activeSideID])
		if state.pendingUnitTurns.has(monsterID):
			found.append("unit %d is spent and still holds an unfinished turn" % monsterID)

	for monsterID: int in _sortedIDs(state.pendingUnitTurns):
		if not state.monsters.has(monsterID):
			found.append("unit %d holds an unfinished turn but is not registered" % monsterID)
			continue
		var monster: Monster = state.monsters[monsterID]
		if monster == null:
			continue
		if not monster.is_alive():
			found.append("defeated unit %d still holds an unfinished turn" % monsterID)
		if state.activeSideID != -1 and monster.team != state.activeSideID:
			found.append("unit %d of side %d holds an unfinished turn while side %d is open" % [
				monsterID, monster.team, state.activeSideID])
		var accumulator: Dictionary = state.pendingUnitTurns[monsterID]
		if bool(accumulator.get("has_moved", false)) and accumulator.get("action", "") == "spell":
			found.append("unit %d resolved magic after moving" % monsterID)


## A withdrawn party takes its whole membership off the board with it.
static func _checkWithdrawals(state: BattleState, found: Array[String]) -> void:
	for partyID: int in _sortedIDs(state.withdrawnPartyIDs):
		if not state.parties.has(partyID):
			found.append("party %d is withdrawn but not registered" % partyID)
			continue
		for monsterID: int in _sortedIDs(state.monsterPartyIDs):
			if int(state.monsterPartyIDs[monsterID]) != partyID:
				continue
			var monster: Monster = state.monsters.get(monsterID)
			if monster != null and not monster.is_alive():
				continue
			if not state.isMonsterWithdrawn(monsterID):
				found.append("unit %d belongs to withdrawn party %d but is not withdrawn" % [
					monsterID, partyID])


## Effects belong to units of this battle and never carry a negative duration.
static func _checkEffects(state: BattleState, found: Array[String]) -> void:
	for monsterID: int in _sortedIDs(state.activeEffects):
		if not state.monsters.has(monsterID):
			found.append("unit %d carries effects but is not registered in this battle" % monsterID)
			continue
		for effect: Dictionary in state.activeEffects[monsterID]:
			var effectName := str(effect.get("name", ""))
			if effectName.is_empty():
				found.append("unit %d carries an unnamed effect" % monsterID)
			if int(effect.get("remainingTurns", 0)) < 0:
				found.append("unit %d carries '%s' with %d turns remaining" % [
					monsterID, effectName, int(effect.get("remainingTurns", 0))])


## The outcome names a team that fought, a draw, or nothing yet.
static func _checkOutcome(state: BattleState, found: Array[String]) -> void:
	if state.battleOutcome == -1 or state.battleOutcome == 0:
		return
	if not state.teamRosters.has(state.battleOutcome) and not state.teamPartyIDs.has(
			state.battleOutcome):
		found.append("the battle is recorded as won by team %d, which never fought" % state.battleOutcome)


static func _sortedIDs(values: Dictionary) -> Array[int]:
	var result: Array[int] = []
	for value in values:
		result.append(int(value))
	result.sort()
	return result
