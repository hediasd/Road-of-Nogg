## HPR-7: the playable and watchable battle lifecycle.
##
## What this proves: a refused start says why on the setup form; a pause freezes CPU commands,
## the playing cast and player commands while the camera and inspection keep working; resume,
## speed and skip move playback on; the result waits for the last consequence and names a draw as a
## draw; restart keeps scenario and seed; the command ledger does not depend on presentation speed
## or a pause; and three start/return cycles leave one set of battle resources. It cannot judge how
## any of it looks or feels. That is HPR-8.
##
## Fixtures are in memory or under user://, and removed afterwards.

extends SceneTree

const HexBattleControllerScript = preload("res://src/systems/hex_battle/HexBattleController.gd")
const HudScript = preload("res://src/presentation/battle/HexBattleHud.gd")
const SessionPanelScript = preload("res://src/presentation/battle/ui/HexGraphicsPanel.gd")
const BattleSetupConfigScript = preload("res://src/battle_sim/BattleSetupConfig.gd")
const BattleSetupFactoryScript = preload("res://src/battle_sim/BattleSetupFactory.gd")

const CPU_SCENARIO := "res://data/battle/scenarios/technical_hxb_contract_cpu_cpu.json"
const PLAYER_SCENARIO := "res://data/battle/scenarios/technical_hxb_contract_player_cpu.json"
const SEED := 42
const SCREEN := Vector2i(1280, 720)
const BAD_JSON_PATH := "user://hpr_session_bad_json.json"
const BAD_VERSION_PATH := "user://hpr_session_bad_version.json"
const PAUSE_FRAMES := 90
const LEDGER_COMMANDS := 10
const FRAME_LIMIT := 20000

var failures: Array[String] = []
var _controller: HexBattleController
var _panelRows: Dictionary = {}
var _evidence: Dictionary = {}


func _init() -> void:
	process_frame.connect(_run, CONNECT_ONE_SHOT)


func _run() -> void:
	root.size = SCREEN
	_controller = HexBattleControllerScript.new()
	root.add_child(_controller)
	await _frames(1)

	await _checkStartRefusals()
	_checkResultAndSessionModels()
	await _checkCpuPauseSpeedSkip()
	await _checkPlayerPause()
	await _checkLedgerFinalDrainAndRestart()
	await _checkRepeatedTransitions()
	_report()


func _report() -> void:
	print("HPR_SESSION_EVIDENCE %s" % JSON.stringify(_evidence))
	for path in [BAD_JSON_PATH, BAD_VERSION_PATH]:
		if FileAccess.file_exists(path):
			DirAccess.remove_absolute(ProjectSettings.globalize_path(path))
	if _controller != null:
		_controller.teardownBattle()
	if not failures.is_empty():
		for failure: String in failures:
			printerr("HPR_SESSION_FAILURE: %s" % failure)
		quit(1)
		return
	print("HPR_SESSION_OK")
	quit(0)


func _require(condition: bool, message: String) -> void:
	if not condition and not failures.has(message):
		failures.append(message)


# --- start refusals ---------------------------------------------------------------

func _checkStartRefusals() -> void:
	_writeText(BAD_JSON_PATH, "{ this is not json")
	_writeText(BAD_VERSION_PATH, JSON.stringify([{"FORMAT_VERSION": 99, "NAME": "probe"}]))
	var cases := {
		BAD_JSON_PATH: "The scenario could not be loaded: ",
		BAD_VERSION_PATH: "The scenario could not be loaded: unsupported scenario version.",
		"res://data/battle/scenarios/hpr_session_missing.json": "The scenario could not be loaded: ",
	}
	var shown := {}
	for path in cases:
		_controller.setupUI.showError("")
		_controller._onBattleRequested(path, 7)
		await _frames(1)
		var text: String = _controller.setupUI._error.text
		shown[path.get_file()] = text
		var expected: String = cases[path]
		_require(text.begins_with(expected) and text.length() > expected.length() - 1,
			"a refused start for %s showed '%s'" % [path.get_file(), text])
		_require(text.length() > "The scenario could not be loaded: .".length(),
			"a refused start for %s gave no cause" % path.get_file())
		_require(_controller.lifecycle == HexBattleController.Lifecycle.SETUP
			and _controller.hud == null and _controller.setupUI._root.visible,
			"a refused start left the setup form hidden or a battle half built")
	_evidence["refusals"] = shown


func _writeText(path: String, text: String) -> void:
	var file := FileAccess.open(path, FileAccess.WRITE)
	file.store_string(text)
	file.close()


# --- models -------------------------------------------------------------------------

func _checkResultAndSessionModels() -> void:
	var config: BattleSetupConfig = BattleSetupConfigScript.new()
	config.scenarioPath = PLAYER_SCENARIO
	config.seed = SEED
	var state: BattleState = BattleSetupFactoryScript.createHexState(config).get("state")
	if state == null:
		_require(false, "fixture state could not be built")
		return
	state.battleOutcome = -1
	_require(HexBattleControllerScript.resultText(state) == "", "an undecided battle had a result")
	state.battleOutcome = BattleSimulator.DRAW_TEAM
	_require(HexBattleControllerScript.resultText(state) == "Draw",
		"a draw read '%s'" % HexBattleControllerScript.resultText(state))
	state.battleOutcome = 1
	_require(HexBattleControllerScript.resultText(state) == "Team 1 wins (you)",
		"a player win read '%s'" % HexBattleControllerScript.resultText(state))
	state.battleOutcome = 2
	_require(HexBattleControllerScript.resultText(state) == "Team 2 wins (CPU)",
		"a CPU win read '%s'" % HexBattleControllerScript.resultText(state))

	# A bare drawer: this check runs before any battle exists, so there is no stage to take one
	# from, and the session rows do not need a renderer.
	var drawer = SessionPanelScript.new(null)
	drawer.setSession({"phase": "battle", "paused": true, "speed": 0.5, "can_skip": false})
	_require(str(drawer.sessionTitle.text).contains("Paused"),
		"a paused session read '%s'" % drawer.sessionTitle.text)
	_require(str(drawer.sessionButtons[SessionPanelScript.PAUSE].text).begins_with("Resume"),
		"a paused session did not offer Resume")
	_require(str(drawer.sessionButtons[SessionPanelScript.SPEED].text).begins_with("Speed 0.5x"),
		"the speed row read '%s'" % drawer.sessionButtons[SessionPanelScript.SPEED].text)
	_require(drawer.sessionButtons[SessionPanelScript.SKIP].disabled,
		"Skip was offered with nothing to skip")
	_require(drawer.sessionButtons[SessionPanelScript.RESTART].disabled,
		"Restart was offered mid-battle")
	drawer.setSession({"phase": "complete", "result": "Draw", "rounds": 7})
	_require(str(drawer.sessionTitle.text).contains("Draw")
		and str(drawer.sessionTitle.text).contains("7 rounds"),
		"a finished session read '%s'" % drawer.sessionTitle.text)
	_require(not drawer.sessionButtons[SessionPanelScript.RESTART].disabled
		and not drawer.sessionButtons[SessionPanelScript.SETUP].disabled
		and drawer.sessionButtons[SessionPanelScript.PAUSE].disabled,
		"a finished session did not offer exactly restart and setup")


# --- CPU battle: pause, speed, skip ------------------------------------------------

func _checkCpuPauseSpeedSkip() -> void:
	if not _start(CPU_SCENARIO):
		return
	var adapter := _controller.adapter
	var feedback = adapter._feedback
	# Wait for a cast to be playing, so the pause is tested on a live effect carrier.
	var sawCast := false
	for _frame in range(FRAME_LIMIT):
		await process_frame
		if adapter.queue().activeActionKind() == "cast_area" and feedback.liveEffectCount() > 0:
			sawCast = true
			break
		if _controller.sim.state.battleOutcome != -1:
			break
	_require(sawCast, "no cast played in the CPU battle, so pause was not tested on a live effect")

	var effects := _liveEffects(feedback)
	_pushKey(KEY_P)
	await _frames(2)
	_require(_controller.playback.isPaused() and adapter.isPlaybackPaused(),
		"P did not pause the gate and the queue")
	_require(_controller.hud.isInputLocked(), "commands were not shown locked while paused")
	var session: Dictionary = _controller.stage.graphicsPanel.drawnSession()
	_require(bool(session.get("paused", false)),
		"the debug drawer did not show the battle as paused")

	var commandsBefore := _commandCount()
	var historyBefore := _controller.sim.state.history.size()
	var activeBefore := adapter.queue().activeActionKind()
	var queuedBefore := adapter.queuedAnimationCount()
	var elapsedBefore := []
	for effect in effects:
		elapsedBefore.append(effect.get_elapsed_time())
		_require(is_zero_approx(_scaleOf(effect)),
			"a live effect carrier kept playing while paused")
	await _frames(PAUSE_FRAMES)
	_require(_commandCount() == commandsBefore and _controller.sim.state.history.size() == historyBefore,
		"the battle submitted commands or events while paused")
	_require(adapter.queue().activeActionKind() == activeBefore
		and adapter.queuedAnimationCount() == queuedBefore,
		"playback moved on while paused")
	for index in range(effects.size()):
		var effect = effects[index]
		if is_instance_valid(effect):
			_require(is_equal_approx(effect.get_elapsed_time(), float(elapsedBefore[index])),
				"a paused cast kept advancing its own clock")
	_evidence["paused_frames"] = PAUSE_FRAMES
	_evidence["paused_live_effects"] = effects.size()
	_evidence["commands_at_pause"] = commandsBefore

	# Skip while paused finalizes the active action but starts nothing.
	_controller.stage.graphicsPanel.session_command.emit(SessionPanelScript.SKIP)
	await _frames(3)
	_require(adapter.queue().activeActionKind() == "" and _commandCount() == commandsBefore,
		"skip while paused did not settle the active action, or started more")

	# Resume, then speed.
	_controller.stage.graphicsPanel.session_command.emit(SessionPanelScript.PAUSE)
	await _frames(1)
	_require(not _controller.playback.isPaused() and not adapter.isPlaybackPaused(),
		"resume did not release the gate and the queue")
	_pushKey(KEY_F)
	await _frames(1)
	_require(is_equal_approx(_controller.playback.speed(), 2.0)
		and is_equal_approx(adapter.playbackSpeed(), 2.0)
		and is_equal_approx(feedback.playbackScale(), 2.0),
		"F did not reach the gate, the adapter and the feedback")
	for effect in _liveEffects(feedback):
		_require(_scaleOf(effect) < 0.0 or is_equal_approx(_scaleOf(effect), 2.0),
			"a live effect carrier did not take the new speed")
	var progressed := false
	for _frame in range(FRAME_LIMIT):
		await process_frame
		if _commandCount() > commandsBefore or _controller.sim.state.battleOutcome != -1:
			progressed = true
			break
	_require(progressed, "the battle did not continue after resume")

	# Pause again while a CPU member is deliberating: the decision must not be applied.
	var sawDeliberation := false
	for _frame in range(FRAME_LIMIT):
		await process_frame
		if _controller._deliberation != null:
			sawDeliberation = true
			break
		if _controller.sim.state.battleOutcome != -1:
			break
	_require(sawDeliberation, "no CPU deliberation was caught in flight to pause")
	if sawDeliberation:
		_controller.togglePause()
		var deliberation = _controller._deliberation
		var commandsAtThink := _commandCount()
		var historyAtThink := _controller.sim.state.history.size()
		await _frames(PAUSE_FRAMES)
		_require(_controller._deliberation == deliberation and _commandCount() == commandsAtThink
			and _controller.sim.state.history.size() == historyAtThink,
			"a CPU decision was applied while paused")
		_controller.togglePause()
		var applied := false
		for _frame in range(FRAME_LIMIT):
			await process_frame
			if _controller._deliberation != deliberation:
				applied = true
				break
		_require(applied, "a paused CPU decision was never applied after resume")

	# Skip while playing moves to a different action.
	var skipped := false
	for _frame in range(FRAME_LIMIT):
		await process_frame
		if adapter.queue()._isAnimating:
			var action = adapter.queue()._activeAction
			_pushKey(KEY_ENTER)
			await _frames(1)
			skipped = adapter.queue()._activeAction != action
			break
	_require(skipped, "Enter did not skip the playing action in a CPU battle")
	_controller.returnToSetup()
	await _frames(2)


## The carrier's own playback scale. Every shipped effect keeps it in `_playbackScale`; 0 is paused.
func _scaleOf(effect) -> float:
	var value = effect.get("_playbackScale")
	return float(value) if value != null else 0.0


## At 1280x720 the session window sits inside the screen and clear of every other HUD window.
func _checkSessionLayout() -> void:
	var hud := _controller.hud
	var screen := Rect2(Vector2.ZERO, Vector2(SCREEN))
	var toggle := _controller.stage.graphicsPanel.toggleButton
	var drawer := Rect2(
		Vector2(SCREEN.x + toggle.position.x, toggle.position.y), toggle.size)
	var boxes := {
		"party": Rect2(hud.partyPanel.position, hud.partyPanel.windowSize()),
		"order": Rect2(hud.orderPanel.position, hud.orderPanel.windowSize()),
		"commands": Rect2(hud.commandMenu.position, hud.commandMenu.windowSize()),
		"readout": Rect2(hud.readout.position, hud.readout.boxSize()),
	}
	for name in boxes:
		var box: Rect2 = boxes[name]
		_require(box.size.y > 0.0, "the %s window was not shown on a player's menu" % name)
		_require(screen.encloses(box), "%s at %s leaves the 1280x720 screen" % [name, box])
		# Every box keeps clear of the screen edges: docked hard into a corner they read as
		# falling off it.
		_require(box.position.x >= NoggTheme.HEX_SCREEN_MARGIN - 0.5
				and box.position.y >= NoggTheme.HEX_SCREEN_MARGIN - 0.5
				and box.end.x <= SCREEN.x - NoggTheme.HEX_SCREEN_MARGIN + 0.5
				and box.end.y <= SCREEN.y - NoggTheme.HEX_SCREEN_MARGIN + 0.5,
			"%s at %s sits inside the HUD's own screen margin" % [name, box])
		_require(not drawer.intersects(box),
			"the debug drawer's toggle overlaps %s at 1280x720" % name)
	for name in boxes:
		for other in boxes:
			if name >= other:
				continue
			_require(not (boxes[name] as Rect2).intersects(boxes[other] as Rect2),
				"%s overlaps %s at 1280x720" % [name, other])
	_evidence["hud_rects_720p"] = str(boxes)


func _liveEffects(feedback) -> Array:
	var result := []
	for ref in feedback._liveEffects:
		var effect = ref.get_ref()
		if effect != null and is_instance_valid(effect):
			result.append(effect)
	return result


# --- player battle: pause refuses commands ---------------------------------------

func _checkPlayerPause() -> void:
	if not _start(PLAYER_SCENARIO):
		return
	_controller.hud.partyPanel._window.row_built.connect(
		func(row: Control, index: int): _panelRows[index] = row)
	if not await _awaitPlayerParty():
		_require(false, "no player activation opened")
		return
	await _frames(1)
	_clickRow(_panelRows.get(1))
	await _frames(2)
	if _controller.memberInput == null:
		_require(false, "no member turn opened")
		return
	var input := _controller.memberInput
	await _frames(2)
	_checkSessionLayout()

	_controller.stage.graphicsPanel.session_command.emit(SessionPanelScript.PAUSE)
	await _frames(2)
	var before := _fingerprint()
	_controller.hud.command_chosen.emit("move")
	_pushKey(KEY_ENTER)
	_pushKey(KEY_RIGHT)
	_controller.hud.end_party_requested.emit()
	_controller.hud.member_selected.emit(int(_controller.sim.state.parties[
		int(_controller.sim.state.activePartyID)].memberIDs[1]))
	await _frames(2)
	_require(_fingerprint() == before, "a paused player battle accepted a command")
	_require(input.phase() == HexBattleMemberInput.Phase.MENU, "a paused menu entered an aim")
	_require(not bool(_controller.hud._partyModel.get("input_enabled", true)),
		"the party panel offered selection while paused")
	_require(not bool(_controller.hud._lockedCommands(_controller.hud._commandModel)
		.get("input_enabled", true)), "the command menu offered commands while paused")

	# The camera and inspection still work.
	var yawBefore: Transform3D = _controller.battleCamera.camera.global_transform
	_pushKey(KEY_E)
	await _frames(30)
	_require(not _controller.battleCamera.camera.global_transform.is_equal_approx(yawBefore),
		"the camera did not turn while paused")
	var unitID := await _hoverSomeUnit()
	_require(unitID >= 0, "hover inspection found no unit while paused")
	_evidence["paused_hover_unit"] = unitID

	_pushKey(KEY_P)
	await _frames(2)
	_controller.hud.command_chosen.emit("move")
	await _frames(1)
	_require(input.phase() == HexBattleMemberInput.Phase.AIM_MOVE, "commands did not return on resume")
	await _frames(2)
	# The session controls live in the debug drawer now, off the board entirely, so an aim has
	# nothing to step aside for: the keys keep working and the drawer keeps its state.
	_require(_controller.stage.graphicsPanel.drawnSession().get("aiming", false),
		"the drawer did not know an aim was open")
	_pushKey(KEY_ESCAPE)
	await _frames(2)
	_controller.returnToSetup()
	await _frames(2)


# --- ledger, final drain, restart ---------------------------------------------------

## The same seed's first commands at 1x, and at 4x with a pause in the middle, must be the same
## commands. Then the 4x battle is played to its end and restarted.
func _checkLedgerFinalDrainAndRestart() -> void:
	var normal := await _ledgerRun(1.0, false)
	var altered := await _ledgerRun(4.0, true)
	_require(normal["ledger"].size() == LEDGER_COMMANDS, "the 1x run recorded %d commands" % normal["ledger"].size())
	_require(JSON.stringify(normal["ledger"]) == JSON.stringify(altered["ledger"]),
		"the command ledger changed with presentation speed or a pause")
	_require(int(altered["frames"]) < int(normal["frames"]),
		"4x playback took %d frames against %d at 1x" % [altered["frames"], normal["frames"]])
	_evidence["ledger_frames_1x"] = normal["frames"]
	_evidence["ledger_frames_4x_paused"] = altered["frames"]

	# Play the 4x battle to its end.
	var sim := _controller.sim
	var endingBusyFrames := 0
	var sawEnding := false
	for _frame in range(FRAME_LIMIT * 3):
		await process_frame
		if sim.state.battleOutcome != -1 and _controller.lifecycle != HexBattleController.Lifecycle.COMPLETE:
			sawEnding = true
			if _controller.adapter.isAnimationBusy():
				endingBusyFrames += 1
		if _controller.lifecycle == HexBattleController.Lifecycle.COMPLETE:
			break
	_require(_controller.lifecycle == HexBattleController.Lifecycle.COMPLETE,
		"the CPU battle did not complete")
	if _controller.lifecycle != HexBattleController.Lifecycle.COMPLETE:
		return
	_require(sawEnding and endingBusyFrames > 0,
		"the result never waited on playback, so the final drain was not exercised")
	_require(not _controller.adapter.isAnimationBusy() and _controller.adapter.queuedAnimationCount() == 0,
		"the battle completed with playback still queued")
	for value in sim.state.monsters.keys():
		var id := int(value)
		var gone: bool = not sim.state.getMonster(id).is_alive() or sim.state.isMonsterWithdrawn(id)
		if gone:
			_require(not _controller.adapter.displayedRemovalReason(id).is_empty(),
				"unit %d was gone when the result showed, but its removal had not played" % id)
	var result := HexBattleControllerScript.resultText(sim.state)
	_require(not result.is_empty() and not result.begins_with("Team 0"), "the result read '%s'" % result)
	_require(_controller.hud.statusText() == result + ".", "the status line did not show the result")
	await _frames(2)
	var session: Dictionary = _controller.stage.graphicsPanel.drawnSession()
	_require(str(session.get("result", "")) == result,
		"the debug drawer did not show the result")
	_evidence["outcome"] = result
	_evidence["rounds"] = sim.state.roundCount
	_evidence["ending_busy_frames"] = endingBusyFrames

	# Restart: R, same scenario and seed, same opening state, the chosen speed, not paused.
	var oldSim := sim
	var oldAdapter := _controller.adapter
	var opening := JSON.stringify(oldSim.initialStateSnapshot)
	_pushKey(KEY_R)
	await _frames(3)
	_require(_controller.lifecycle == HexBattleController.Lifecycle.BATTLE and _controller.sim != oldSim,
		"R did not restart a finished battle")
	if _controller.sim == oldSim or _controller.sim == null:
		return
	_require(_controller._scenarioPath == CPU_SCENARIO and _controller._seedValue == SEED,
		"restart changed the scenario or seed")
	_require(JSON.stringify(_controller.sim.initialStateSnapshot) == opening,
		"the restarted battle did not open in the same state")
	_require(is_equal_approx(_controller.playback.speed(), 4.0) and not _controller.playback.isPaused(),
		"restart did not keep the chosen speed, or opened paused")
	_require(oldAdapter._disposed, "the finished battle's adapter was not disposed on restart")
	_require(oldSim.events.monster_moved.get_connections().is_empty()
		and oldSim.events.spell_cast_started.get_connections().is_empty(),
		"the finished battle's simulator still had listeners after restart")
	_controller.returnToSetup()
	await _frames(2)


func _ledgerRun(speed: float, pauseMidway: bool) -> Dictionary:
	if not _start(CPU_SCENARIO):
		return {"ledger": [], "frames": 0}
	_controller.playback.setSpeed(speed)
	_controller._speedPreference = speed
	var frames := 0
	var paused := false
	while frames < FRAME_LIMIT and _commandCount() < LEDGER_COMMANDS \
			and _controller.sim.state.battleOutcome == -1:
		await process_frame
		frames += 1
		if pauseMidway and not paused and _commandCount() >= 3:
			paused = true
			_controller.togglePause()
			await _frames(PAUSE_FRAMES)
			_controller.togglePause()
	var ledger := []
	for entry in _controller.sim.state.history:
		if str(entry.get("type", "")) == "command" and ledger.size() < LEDGER_COMMANDS:
			ledger.append(entry)
	return {"ledger": ledger, "frames": frames}


# --- repeated transitions ----------------------------------------------------------

func _checkRepeatedTransitions() -> void:
	var counts := []
	for cycle in range(3):
		if not _start(PLAYER_SCENARIO if cycle % 2 == 0 else CPU_SCENARIO):
			return
		await _frames(40)
		if cycle == 1:
			# Start over a battle whose playback is mid-flight.
			_require(_controller.adapter.isAnimationBusy() or _controller._deliberation != null
				or _controller.sim.state.activePartyID != -1, "cycle 2 had nothing in flight to replace")
			_start(CPU_SCENARIO)
			await _frames(40)
		var live := _battleNodeCounts()
		_require(live["stages"] == 1 and live["huds"] == 1 and live["badge_layers"] == 1
			and live["number_layers"] <= 1,
			"a running battle had %s" % [live])
		_controller.returnToSetup()
		await _frames(3)
		var after := _battleNodeCounts()
		_require(after["stages"] == 0 and after["huds"] == 0 and after["badge_layers"] == 0
			and after["number_layers"] == 0,
			"return to setup left battle nodes behind: %s" % [after])
		counts.append(after["all"])
	_require(counts.size() == 3 and counts[0] == counts[1] and counts[1] == counts[2],
		"node count grew across start/return cycles: %s" % [counts])
	_evidence["node_counts_after_return"] = counts


func _battleNodeCounts() -> Dictionary:
	var result := {"stages": 0, "huds": 0, "badge_layers": 0, "number_layers": 0, "all": 0}
	var stack: Array[Node] = [root]
	while not stack.is_empty():
		var node: Node = stack.pop_back()
		if node.is_queued_for_deletion():
			continue
		result["all"] += 1
		if node is HexBattleStage:
			result["stages"] += 1
		elif node is HexBattleHud:
			result["huds"] += 1
		elif node is HexBattleUnitBadges:
			result["badge_layers"] += 1
		elif node.name == "HexCombatNumbers":
			result["number_layers"] += 1
		for child in node.get_children():
			stack.append(child)
	return result


# --- helpers --------------------------------------------------------------------------

func _start(scenario: String) -> bool:
	_panelRows.clear()
	var started := _controller.startBattle(scenario, SEED)
	_require(bool(started.get("ok", false)), "battle %s did not start: %s" % [
		scenario.get_file(), str(started.get("error", ""))])
	return bool(started.get("ok", false))


func _commandCount() -> int:
	if _controller.sim == null:
		return 0
	var count := 0
	for entry in _controller.sim.state.history:
		if str(entry.get("type", "")) == "command":
			count += 1
	return count


func _awaitPlayerParty() -> bool:
	for _frame in range(FRAME_LIMIT):
		await process_frame
		var sim := _controller.sim
		if sim == null or sim.state.activePartyID == -1 or not _controller.playback.isIdle():
			continue
		var party = sim.state.parties.get(int(sim.state.activePartyID))
		if party != null and party.controller == "player":
			return true
	return false


func _fingerprint() -> String:
	var input := _controller.memberInput
	return JSON.stringify({
		"snapshot": _controller.sim.createReplaySnapshot(),
		"history": _controller.sim.state.history.size(),
		"phase": input.phase() if input != null else -1,
		"cursor": str(input.cursorCell()) if input != null else "",
		"owner": _controller.playback.owner(),
		"member": _controller.memberTurn.monsterID() if _controller.memberTurn != null else -1,
		"party": _controller.sim.state.activePartyID,
	})


## Points at each unit on screen in turn until one is hovered. Returns it, or -1.
func _hoverSomeUnit() -> int:
	for value in _controller.adapter.shownModelIDs():
		var id := int(value)
		var point: Vector2 = _controller._projectCell(_controller.adapter.displayedPosition(id))
		if point.x < 0.0 or not Rect2(Vector2.ZERO, Vector2(SCREEN)).has_point(point):
			continue
		_pushMotion(point)
		await _frames(2)
		if _controller.hud.hoverID() == id:
			return id
	return -1


func _pushKey(keycode: Key) -> void:
	var event := InputEventKey.new()
	event.keycode = keycode
	event.pressed = true
	root.push_input(event)


func _pushMotion(point: Vector2) -> void:
	var event := InputEventMouseMotion.new()
	event.position = point
	event.global_position = point
	root.push_input(event)


func _clickRow(row: Control) -> void:
	if row == null:
		return
	var event := InputEventMouseButton.new()
	event.button_index = MOUSE_BUTTON_LEFT
	event.pressed = true
	row.gui_input.emit(event)


func _frames(count: int) -> void:
	for _index in range(count):
		await process_frame
