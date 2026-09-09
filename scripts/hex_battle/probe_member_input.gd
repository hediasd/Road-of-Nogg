## Drives a player member turn the way a player does: clicks the party panel, clicks the command
## menu, and pushes real key and mouse events through the viewport. Nothing here calls a controller
## handler to stand in for a driven cursor -- the point is that the path from an event to a phase
## call on the simulator works end to end, and calling the middle of it would prove nothing about
## the ends.

extends SceneTree

const HexBattleControllerScript = preload("res://src/systems/hex_battle/HexBattleController.gd")

const SCENARIO := "res://data/battle/scenarios/technical_hxb_contract_player_cpu.json"
const SEED := 42

var failures: Array[String] = []
var _controller: HexBattleController
## Whichever member the panel click actually opened -- read back rather than assumed, since the
## simulator decides which party activates first.
var _memberID := -1
var _panelRows: Dictionary = {}
var _menuRows: Dictionary = {}

## Every value playback ownership has taken, sampled after each step. Claims and releases are
## counted off this rather than trusted from a signal the gate does not emit.
var _ownerLog: Array[String] = []


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
	_controller.hud.commandMenu._window.row_built.connect(
		func(row: Control, index: int): _menuRows[index] = row)

	if not await _awaitPlayerParty():
		_fail("no player activation opened")
		return _report()

	await _checkOpeningATurn()
	if _controller.memberInput == null:
		return _report()

	await _checkConfirmNeedsAnAim()
	await _checkDrivenMoveMatchesTheCursor()
	await _checkUndoFollowsTheSimulator()
	await _checkMouseReachesTheSameCursor()
	await _checkEndingTheTurn()

	_report()


func _report() -> void:
	if not failures.is_empty():
		for failure: String in failures:
			printerr("HXB_INPUT_FAILURE: %s" % failure)
		quit(1)
		return
	print("HXB_INPUT_OK")
	quit(0)


func _fail(message: String) -> void:
	failures.append(message)


func _require(condition: bool, message: String) -> void:
	if not condition:
		failures.append(message)


# --- checks -----------------------------------------------------------------

func _checkOpeningATurn() -> void:
	_sampleOwner()
	_require(_controller.playback.isIdle(),
		"the gate was already held before the player picked anyone")

	_clickRow(_panelRows.get(1))
	await _frames(2)
	_sampleOwner()

	_require(_controller.memberTurn != null and _controller.memberInput != null,
		"clicking a party member did not open a member turn")
	if _controller.memberTurn == null:
		return
	_memberID = _controller.memberTurn.monsterID()
	var party = _controller.sim.state.parties.get(int(_controller.sim.state.activePartyID))
	_require(party != null and int(party.memberIDs[0]) == _memberID,
		"clicking the first member row opened a different member's turn")
	_require(_controller.playback.owner() == HexBattlePlayback.OWNER_PLAYER,
		"the player did not hold the gate during their own turn")
	_require(_controller.hud.commandMenu.visible,
		"the command menu was not shown when the turn opened")
	_require(_menuRowWithLabel("Move") != null and _menuRowWithLabel("Attack") != null
		and _menuRowWithLabel("End turn") != null,
		"the command menu is missing rows the turn needs")


## Enter at the menu is not a confirm of anything: nothing is being aimed, so nothing may resolve.
func _checkConfirmNeedsAnAim() -> void:
	var before: Vector2i = _controller.sim.state.getMonsterPosition(_memberID)
	_pushKey(KEY_ENTER)
	await _frames(1)
	_require(_controller.sim.state.getMonsterPosition(_memberID) == before,
		"confirming from the menu moved the member without an aim")
	_require(_controller.memberInput.phase() == HexBattleMemberInput.Phase.MENU,
		"confirming from the menu left the menu")


## The item's own wording: a synthetic direction must resolve to the same cell the confirmed
## command carries. The cursor is stepped by a real key event, read back, and then compared against
## where the simulator actually put the member.
func _checkDrivenMoveMatchesTheCursor() -> void:
	var origin: Vector2i = _controller.sim.state.getMonsterPosition(_memberID)

	_clickRow(_menuRowWithLabel("Move"))
	await _frames(1)
	_require(_controller.memberInput.phase() == HexBattleMemberInput.Phase.AIM_MOVE,
		"choosing Move did not begin an aim")
	_require(not _controller.hud.commandMenu.visible,
		"the menu stayed up while aiming a move")
	_require(_controller.memberInput.cursorCell() == origin,
		"the aim did not start on the member")

	var stepped := false
	for keycode in [KEY_RIGHT, KEY_DOWN, KEY_LEFT, KEY_UP]:
		_pushKey(keycode)
		await _frames(1)
		if _controller.memberInput.cursorCell() != origin:
			stepped = true
			break
	_require(stepped, "no arrow key moved the cursor off the member's own cell")
	if not stepped:
		return

	var aimed: Vector2i = _controller.memberInput.cursorCell()
	_pushKey(KEY_ENTER)
	await _frames(2)

	var landed: Vector2i = _controller.sim.state.getMonsterPosition(_memberID)
	_require(landed == aimed,
		"confirmed a move to %s while the cursor was on %s" % [landed, aimed])
	_require(_controller.hud.commandMenu.visible,
		"the menu did not come back after the move resolved")
	_require(not _controller.memberTurn.canMove(),
		"the move phase is still open after a move resolved")
	_require(not _rowLooksEnabled(_menuRowWithLabel("Move")),
		"Move is still offered after the move phase was spent")


## Undo is the simulator's answer, and the menu must never offer one it would refuse.
func _checkUndoFollowsTheSimulator() -> void:
	var moved: Vector2i = _controller.sim.state.getMonsterPosition(_memberID)
	_require(_controller.memberTurn.canUndoMove(),
		"the simulator will not undo a move that just happened")
	_require(_rowLooksEnabled(_menuRowWithLabel("Undo move")),
		"the menu did not offer an undo the simulator would accept")

	_clickRow(_menuRowWithLabel("Undo move"))
	await _frames(2)

	var restored: Vector2i = _controller.sim.state.getMonsterPosition(_memberID)
	_require(restored != moved, "undo did not move the member back")
	_require(not _controller.memberTurn.canUndoMove(),
		"the simulator still offers an undo after one was taken")
	_require(not _rowLooksEnabled(_menuRowWithLabel("Undo move")),
		"the menu still offers an undo the simulator would now refuse")
	_require(_controller.memberTurn.canMove(),
		"the move phase did not reopen after the undo")


## A hover reaches the same cursor the keyboard drives, so a confirm cannot mean two cells.
func _checkMouseReachesTheSameCursor() -> void:
	_clickRow(_menuRowWithLabel("Move"))
	await _frames(1)
	if _controller.memberInput.phase() != HexBattleMemberInput.Phase.AIM_MOVE:
		_fail("could not re-enter a move aim for the mouse check")
		return

	var origin: Vector2i = _controller.sim.state.getMonsterPosition(_memberID)
	var target := Vector2i(-1, -1)
	for neighbour: Vector2i in _controller.cursor.reachableNeighbours(_controller.map):
		if neighbour != origin:
			target = neighbour
			break
	if target.x < 0:
		_fail("the member has no neighbour to point at")
		return

	var point: Vector2 = _controller.battleCamera.projectToScreen(
		_controller.adapter.worldPositionOf(target))
	if point == Vector2.ZERO:
		_fail("the target cell did not project to the screen")
		return

	# Headless pins the window to 64x64, and at that size the party panel covers the whole board,
	# so it consumes the hover before the viewport can route it to the battle. That is the right
	# behaviour -- a hover over the HUD is not a hover over a cell -- and it is not what this check
	# is about, so the panel is taken out of the way for the length of the hover rather than the
	# event being fed past the viewport, which would stop proving that real routing works.
	_controller.hud.partyPanel.hide()
	_pushMouseMotion(point)
	await _frames(1)
	_controller.hud.partyPanel.show()
	_require(_controller.memberInput.cursorCell() == target,
		"a hover over %s left the cursor on %s" % [target, _controller.memberInput.cursorCell()])

	# Escape backs out of the aim without ending the turn -- a member turn ends by acting or
	# waiting, never by escaping.
	_pushKey(KEY_ESCAPE)
	await _frames(1)
	_require(_controller.memberInput.phase() == HexBattleMemberInput.Phase.MENU,
		"escape did not return to the menu")
	_require(_controller.memberTurn != null and not _controller.memberTurn.isFinished(),
		"escape ended the member's turn")


func _checkEndingTheTurn() -> void:
	_clickRow(_menuRowWithLabel("End turn"))
	await _frames(3)
	_sampleOwner()

	_require(_controller.memberTurn == null,
		"the member turn did not close when the player ended it")
	_require(not _controller.hud.commandMenu.visible,
		"the command menu survived the end of the turn")

	var claims := 0
	var releases := 0
	for index in range(1, _ownerLog.size()):
		var previous: String = _ownerLog[index - 1]
		var current: String = _ownerLog[index]
		if previous != HexBattlePlayback.OWNER_PLAYER \
				and current == HexBattlePlayback.OWNER_PLAYER:
			claims += 1
		if previous == HexBattlePlayback.OWNER_PLAYER \
				and current != HexBattlePlayback.OWNER_PLAYER:
			releases += 1
	_require(claims == 1, "the player claimed the gate %d times for one turn" % claims)
	_require(releases == 1, "the player released the gate %d times for one turn" % releases)


# --- driving ----------------------------------------------------------------

func _awaitPlayerParty() -> bool:
	for _attempt in range(240):
		await _frames(1)
		var partyID := int(_controller.sim.state.activePartyID)
		if partyID == -1:
			continue
		var party = _controller.sim.state.parties.get(partyID)
		if party != null and party.controller == "player":
			return true
	return false


func _frames(count: int) -> void:
	for _index in range(count):
		await process_frame


func _pushKey(keycode: Key) -> void:
	var event := InputEventKey.new()
	event.keycode = keycode
	event.pressed = true
	root.push_input(event)
	_sampleOwner()


func _pushMouseMotion(point: Vector2) -> void:
	var event := InputEventMouseMotion.new()
	event.position = point
	root.push_input(event)
	_sampleOwner()


## The rows are real Controls built by NoggWindow, and this is the event one actually receives when
## it is clicked.
func _clickRow(row: Control) -> void:
	if row == null:
		_fail("tried to click a row that was never built")
		return
	var event := InputEventMouseButton.new()
	event.button_index = MOUSE_BUTTON_LEFT
	event.pressed = true
	row.gui_input.emit(event)
	_sampleOwner()


func _sampleOwner() -> void:
	if _controller == null or _controller.playback == null:
		return
	var owner := _controller.playback.owner()
	if _ownerLog.is_empty() or _ownerLog[-1] != owner:
		_ownerLog.append(owner)


# --- reading the menu -------------------------------------------------------

func _menuRowWithLabel(label: String) -> Control:
	for index in _menuRows:
		var row: Control = _menuRows[index]
		if is_instance_valid(row) and _labelText(row) == label:
			return row
	return null


func _labelText(row: Control) -> String:
	if row == null or row.get_child_count() == 0:
		return ""
	var clip := row.get_child(0)
	if clip == null or clip.get_child_count() == 0:
		return ""
	return str((clip.get_child(0) as Label).text)


## A row NoggWindow built disabled carries a dim override on its label; an enabled one is left at
## the theme default. Read back rather than re-derived from the model, so this checks what the menu
## actually showed.
func _rowLooksEnabled(row: Control) -> bool:
	if row == null:
		return false
	var label := row.get_child(0).get_child(0) as Label
	if not label.has_theme_color_override("font_color"):
		return true
	return label.get_theme_color("font_color") != NoggTheme.TEXT_DIM
