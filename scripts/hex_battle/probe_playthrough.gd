## Full player-vs-CPU battle through the side-turn controller. Player commands are submitted via
## the same member-input and context-click paths as live input; the enemy uses the controller's
## frame-sliced side deliberation.

extends SceneTree

const ControllerScript = preload("res://src/systems/hex_battle/HexBattleController.gd")
const SideDeliberationScript = preload("res://src/entity_ai/PartyCommandDeliberation.gd")

const SCENARIO := "res://data/battle/scenarios/technical_hxb_contract_player_cpu.json"
const SEED := 42
const MAX_FRAMES := 30000

var failures: Array[String] = []
var controller: HexBattleController
var moves := 0
var undos := 0
var attacks := 0
var casts := 0
var waits := 0
var cancels := 0
var endedEarly := 0
var keyboardTurns := 0


func _init() -> void:
	controller = ControllerScript.new()
	root.add_child(controller)
	process_frame.connect(_run, CONNECT_ONE_SHOT)


func _run() -> void:
	var started := controller.startBattle(SCENARIO, SEED)
	_require(bool(started.get("ok", false)), "battle did not start")
	if not failures.is_empty():
		return _report()
	controller.playback.setSpeed(4.0)
	controller.battleCamera.orbitDetent(1)
	await _playBattle()
	_report()


func _playBattle() -> void:
	var frames := 0
	while controller.sim != null and controller.sim.state.battleOutcome == -1:
		frames += 1
		if frames > MAX_FRAMES:
			failures.append("battle stalled before a result")
			return
		await process_frame
		var sideID := int(controller.sim.state.activeSideID)
		if sideID == -1 or controller._sideController(sideID) != "player":
			continue
		if controller.memberInput != null:
			continue
		if controller.sim.eligibleSideUnitIDs().is_empty():
			continue

		# One complete keyboard-only selection and Wait proves the rail's removal did not strand
		# keyboard play. Later turns use context clicks plus the action controls.
		if keyboardTurns == 0:
			_pushKey(KEY_TAB)
			await _frames(1)
			_pushKey(KEY_4)
			await _frames(1)
			keyboardTurns += 1
			waits += 1
			continue

		var proposal = controller.sim.beginSideDeliberation().run(64)
		if proposal == null:
			controller.sideCues._endButton._onPressed()
			controller.sideCues._endButton._onPressed()
			await _frames(1)
			continue
		controller._onHudMemberSelected(int(proposal.actor_id))
		await _frames(1)
		if controller.memberInput == null:
			failures.append("proposal actor could not be selected")
			return
		await _driveCommand(proposal.command)

		if endedEarly == 0 and controller.sim.state.activeSideID == sideID \
				and not controller.sim.eligibleSideUnitIDs().is_empty():
			controller.sideCues._endButton._onPressed()
			_require(controller.sideCues.endTurnConfirming(),
				"End turn did not confirm while units remained")
			controller.sideCues._endButton._onPressed()
			endedEarly += 1

	_require(controller.sim.state.battleOutcome != -1, "battle ended without an outcome")
	_require(keyboardTurns > 0, "keyboard path never selected and waited a unit")
	_require(moves > 0, "mouse-equivalent context clicks never moved a unit")
	_require(undos > 0, "Undo never resolved")
	_require(cancels > 0, "an aim was never cancelled")
	_require(attacks > 0, "no player attack resolved")
	_require(casts > 0, "no player spell resolved")
	_require(endedEarly > 0, "End turn with ready units was never confirmed")


func _driveCommand(command: BattleCommand) -> void:
	if not command.move_path.is_empty():
		var destination: Vector2i = command.move_path.back()
		if cancels == 0:
			controller.memberInput.chooseCommand(HexBattleMemberInput.MOVE_COMMAND)
			controller.memberInput.cancel()
			cancels += 1
		var point := controller.stage.projectWorldToScreen(controller.adapter.worldPositionOf(destination))
		controller._handleSideClick(point)
		await _frames(1)
		moves += 1
		if undos == 0 and controller.memberTurn != null and controller.memberTurn.canUndoMove():
			controller.sideCues.action_requested.emit("undo")
			await _frames(1)
			undos += 1
			controller._handleSideClick(point)
			await _frames(1)
			moves += 1
	if controller.memberInput == null:
		return
	match command.action:
		"attack":
			var point := controller.stage.projectWorldToScreen(
				controller.adapter.worldPositionOf(command.target_pos))
			controller._handleSideClick(point)
			await _frames(1)
			attacks += 1
		"spell":
			var id := "spell:%d:%d" % [command.spell_set_index, command.spell_index]
			controller._onHudCommandChosen(id)
			controller.memberInput.aimAt(command.target_pos)
			controller.memberInput.confirm()
			await _frames(1)
			casts += 1
		_:
			_pushKey(KEY_4)
			await _frames(1)
			waits += 1


func _pushKey(keycode: Key) -> void:
	var event := InputEventKey.new()
	event.keycode = keycode
	event.pressed = true
	root.push_input(event)


func _frames(count: int) -> void:
	for _index in range(count):
		await process_frame


func _require(condition: bool, message: String) -> void:
	if not condition and not failures.has(message):
		failures.append(message)


func _report() -> void:
	print("HXB_PLAY_MATRIX moves=%d undos=%d attacks=%d casts=%d waits=%d cancels=%d ended=%d" % [
		moves, undos, attacks, casts, waits, cancels, endedEarly])
	if not failures.is_empty():
		for failure: String in failures:
			printerr("HXB_PLAY_FAILURE: %s" % failure)
		quit(1)
		return
	print("HXB_PLAY_OK")
	quit(0)
