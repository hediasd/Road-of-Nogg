## One player-controlled member's turn: aim, move, act, and finish.
##
## REUSES `PlayerTurnController`'S SHAPE, NOT ITS GEOMETRY. The phase structure is the same one
## that already works -- an optional movement phase followed by an action, with move undo
## available until something irreversible happens -- because that is the simulator's contract and
## not a square-board idea. What is deliberately NOT carried over is the two things in that file
## that are square: clamping the cursor to a rectangle, and rotating a direction into one of four
## quadrants. A hex cursor is bounded by the map's valid-cell mask rather than by a rectangle, and
## its directions come from `HexBattleCursor` projecting the six neighbours through the live
## camera.
##
## THE SIMULATOR REMAINS AUTHORITATIVE. Nothing here writes to `BattleState`. Movement goes through
## `executeMovePhase`, actions through `executeActionPhase`, undo through `undoMovePhase`, and the
## turn closes through `finishTurn`; each returns a result this file reads rather than assumes.

class_name HexBattleMemberTurn
extends RefCounted

const ReachQueryScript = preload("res://src/battle_sim/ReachQuery.gd")

## Emitted once, when the member's turn is over for any reason -- acted, waited, or cancelled.
signal turn_finished(monsterID: int)

var _sim: BattleSimulator
var _adapter: HexBattleVisualAdapter
var _cursor: HexBattleCursor
var _map: BattleMapDefinition
var _monsterID: int
var _finished := false
var _reachable: Array = []
var _attackable: Array = []


func _init(
	sim: BattleSimulator,
	adapter: HexBattleVisualAdapter,
	cursor: HexBattleCursor,
	map: BattleMapDefinition,
	monsterID: int
) -> void:
	_sim = sim
	_adapter = adapter
	_cursor = cursor
	_map = map
	_monsterID = monsterID


func monsterID() -> int:
	return _monsterID


func isFinished() -> bool:
	return _finished


## Opens the turn: seats the cursor on the member and paints where it can go.
func begin() -> void:
	if _sim == null or _finished:
		return
	var origin: Vector2i = _sim.state.getMonsterPosition(_monsterID)
	if _cursor != null:
		_cursor.moveTo(origin, _map)
	if _adapter != null:
		_adapter.show_player_cursor(origin)
	refreshReach()


## Repaints the member's reach from the simulator's own reachability query, so the overlay and
## the movement the simulator will actually accept are the same set.
func refreshReach() -> void:
	if _sim == null or _adapter == null:
		return
	var reach := ReachQueryScript.forMonster(_sim, _monsterID)
	# The query answers from where the unit stands, not whether it may still walk. Once it has
	# moved or acted there is nowhere it can go, so nothing is painted and no cell accepts a move.
	_reachable = reach.get("reachable", []) if canMove() else []
	_attackable = reach.get("attackable", [])
	# Walkable cells only. Painting the attack ring beyond them read as one extra step of movement.
	_adapter.show_movement_options(_reachable)


func reachableCells() -> Array:
	return _reachable.duplicate()


## Steps the cursor one hex in a screen-space direction. `project` maps a cell to a viewport
## point; the controller supplies the live camera's own projection.
func moveCursor(input: Vector2, project: Callable) -> bool:
	if _cursor == null or _finished:
		return false
	var target := _cursor.neighbourFor(input, project, _map)
	if not _cursor.moveTo(target, _map):
		return false
	if _adapter != null:
		_adapter.show_player_cursor(target)
	return true


func cursorCell() -> Vector2i:
	return _cursor.cell() if _cursor != null else Vector2i(-1, -1)


## Puts the cursor on a named cell, for a mouse that is pointing rather than stepping. Same
## refusal rule as a keyboard step: a cell the map does not carry is not a place to point.
func pointCursorAt(cell: Vector2i) -> bool:
	if _cursor == null or _finished:
		return false
	if not _cursor.moveTo(cell, _map):
		return false
	if _adapter != null:
		_adapter.show_player_cursor(cell)
	return true


## What the turn still has left, and whether an undo would be accepted right now.
##
## All three read the simulator's own record of the turn in progress rather than flags kept here.
## The rules are its: a phase is spent once it has resolved, and an undo is legal only while the
## move is still the only thing that has happened. A second copy of that bookkeeping in this file
## is exactly the parallel flag the item forbids, and it would drift the first time the simulator
## refused something this file thought it had allowed.
##
## Read directly from the record because publishing a query for it would mean writing to
## `BattleSimulator`, which this item does not claim.
func canMove() -> bool:
	var record := _turnRecord()
	return not bool(record.get("has_moved", false)) and not bool(record.get("has_acted", false))


func canAct() -> bool:
	return not bool(_turnRecord().get("has_acted", false))


func canUndoMove() -> bool:
	var record := _turnRecord()
	return bool(record.get("has_moved", false)) and not bool(record.get("has_acted", false))


## Whether the simulator would admit ANY phase from this member right now, and its reason if not.
##
## The simulator's own guard, called rather than restated. A petrified member still has an unspent
## move and action in the turn record, so `canMove`/`canAct` alone would offer rows the simulator
## refuses on confirm. The guard is read-only: it compares ids and reads effects, and writes
## nothing. Private for the same reason `_turnRecord` is: publishing it would mean editing
## `BattleSimulator`, which this item does not own.
func phaseGuard() -> Dictionary:
	if _sim == null or _finished:
		return {"success": false, "reason": "turn_closed"}
	return _sim._guardPhase(_monsterID)


func _turnRecord() -> Dictionary:
	if _sim == null or _finished:
		return {}
	return _sim.turnPhaseState(_monsterID)


## Walks the member to the cursor, if the simulator accepts the path. Returns its result rather
## than a bare bool so a refusal carries its reason.
func confirmMove(path: Array) -> Dictionary:
	if _sim == null or _finished:
		return {"success": false, "reason": "turn_closed"}
	var result := _sim.executeMovePhase(_monsterID, path, "player")
	if bool(result.get("success", false)):
		refreshReach()
	return result


## Undo is available only while the move is still the only thing that has happened -- the
## simulator enforces that, and this reports what it decided rather than guessing.
func undoMove() -> Dictionary:
	if _sim == null or _finished:
		return {"success": false, "reason": "turn_closed"}
	var result := _sim.undoMovePhase(_monsterID)
	if bool(result.get("success", false)):
		begin()
	return result


## `action` is "wait", "attack" or "spell" -- the simulator's own action vocabulary, passed
## through rather than wrapped, so this file adds no third spelling of what a member can do.
func confirmAction(
	action: String,
	targetPos: Vector2i = Vector2i(-1, -1),
	spellSetIndex: int = 0,
	spellIndex: int = 0
) -> Dictionary:
	if _sim == null or _finished:
		return {"success": false, "reason": "turn_closed"}
	var result := _sim.executeActionPhase(
		_monsterID, action, targetPos, spellSetIndex, spellIndex, "player"
	)
	if bool(result.get("success", false)):
		refreshReach()
	return result


## Closes the turn. Wait and "done acting" are the same call, which is the approved rule: a wait
## consumes the member's turn exactly as an action does.
func finish() -> void:
	if _finished or _sim == null:
		return
	var result = _sim.finishTurn(_monsterID, "player")
	if not result.success:
		return
	_finished = true
	_clearOverlays()
	turn_finished.emit(_monsterID)


## Abandons the turn without closing it in the simulator -- used only when the battle is being
## torn down under it, where finishing a turn into a state that is about to be discarded would
## emit events nothing is listening for any more.
func cancel() -> void:
	if _finished:
		return
	_finished = true
	_clearOverlays()


func _clearOverlays() -> void:
	if _adapter == null:
		return
	_adapter.clear_tactical_overlays()
	_adapter.release_player_cursor()
