## Focused side-turn input contract through the live controller.

extends SceneTree

const ControllerScript = preload("res://src/systems/hex_battle/HexBattleController.gd")
const SCENARIO := "res://data/battle/scenarios/technical_hxb_contract_player_cpu.json"
const SEED := 42

var failures: Array[String] = []
var controller: HexBattleController


func _init() -> void:
	controller = ControllerScript.new()
	root.add_child(controller)
	process_frame.connect(_run, CONNECT_ONE_SHOT)


func _run() -> void:
	var started := controller.startBattle(SCENARIO, SEED)
	_require(bool(started.get("ok", false)), "battle did not start")
	if failures.is_empty():
		_require(await _awaitPlayerSide(), "no player side turn opened")
	if failures.is_empty():
		await _checkKeyboardFlow()
	_report()


func _checkKeyboardFlow() -> void:
	_pushKey(KEY_TAB)
	await _frames(2)
	_require(controller.memberTurn != null, "Tab did not select a ready unit")
	if controller.memberTurn == null:
		return
	var firstID := controller.memberTurn.monsterID()
	_require(controller.playback.owner() == HexBattlePlayback.OWNER_PLAYER,
		"selected player unit did not claim playback")
	_require(not controller.hud.partyPanel.visible and not controller.hud.orderPanel.visible
		and not controller.hud.prompt.visible and not controller.hud.commandMenu.visible,
		"a removed party/order/prompt/command surface remained visible")
	_require(controller.sideCues._arc.visible, "selected unit did not show its action arc")

	var origin: Vector2i = controller.sim.state.getMonsterPosition(firstID)
	var aimed := origin
	for keycode in [KEY_RIGHT, KEY_DOWN, KEY_LEFT, KEY_UP]:
		_pushKey(keycode)
		await _frames(1)
		aimed = controller.memberInput.cursorCell()
		if aimed != origin and controller.memberTurn.reachableCells().has(aimed):
			break
	_require(aimed != origin, "keyboard movement aim never left the origin")
	_pushKey(KEY_ENTER)
	await _frames(2)
	_require(controller.sim.state.getMonsterPosition(firstID) == aimed,
		"Enter did not confirm the keyboard cursor's move")
	_require(controller.memberTurn.canUndoMove(), "a resolved move did not expose Undo")
	var magic = _commandEntry("magic")
	_require(not bool(magic.get("enabled", true)), "Magic stayed enabled after movement")

	controller.sideCues.action_requested.emit("undo")
	await _frames(2)
	_require(controller.sim.state.getMonsterPosition(firstID) == origin,
		"Undo did not restore the unit's origin")

	for keycode in [KEY_RIGHT, KEY_DOWN, KEY_LEFT, KEY_UP]:
		_pushKey(keycode)
		await _frames(1)
		aimed = controller.memberInput.cursorCell()
		if aimed != origin and controller.memberTurn.reachableCells().has(aimed):
			break
	_pushKey(KEY_ENTER)
	await _frames(2)
	_pushKey(KEY_TAB)
	await _frames(2)
	_require(controller.memberTurn != null and controller.memberTurn.monsterID() != firstID,
		"Tab did not switch to another ready unit")
	var secondID := controller.memberTurn.monsterID() if controller.memberTurn != null else -1
	_pushShiftTab()
	await _frames(2)
	_require(controller.memberTurn != null and controller.memberTurn.monsterID() == firstID,
		"Shift-Tab did not return to the moved unit")
	_require(controller.memberTurn.canUndoMove(), "switching discarded the pending move")

	_pushRightTap(Vector2(20.0, 20.0))
	await _frames(2)
	_require(controller.memberTurn == null, "right tap did not cancel selection")
	_require(controller.sim.eligibleSideUnitIDs().has(firstID),
		"cancelling selection spent the moved unit")

	_pushKey(KEY_TAB)
	await _frames(2)
	var waitedID := controller.memberTurn.monsterID() if controller.memberTurn != null else secondID
	_pushKey(KEY_4)
	await _frames(3)
	_require(controller.sim.state.spentUnitIDs.has(waitedID), "Wait did not spend the unit")
	_require(controller.memberTurn == null, "Wait left the member input open")

	var sideID := int(controller.sim.state.activeSideID)
	controller.sideCues._endButton._onPressed()
	_require(controller.sideCues.endTurnConfirming(),
		"End turn skipped its ready-unit confirmation")
	controller.sideCues._endButton._onPressed()
	await _frames(2)
	_require(controller.sim.state.activeSideID != sideID,
		"confirmed End turn did not close the player's side")


func _commandEntry(id: String) -> Dictionary:
	if controller.memberInput == null:
		return {}
	for entry in controller.memberInput.commandModel().get("commands", []):
		if str(entry.get("id", "")) == id:
			return entry
	return {}


func _awaitPlayerSide() -> bool:
	for _attempt in range(300):
		await _frames(1)
		if controller.sim.state.activeSideID == -1:
			continue
		if controller._sideController(int(controller.sim.state.activeSideID)) == "player":
			return true
	return false


func _pushKey(keycode: Key) -> void:
	var event := InputEventKey.new()
	event.keycode = keycode
	event.pressed = true
	root.push_input(event)


func _pushShiftTab() -> void:
	var event := InputEventKey.new()
	event.keycode = KEY_TAB
	event.shift_pressed = true
	event.pressed = true
	root.push_input(event)


func _pushRightTap(point: Vector2) -> void:
	for pressed in [true, false]:
		var event := InputEventMouseButton.new()
		event.button_index = MOUSE_BUTTON_RIGHT
		event.position = point
		event.pressed = pressed
		# Headless fixes the viewport at 64x64, where the debug drawer covers every pixel. Feed the
		# controller's unhandled stage directly so the tap-vs-drag contract is still exercised.
		controller._unhandled_input(event)


func _frames(count: int) -> void:
	for _index in range(count):
		await process_frame


func _require(condition: bool, message: String) -> void:
	if not condition:
		failures.append(message)


func _report() -> void:
	if not failures.is_empty():
		for failure: String in failures:
			printerr("HXB_INPUT_FAILURE: %s" % failure)
		quit(1)
		return
	print("HXB_INPUT_OK")
	quit(0)
