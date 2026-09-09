## A whole battle, played to a result through the input path rather than the API.
##
## WHAT THIS IS FOR. Every other probe in this directory checks one surface in isolation, and the
## cycle's own risk note is that a probe can pass because it only exercises the easy case. This one
## takes the opposite approach: it commands every player member the way a player does -- panel
## click, menu click, cursor keys, confirm -- lets the CPU parties run themselves, and keeps going
## until someone wins. A stall anywhere in the composition shows up here as a battle that never
## ends, which is exactly the failure that survived the migration undetected.
##
## WHAT IT IS NOT. It cannot judge whether the battle is legible, whether the camera reads well, or
## whether any of it is pleasant. Those need a person at a window and are recorded as unverified
## rather than assumed.
##
## THE CAMERA IS ROTATED FIRST, and left rotated for the whole battle. Direction resolution is
## screen-space against the live camera, so a battle played at a detent the identity transform does
## not cover is the one that would catch a mapping that only works unrotated.

extends SceneTree

const HexBattleControllerScript = preload("res://src/systems/hex_battle/HexBattleController.gd")

const SCENARIO := "res://data/battle/scenarios/technical_hxb_contract_player_cpu.json"
const SEED := 42

## Whole battle, so the bound is generous. It exists to end a stalled run with a readable failure
## rather than a timeout with no output.
const MAX_FRAMES := 30000
const CAMERA_DETENTS := 2

var failures: Array[String] = []
var _controller: HexBattleController
var _menuRows: Dictionary = {}
var _panelRows: Dictionary = {}

## What actually happened, so the commit can record a matrix rather than a claim.
var _moves := 0
var _undos := 0
var _attacks := 0
var _casts := 0
var _cancels := 0
var _waits := 0
var _partiesEnded := 0
var _memberTurns := 0
## Set when a member turn cannot be advanced, so the run stops at the state that caused it rather
## than burning the frame budget and reporting only that time ran out.
var _stalled := false


func _init() -> void:
	_controller = HexBattleControllerScript.new()
	root.add_child(_controller)
	process_frame.connect(_run, CONNECT_ONE_SHOT)


func _run() -> void:
	var started := _controller.startBattle(SCENARIO, SEED)
	if not bool(started.get("ok", false)):
		_fail("battle did not start: %s" % str(started.get("error", "")))
		return _report()

	_controller.hud.partyPanel._window.row_built.connect(
		func(row: Control, index: int): _panelRows[index] = row)
	_controller.hud.commandMenu._window.row_built.connect(_onMenuRowBuilt)

	# Rotated before the first turn and never straightened, so every direction resolved in this
	# run is resolved against a camera the identity case does not cover.
	for _detent in range(CAMERA_DETENTS):
		_controller.battleCamera.orbitDetent(1)
	await _frames(1)

	await _playToAResult()
	_report()


func _report() -> void:
	print("HXB_PLAY_MATRIX turns=%d moves=%d undos=%d attacks=%d casts=%d cancels=%d waits=%d parties_ended=%d" % [
		_memberTurns, _moves, _undos, _attacks, _casts, _cancels, _waits, _partiesEnded,
	])
	if not failures.is_empty():
		for failure: String in failures:
			printerr("HXB_PLAY_FAILURE: %s" % failure)
		quit(1)
		return
	print("HXB_PLAY_OK")
	quit(0)


func _fail(message: String) -> void:
	if not failures.has(message):
		failures.append(message)


func _require(condition: bool, message: String) -> void:
	if not condition:
		_fail(message)


# --- the battle -------------------------------------------------------------

func _playToAResult() -> void:
	var frames := 0
	while _controller.sim != null and _controller.sim.state.battleOutcome == -1 and not _stalled:
		frames += 1
		if frames > MAX_FRAMES:
			_fail("battle did not reach a result in %d frames -- stalled at round %d" % [
				MAX_FRAMES, _controller.sim.state.roundCount])
			return
		await _frames(1)

		# A player member turn is open: command it. Everything else -- CPU parties, playback,
		# activation boundaries -- is the controller's own loop and is deliberately left alone.
		if _controller.memberInput != null and _controller.memberTurn != null \
				and not _controller.memberTurn.isFinished():
			await _commandOneMember()
			continue

		# The player's party is open with nobody selected. Pick the first member the panel offers,
		# and end the party when it offers none.
		if _isPlayerPartyWaiting():
			# Once in the battle, cut a party short while a member could still act. That is the
			# only way the End Party row is ever reached -- a party whose members have all acted
			# ends itself -- and it is a decision a player makes, so it should be played once.
			if _partiesEnded == 0 and _memberTurns > 0 \
					and not _controller.sim.eligiblePartyMemberIDs().is_empty():
				_endParty()
			elif not await _selectAMember():
				_endParty()

	_require(_controller.sim.state.battleOutcome != -1, "battle ended without an outcome")
	_require(_memberTurns > 0, "no player member turn was ever commanded")
	_require(_moves > 0, "no member was ever moved")
	_require(_undos > 0, "no move was ever undone")
	_require(_cancels > 0, "no aim was ever cancelled")
	_require(_attacks > 0, "no attack ever resolved from player input")
	_require(_casts > 0, "no spell ever resolved from player input")
	_require(_partiesEnded > 0, "End Party was never used")


func _isPlayerPartyWaiting() -> bool:
	var sim := _controller.sim
	if sim == null or sim.state.activePartyID == -1:
		return false
	if _controller.playback == null or not _controller.playback.isIdle():
		return false
	var party = sim.state.parties.get(int(sim.state.activePartyID))
	return party != null and party.controller == "player"


## Clicks the first eligible member row. Returns whether a turn opened.
func _selectAMember() -> bool:
	var sim := _controller.sim
	var party = sim.state.parties.get(int(sim.state.activePartyID))
	if party == null:
		return false
	var eligible := sim.eligiblePartyMemberIDs()
	if eligible.is_empty():
		return false
	for index in range(party.memberIDs.size()):
		if not eligible.has(int(party.memberIDs[index])):
			continue
		# Row 0 is the header, so member N is row N + 1 -- the same order the panel was given.
		_clickRow(_panelRows.get(index + 1))
		await _frames(2)
		if _controller.memberTurn != null:
			_memberTurns += 1
			return true
		return false
	return false


## Clicks the panel's own End Party row. Natural exhaustion never reaches it -- a party whose
## members have all acted ends itself -- so the one path a player takes to cut a party short would
## otherwise go unplayed for the whole battle.
func _endParty() -> void:
	var before := int(_controller.sim.state.activePartyID)
	var row := _panelRowWithLabel("End Party")
	if row != null and _rowLooksEnabled(row):
		_clickRow(row)
	else:
		_controller.hud.end_party_requested.emit()
	if int(_controller.sim.state.activePartyID) != before:
		_partiesEnded += 1


func _panelRowWithLabel(label: String) -> Control:
	for index in _panelRows.keys():
		var value = _panelRows.get(index)
		if is_instance_valid(value) and _labelText(value) == label:
			return value
	return null


## One member's turn, played out. The order varies with what the turn offers so the run does not
## only ever exercise move-then-attack.
func _commandOneMember() -> void:
	var turn := _controller.memberTurn
	var input := _controller.memberInput

	# Aim a move, cancel it, then aim it again -- cancelling has to leave the turn intact, and a
	# turn that quietly ended on escape would be a real defect the other probes do not see.
	if turn.canMove():
		if _chooseCommand("Move"):
			_pushKey(KEY_ESCAPE)
			await _frames(1)
			if input.phase() == HexBattleMemberInput.Phase.MENU:
				_cancels += 1
			else:
				_fail("escape did not return to the menu mid-battle")
			_require(not turn.isFinished(), "cancelling an aim ended the member's turn")

		if _chooseCommand("Move"):
			await _aimSomewhereElse()
			var before: Vector2i = _controller.sim.state.getMonsterPosition(turn.monsterID())
			_pushKey(KEY_ENTER)
			await _frames(2)
			var after: Vector2i = _controller.sim.state.getMonsterPosition(turn.monsterID())
			if after != before:
				_moves += 1
				# Undo the first move of the battle and take it again, so the undo path is
				# exercised against a real board rather than only in isolation.
				if _undos == 0 and turn.canUndoMove():
					_chooseCommand("Undo move")
					await _frames(2)
					if _controller.sim.state.getMonsterPosition(turn.monsterID()) == before:
						_undos += 1
					else:
						_fail("undo did not restore the member's position mid-battle")

	await _returnToMenu()
	if _controller.memberTurn == null or _controller.memberTurn.isFinished():
		return

	# Try every action the menu currently offers, nearest first: an attack if anything is in
	# reach, otherwise a spell, otherwise end the turn.
	# Alternated deliberately: attacks succeed on this board most turns, so trying them first every
	# time would mean the spell path never ran at all. Odd turns cast first, even turns strike
	# first, and either falls back to the other.
	if turn.canAct():
		if _memberTurns % 2 == 1:
			if await _trySomeSpell():
				_casts += 1
			elif await _tryAction("Attack"):
				_attacks += 1
		else:
			if await _tryAction("Attack"):
				_attacks += 1
			elif await _trySomeSpell():
				_casts += 1

	await _returnToMenu()
	if _controller.memberTurn != null and not _controller.memberTurn.isFinished():
		if not _chooseCommand("End turn"):
			_fail(("could not end a member turn: phase=%d menu_visible=%s rows=[%s] " +
				"canMove=%s canAct=%s") % [
				_controller.memberInput.phase(),
				_controller.hud.commandMenu.visible,
				", ".join(_menuLabels()),
				_controller.memberTurn.canMove(),
				_controller.memberTurn.canAct(),
			])
			_stalled = true
			return
		_waits += 1
		await _frames(2)


func _menuLabels() -> Array:
	var labels: Array = []
	for index in _menuRows.keys():
		var value = _menuRows.get(index)
		if is_instance_valid(value):
			labels.append(_labelText(value))
	return labels


## Steps the cursor with real key presses until it is somewhere the member can actually go.
##
## Not every neighbour is reachable -- an ally may be standing there, or the terrain may cost more
## than the member has left -- and a confirm on one of those is refused. That refusal is correct
## and deliberately leaves the aim open so another cell can be tried, which is exactly what this
## does rather than treating the first neighbour as the answer.
func _aimSomewhereElse() -> bool:
	var input := _controller.memberInput
	var reachable: Array = _controller.memberTurn.reachableCells()
	var start: Vector2i = input.cursorCell()
	for keycode in [KEY_RIGHT, KEY_DOWN, KEY_LEFT, KEY_UP, KEY_RIGHT, KEY_DOWN]:
		_pushKey(keycode)
		await _frames(1)
		var cell: Vector2i = input.cursorCell()
		if cell != start and reachable.has(cell):
			return true
	return false


## Escapes an aim that is still open. A refused confirm keeps the player aiming on purpose, so the
## next decision has to be started from the menu rather than assumed to be there.
func _returnToMenu() -> void:
	if _controller.memberInput == null or not _controller.memberInput.isAiming():
		return
	_pushKey(KEY_ESCAPE)
	await _frames(1)


## Aims the named action at each cell the cursor can reach from the member and confirms the first
## one the simulator accepts. A refusal is information, not a failure -- most cells are not valid
## targets, and the point is that a valid one resolves.
func _tryAction(label: String) -> bool:
	if not _chooseCommand(label):
		return false
	var turn := _controller.memberTurn
	var input := _controller.memberInput
	var origin: Vector2i = _controller.sim.state.getMonsterPosition(turn.monsterID())
	var candidates: Array = _controller.cursor.reachableNeighbours(_controller.map)
	candidates.append(origin)
	for cell: Vector2i in candidates:
		if not input.aimAt(cell):
			continue
		var result := input.confirm()
		if bool(result.get("success", false)):
			await _frames(2)
			return true
	_pushKey(KEY_ESCAPE)
	await _frames(1)
	_cancels += 1
	return false


func _trySomeSpell() -> bool:
	for index in _menuRows.keys():
		var value = _menuRows.get(index)
		if not is_instance_valid(value):
			continue
		var row: Control = value
		var label := _labelText(row)
		if label in ["Move", "Attack", "Undo move", "End turn", "Cancel", ""]:
			continue
		if not _rowLooksEnabled(row):
			continue
		if await _tryAction(label):
			return true
	return false


# --- driving ----------------------------------------------------------------

func _chooseCommand(label: String) -> bool:
	var row := _menuRowWithLabel(label)
	if row == null or not _rowLooksEnabled(row):
		return false
	_clickRow(row)
	return true


func _frames(count: int) -> void:
	for _index in range(count):
		await process_frame


func _pushKey(keycode: Key) -> void:
	var event := InputEventKey.new()
	event.keycode = keycode
	event.pressed = true
	root.push_input(event)


func _clickRow(row: Control) -> void:
	if row == null:
		return
	var event := InputEventMouseButton.new()
	event.button_index = MOUSE_BUTTON_LEFT
	event.pressed = true
	row.gui_input.emit(event)


## Rebuilding the menu frees every row it had, so the previous generation is dropped as the new
## one arrives rather than lingering as references that error the moment they are read.
func _onMenuRowBuilt(row: Control, index: int) -> void:
	if index == 0:
		_menuRows.clear()
	_menuRows[index] = row


func _menuRowWithLabel(label: String) -> Control:
	for index in _menuRows:
		var value = _menuRows[index]
		if not is_instance_valid(value):
			continue
		var row: Control = value
		if _labelText(row) == label:
			return row
	return null


func _labelText(row: Control) -> String:
	if row == null or row.get_child_count() == 0:
		return ""
	var clip := row.get_child(0)
	if clip == null or clip.get_child_count() == 0:
		return ""
	return str((clip.get_child(0) as Label).text)


func _rowLooksEnabled(row: Control) -> bool:
	if row == null:
		return false
	var label := row.get_child(0).get_child(0) as Label
	if not label.has_theme_color_override("font_color"):
		return true
	return label.get_theme_color("font_color") != NoggTheme.TEXT_DIM
