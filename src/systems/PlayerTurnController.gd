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
## Cancelling a confirm that never showed a target chooser should land the
## player back where they actually made their last choice — the spell list.
## This controller does not own that window, so it asks rather than reaches.
signal spell_list_requested

enum Phase { INACTIVE, MENU, MOVE_SELECT, TARGET_SELECT, CONFIRM_ACTION, RESOLVING }

const ReachQueryScript = preload("res://src/battle_sim/ReachQuery.gd")

const ENTRY_MOVE := "move"
const ENTRY_UNDO_MOVE := "undo_move"
const ENTRY_ATTACK := "attack"
const ENTRY_MAGIC := "magic"
const ENTRY_PASS := "pass"

var phase: Phase = Phase.INACTIVE
var activeMonsterID: int = -1
var gridCursor := Vector2i.ZERO

var _sim: BattleSimulator
## The interactive visual port. Busy state and the drain signal come from here
## directly; they used to be passed separately as a Callable and a Signal so
## this class could stay adapter-agnostic, which the typed port now provides.
var _adapter: IPlayerTurnVisualAdapter

var _reachableTiles: Array = []
var _attackableTiles: Array = []
var _validTargetPositions: Array = []
var _pendingAction: String = ""
var _pendingTargetPos := Vector2i(-1, -1)
var _pendingSpellSet: int = 0
var _pendingSpellIndex: int = 0
var _selectedSpellSet: int = -1
var _selectedSpellIndex: int = -1
var _waitingForDrain: bool = false
## Which path reached CONFIRM_ACTION. Tracked explicitly rather than
## re-derived from the spell, because `cancel()` must undo the transition that
## actually happened: re-entering target select for a spell that never showed
## it would strand the player in a chooser with one option.
var _confirmSkippedTargetSelect: bool = false


func _init(sim: BattleSimulator, adapter: IPlayerTurnVisualAdapter) -> void:
	_sim = sim
	_adapter = adapter


func isActive() -> bool:
	return activeMonsterID != -1


func acceptsGridInput() -> bool:
	return phase in [Phase.MOVE_SELECT, Phase.TARGET_SELECT]


## Vertical target-select input has spell meaning only while aiming a spell.
## Attack targeting keeps all four directions on legal-target cycling.
func canCycleTargetSpell() -> bool:
	return phase == Phase.TARGET_SELECT and _pendingAction == "spell"


# --- Turn lifecycle --------------------------------------------------------


func beginTurn(monsterID: int) -> void:
	activeMonsterID = monsterID
	_pendingAction = ""
	_pendingTargetPos = Vector2i(-1, -1)
	_selectedSpellSet = -1
	_selectedSpellIndex = -1
	_reachableTiles = []
	_attackableTiles = []
	_validTargetPositions = []
	_waitingForDrain = false
	_confirmSkippedTargetSelect = false
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
	_attackableTiles = []
	_validTargetPositions = []
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
			# "Undo" not "Undo Move": a move is the only thing undoable, the row
			# sits directly under Move, and the short form lets the command window
			# size to ATTACK instead of to this label. Id stays `undo_move`.
			"label": "Undo",
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
				# Not the same question as "range == 0". `Think`/`Thought` on
				# Mage Dragon are `targetType == "single"` with `RANGE: 0` —
				# real, monster-attached spells that can only ever reach the
				# caster's own tile, the same as a self spell functionally,
				# but not one by the data. Labelling those "Self" would claim
				# a targeting rule the spell does not have.
				"self_targeted": spellOffersNoTargetChoice(spell),
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


## The tiles the player may currently aim at, as a copy. Exists so the scene
## controller can resolve an ambiguous mouse pick toward a legal target
## without reaching into private phase state; empty outside `TARGET_SELECT`.
func validTargetPositions() -> Array:
	return _validTargetPositions.duplicate()


## The tile a click must land on to confirm during `CONFIRM_ACTION`. Follows
## `validTargetPositions()`'s pattern — a read-only view of private phase
## state, so the scene controller can compare a clicked tile without reaching
## in. `Vector2i(-1, -1)` outside `CONFIRM_ACTION`, matching the sentinel
## `_pendingTargetPos` itself uses before a target is committed.
func pendingTargetPosition() -> Vector2i:
	return _pendingTargetPos


func selectedSpell() -> Vector2i:
	return Vector2i(_selectedSpellSet, _selectedSpellIndex)


func selectSpell(setIndex: int, spellIndex: int) -> void:
	_selectedSpellSet = setIndex
	_selectedSpellIndex = spellIndex
	for entry in spellEntries():
		if entry["set_index"] == setIndex and entry["spell_index"] == spellIndex:
			# "Range 0" is honest for a spell that genuinely has one (Think,
			# Thought — see spellEntries()) but wrong for a true self spell,
			# where the concept of range does not apply at all.
			var range_text = (
				"self" if bool(entry["self_targeted"])
				else "range %d" % int(entry["range"])
			)
			status_changed.emit("%s — %s, cooldown %d." % [
				entry["name"], range_text, entry["cooldown_remaining"]
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
			# Undo the transition that actually happened. A confirm reached
			# without a chooser goes back to the spell list — the last place
			# the player made a real choice — not into a one-option chooser
			# they were deliberately spared.
			if _confirmSkippedTargetSelect:
				_enterMenu()
				# After _enterMenu(), so the root window is on screen and the
				# spell column opens beside it rather than over nothing.
				spell_list_requested.emit()
			else:
				var previous_target_pos := _pendingTargetPos
				_enterTargetSelect(_pendingAction, previous_target_pos)
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
		if not _validTargetPositions.has(pos):
			return false
		if pos == gridCursor:
			return true
		gridCursor = pos
		_refreshTargetPreview(pos)
		return true
	gridCursor = pos
	_adapter.show_player_cursor(pos)
	_previewPath(pos)
	return true


func moveCursor(direction: Vector2i) -> void:
	if phase == Phase.TARGET_SELECT:
		_cycleTargetPosition(-1 if direction in [Vector2i.LEFT, Vector2i.UP] else 1)
		return
	var next = gridCursor + direction
	next.x = clampi(next.x, 0, _sim.state.boardSize.x - 1)
	next.y = clampi(next.y, 0, _sim.state.boardSize.y - 1)
	setCursor(next)


func cycleTargetSpell(step: int) -> void:
	if not canCycleTargetSpell():
		return
	var ready_entries: Array = []
	for entry in spellEntries():
		if bool(entry["ready"]):
			ready_entries.append(entry)
	if ready_entries.size() <= 1:
		return

	var current_index := -1
	for index in range(ready_entries.size()):
		var entry = ready_entries[index]
		if (
			int(entry["set_index"]) == _selectedSpellSet and
			int(entry["spell_index"]) == _selectedSpellIndex
		):
			current_index = index
			break
	if current_index < 0:
		current_index = 0

	var previous_target := gridCursor
	var from_pos := _sim.state.getMonsterPosition(activeMonsterID)
	for offset in range(1, ready_entries.size() + 1):
		var candidate_index := posmod(
			current_index + step * offset, ready_entries.size()
		)
		var candidate = ready_entries[candidate_index]
		var candidate_positions: Array = _sim.combatResolver.getSpellTargetPositionsFrom(
			activeMonsterID,
			int(candidate["set_index"]),
			int(candidate["spell_index"]),
			from_pos,
			true
		)
		if candidate_positions.is_empty():
			continue
		_selectedSpellSet = int(candidate["set_index"])
		_selectedSpellIndex = int(candidate["spell_index"])
		_validTargetPositions = candidate_positions
		_sortValidTargetPositions()
		gridCursor = (
			previous_target
			if _validTargetPositions.has(previous_target)
			else _validTargetPositions[0]
		)
		_refreshTargetPreview(gridCursor)
		return


func selectGridPosition(pos: Vector2i) -> void:
	## Mouse selection may only commit a legal destination or displayed center.
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
	_reachableTiles = []
	_attackableTiles = []
	_validTargetPositions = []
	_pendingAction = ""
	_pendingTargetPos = Vector2i(-1, -1)
	_confirmSkippedTargetSelect = false
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


## Empty for the baseline case (both phases still open): the command window
## being open already says "choose a command," and a prompt that repeats it
## was the third-largest permanently-drawn element in the HUD for zero new
## information. The other two strings stay — each names a constraint the
## command window's enabled/disabled rows don't spell out on their own (which
## specific phase is now closed off, and that Pass still ends the turn).
func _menuStatusText(phases: Dictionary) -> String:
	if phases["has_moved"] and not phases["has_acted"]:
		return "Choose an action, or Pass to end the turn."
	if phases["has_acted"] and not phases["has_moved"]:
		return "Choose where to move, or Pass to end the turn."
	return ""


func _enterMoveSelect() -> void:
	phase = Phase.MOVE_SELECT
	var currentPos = _sim.state.getMonsterPosition(activeMonsterID)
	var reach: Dictionary = ReachQueryScript.forMonster(_sim, activeMonsterID)
	_reachableTiles = reach["reachable"]
	_attackableTiles = reach["attackable"]
	gridCursor = currentPos
	_adapter.show_player_cursor(currentPos)
	_adapter.show_movement_options(_reachableTiles, [], _attackableTiles)
	status_changed.emit("Select a destination. Height %d." % _sim.state.getHeight(currentPos))
	menu_changed.emit()


func _previewPath(pos: Vector2i) -> void:
	if not _reachableTiles.has(pos):
		_adapter.show_movement_options(_reachableTiles, [], _attackableTiles)
		return
	_adapter.show_movement_options(
		_reachableTiles, _pathTo(pos), _attackableTiles
	)


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


func _enterTargetSelect(
		action: String,
		preferredTargetPos: Vector2i = Vector2i(-1, -1)) -> void:
	_pendingAction = action
	_pendingTargetPos = Vector2i(-1, -1)
	_confirmSkippedTargetSelect = false
	forecast_changed.emit("")
	var fromPos = _sim.state.getMonsterPosition(activeMonsterID)
	if action == "attack":
		_validTargetPositions = _sim.combatResolver.getBasicAttackTargetPositionsFrom(
			activeMonsterID, fromPos
		)
	else:
		if _selectedSpellSet < 0:
			_selectFirstAvailableSpell()
		if _selectedSpellSet < 0:
			_enterMenu("No spell is ready.")
			return
		# Empty centers are always displayed for non-self spells. The authored
		# CAN_TARGET_EMPTY flag is checked separately when the player confirms.
		_validTargetPositions = _sim.combatResolver.getSpellTargetPositionsFrom(
			activeMonsterID,
			_selectedSpellSet,
			_selectedSpellIndex,
			fromPos,
			true
		)

	if _validTargetPositions.is_empty():
		_enterMenu("No valid %s target from here." % (
			"attack" if action == "attack" else "spell"
		))
		return

	_sortValidTargetPositions()
	# A spell with no target choice goes straight to confirm. The guards above
	# still ran, so an unready spell has already been turned away and
	# `_validTargetPositions` is populated — which `_refreshTargetPreview()`
	# requires, and which is why this branch sits here rather than earlier.
	if action == "spell" and _selectedSpellOffersNoTargetChoice():
		_enterConfirmAction(fromPos, true)
		return

	phase = Phase.TARGET_SELECT
	gridCursor = (
		preferredTargetPos
		if _validTargetPositions.has(preferredTargetPos)
		else _validTargetPositions[0]
	)
	_refreshTargetPreview(gridCursor)
	menu_changed.emit()


## True when the selected spell can only ever be aimed at one tile, so asking
## the player to choose is ceremony rather than a decision.
##
## Derived from the authored spell, never from `_validTargetPositions.size()`:
## a ranged spell with one enemy left in reach also has a single entry, and
## silently skipping aiming for it would be wrong the moment a second enemy
## walks into range.
func _selectedSpellOffersNoTargetChoice() -> bool:
	if _selectedSpellSet < 0 or _selectedSpellIndex < 0:
		return false
	var caster = _sim.state.getMonster(activeMonsterID)
	if caster == null:
		return false
	var spell = caster.spellSets[_selectedSpellSet][_selectedSpellIndex]
	return spellOffersNoTargetChoice(spell)


## Shared with `spellEntries()`'s `self_targeted` label, which is what
## `PlayerCommandMenu` renders `Self` from. One predicate, so a spell can never
## be labelled `Self` in the list and still show a chooser when picked, or the
## reverse. Static and spell-only — no read of controller state — so both call
## sites can use it without one depending on the other's context.
static func spellOffersNoTargetChoice(spell: Spell) -> bool:
	return spell.targetType == "self" and spell.range == 0


## The tail shared by the ordinary target-select commit and the no-choice
## spell path. Factored rather than duplicated so the two can never drift on
## what entering confirm means.
func _enterConfirmAction(pos: Vector2i, skippedTargetSelect: bool) -> void:
	_pendingTargetPos = pos
	_confirmSkippedTargetSelect = skippedTargetSelect
	phase = Phase.CONFIRM_ACTION
	_refreshTargetPreview(pos)
	var target = _sim.state.getMonsterAt(pos)
	var confirm_text: String
	if target != null and target.uniqueID == activeMonsterID:
		# "on yourself", not "at <own name>": the latter read as if the caster
		# were a target that had been found somewhere else on the board.
		confirm_text = "Confirm %s on yourself, or cancel to choose again." % _pendingAction.capitalize()
	else:
		var target_label = target.name if target != null else "tile %s" % str(pos)
		confirm_text = "Confirm %s at %s, or cancel to choose again." % [
			_pendingAction.capitalize(), target_label
		]
	status_changed.emit(confirm_text)
	menu_changed.emit()


func _commitTarget(pos: Vector2i) -> void:
	if not _validTargetPositions.has(pos):
		status_changed.emit("Choose one of the yellow target tiles.")
		return
	if not _canConfirmTarget(pos):
		status_changed.emit("This spell cannot be cast on an empty tile.")
		forecast_changed.emit(_forecastText(pos))
		return
	_enterConfirmAction(pos, false)


func _canConfirmTarget(pos: Vector2i) -> bool:
	if not _validTargetPositions.has(pos):
		return false
	if _pendingAction == "attack":
		return true
	var from_pos = _sim.state.getMonsterPosition(activeMonsterID)
	return _sim.combatResolver.canSpellTargetPositionFrom(
		activeMonsterID,
		_selectedSpellSet,
		_selectedSpellIndex,
		from_pos,
		pos
	)


func _sortValidTargetPositions() -> void:
	_validTargetPositions.sort_custom(func(left_pos: Vector2i, right_pos: Vector2i) -> bool:
		if left_pos.y != right_pos.y:
			return left_pos.y < right_pos.y
		return left_pos.x < right_pos.x
	)


func _cycleTargetPosition(step: int) -> void:
	if _validTargetPositions.is_empty():
		return
	var index = _validTargetPositions.find(gridCursor)
	index = 0 if index < 0 else posmod(index + step, _validTargetPositions.size())
	gridCursor = _validTargetPositions[index]
	_refreshTargetPreview(gridCursor)


func _refreshTargetPreview(centerPos: Vector2i) -> void:
	if not _validTargetPositions.has(centerPos):
		return
	var target = _sim.state.getMonsterAt(centerPos)
	var target_id = target.uniqueID if target != null else -1
	var affected_positions: Array = [centerPos]
	var affected_target_ids: Array = [] if target == null else [target_id]
	var beneficial = false
	var armed_spell_name := ""
	if _pendingAction == "spell":
		var armed_caster = _sim.state.getMonster(activeMonsterID)
		if armed_caster != null:
			armed_spell_name = armed_caster.spellSets[
				_selectedSpellSet
			][_selectedSpellIndex].name
	if _pendingAction == "spell":
		var caster = _sim.state.getMonster(activeMonsterID)
		var spell = caster.spellSets[_selectedSpellSet][_selectedSpellIndex]
		var from_pos = _sim.state.getMonsterPosition(activeMonsterID)
		affected_positions = _sim.combatResolver.getSpellAffectedPositionsFrom(
			activeMonsterID,
			_selectedSpellSet,
			_selectedSpellIndex,
			from_pos,
			centerPos,
			true
		)
		affected_target_ids = _sim.combatResolver.getSpellAffectedTargetsFrom(
			activeMonsterID,
			_selectedSpellSet,
			_selectedSpellIndex,
			from_pos,
			centerPos,
			true
		)
		beneficial = spell.heals or spell.targetType == "self"
	_adapter.show_target_options(_validTargetPositions, affected_positions, beneficial)
	_adapter.show_target_cursor(centerPos)
	_adapter.show_target_status(target_id)
	forecast_changed.emit(_forecastText(centerPos))
	var armed_prefix := ("%s: " % armed_spell_name) if not armed_spell_name.is_empty() else ""
	if target != null:
		var target_name = "yourself" if target.uniqueID == activeMonsterID else target.name
		status_changed.emit("%sChoose a target: %s. %d unit(s) in the affected area." % [
			armed_prefix, target_name, affected_target_ids.size()
		])
	elif not _canConfirmTarget(centerPos):
		status_changed.emit("%sPreview tile %s. Empty-center casting is disabled." % [
			armed_prefix, str(centerPos)
		])
	elif affected_target_ids.is_empty():
		status_changed.emit("%sChoose a target tile. No units are in the affected area." % armed_prefix)
	else:
		status_changed.emit("%sChoose a target tile. %d unit(s) in the affected area." % [
			armed_prefix, affected_target_ids.size()
		])

func _commitAction() -> void:
	var result = _sim.executeActionPhase(
		activeMonsterID,
		_pendingAction,
		_pendingTargetPos,
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
	if not _adapter.isAnimationBusy():
		_enterMenu()
		return
	if _waitingForDrain:
		return
	_waitingForDrain = true
	_adapter.animation_queue_drained.connect(_onQueueDrained, CONNECT_ONE_SHOT)


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

func _forecastText(centerPos: Vector2i) -> String:
	var attacker = _sim.state.getMonster(activeMonsterID)
	if attacker == null:
		return ""
	var center_target = _sim.state.getMonsterAt(centerPos)
	if _pendingAction == "attack":
		if center_target == null:
			return "Expected: miss (0 units affected)\nAction will be spent"
		# is_simulation=true prevents passive_triggered from firing during a
		# read-only preview.
		var damage = mini(
			center_target.hitpoints,
			_sim.combatResolver.calculateBasicDamage(attacker, center_target, true)
		)
		var elevation = _sim.combatResolver.getElevationPercent(
			activeMonsterID, center_target.uniqueID
		)
		return "Expected: %d damage / %d%% elevation" % [damage, elevation]

	var spell = attacker.spellSets[_selectedSpellSet][_selectedSpellIndex]
	var from_pos = _sim.state.getMonsterPosition(activeMonsterID)
	var affected_target_ids = _sim.combatResolver.getSpellAffectedTargetsFrom(
		activeMonsterID,
		_selectedSpellSet,
		_selectedSpellIndex,
		from_pos,
		centerPos,
		true
	)
	if affected_target_ids.is_empty():
		if not _canConfirmTarget(centerPos):
			return "Expected: 0 units affected\nEmpty-center casting is disabled"
		return "Expected: 0 units affected\nCast spends action, cooldown & Resonance"

	var total := 0
	var minimum_elevation := 0
	var maximum_elevation := 0
	var has_elevation := false
	for target_id in affected_target_ids:
		var target = _sim.state.getMonster(target_id)
		if target == null:
			continue
		if spell.heals:
			total += mini(
				target.max_hitpoints - target.hitpoints,
				_sim.combatResolver.calculateHeal(attacker, spell)
			)
		elif not spell.damage_lines.is_empty():
			var target_damage := 0
			for line in spell.damage_lines:
				target_damage += _sim.combatResolver.calculateSpellDamage(
					attacker,
					target,
					int(line.get("damage", 0)),
					str(line.get("element", "none")),
					true
				)
			total += mini(target.hitpoints, target_damage)
			var elevation = _sim.combatResolver.getElevationPercent(
				activeMonsterID, target.uniqueID
			)
			if not has_elevation:
				minimum_elevation = elevation
				maximum_elevation = elevation
				has_elevation = true
			else:
				minimum_elevation = mini(minimum_elevation, elevation)
				maximum_elevation = maxi(maximum_elevation, elevation)

	var unit_count = affected_target_ids.size()
	var summary: String
	if spell.heals:
		summary = "Expected: %d healing across %d unit(s)" % [total, unit_count]
	elif not spell.damage_lines.is_empty():
		summary = "Expected: %d damage across %d unit(s)" % [total, unit_count]
	else:
		summary = "Expected: %d unit(s) affected" % unit_count
	if not _canConfirmTarget(centerPos):
		return summary + "\nEmpty-center casting is disabled"
	if has_elevation:
		var elevation_text = (
			"%d%%" % minimum_elevation
			if minimum_elevation == maximum_elevation
			else "%d%% to %d%%" % [minimum_elevation, maximum_elevation]
		)
		return summary + "\nElevation: " + elevation_text
	return summary
