## The hex battle's composition root: setup, whole-side turns, and return to setup.
##
## NOT A SUBCLASS OF `BattlePresentationController`, deliberately and by instruction. That
## controller's loop is `turnManager.startNextTurn()` -- a speed-ordered queue of individual
## monsters -- and the approved model here is a queue of PARTIES, each of which then lets its
## members act in an order the player chooses. Those are different loops, not the same loop with
## different data, and inheriting one to express the other would have meant overriding the parts
## that matter while carrying the parts that no longer apply.
##
## THE LOOP, WHOLE:
##
##     startNextSideTurn()             -- deterministic side order
##       -> player side: click any ready unit, move/act, switch freely, repeat
##       -> CPU side: re-deliberate one ready unit after every resolution
##     endSideTurn()                   -- when no unit is ready, or the player confirms
##
## ONE SCHEDULING OWNER, and it is `HexBattlePlayback`. Every path that could start something --
## the frame loop, the playback-drained signal, a HUD click, CPU deliberation finishing -- asks
## the gate first and claims it before acting. That is what stops the two failures this item
## names: a second turn opening on top of an open one, and input reaching a side that has already
## ended.
##
## EVERY POSITION COMES FROM `HexBattleLayout`, through the adapter. This file computes no
## coordinates of its own.

class_name HexBattleController
extends Node3D

const HexBattleVisualAdapterScript = preload(
	"res://src/presentation/battle/HexBattleVisualAdapter.gd")
const HexBattleCameraScript = preload("res://src/presentation/battle/HexBattleCamera.gd")
const HexBattleStageScript = preload("res://src/presentation/battle/HexBattleStage.gd")
const HexBattleCursorScript = preload("res://src/presentation/battle/HexBattleCursor.gd")
const HexBattleHudScript = preload("res://src/presentation/battle/HexBattleHud.gd")
const HexBattleSetupUIScript = preload("res://src/presentation/battle/HexBattleSetupUI.gd")
const HexBattlePlaybackScript = preload("res://src/presentation/battle/HexBattlePlayback.gd")
const HexBattleMemberTurnScript = preload("res://src/systems/hex_battle/HexBattleMemberTurn.gd")
const HexBattleMemberInputScript = preload(
	"res://src/systems/hex_battle/HexBattleMemberInput.gd")
const SideTurnScreenCuesScript = preload(
	"res://src/presentation/battle/ui/side_turn/SideTurnScreenCues.gd")
const SideDeliberationScript = preload("res://src/entity_ai/PartyCommandDeliberation.gd")
const BattleSimulatorScript = preload("res://src/battle_sim/BattleSimulator.gd")
const BattleSetupConfigScript = preload("res://src/battle_sim/BattleSetupConfig.gd")
const BattleSetupFactoryScript = preload("res://src/battle_sim/BattleSetupFactory.gd")
const BattleScenarioFactoryScript = preload("res://src/factories/BattleScenarioFactory.gd")
const NoggThemeScript = preload("res://src/presentation/theme/NoggTheme.gd")
const HexGraphicsPanelScript = preload("res://src/presentation/battle/ui/HexGraphicsPanel.gd")

## ENDING is the stretch between the simulator deciding the battle and the screen showing the blow
## that decided it. Nothing may start in it, and the result waits for playback to drain.
enum Lifecycle { SETUP, BATTLE, ENDING, COMPLETE }

## How often the loop re-checks whether it may advance. A timer rather than `_process` so a
## battle that is waiting on playback is not re-evaluated sixty times a second for no reason.
const ADVANCE_INTERVAL_SECONDS := 0.05

## PartyCommandDeliberation already exposes deterministic slices. Four inner slices per rendered
## frame kept the measured proving-ground maximum comfortably responsive without cross-thread
## access to mutable battle state.
const DELIBERATION_SLICES_PER_FRAME := 4
## How far, in viewport pixels, a right press may travel and still count as a click.
const RIGHT_TAP_SLOP := 4.0

var sim: BattleSimulator
var adapter: HexBattleVisualAdapter
var battleCamera: HexBattleCamera
var stage: HexBattleStage
var hud: HexBattleHud
var setupUI: HexBattleSetupUI
var playback: HexBattlePlayback
var cursor: HexBattleCursor
var memberTurn: HexBattleMemberTurn
var memberInput: HexBattleMemberInput
var sideCues

var lifecycle: Lifecycle = Lifecycle.SETUP
var map: BattleMapDefinition

var _advanceTimer: Timer
var _boardRoot: Node3D
## Where the current right press started, or (-1, -1). A release within RIGHT_TAP_SLOP of it is a
## tap, which cancels the current aim or selection; anything further was a camera pan.
var _rightPressPosition := Vector2(-1.0, -1.0)
var _deliberation = null
var _deliberatingMemberID := -1
var _scenarioPath := ""
var _seedValue := 0
## The presentation speed the player last chose. Carried into a restart, which is the same battle
## watched again; pause is not carried, because a restarted battle that opens frozen reads as hung.
var _speedPreference := HexBattlePlaybackScript.DEFAULT_SPEED
## Why the authored terrain is not drawn, for the status line. Empty when it is, or when the map
## declares no scene at all.
var _terrainNotice := ""
var _lastReadyCount := -1
## The enemy the pointer currently previews outside an aim, or -1. Rebuilding the preview box on
## every motion event would replay its entrance, so the cues change only when this does.
var _pointerTargetID := -1


func _ready() -> void:
	setupUI = HexBattleSetupUIScript.new()
	add_child(setupUI)
	setupUI.battle_requested.connect(_onBattleRequested)

	_advanceTimer = Timer.new()
	_advanceTimer.name = "AdvanceTimer"
	_advanceTimer.wait_time = ADVANCE_INTERVAL_SECONDS
	_advanceTimer.timeout.connect(_advance)
	add_child(_advanceTimer)

	_enterSetup()


# --- lifecycle --------------------------------------------------------------

func _enterSetup() -> void:
	lifecycle = Lifecycle.SETUP
	_advanceTimer.stop()
	setupUI.setVisibleUI(true)
	if hud != null:
		hud.clearParty()


## Tears the battle down completely before building another. Everything this controller owns is
## disconnected and freed here -- the failure named for return-to-setup is old callbacks surviving
## into the next battle, and the only reliable defence is that nothing survives at all.
func teardownBattle() -> void:
	_deliberation = null
	_deliberatingMemberID = -1
	if memberTurn != null:
		memberTurn.cancel()
		memberTurn = null
	memberInput = null
	if adapter != null:
		adapter.disconnectFromEvents()
		if adapter.animation_queue_drained.is_connected(_onPlaybackDrained):
			adapter.animation_queue_drained.disconnect(_onPlaybackDrained)
		adapter.dispose()
		adapter = null
	if hud != null:
		hud.queue_free()
		hud = null
	if sideCues != null:
		sideCues.queue_free()
		sideCues = null
	if _boardRoot != null:
		_boardRoot.queue_free()
		_boardRoot = null
	if stage != null:
		stage.dispose()
		stage = null
	battleCamera = null
	playback = null
	cursor = null
	sim = null
	map = null
	_terrainNotice = ""
	_lastReadyCount = -1


func returnToSetup() -> void:
	teardownBattle()
	_enterSetup()


func _onBattleRequested(scenarioPath: String, seedValue: int) -> void:
	var started := startBattle(scenarioPath, seedValue)
	if not started.get("ok", false):
		_enterSetup()
		setupUI.showError(startErrorText(started))


## A refusal the player can act on. The code says which step refused; the detail, when the step
## gave one, says why.
static func startErrorText(result: Dictionary) -> String:
	var code := str(result.get("error", ""))
	var detail := str(result.get("detail", ""))
	var step := "The battle could not start"
	match str(result.get("step", "")):
		"scenario":
			step = "The scenario could not be loaded"
		"validation":
			step = "The scenario is not a valid battle"
		"state":
			step = "The battle could not be set up"
	var cause := detail if not detail.is_empty() else code.replace("_", " ")
	return "%s: %s." % [step, cause] if not cause.is_empty() else "%s." % step


## Builds a battle from a scenario. Returns a result rather than reporting through a status line,
## so the scene probe can assert WHY a start was refused.
func startBattle(scenarioPath: String, seedValue: int) -> Dictionary:
	teardownBattle()

	var loaded := BattleScenarioFactoryScript.loadFromPath(scenarioPath)
	if not loaded["success"]:
		return {"ok": false, "step": "scenario",
			"error": str(loaded.get("error", "scenario_unreadable")),
			"detail": str(loaded.get("detail", ""))}
	var scenario: BattleScenario = loaded["scenario"]

	var config: BattleSetupConfig = BattleSetupConfigScript.new()
	config.scenarioPath = scenarioPath
	config.seed = seedValue
	var validation := config.validate()
	if not validation.success:
		return {"ok": false, "step": "validation", "error": "invalid_setup",
			"detail": validation.errorText()}

	var stateResult := BattleSetupFactoryScript.createHexState(config)
	if not stateResult["success"]:
		return {"ok": false, "step": "state",
			"error": str(stateResult.get("error", "state_failed")),
			"detail": str(stateResult.get("detail", ""))}

	_scenarioPath = scenarioPath
	_seedValue = seedValue
	map = scenario.battleMap
	sim = BattleSimulatorScript.new(seedValue)
	sim.configureHexState(stateResult["state"], scenario, {"scenarioPath": scenarioPath})

	stage = HexBattleStageScript.new()
	add_child(stage)
	_boardRoot = Node3D.new()
	_boardRoot.name = "HexBoard"
	stage.worldRoot().add_child(_boardRoot)

	adapter = HexBattleVisualAdapterScript.new(_boardRoot, map, sim.state)
	sim.setVisualAdapter(adapter)
	# Without the resolver the adapter previews no spell cells and forecasts nothing. Only the preview
	# probe ever set it, so the live battle aimed blind.
	adapter.setCombatResolver(sim.combatResolver)
	adapter.connectToEvents(sim.events)
	adapter.animation_queue_drained.connect(_onPlaybackDrained)
	# FHB-1: the adapter is listening now, so this is the earliest point the board can be
	# announced -- and it must happen before sim.startBattle() opens the turn loop, or the first
	# move would be the first thing a connected adapter ever hears about.
	sim.emitInitialBoard()

	# The authored terrain goes into the stage's own world, under the board. A map without
	# its generated scene still starts, on the grey board, with a notice saying to re-export.
	_terrainNotice = str(stage.loadTerrain(map).get("notice", ""))
	adapter.boardView.showOverTerrain(stage.hasTerrain())

	# Frames the battlefield, not the art. The valid cells are what a player acts on; exported
	# ground extends past them by a fog-length skirt, and framing that would shrink the board.
	battleCamera = HexBattleCameraScript.new()
	stage.worldRoot().add_child(battleCamera)
	stage.attachCamera(battleCamera)
	battleCamera.frameMap(map, adapter.layout)
	battleCamera.camera.current = true

	# The HUD's windows are measured in design units; the scale must match this window before they
	# are built, as the square battle did, or a 720p HUD is laid out for the default x3.
	NoggThemeScript.configure_for_window_height(get_window().size.y)
	hud = HexBattleHudScript.new()
	add_child(hud)
	hud.member_selected.connect(_onHudMemberSelected)
	hud.end_party_requested.connect(_onHudEndParty)
	hud.command_chosen.connect(_onHudCommandChosen)
	hud.command_cancelled.connect(_onHudCommandCancelled)
	stage.graphicsPanel.session_command.connect(_onSessionCommand)
	hud.selection_lost.connect(func(_id: int): _selectUnit(_actingMemberID()))
	hud.bind(sim, adapter)
	hud.setSideTurnMode(true)

	sideCues = SideTurnScreenCuesScript.new()
	add_child(sideCues)
	sideCues.setProjector(stage.projectWorldToScreen)
	sideCues.action_requested.connect(_onSideActionRequested)
	sideCues.end_turn_requested.connect(_onHudEndParty)
	# Puts a terrain notice, if there is one, on the status line before the battle says anything.
	_setStatus("")

	playback = HexBattlePlaybackScript.new(adapter)
	playback.setSpeed(_speedPreference)
	cursor = HexBattleCursorScript.new()

	setupUI.setVisibleUI(false)
	lifecycle = Lifecycle.BATTLE
	sim.startBattle()
	_advanceTimer.start()
	return {"ok": true, "scenario": scenarioPath, "terrain": stage.terrainReport()}


# --- the loop ---------------------------------------------------------------

## The only place a side turn or CPU choice is started.
func _advance() -> void:
	if sim == null or playback == null:
		return
	if lifecycle == Lifecycle.ENDING:
		# The result waits for the last consequence to finish playing. Paused counts as not yet.
		if playback.isDrained() and not playback.isPaused():
			_completeBattle()
		return
	if lifecycle != Lifecycle.BATTLE:
		return
	if sim.state.battleOutcome != -1:
		_beginEnding()
		return
	if not playback.canAdvance():
		return

	# A side turn is open: serve whichever controller owns that team.
	if sim.state.activeSideID != -1:
		_serveOpenActivation()
		return

	# Nothing open, and the screen has caught up: open the next side.
	if not playback.isDrained():
		return
	var opened := sim.startNextSideTurn()
	if not bool(opened.get("success", false)):
		if str(opened.get("reason", "")) == "battle_ended":
			_beginEnding()
		return
	_onActivationOpened(int(opened.get("side_id", -1)))


func _onActivationOpened(sideID: int) -> void:
	var controller := _sideController(sideID)
	if controller.is_empty():
		return
	adapter.setSelectedUnit(-1)
	adapter.setTargetedUnit(-1)
	if sideCues != null:
		sideCues.hideActionArc()
		sideCues.clearForecasts()
	if sideCues != null:
		sideCues.showTurnBanner(controller == "player")
		_lastReadyCount = sim.eligibleSideUnitIDs().size()
		sideCues.setReadyCount(_lastReadyCount)
	_syncSpentCues()
	_setStatus("Your turn." if controller == "player" else "Enemy turn.")


func _serveOpenActivation() -> void:
	var sideID := int(sim.state.activeSideID)
	var controller := _sideController(sideID)
	if controller.is_empty():
		return
	var eligible := sim.eligibleSideUnitIDs()
	if eligible.is_empty():
		sim.endSideTurn("system")
		return
	if controller == "player":
		return
	_beginCpuMember(int(eligible[0]))


## Opens one sliced whole-side deliberation. It chooses the actor as well as the command, then a
## fresh instance is built after resolution so later units see the changed board.
func _beginCpuMember(_monsterID: int) -> void:
	if _deliberation != null:
		return
	if not playback.claim(HexBattlePlayback.OWNER_CPU):
		return
	_deliberation = SideDeliberationScript.new(sim)


## CPU work is sliced on the presentation thread so mutable canonical state is never read from a
## worker while playback or input can change it. The completed proposal is applied atomically.
func _process(_delta: float) -> void:
	_refreshHud()
	if _deliberation == null or sim == null:
		return
	if playback == null or playback.isPaused():
		return
	if not _deliberation.stepSlices(DELIBERATION_SLICES_PER_FRAME):
		return
	var proposal = _deliberation.result()
	_deliberation = null
	if proposal == null:
		sim.endSideTurn("cpu_no_proposal")
		playback.release(HexBattlePlayback.OWNER_CPU)
		return
	_deliberatingMemberID = int(proposal.actor_id)
	var selected := sim.selectUnit(_deliberatingMemberID, "cpu")
	if bool(selected.get("success", false)):
		_selectUnit(_deliberatingMemberID)
		var executed: BattleCommandResult = sim.executeCommand(
			_deliberatingMemberID, proposal.command, "cpu")
		if not executed.success:
			push_error("CPU side-turn command was refused: %s" % executed.reason)
			sim.endSideTurn("cpu_command_refused")
	else:
		push_error("CPU side-turn actor was refused: %s" % str(selected.get("reason", "unknown")))
		sim.endSideTurn("cpu_actor_refused")
	_syncSpentCues()
	playback.release(HexBattlePlayback.OWNER_CPU)
	_deliberatingMemberID = -1
	_checkFinished()


# --- player input -----------------------------------------------------------

## Selects or switches to any ready unit on the player's active side. A moved unit can be left and
## revisited because its pending turn lives in BattleState, not in this input object.
func _onHudMemberSelected(monsterID: int) -> void:
	if lifecycle != Lifecycle.BATTLE or sim == null or playback == null:
		return
	if _commandsLocked():
		return
	if sim.state.activeSideID == -1:
		return
	if _sideController(int(sim.state.activeSideID)) != "player":
		return
	if memberTurn != null and not memberTurn.isFinished():
		var previous := memberTurn.monsterID()
		memberTurn.cancel()
		memberTurn = null
		memberInput = null
		playback.release(HexBattlePlayback.OWNER_PLAYER, previous)
	if not playback.claim(HexBattlePlayback.OWNER_PLAYER, monsterID):
		return
	var selected := sim.selectUnit(monsterID, "player")
	if not bool(selected.get("success", false)):
		playback.release(HexBattlePlayback.OWNER_PLAYER, monsterID)
		return
	memberTurn = HexBattleMemberTurnScript.new(sim, adapter, cursor, map, monsterID)
	memberTurn.turn_finished.connect(_onMemberTurnFinished, CONNECT_ONE_SHOT)
	memberInput = HexBattleMemberInputScript.new(memberTurn, sim, adapter, map)
	memberInput.menu_changed.connect(_onMenuChanged)
	memberInput.menu_dismissed.connect(_onMenuDismissed)
	memberInput.status_changed.connect(_onMemberStatus)
	memberInput.aim_changed.connect(_onAimChanged)
	_selectUnit(monsterID)
	memberInput.begin()


func _onMenuChanged(model: Dictionary) -> void:
	if hud != null:
		hud.hideCommands()
	if sideCues == null or memberTurn == null:
		return
	var enabled := {"magic": false, "item": false, "status": true, "wait": true}
	for entry in model.get("commands", []):
		var id := str(entry.get("id", ""))
		if enabled.has(id):
			enabled[id] = bool(entry.get("enabled", false))
	var moved := bool(sim.turnPhaseState(memberTurn.monsterID()).get("has_moved", false))
	var anchor := adapter.worldPositionOf(sim.state.getMonsterPosition(memberTurn.monsterID())) \
		+ Vector3.UP * 1.35
	sideCues.showActionArc(anchor, enabled, ["magic"] if moved else [], memberTurn.canUndoMove())


func _onMenuDismissed() -> void:
	if hud != null:
		hud.hideCommands()
	if sideCues != null:
		sideCues.hideActionArc()
		sideCues.clearForecasts()


func _onMemberStatus(text: String) -> void:
	_setStatus(text)


func _onAimChanged(model: Dictionary) -> void:
	if hud != null:
		hud.showAim(model)
	if sideCues == null:
		return
	sideCues.setAiming(not model.is_empty())
	_pointerTargetID = -1
	_showTargetCues(model)


## Sword and preview boxes for an aim model, or for the pointer's attack model outside an aim.
func _showTargetCues(model: Dictionary) -> void:
	adapter.setTargetedUnit(-1)
	sideCues.clearForecasts()
	if model.is_empty():
		return
	var targetID := int(model.get("target_id", -1))
	if targetID != -1 and bool(model.get("legal", false)):
		adapter.setTargetedUnit(targetID)
	var forecasts: Array = []
	if str(model.get("kind", "")) == HexBattleMemberInputScript.SPELL_PREFIX:
		for cellValue in model.get("affected_cells", []):
			var cell: Vector2i = cellValue
			var affectedID := int(sim.state.board.at(cell)) if map.containsCell(cell) else 0
			if affectedID == 0:
				continue
			var forecast := adapter.forecastSpell(
				memberTurn.monsterID(), int(model.get("spell_set_index", 0)),
				int(model.get("spell_index", 0)), cell)
			if forecast.is_empty() or not bool(forecast.get("available", false)):
				continue
			var affected = sim.state.getMonster(affectedID)
			forecasts.append({
				"monster_id": affectedID,
				"name": str(affected.name) if affected != null else "Target",
				"world_anchor": adapter.worldPositionOf(cell) + Vector3.UP * 1.2,
				"forecast": forecast,
			})
	else:
		var forecast: Dictionary = model.get("forecast", {})
		if targetID != -1 and not forecast.is_empty():
			var target = sim.state.getMonster(targetID)
			forecasts.append({
				"monster_id": targetID,
				"name": str(target.name) if target != null else "Target",
				"world_anchor": adapter.worldPositionOf(sim.state.getMonsterPosition(targetID)) \
					+ Vector3.UP * 1.2,
				"forecast": forecast,
			})
	if not forecasts.is_empty():
		sideCues.showForecasts(forecasts)


func _onHudCommandChosen(commandID: String) -> void:
	if memberInput != null and not _commandsLocked():
		memberInput.chooseCommand(commandID)


func _onHudCommandCancelled() -> void:
	if memberInput != null and not _commandsLocked():
		memberInput.cancel()


func _onSideActionRequested(actionID: String) -> void:
	if memberInput == null or memberTurn == null or _commandsLocked():
		return
	match actionID:
		"magic":
			if hud != null:
				hud.showSpellCommands(memberInput.commandModel())
		"item":
			_setStatus("Items are not in battle yet.")
		"status":
			if hud != null:
				hud.openStatus(memberTurn.monsterID())
		"wait":
			memberInput.chooseCommand(HexBattleMemberInputScript.END_COMMAND)
		"undo":
			memberInput.chooseCommand(HexBattleMemberInputScript.UNDO_COMMAND)


func _onMemberTurnFinished(monsterID: int) -> void:
	memberTurn = null
	memberInput = null
	if hud != null:
		hud.hideCommands()
		hud.showAim({})
	if sideCues != null:
		sideCues.hideActionArc()
		sideCues.clearForecasts()
	adapter.setTargetedUnit(-1)
	_pointerTargetID = -1
	playback.release(HexBattlePlayback.OWNER_PLAYER, monsterID)
	_syncSpentCues()
	_checkFinished()


## End turn converts every remaining ready unit into Wait in deterministic ID order. The button
## owns the first-click confirmation when that list is non-empty.
func _onHudEndParty() -> void:
	if lifecycle != Lifecycle.BATTLE or sim == null or playback == null:
		return
	if _commandsLocked():
		return
	if sim.state.activeSideID == -1:
		return
	# A selected unit holds the player's playback claim, so the idle check must come after the
	# selection is let go. Checked first, End turn did nothing whenever a unit was selected -- which
	# is most of the time -- and left the button stuck asking.
	if memberTurn != null and not memberTurn.isFinished() 			and playback.owner() == HexBattlePlayback.OWNER_PLAYER:
		_cancelPlayerSelection()
	if not playback.isIdle():
		return
	sim.endSideTurn("player")
	if hud != null:
		hud.clearParty()
	if sideCues != null:
		sideCues.hideActionArc()
		sideCues.setReadyCount(0)
	_syncSpentCues()
	_checkFinished()


## Keeps the HUD on what the screen has shown. Every frame, because displayed HP and removals
## change when queued playback reaches them, and that has no signal the controller hears. The
## HUD redraws a panel only when its model changed.
##
## A pointer resting on a HUD window reaches no `_unhandled_input`, so a hover set over the board
## would otherwise stay stuck on the last unit crossed on the way to the panel.
func _refreshHud() -> void:
	if hud == null or sim == null:
		return
	if get_viewport().gui_get_hovered_control() != null:
		_hoverUnit(-1)
		if adapter != null and adapter.boardView != null:
			adapter.boardView.clearHover()
	hud.setInputLocked(_commandsLocked())
	if sideCues != null and sim.state.activeSideID != -1:
		sideCues.setEndTurnVisible(_sideController(int(sim.state.activeSideID)) == "player")
		var readyCount := sim.eligibleSideUnitIDs().size()
		if readyCount != _lastReadyCount:
			_lastReadyCount = readyCount
			sideCues.setReadyCount(readyCount)
	if stage != null and stage.graphicsPanel != null:
		stage.graphicsPanel.setSession(_sessionState())
	hud.refresh()


## Camera first, then inspection and the member turn. A camera drag owns its motion event, so it
## cannot also move an aim cursor or leave a stale unit inspection under the pointer. Ordinary
## hover and left clicks still fall through exactly as before.
##
## INSPECTION NEVER CONSUMES AN EVENT. Hover and click only tell the HUD which unit to read out, and
## the same event then continues to the aim, so pointing at a unit while aiming both aims at it and
## shows it. A click reaches inspection only when nobody is aiming, where a board click had no
## meaning before. GUI controls consume their own clicks before this runs, so a click on a panel
## row never inspects the unit behind it.
func _unhandled_input(event: InputEvent) -> void:
	if lifecycle == Lifecycle.SETUP or battleCamera == null:
		return
	if event is InputEventKey and event.pressed and not event.echo and _handleSessionKey(event):
		get_viewport().set_input_as_handled()
		return
	# The STATUS sheet is modal: while it is open every key is its, and any click outside its own
	# windows closes it. Nothing reaches the camera, the board or the turn.
	if hud != null and hud.isModalOpen():
		var claimed := false
		if event is InputEventKey:
			claimed = hud.handleKey(event)
		elif event is InputEventMouseButton:
			claimed = hud.handleBoardMouse(event)
		if claimed or event is InputEventMouseButton:
			get_viewport().set_input_as_handled()
		return
	# A right click that never became a pan cancels the current aim or selection; a right drag pans.
	if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_RIGHT:
		if event.pressed:
			_rightPressPosition = event.position
		elif _rightPressPosition.x >= 0.0:
			var tapped: bool = event.position.distance_to(_rightPressPosition) <= RIGHT_TAP_SLOP
			_rightPressPosition = Vector2(-1.0, -1.0)
			if tapped:
				battleCamera.cancelDrag()
				if memberInput != null and memberInput.isAiming():
					memberInput.cancel()
					get_viewport().set_input_as_handled()
					return
				if memberTurn != null:
					_cancelPlayerSelection()
					get_viewport().set_input_as_handled()
					return
	if battleCamera.handleInput(event, get_viewport().get_visible_rect().size.y):
		_hoverUnit(-1)
		if adapter != null and adapter.boardView != null:
			adapter.boardView.clearHover()
		get_viewport().set_input_as_handled()
		return
	if event is InputEventMouseButton and event.pressed \
			and event.button_index == MOUSE_BUTTON_LEFT and _handleSideClick(event.position):
		get_viewport().set_input_as_handled()
		return
	if hud != null:
		if event is InputEventMouseMotion:
			_hoverUnit(_unitUnderPointer(event.position))
		elif event is InputEventMouseButton and event.pressed \
				and event.button_index == MOUSE_BUTTON_LEFT \
				and (memberInput == null or not memberInput.isAiming()):
			# Empty ground hands inspection back to whoever is acting, so a stray click never
			# leaves the player's own unit unexplained mid-turn.
			var picked := _unitUnderPointer(event.position)
			_selectUnit(picked if picked != -1 else _actingMemberID())
	if event is InputEventMouseMotion and adapter != null and adapter.boardView != null:
		if memberInput != null and memberInput.isAiming():
			adapter.boardView.clearHover()
		else:
			_refreshPointerTarget(event.position)
			var hoveredCell := _cellAtPoint(event.position)
			if hoveredCell.x >= 0:
				adapter.boardView.showHover(hoveredCell)
			else:
				adapter.boardView.clearHover()
	if event is InputEventKey and event.pressed and not event.echo:
		match event.keycode:
			KEY_Q:
				battleCamera.orbitDetent(-1)
				get_viewport().set_input_as_handled()
				return
			KEY_E:
				battleCamera.orbitDetent(1)
				get_viewport().set_input_as_handled()
				return
			KEY_TAB:
				if _cycleReadyUnit(-1 if event.shift_pressed else 1):
					get_viewport().set_input_as_handled()
					return
	if lifecycle == Lifecycle.BATTLE:
		_handleMemberInput(event)


## Input reaches a member turn only while one is open, which is only ever true for the player's
## active side -- `_onHudMemberSelected` is the single place a turn is opened and it refuses every
## other side. There is no second condition to re-check here.
func _handleMemberInput(event: InputEvent) -> void:
	if memberInput == null or memberTurn == null or memberTurn.isFinished():
		return
	if _commandsLocked():
		return

	if event is InputEventKey and event.pressed and not event.echo:
		match event.keycode:
			KEY_1:
				_onSideActionRequested("magic")
				get_viewport().set_input_as_handled()
				return
			KEY_2:
				_onSideActionRequested("item")
				get_viewport().set_input_as_handled()
				return
			KEY_3:
				_onSideActionRequested("status")
				get_viewport().set_input_as_handled()
				return
			KEY_4:
				_onSideActionRequested("wait")
				get_viewport().set_input_as_handled()
				return
			KEY_ENTER, KEY_KP_ENTER, KEY_SPACE:
				if memberInput.isAiming():
					memberInput.confirm()
					get_viewport().set_input_as_handled()
					return
			KEY_ESCAPE:
				if memberInput.cancel():
					get_viewport().set_input_as_handled()
				return
		var direction := _directionFor(event.keycode)
		if direction != Vector2.ZERO:
			if not memberInput.isAiming() and memberTurn.canMove():
				memberInput.chooseCommand(HexBattleMemberInputScript.MOVE_COMMAND)
			if memberInput.aimDirection(direction, _projectCell):
				get_viewport().set_input_as_handled()
			return

	if not memberInput.isAiming():
		return

	if event is InputEventMouseMotion:
		var hovered := _cellAtPoint(event.position)
		if hovered.x >= 0:
			memberInput.aimAt(hovered)
		return

	if event is InputEventMouseButton and event.pressed \
			and event.button_index == MOUSE_BUTTON_LEFT:
		var clicked := _cellAtPoint(event.position)
		if clicked.x < 0:
			return
		# Aimed and confirmed in one gesture, so a click cannot commit a cell other than the one
		# under the pointer -- the cursor is moved there first and the confirm reads the cursor.
		memberInput.aimAt(clicked)
		memberInput.confirm()
		get_viewport().set_input_as_handled()


## Context resolves a left click once: ready friendly selects/switches, legal empty ground moves,
## a legal enemy is attacked, and every other unit click is inspection only.
func _handleSideClick(point: Vector2) -> bool:
	if sim == null or playback == null or _commandsLocked() or sim.state.activeSideID == -1:
		return false
	if _sideController(int(sim.state.activeSideID)) != "player":
		return false
	if memberInput != null and memberInput.isAiming():
		return false
	var picked := _pointerUnit(point)
	if picked != -1:
		var pickedMonster = sim.state.getMonster(picked)
		if pickedMonster != null and pickedMonster.team == sim.state.activeSideID:
			if sim.eligibleSideUnitIDs().has(picked):
				_onHudMemberSelected(picked)
			else:
				_selectUnit(picked)
			return true
	if memberTurn == null or memberInput == null:
		if picked != -1:
			_selectUnit(picked)
			return true
		return false
	var cell := _cellAtPoint(point)
	if cell.x < 0:
		return false
	if picked != -1:
		if sim.combatResolver.canBasicAttackPositionFrom(
				memberTurn.monsterID(), sim.state.getMonsterPosition(memberTurn.monsterID()), cell):
			memberInput.chooseCommand(HexBattleMemberInputScript.ATTACK_COMMAND)
			memberInput.aimAt(cell)
			memberInput.confirm()
		else:
			_selectUnit(picked)
		return true
	if memberTurn.canMove() and memberTurn.reachableCells().has(cell):
		memberInput.chooseCommand(HexBattleMemberInputScript.MOVE_COMMAND)
		memberInput.aimAt(cell)
		memberInput.confirm()
		return true
	return true


## The unit a left click or pointer means. A model stands taller than its tile, so its body covers
## the cell behind it -- usually the very cell a unit walks to before attacking it. When the cell
## under the pointer is a legal move, that cell wins over a body the pointer merely overlaps,
## unless that body is an enemy the selected unit can hit from where it stands (rule 7's sword).
func _pointerUnit(point: Vector2) -> int:
	var picked := _unitUnderPointer(point)
	if picked == -1 or memberTurn == null or not memberTurn.canMove():
		return picked
	var cell := _cellAtPoint(point)
	if cell.x < 0 or adapter.displayedPosition(picked) == cell:
		return picked
	if not memberTurn.reachableCells().has(cell):
		return picked
	if _canAttackFromHere(picked):
		return picked
	return -1


func _canAttackFromHere(targetID: int) -> bool:
	if memberTurn == null or sim == null:
		return false
	var target = sim.state.getMonster(targetID)
	if target == null or target.team == sim.state.activeSideID:
		return false
	return sim.combatResolver.canBasicAttackPositionFrom(memberTurn.monsterID(),
		sim.state.getMonsterPosition(memberTurn.monsterID()), sim.state.getMonsterPosition(targetID))


## Rules 7-8 outside an aim: pointing at an enemy shows its preview box, and the sword only when
## the selected unit can hit it from where it stands. The same resolution a click uses, so the cue
## never promises an attack the click would not make.
func _refreshPointerTarget(point: Vector2) -> void:
	if sideCues == null or memberTurn == null or memberInput == null or _commandsLocked():
		_clearPointerTarget()
		return
	var picked := _pointerUnit(point)
	var monster = sim.state.getMonster(picked) if picked != -1 else null
	if monster == null or monster.team == sim.state.activeSideID or not memberTurn.canAct():
		_clearPointerTarget()
		return
	if picked == _pointerTargetID:
		return
	_pointerTargetID = picked
	# The arc floats over the selected unit, which after a move usually stands beside its target;
	# it steps aside exactly as it does for an aim, or it covers the sword it is promising.
	sideCues.setAiming(true)
	var cell: Vector2i = sim.state.getMonsterPosition(picked)
	_showTargetCues({
		"kind": HexBattleMemberInputScript.ATTACK_COMMAND,
		"target_id": picked,
		"legal": _canAttackFromHere(picked),
		"forecast": adapter.forecastAttack(memberTurn.monsterID(), cell),
	})


func _clearPointerTarget() -> void:
	if _pointerTargetID == -1:
		return
	_pointerTargetID = -1
	if adapter != null:
		adapter.setTargetedUnit(-1)
	if sideCues != null:
		sideCues.clearForecasts()
		sideCues.setAiming(false)


func _cancelPlayerSelection() -> void:
	if memberTurn == null:
		return
	var monsterID := memberTurn.monsterID()
	memberTurn.cancel()
	memberTurn = null
	memberInput = null
	playback.release(HexBattlePlayback.OWNER_PLAYER, monsterID)
	adapter.setSelectedUnit(-1)
	adapter.setTargetedUnit(-1)
	_pointerTargetID = -1
	if hud != null:
		hud.hideCommands()
		hud.showAim({})
	if sideCues != null:
		sideCues.hideActionArc()
		sideCues.clearForecasts()


func _cycleReadyUnit(direction: int) -> bool:
	if sim == null or sim.state.activeSideID == -1 \
			or _sideController(int(sim.state.activeSideID)) != "player":
		return false
	var ready: Array[int] = sim.eligibleSideUnitIDs()
	if ready.is_empty():
		return false
	ready.sort()
	var current := _actingMemberID()
	var index := ready.find(current)
	index = 0 if index < 0 else posmod(index + direction, ready.size())
	_onHudMemberSelected(ready[index])
	return memberTurn != null and memberTurn.monsterID() == ready[index]


func _sideController(sideID: int) -> String:
	var controllers: Array[String] = []
	for partyIDValue in sim.state.teamPartyIDs.get(sideID, []):
		var party: BattleParty = sim.state.parties.get(int(partyIDValue))
		if party != null and not controllers.has(str(party.controller)):
			controllers.append(str(party.controller))
	if controllers.has("player"):
		return "player"
	return controllers[0] if not controllers.is_empty() else ""


func _syncSpentCues() -> void:
	if adapter == null or sim == null:
		return
	for idValue in adapter.shownModelIDs():
		var monsterID := int(idValue)
		adapter.setUnitSpent(monsterID, sim.state.spentUnitIDs.has(monsterID))


## Screen axes, y growing downward, which is what `HexBattleCursor` resolves against. Arrows and
## the WASD cluster produce the same four vectors; the diagonals reach the remaining two
## neighbours directly, and four-way input reaches them through the nearer cardinal.
func _directionFor(keycode: Key) -> Vector2:
	match keycode:
		KEY_UP, KEY_W: return Vector2(0.0, -1.0)
		KEY_DOWN, KEY_S: return Vector2(0.0, 1.0)
		KEY_LEFT, KEY_A: return Vector2(-1.0, 0.0)
		KEY_RIGHT, KEY_D: return Vector2(1.0, 0.0)
	return Vector2.ZERO


## The live camera's projection of a cell centre, handed to the cursor so a direction is resolved
## against the board as it currently sits on screen.
func _projectCell(cell: Vector2i) -> Vector2:
	if stage == null or adapter == null:
		return Vector2.ZERO
	return stage.projectWorldToScreen(adapter.worldPositionOf(cell))


## The unit drawn on the cell under a viewport point, or -1.
##
## Displayed positions, not authoritative ones: the pointer is over what the screen shows, and a
## unit the simulation has already moved or removed is still standing where it is drawn.
func _unitAtPoint(point: Vector2) -> int:
	if adapter == null:
		return -1
	var cell := _cellAtPoint(point)
	if cell.x < 0:
		return -1
	for value in adapter.shownModelIDs():
		var monsterID := int(value)
		if adapter.displayedPosition(monsterID) == cell \
				and adapter.displayedRemovalReason(monsterID).is_empty():
			return monsterID
	return -1


## The unit under a viewport point: its cell first, then its drawn body.
##
## The cell alone is not enough. A model stands taller than its own tile, so a pointer on a unit's
## head is over the cell BEHIND it, and pointing at a unit would fail exactly where the player is
## most obviously pointing at one.
func _unitUnderPointer(point: Vector2) -> int:
	var byCell := _unitAtPoint(point)
	if byCell != -1:
		return byCell
	if adapter == null or stage == null:
		return -1
	var byBody := adapter.unitAtScreenPoint(point, stage.projectWorldToScreen)
	if byBody != -1 and adapter.displayedRemovalReason(byBody).is_empty():
		return byBody
	return -1


## Hover: the HUD reads the unit out, the board draws its outline. One owner each, one call.
func _hoverUnit(monsterID: int) -> void:
	if hud != null:
		hud.setHover(monsterID)
	if adapter != null:
		adapter.setHoveredUnit(monsterID)


## Selection: the readout commits to the unit and the board rings it. -1 clears both.
func _selectUnit(monsterID: int) -> void:
	if hud == null or adapter == null:
		return
	adapter.setSelectedUnit(hud.commitInspection(monsterID))


func _actingMemberID() -> int:
	return memberTurn.monsterID() if memberTurn != null and not memberTurn.isFinished() else -1


## Which cell a viewport point is over, or (-1, -1).
##
## Nearest projected centre, then confirmed against that cell's own projected outline, so a point
## in the gap outside the board picks nothing rather than the least-wrong cell. Deliberately the
## same projection the keyboard resolves through: a hover and an arrow key that land on the same
## cell agree because they are reading the same geometry, not two approximations of it.
func _cellAtPoint(point: Vector2) -> Vector2i:
	if adapter == null or stage == null or map == null:
		return Vector2i(-1, -1)
	var best := Vector2i(-1, -1)
	var bestDistance := INF
	for cell: Vector2i in map.validCells():
		var projected := _projectCell(cell)
		if projected.x < 0.0:
			continue
		var distance := projected.distance_squared_to(point)
		if distance < bestDistance:
			bestDistance = distance
			best = cell
	if best.x < 0:
		return best
	var outline := PackedVector2Array()
	for vertex: Vector3 in adapter.layout.cellPolygon(best):
		outline.append(stage.projectWorldToScreen(vertex))
	if not Geometry2D.is_point_in_polygon(point, outline):
		return Vector2i(-1, -1)
	return best


## Every status line goes through here, so a missing-terrain notice stays on screen under whatever
## the battle is saying rather than being replaced by the first "Your turn."
func _setStatus(text: String) -> void:
	if hud == null:
		return
	if _terrainNotice.is_empty():
		hud.setStatus(text)
	elif text.is_empty():
		hud.setStatus(_terrainNotice)
	else:
		hud.setStatus("%s\n%s" % [text, _terrainNotice])


## The notice shown while the map's terrain could not be drawn, or empty.
func terrainNotice() -> String:
	return _terrainNotice


# --- session controls ---------------------------------------------------------

## Pause, speed, skip, restart and setup, whether they came from a key or a session row. One
## place, so a key and its row cannot disagree about what they do.
func _onSessionCommand(commandID: String) -> void:
	match commandID:
		HexGraphicsPanelScript.PAUSE:
			togglePause()
		HexGraphicsPanelScript.SPEED:
			cycleSpeed()
		HexGraphicsPanelScript.SKIP:
			skipAnimation()
		HexGraphicsPanelScript.RESTART:
			restartBattle()
		HexGraphicsPanelScript.SETUP:
			returnToSetup()


## P pauses, F changes speed, Enter or Space skips when no member turn is open (inside a member
## turn they confirm, as they always have), R restarts a finished battle.
func _handleSessionKey(event: InputEventKey) -> bool:
	match event.keycode:
		KEY_P:
			return togglePause()
		KEY_F:
			if lifecycle == Lifecycle.BATTLE or lifecycle == Lifecycle.ENDING:
				cycleSpeed()
				return true
		KEY_ENTER, KEY_KP_ENTER, KEY_SPACE:
			if memberInput == null and _canSkip():
				skipAnimation()
				return true
		KEY_R:
			if lifecycle == Lifecycle.COMPLETE:
				restartBattle()
				return true
	return false


## Returns whether a pause or resume happened. Only while the battle or its final playback runs.
func togglePause() -> bool:
	if playback == null or not (lifecycle == Lifecycle.BATTLE or lifecycle == Lifecycle.ENDING):
		return false
	playback.setPaused(not playback.isPaused())
	if hud != null:
		hud.setInputLocked(_commandsLocked())
	return true


func cycleSpeed() -> float:
	if playback == null:
		return _speedPreference
	_speedPreference = playback.cycleSpeed()
	return _speedPreference


## Skips the action playing now: a cast jumps to its settle tail, then the queue finalizes it.
## Allowed while paused; the queue does not start the next action until resumed.
func skipAnimation() -> void:
	if adapter != null:
		adapter.skipCurrentAnimation()


func _canSkip() -> bool:
	return adapter != null and adapter.isAnimationBusy() and \
		(lifecycle == Lifecycle.BATTLE or lifecycle == Lifecycle.ENDING)


## Whether commands are refused right now. Paused playback admits no command from any source: no
## member selection, no action choice, no aim, no End turn. The camera and inspection still work.
func _commandsLocked() -> bool:
	return playback != null and playback.isPaused()


func _sessionState() -> Dictionary:
	if sim == null or playback == null:
		return {}
	var phase := "battle"
	if lifecycle == Lifecycle.ENDING:
		phase = "ending"
	elif lifecycle == Lifecycle.COMPLETE:
		phase = "complete"
	return {
		"phase": phase,
		"paused": playback.isPaused(),
		"speed": playback.speed(),
		"can_skip": _canSkip(),
		"aiming": memberInput != null and memberInput.isAiming(),
		"result": resultText(sim.state) if phase == "complete" else "",
		"rounds": int(sim.state.roundCount),
	}


## The same scenario and seed again, from the start. Scenario and seed are what make a battle
## reproducible, so they are the whole of what a restart carries (with the chosen speed).
func restartBattle() -> Dictionary:
	var path := _scenarioPath
	var seedValue := _seedValue
	if path.is_empty():
		return {"ok": false, "error": "no_battle"}
	var started := startBattle(path, seedValue)
	if not bool(started.get("ok", false)):
		_enterSetup()
		setupUI.showError(startErrorText(started))
	return started


# --- completion -------------------------------------------------------------

func _onPlaybackDrained() -> void:
	# The drain signal does not itself start anything; it only lets the timer's next tick find
	# the gate open. One starter, and it is `_advance`.
	if lifecycle == Lifecycle.BATTLE:
		_checkFinished()


func _checkFinished() -> void:
	if sim != null and sim.state.battleOutcome != -1:
		_beginEnding()


## The simulator has decided the battle. Nothing may start from here on, but the screen has not
## necessarily shown the blow that decided it, so the result is not announced yet: `_advance`
## completes the battle once playback has drained.
##
## A player member turn can still be open (the finishing attack left its move unspent). It is
## abandoned, not finished: finishing would write a turn into a battle that is over.
func _beginEnding() -> void:
	if lifecycle != Lifecycle.BATTLE:
		return
	lifecycle = Lifecycle.ENDING
	_deliberation = null
	_deliberatingMemberID = -1
	if memberTurn != null:
		memberTurn.cancel()
		memberTurn = null
	memberInput = null
	if playback != null:
		playback.finish()
	if hud != null:
		hud.clearParty()
		hud.showAim({})
	if sideCues != null:
		sideCues.hideActionArc()
		sideCues.clearForecasts()
		sideCues.hideTurnBanner()
	if adapter != null:
		adapter.setTargetedUnit(-1)
	_setStatus("The battle is decided.")


func _completeBattle() -> void:
	if lifecycle != Lifecycle.ENDING:
		return
	lifecycle = Lifecycle.COMPLETE
	_advanceTimer.stop()
	if hud != null:
		_setStatus("%s." % resultText(sim.state))


## "Draw" for the draw team, otherwise the winning team, and whose side that is. A draw is team 0
## (`BattleSimulator.DRAW_TEAM`); printing "Team 0 wins" for it was a false result.
static func resultText(state: BattleState) -> String:
	if state == null or state.battleOutcome == -1:
		return ""
	var outcome := int(state.battleOutcome)
	if outcome == BattleSimulatorScript.DRAW_TEAM:
		return "Draw"
	var side := ""
	for value in state.parties:
		var party = state.parties[value]
		if int(party.teamID) == outcome:
			side = "you" if str(party.controller) == "player" else "CPU"
			break
	return "Team %d wins (%s)" % [outcome, side] if not side.is_empty() else "Team %d wins" % outcome


func _exit_tree() -> void:
	teardownBattle()
