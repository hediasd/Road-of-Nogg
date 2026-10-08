## Full player-vs-CPU battle through the side-turn controller. Player commands are submitted via
## the same member-input and context-click paths as live input; the enemy uses the controller's
## frame-sliced side deliberation.

extends SceneTree

const ControllerScript = preload("res://battle/HexBattleController.gd")
const SideDeliberationScript = preload("res://ai/PartyCommandDeliberation.gd")

const SCENARIO := "res://data/scenarios/technical_hxb_contract_player_cpu.json"
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

		# The click-to-attack path is what this probe proves, not that the CPU likes basic attacks.
		# Once stats grow with level, this side's CPU fights the levelled enemy at range and never
		# proposes one, at any seed. So the first time a ready unit can reach an enemy, it walks
		# there and attacks it by clicking the enemy, and the hit must land.
		if attacks == 0:
			var attack: Dictionary = await _readyAttack()
			if not attack.is_empty():
				if attack.has("move_to"):
					await _submitMove(attack["move_to"])
				var target = controller.sim.state.getMonster(int(attack["target_id"]))
				var hpBefore: int = target.hitpoints
				controller._handleSideClick(controller.stage.projectWorldToScreen(
					controller.adapter.worldPositionOf(controller.sim.state.getMonsterPosition(int(attack["target_id"])))))
				await _frames(1)
				_require(not target.is_alive() or target.hitpoints < hpBefore,
					"clicking an enemy in reach did not attack it")
				attacks += 1
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
		await _submitMove(destination)
		if undos == 0 and controller.memberTurn != null and controller.memberTurn.canUndoMove():
			controller.sideCues.action_requested.emit("undo")
			await _frames(1)
			undos += 1
			await _submitMove(destination)
	if controller.memberInput == null:
		return
	match command.action:
		"attack":
			var point := controller.stage.projectWorldToScreen(
				controller.adapter.worldPositionOf(command.target_pos))
			var occupant = controller.sim.state.getMonsterAt(command.target_pos)
			var targetID: int = occupant.uniqueID if occupant != null else -1
			if controller._pointerUnit(point) == targetID:
				controller._handleSideClick(point)
			else:
				# Another body is in front of the target here; aim at it as the keyboard would.
				controller.memberInput.chooseCommand(HexBattleMemberInput.ATTACK_COMMAND)
				controller.memberInput.aimAt(command.target_pos)
				controller.memberInput.confirm()
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


## Moves the selected unit to `destination` by clicking the cell, as a mouse player would. When
## an attackable enemy's body covers that cell, the click would (rightly) attack it, so the move is
## aimed instead, as the keyboard does.
func _submitMove(destination: Vector2i) -> void:
	var point := controller.stage.projectWorldToScreen(controller.adapter.worldPositionOf(destination))
	if controller._pointerUnit(point) == -1:
		controller._handleSideClick(point)
	else:
		controller.memberInput.chooseCommand(HexBattleMemberInput.MOVE_COMMAND)
		controller.memberInput.aimAt(destination)
		controller.memberInput.confirm()
	await _frames(1)
	moves += 1


## Selects ready units, lowest id first, until one can basic-attack an enemy from where it stands
## or from a cell it can walk to. Returns `{unit, target_id}` plus `move_to` when it must walk,
## with that unit left selected. Returns empty, with nothing selected, when none can.
func _readyAttack() -> Dictionary:
	var state = controller.sim.state
	var ready: Array = controller.sim.eligibleSideUnitIDs().duplicate()
	ready.sort()
	var enemies: Array = []
	var others: Array = state.monsterPositions.keys()
	others.sort()
	for otherID in others:
		var other = state.getMonster(int(otherID))
		if other != null and other.team != state.activeSideID and other.is_alive():
			enemies.append(int(otherID))
	for unitID in ready:
		controller._onHudMemberSelected(int(unitID))
		await _frames(1)
		if controller.memberTurn == null:
			continue
		var origins: Array = [state.getMonsterPosition(int(unitID))]
		var reachable: Array = controller.memberTurn.reachableCells()
		reachable.sort()
		origins.append_array(reachable)
		for index in range(origins.size()):
			for enemyID in enemies:
				if controller.sim.combatResolver.canBasicAttackPositionFrom(
						int(unitID), origins[index], state.getMonsterPosition(enemyID)):
					var plan := {"unit": int(unitID), "target_id": enemyID}
					if index > 0:
						plan["move_to"] = origins[index]
					return plan
	# Nothing in reach: let go of the last unit looked at, or the turn loop waits on it forever.
	controller._cancelPlayerSelection()
	await _frames(1)
	return {}


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
