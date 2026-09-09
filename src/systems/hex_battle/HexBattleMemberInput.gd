## What the player is doing inside one member's turn, and how a key or a click becomes a phase
## call on the simulator.
##
## THE MENU IS THE HUB. A member turn opens on HBP-2's command menu rather than on a bare cursor,
## and every aim is entered from it and cancelled back to it. The alternative -- a cursor that is
## always live and a menu that appears only sometimes -- gives the same input two meanings
## depending on state the player cannot see, which is the disagreement this item's risk names.
##
## ONE CURSOR, AND THE LAST DEVICE TO MOVE IT OWNS IT. Mouse hover and the arrow keys both drive
## the same `HexBattleCursor`, so there is exactly one selected cell at any moment and a confirm
## can only mean that cell. Neither device locks the other out: reaching for the mouse moves the
## cursor to what the mouse is over, and a subsequent arrow key steps from there rather than
## jumping back to wherever the keyboard last was. Making one device authoritative would leave the
## visible cursor and the device in the player's hand disagreeing, which is worse than either
## device occasionally moving the other's selection.
##
## PHASE ORDER IS THE SIMULATOR'S. Move and action can happen in either order and this file does
## not impose one; it asks what is still unspent and offers exactly that. Undo eligibility is read
## from the simulator's own turn record rather than tracked here.

class_name HexBattleMemberInput
extends RefCounted

const CANCEL_COMMAND := "cancel"
const MOVE_COMMAND := "move"
const ATTACK_COMMAND := "attack"
const UNDO_COMMAND := "undo"
const END_COMMAND := "end"
## Spell rows carry their own coordinates: "spell:<setIndex>:<spellIndex>".
const SPELL_PREFIX := "spell"

enum Phase { MENU, AIM_MOVE, AIM_ATTACK, AIM_SPELL }

## The menu model changed and the HUD should show this. Emitted rather than pushed so this file
## needs no reference to the HUD.
signal menu_changed(model: Dictionary)
## The menu should not be on screen at all -- the player is aiming, or the turn is over.
signal menu_dismissed()
signal status_changed(text: String)

var _turn: HexBattleMemberTurn
var _sim: BattleSimulator
var _adapter: HexBattleVisualAdapter
var _map: BattleMapDefinition
var _phase: Phase = Phase.MENU
var _spellSetIndex := 0
var _spellIndex := 0


func _init(
	turn: HexBattleMemberTurn,
	sim: BattleSimulator,
	adapter: HexBattleVisualAdapter,
	map: BattleMapDefinition
) -> void:
	_turn = turn
	_sim = sim
	_adapter = adapter
	_map = map


func phase() -> Phase:
	return _phase


func isAiming() -> bool:
	return _phase != Phase.MENU


## Opens the turn on the menu.
func begin() -> void:
	_toMenu()


# --- cursor -----------------------------------------------------------------

## A direction from the keyboard or a pad. `project` maps a cell to a viewport point; the caller
## supplies the live camera's own projection, which is what lets the six neighbours be resolved on
## screen instead of through a fixed table.
func aimDirection(input: Vector2, project: Callable) -> bool:
	if not isAiming() or _turn == null:
		return false
	if not _turn.moveCursor(input, project):
		return false
	_refreshAimFeedback()
	return true


## The mouse is over a cell. Same cursor the keyboard drives, so a confirm after a hover and a
## confirm after an arrow key mean the same thing.
func aimAt(cell: Vector2i) -> bool:
	if not isAiming() or _turn == null:
		return false
	if not _turn.pointCursorAt(cell):
		return false
	_refreshAimFeedback()
	return true


func cursorCell() -> Vector2i:
	return _turn.cursorCell() if _turn != null else Vector2i(-1, -1)


# --- menu -------------------------------------------------------------------

## The player picked a row. Returns whether the choice was accepted, so a refusal is visible
## rather than silent.
func chooseCommand(commandID: String) -> bool:
	if _turn == null or _turn.isFinished():
		return false
	if commandID.begins_with(SPELL_PREFIX + ":"):
		return _beginSpellAim(commandID)
	match commandID:
		MOVE_COMMAND:
			if not _turn.canMove():
				return false
			_phase = Phase.AIM_MOVE
			_enterAim("Choose where to move.")
			return true
		ATTACK_COMMAND:
			if not _turn.canAct():
				return false
			_phase = Phase.AIM_ATTACK
			_enterAim("Choose a target.")
			return true
		UNDO_COMMAND:
			# Attempted rather than pre-judged: the simulator decides, and its refusal reason is
			# the honest one to show.
			var undone := _turn.undoMove()
			if not bool(undone.get("success", false)):
				status_changed.emit("Cannot undo: %s" % str(undone.get("reason", "")))
				return false
			_toMenu()
			return true
		END_COMMAND:
			_turn.finish()
			menu_dismissed.emit()
			return true
	return false


## Backs out of an aim. At the menu there is nothing to back out of, and the turn is deliberately
## not cancellable from here -- a member turn ends by acting or waiting, never by escaping.
func cancel() -> bool:
	if not isAiming():
		return false
	_toMenu()
	return true


# --- confirm ----------------------------------------------------------------

## Commits whatever is being aimed at the cursor's current cell. Returns the simulator's own
## result for a phase call, or a refusal carrying a reason.
func confirm() -> Dictionary:
	if _turn == null or _turn.isFinished():
		return {"success": false, "reason": "turn_closed"}
	match _phase:
		Phase.AIM_MOVE:
			return _confirmMove()
		Phase.AIM_ATTACK:
			return _confirmAction(ATTACK_COMMAND)
		Phase.AIM_SPELL:
			return _confirmAction(SPELL_PREFIX)
	return {"success": false, "reason": "not_aiming"}


func _confirmMove() -> Dictionary:
	var destination := _turn.cursorCell()
	var origin: Vector2i = _sim.state.getMonsterPosition(_turn.monsterID())
	# Standing still is a legal outcome of a move phase, but there is no path to walk for it, and
	# the resolver would answer an empty path for an unreachable cell too. Distinguished here so a
	# confirm on the member's own tile does not read as a refusal.
	if destination == origin:
		_toMenu()
		return {"success": true, "destination": origin, "unmoved": true}
	var path: Array = _sim.movementResolver.findPath(origin, destination)
	if path.is_empty():
		status_changed.emit("Cannot reach that cell.")
		return {"success": false, "reason": "unreachable"}
	var result := _turn.confirmMove(path)
	if not bool(result.get("success", false)):
		status_changed.emit("Move refused: %s" % str(result.get("reason", "")))
		return result
	_afterPhase()
	return result


func _confirmAction(kind: String) -> Dictionary:
	var targetPos := _turn.cursorCell()
	var result: Dictionary
	if kind == SPELL_PREFIX:
		result = _turn.confirmAction("spell", targetPos, _spellSetIndex, _spellIndex)
	else:
		result = _turn.confirmAction("attack", targetPos)
	if not bool(result.get("success", false)):
		status_changed.emit("Refused: %s" % str(result.get("reason", "")))
		return result
	_afterPhase()
	return result


## After any accepted phase: close the turn when nothing is left to choose, and otherwise return
## to the menu offering only what remains. The simulator allows move and action in either order,
## so this asks what is unspent rather than assuming acting was last.
func _afterPhase() -> void:
	if _turn.canMove() or _turn.canAct():
		_toMenu()
		return
	_turn.finish()
	menu_dismissed.emit()


# --- internals --------------------------------------------------------------

func _beginSpellAim(commandID: String) -> bool:
	if not _turn.canAct():
		return false
	var parts := commandID.split(":")
	if parts.size() != 3:
		return false
	_spellSetIndex = int(parts[1])
	_spellIndex = int(parts[2])
	_phase = Phase.AIM_SPELL
	_enterAim("Choose where to cast.")
	return true


func _toMenu() -> void:
	_phase = Phase.MENU
	if _turn != null:
		_turn.begin()
	if _adapter != null:
		_adapter.clearCommandPreview()
	menu_changed.emit(commandModel())
	status_changed.emit("Choose a command.")


func _enterAim(prompt: String) -> void:
	menu_dismissed.emit()
	status_changed.emit(prompt)
	_refreshAimFeedback()


## Paints what the pending command would do from the cursor's cell, using HBP-3's preview layer.
## Movement already has its reach overlay, so only the action aims add anything here.
func _refreshAimFeedback() -> void:
	if _adapter == null:
		return
	var cell := _turn.cursorCell()
	var casterPos: Vector2i = _sim.state.getMonsterPosition(_turn.monsterID())
	match _phase:
		Phase.AIM_ATTACK:
			_adapter.showCommandPreview([cell], [cell])
		Phase.AIM_SPELL:
			var cells: Array = _adapter.previewSpellCells(
				_turn.monsterID(), _spellSetIndex, _spellIndex, casterPos, cell
			)
			_adapter.showCommandPreview(cells, [cell])
		_:
			_adapter.clearCommandPreview()


## The model HBP-2's menu renders. Every row's `enabled` is an answer from the simulator or the
## monster itself -- what is still unspent, and what the caster can currently afford -- rather
## than a rule restated here.
func commandModel() -> Dictionary:
	if _turn == null or _sim == null:
		return {}
	var monster = _sim.state.getMonster(_turn.monsterID())
	if monster == null:
		return {}

	var commands: Array = []
	commands.append({
		"id": MOVE_COMMAND, "label": "Move", "enabled": _turn.canMove(),
		"detail": "", "spent": not _turn.canMove(),
	})
	commands.append({
		"id": ATTACK_COMMAND, "label": "Attack", "enabled": _turn.canAct(),
		"detail": "", "spent": not _turn.canAct(),
	})
	for setIndex in range(monster.spellSets.size()):
		for spellIndex in range(monster.spellSets[setIndex].size()):
			var spell = monster.spellSets[setIndex][spellIndex]
			var castable: bool = _turn.canAct() and monster.can_cast(spell)
			commands.append({
				"id": "%s:%d:%d" % [SPELL_PREFIX, setIndex, spellIndex],
				"label": str(spell.name),
				"enabled": castable,
				"detail": "Rng %d" % int(spell.range),
				"spent": not _turn.canAct(),
			})
	commands.append({
		"id": UNDO_COMMAND, "label": "Undo move", "enabled": _turn.canUndoMove(),
		"detail": "", "spent": false,
	})
	commands.append({
		"id": END_COMMAND, "label": "End turn", "enabled": true, "detail": "", "spent": false,
	})

	return {
		"input_enabled": true,
		"title": str(monster.name),
		"commands": commands,
	}
