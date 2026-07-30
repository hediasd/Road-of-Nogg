## PlayerTurnController — Owns one player-controlled turn: which phase the
## player is in, what the command menu currently offers, and the submission of
## each phase through `BattleSimulator`'s incremental turn API.
##
## Extracted from `BattlePresentationController`, which kept the player state
## machine tangled with scene lifecycle, camera, pacing, and adapter wiring.
## The controller that remains routes input here and reacts to the signals
## below; it does not know what a phase is.
##
## The phase model, and why it is not the old one:
##
## ```text
## MENU -> MOVE_SELECT                     -> (resolve, animate) -> MENU
## MENU -> TARGET_SELECT -> CONFIRM_ACTION -> (resolve, animate) -> MENU
## MENU -> (Undo Move)                     -> (rewind, animate)  -> MENU
## MENU -> (Pass)                                                -> turn end
## ```
##
## The previous chain accumulated a whole turn and submitted it atomically at
## the end, so the player chose an action from a tile they were not standing on
## yet, and acting before moving was inexpressible. Here each phase resolves on
## its own and the menu reopens with that entry spent, in either order.
##
## Movement has no confirm step; `Undo Move` is the safety net, and it is
## withdrawn as soon as an action resolves — see `BattleSimulator.undoMovePhase`
## for why that rule is not negotiable.

class_name PlayerTurnController
extends RefCounted

## The menu model changed and should be rebuilt.
signal menu_changed
## Player-facing status line for the current phase.
signal status_changed(text: String)
## Read-only outcome preview for the action awaiting confirmation.
signal forecast_changed(text: String)
## Every phase is spent, or the player passed. The scene controller closes the
## turn out from here: end the turn, check the win condition, resume pacing.
signal turn_finished(monsterID: int)

enum Phase { INACTIVE, MENU, MOVE_SELECT, TARGET_SELECT, CONFIRM_ACTION, RESOLVING }

const ENTRY_MOVE := "move"
const ENTRY_UNDO_MOVE := "undo_move"
const ENTRY_ATTACK := "attack"
const ENTRY_MAGIC := "magic"
const ENTRY_PASS := "pass"

var phase: Phase = Phase.INACTIVE
var activeMonsterID: int = -1
var gridCursor := Vector2i.ZERO

var _sim: BattleSimulator
var _adapter
## () -> bool — true while the visual queue still has work to play. Kept as a
## callable so this class does not depend on a concrete adapter type.
var _isAnimating: Callable
## Signal the adapter emits when its queue empties.
var _drainedSignal: Signal

var _reachableTiles: Array = []
var _validTargetIDs: Array = []
var _pendingAction: String = ""
var _pendingTargetID: int = -1
var _pendingSpellSet: int = 0
var _pendingSpellIndex: int = 0
var _selectedSpellSet: int = -1
var _selectedSpellIndex: int = -1
var _waitingForDrain: bool = false


func _init(sim: BattleSimulator, adapter, isAnimating: Callable, drainedSignal: Signal) -> void:
	_sim = sim
	_adapter = adapter
	_isAnimating = isAnimating
	_drainedSignal = drainedSignal


func isActive() -> bool:
	return activeMonsterID != -1


func acceptsGridInput() -> bool:
	return phase in [Phase.MOVE_SELECT, Phase.TARGET_SELECT]


# --- Turn lifecycle --------------------------------------------------------


func beginTurn(monsterID: int) -> void:
	activeMonsterID = monsterID
	_pendingAction = ""
	_pendingTargetID = -1
	_selectedSpellSet = -1
	_selectedSpellIndex = -1
	_reachableTiles = []
	_validTargetIDs = []
	_waitingForDrain = false
	gridCursor = _sim.state.getMonsterPosition(monsterID)
	_selectFirstAvailableSpell()
	_enterMenu()


func endTurnNow() -> void:
	## Closes the turn and hands back to the scene controller. The simulator
	## writes its single aggregate command event here.
	if activeMonsterID == -1:
		return
	var completedID = activeMonsterID
	_sim.finishTurn(completedID, "player")
	_adapter.release_player_cursor()
	_adapter.clear_tactical_overlays()
	activeMonsterID = -1
	phase = Phase.INACTIVE
	_reachableTiles = []
	_validTargetIDs = []
	menu_changed.emit()
	turn_finished.emit(completedID)


# --- Menu model ------------------------------------------------------------


func menuEntries() -> Array:
	## The command menu as data, top to bottom, so the widget that renders it
	## owns no rules. `Pass` is always last and always enabled.
	if activeMonsterID == -1:
		return []
	var phases = _sim.turnPhaseState(activeMonsterID)
	var interactive = phase == Phase.MENU
	return [
		{
			"id": ENTRY_MOVE,
			"label": "Move",
			"enabled": interactive and not phases["has_moved"],
			"visible": true
		},
		{
			"id": ENTRY_UNDO_MOVE,
			"label": "Undo Move",
			"enabled": interactive,
			"visible": phases["can_undo_move"]
		},
		{
			"id": ENTRY_ATTACK,
			"label": "Attack",
			"enabled": interactive and not phases["has_acted"],
			"visible": true
		},
		{
			"id": ENTRY_MAGIC,
			"label": "Spell",
			"enabled": interactive and not phases["has_acted"] and not spellEntries().is_empty(),
			"visible": true
		},
		{
			"id": ENTRY_PASS,
			"label": "Pass",
			"enabled": interactive,
			"visible": true
		}
	]


func spellEntries() -> Array:
	## Every spell the active monster owns, ready or not. Cooldowns are shown
	## rather than hidden so the player can see what is coming back.
	if activeMonsterID == -1:
		return []
	var monster = _sim.state.getMonster(activeMonsterID)
	if monster == null:
		return []
	var entries: Array = []
	for setIndex in range(monster.spellSets.size()):
		for spellIndex in range(monster.spellSets[setIndex].size()):
			var spell = monster.spellSets[setIndex][spellIndex]
			var ready = monster.can_cast(spell)
			entries.append({
				"set_index": setIndex,
				"spell_index": spellIndex,
				"name": spell.name,
				"range": spell.range,
				"cooldown_remaining": int(monster.spell_cooldowns.get(spell.name, 0)),
				"ready": ready,
				"label": "%s [%s]" % [
					spell.name,
					"R%d" % spell.range if ready else "CD %d" % int(
						monster.spell_cooldowns.get(spell.name, 0)
					)
				]
			})
	return entries


func selectedSpell() -> Vector2i:
	return Vector2i(_selectedSpellSet, _selectedSpellIndex)


func selectSpell(setIndex: int, spellIndex: int) -> void:
	_selectedSpellSet = setIndex
	_selectedSpellIndex = spellIndex
	for entry in spellEntries():
		if entry["set_index"] == setIndex and entry["spell_index"] == spellIndex:
			status_changed.emit("%s — range %d, cooldown %d." % [
				entry["name"], entry["range"], entry["cooldown_remaining"]
			])
			return


# --- Menu selection --------------------------------------------------------


func selectMenuEntry(entryID: String) -> void:
	if phase != Phase.MENU or activeMonsterID == -1:
		return
	for entry in menuEntries():
		if entry["id"] != entryID:
			continue
		if not entry["visible"] or not entry["enabled"]:
			return
		break
	match entryID:
		ENTRY_MOVE: _enterMoveSelect()
		ENTRY_UNDO_MOVE: _undoMove()
		ENTRY_ATTACK: _enterTargetSelect("attack")
		ENTRY_MAGIC: _enterTargetSelect("spell")
		ENTRY_PASS: endTurnNow()


func cancel() -> void:
	## Walks back one phase. At the root menu there is nothing to walk back to;
	## a turn is only left through Pass or by spending both phases.
	match phase:
		Phase.MOVE_SELECT, Phase.TARGET_SELECT:
			_enterMenu()
		Phase.CONFIRM_ACTION:
			var previous_target_id = _pendingTargetID
			_enterTargetSelect(_pendingAction, previous_target_id)
		_:
			pass


func confirmSelection() -> void:
	## Accept in the current phase: commit the destination, pick the target, or
	## commit the action.
	match phase:
		Phase.MOVE_SELECT: _commitMove(gridCursor)
		Phase.TARGET_SELECT: _commitTarget(gridCursor)
		Phase.CONFIRM_ACTION: _commitAction()
		_:
			pass


func setCursor(pos: Vector2i) -> bool:
	if not acceptsGridInput() or not _sim.state.withinBounds(pos):
		return false
	if phase == Phase.TARGET_SELECT:
		var target_id = _targetIDAt(pos)
		if not _validTargetIDs.has(target_id):
			return false
		if pos == gridCursor:
			return true
		gridCursor = pos
		_refreshTargetPreview(target_id)
		return true
	gridCursor = pos
	_adapter.show_player_cursor(pos)
	_previewPath(pos)
	return true


func moveCursor(direction: Vector2i) -> void:
	if phase == Phase.TARGET_SELECT:
		_cycleTarget(-1 if direction in [Vector2i.LEFT, Vector2i.UP] else 1)
		return
	var next = gridCursor + direction
	next.x = clampi(next.x, 0, _sim.state.boardSize.x - 1)
	next.y = clampi(next.y, 0, _sim.state.boardSize.y - 1)
	setCursor(next)


func selectGridPosition(pos: Vector2i) -> void:
	## Mouse selection may only commit a legal destination or occupied target.
	if not acceptsGridInput():
		return
	if not setCursor(pos):
		if phase == Phase.TARGET_SELECT:
			status_changed.emit("Choose one of the yellow target tiles.")
		return
	confirmSelection()

# --- Phases ----------------------------------------------------------------


func _enterMenu(statusOverride: String = "") -> void:
	if activeMonsterID == -1:
		return
	phase = Phase.MENU
	_validTargetIDs = []
	_pendingAction = ""
	_pendingTargetID = -1
	forecast_changed.emit("")
	var pos = _sim.state.getMonsterPosition(activeMonsterID)
	gridCursor = pos
	_adapter.clear_tactical_overlays()
	_adapter.show_player_cursor(pos)
	var phases = _sim.turnPhaseState(activeMonsterID)
	if phases["has_moved"] and phases["has_acted"]:
		endTurnNow()
		return
	status_changed.emit(
		statusOverride if not statusOverride.is_empty() else _menuStatusText(phases)
	)
	menu_changed.emit()


func _menuStatusText(phases: Dictionary) -> String:
	if phases["has_moved"] and not phases["has_acted"]:
		return "Choose an action, or Pass to end the turn."
	if phases["has_acted"] and not phases["has_moved"]:
		return "Choose where to move, or Pass to end the turn."
	return "Choose a command."


func _enterMoveSelect() -> void:
	phase = Phase.MOVE_SELECT
	var currentPos = _sim.state.getMonsterPosition(activeMonsterID)
	_reachableTiles = _sim.movementResolver.getReachablePositions(activeMonsterID)
	if not _reachableTiles.has(currentPos):
		_reachableTiles.append(currentPos)
	gridCursor = currentPos
	_adapter.show_player_cursor(currentPos)
	_adapter.show_movement_options(_reachableTiles)
	status_changed.emit("Select a destination. Height %d." % _sim.state.getHeight(currentPos))
	menu_changed.emit()


func _previewPath(pos: Vector2i) -> void:
	if not _reachableTiles.has(pos):
		_adapter.show_movement_options(_reachableTiles)
		return
	_adapter.show_movement_options(_reachableTiles, _pathTo(pos))


func _pathTo(pos: Vector2i) -> Array:
	var currentPos = _sim.state.getMonsterPosition(activeMonsterID)
	if pos == currentPos:
		return []
	return _sim.movementResolver.findPath(currentPos, pos, 100)


func _commitMove(pos: Vector2i) -> void:
	if not _reachableTiles.has(pos):
		status_changed.emit("That tile is not reachable.")
		return
	var result = _sim.executeMovePhase(activeMonsterID, _pathTo(pos), "player")
	if not result.get("success", false):
		status_changed.emit("Cannot move there: %s" % result.get("reason", "unknown"))
		return
	_adapter.clear_tactical_overlays()
	_resolveThenReturnToMenu()


func _undoMove() -> void:
	var result = _sim.undoMovePhase(activeMonsterID)
	if not result.get("success", false):
		status_changed.emit("Cannot undo: %s" % result.get("reason", "unknown"))
		return
	status_changed.emit("Movement undone.")
	_resolveThenReturnToMenu()


func _enterTargetSelect(action: String, preferredTargetID: int = -1) -> void:
	_pendingAction = action
	_pendingTargetID = -1
	forecast_changed.emit("")
	var fromPos = _sim.state.getMonsterPosition(activeMonsterID)
	if action == "attack":
		_validTargetIDs = _sim.combatResolver.getBasicAttackTargetsFrom(activeMonsterID, fromPos)
	else:
		if _selectedSpellSet < 0:
			_selectFirstAvailableSpell()
		if _selectedSpellSet < 0:
			_enterMenu("No spell is ready.")
			return
		_validTargetIDs = _sim.combatResolver.getSpellTargetsFrom(
			activeMonsterID, _selectedSpellSet, _selectedSpellIndex, fromPos
		)

	if _validTargetIDs.is_empty():
		_enterMenu("No valid %s target from here." % (
			"attack" if action == "attack" else "spell"
		))
		return

	_sortValidTargets()
	phase = Phase.TARGET_SELECT
	var selected_target_id = (
		preferredTargetID if _validTargetIDs.has(preferredTargetID) else _validTargetIDs[0]
	)
	gridCursor = _sim.state.getMonsterPosition(selected_target_id)
	_refreshTargetPreview(selected_target_id)
	menu_changed.emit()


func _commitTarget(pos: Vector2i) -> void:
	var target_id = _targetIDAt(pos)
	if not _validTargetIDs.has(target_id):
		status_changed.emit("Choose one of the yellow target tiles.")
		return
	var target = _sim.state.getMonster(target_id)
	_pendingTargetID = target_id
	phase = Phase.CONFIRM_ACTION
	_refreshTargetPreview(target_id)
	status_changed.emit("Confirm %s on %s, or cancel to choose again." % [_pendingAction.capitalize(), target.name])
	forecast_changed.emit(_forecastText(target))
	menu_changed.emit()


func _targetIDAt(pos: Vector2i) -> int:
	var target = _sim.state.getMonsterAt(pos)
	return target.uniqueID if target != null else -1


func _sortValidTargets() -> void:
	_validTargetIDs.sort_custom(func(left_id: int, right_id: int) -> bool:
		var left_pos = _sim.state.getMonsterPosition(left_id)
		var right_pos = _sim.state.getMonsterPosition(right_id)
		if left_pos.y != right_pos.y:
			return left_pos.y < right_pos.y
		if left_pos.x != right_pos.x:
			return left_pos.x < right_pos.x
		return left_id < right_id
	)


func _cycleTarget(step: int) -> void:
	if _validTargetIDs.is_empty():
		return
	var current_id = _targetIDAt(gridCursor)
	var index = _validTargetIDs.find(current_id)
	index = 0 if index < 0 else posmod(index + step, _validTargetIDs.size())
	var target_id = _validTargetIDs[index]
	gridCursor = _sim.state.getMonsterPosition(target_id)
	_refreshTargetPreview(target_id)


func _refreshTargetPreview(targetID: int) -> void:
	if not _validTargetIDs.has(targetID):
		return
	var target = _sim.state.getMonster(targetID)
	if target == null:
		return
	var affected_positions: Array = [_sim.state.getMonsterPosition(targetID)]
	var affected_target_ids: Array = [targetID]
	var beneficial = false
	if _pendingAction == "spell":
		var caster = _sim.state.getMonster(activeMonsterID)
		var spell = caster.spellSets[_selectedSpellSet][_selectedSpellIndex]
		var from_pos = _sim.state.getMonsterPosition(activeMonsterID)
		affected_positions = _sim.combatResolver.getSpellAffectedPositionsFrom(
			activeMonsterID, _selectedSpellSet, _selectedSpellIndex, from_pos, targetID
		)
		affected_target_ids = _sim.combatResolver.getSpellAffectedTargetsFrom(
			activeMonsterID, _selectedSpellSet, _selectedSpellIndex, from_pos, targetID
		)
		beneficial = spell.heals or spell.targetType == "self"
	_adapter.show_target_options(
		_validTargetIDs, affected_positions, beneficial
	)
	_adapter.show_target_cursor(gridCursor)
	if affected_positions.size() > 1:
		status_changed.emit("Choose a target: %s. %d unit(s) in the affected area." % [
			target.name, affected_target_ids.size()
		])
	else:
		status_changed.emit("Choose a target: %s." % target.name)

func _commitAction() -> void:
	var result = _sim.executeActionPhase(
		activeMonsterID,
		_pendingAction,
		_pendingTargetID,
		_selectedSpellSet if _pendingAction == "spell" else 0,
		_selectedSpellIndex if _pendingAction == "spell" else 0,
		"player"
	)
	if not result.get("success", false):
		_enterMenu("Action rejected: %s" % result.get("reason", "unknown"))
		return
	_adapter.clear_tactical_overlays()
	_selectFirstAvailableSpell()
	_resolveThenReturnToMenu()


# --- Waiting for presentation ----------------------------------------------


func _resolveThenReturnToMenu() -> void:
	## A resolved phase animates before the menu reopens. Choosing a target
	## while the model is still walking would mean aiming from a tile the unit
	## has already left on screen.
	phase = Phase.RESOLVING
	menu_changed.emit()
	if not _isAnimating.call():
		_enterMenu()
		return
	if _waitingForDrain:
		return
	_waitingForDrain = true
	_drainedSignal.connect(_onQueueDrained, CONNECT_ONE_SHOT)


func _onQueueDrained() -> void:
	_waitingForDrain = false
	if phase != Phase.RESOLVING or activeMonsterID == -1:
		return
	_enterMenu()


func _selectFirstAvailableSpell() -> void:
	_selectedSpellSet = -1
	_selectedSpellIndex = -1
	for entry in spellEntries():
		if entry["ready"]:
			_selectedSpellSet = entry["set_index"]
			_selectedSpellIndex = entry["spell_index"]
			return

func _forecastText(target: Monster) -> String:
	var attacker = _sim.state.getMonster(activeMonsterID)
	var elevation = _sim.combatResolver.getElevationPercent(activeMonsterID, target.uniqueID)
	if _pendingAction == "attack":
		var damage = mini(target.hitpoints, _sim.combatResolver.calculateBasicDamage(attacker, target))
		return "Expected: %d damage / %d%% elevation" % [damage, elevation]
	var spell = attacker.spellSets[_selectedSpellSet][_selectedSpellIndex]
	if spell.heals:
		var healing = mini(target.max_hitpoints - target.hitpoints, _sim.combatResolver.calculateHeal(attacker, spell))
		return "Expected: %d healing" % healing
	var damage = 0
	for line in spell.damage_lines:
		damage += _sim.combatResolver.calculateSpellDamage(attacker, target, int(line.get("damage", 0)), str(line.get("element", "none")), true)
	damage = mini(target.hitpoints, damage)
	return "Expected: %d damage / %d%% elevation" % [damage, elevation]
