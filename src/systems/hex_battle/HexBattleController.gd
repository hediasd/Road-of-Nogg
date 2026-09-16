## The hex battle's composition root: setup, the party-activation loop, and return to setup.
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
##     startNextPartyActivation()      -- the simulation orders parties and opens one
##       -> player party:  wait for the player to pick a member, act, repeat
##       -> CPU party:     deliberate a member, apply, repeat
##     endPartyActivation()            -- when no member is eligible, or the player says so
##
## ONE SCHEDULING OWNER, and it is `HexBattlePlayback`. Every path that could start something --
## the frame loop, the playback-drained signal, a HUD click, CPU deliberation finishing -- asks
## the gate first and claims it before acting. That is what stops the two failures this item
## names: a second turn opening on top of an open one, and input reaching a party that has already
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

## Fallback frame budget when the worker pool refuses a task. Normal interactive deliberation runs
## away from the presentation thread; keeping the old resumable path as a refusal fallback avoids
## stranding an already-selected member without making it the ordinary scheduler again.
const DELIBERATION_BUDGET_MSEC := 4.0
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

var lifecycle: Lifecycle = Lifecycle.SETUP
var map: BattleMapDefinition

var _advanceTimer: Timer
var _boardRoot: Node3D
## Where the current right press started, or (-1, -1). A release within RIGHT_TAP_SLOP of it is a
## click, which cancels the command menu; anything further was a camera pan.
var _rightPressPosition := Vector2(-1.0, -1.0)
var _deliberation: CommandDeliberation = null
var _deliberatingMemberID := -1
## CPU planning is pure and owns no scene nodes, so it may run on the low-priority worker pool while
## the main thread renders. Only `_process` consumes the completed result and mutates simulation.
var _deliberationTaskID := -1
var _retiredDeliberationTaskIDs: Array[int] = []
var _scenarioPath := ""
var _seedValue := 0
## The presentation speed the player last chose. Carried into a restart, which is the same battle
## watched again; pause is not carried, because a restarted battle that opens frozen reads as hung.
var _speedPreference := HexBattlePlaybackScript.DEFAULT_SPEED
## Why the authored terrain is not drawn, for the status line. Empty when it is, or when the map
## declares no scene at all.
var _terrainNotice := ""


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
	_retireDeliberationTask()
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

## The only place a party activation or a member turn is started.
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

	# An activation is open: serve whichever kind of party it belongs to.
	if sim.state.activePartyID != -1:
		_serveOpenActivation()
		return

	# Nothing open, and the screen has caught up: open the next party. Waiting for a full drain
	# at the PARTY boundary specifically, so an activation does not begin over the tail of the
	# previous one's animations.
	if not playback.isDrained():
		return
	var opened := sim.startNextPartyActivation()
	if not bool(opened.get("success", false)):
		if str(opened.get("reason", "")) == "battle_ended":
			_beginEnding()
		return
	_onActivationOpened(int(opened.get("party_id", -1)))


func _onActivationOpened(partyID: int) -> void:
	var party = sim.state.parties.get(partyID)
	if party == null:
		return
	if hud != null:
		hud.showParty(sim, partyID, -1, party.controller == "player")
		_setStatus(
			"Your party is up." if party.controller == "player" else "The enemy is moving."
		)


func _serveOpenActivation() -> void:
	var partyID := int(sim.state.activePartyID)
	var party = sim.state.parties.get(partyID)
	if party == null:
		return
	var eligible := sim.eligiblePartyMemberIDs()
	if eligible.is_empty():
		sim.endPartyActivation("system")
		if hud != null:
			hud.clearParty()
		return
	if party.controller == "player":
		# The player's own turn is opened by their click on the panel, not by this loop -- the
		# gate is claimed there. Nothing to do until they pick.
		return
	_beginCpuMember(int(eligible[0]))


## Opens a CPU member's turn and starts its deliberation. The gate is claimed for the whole of it,
## so nothing else can begin a turn while this one thinks.
func _beginCpuMember(monsterID: int) -> void:
	if not playback.claim(HexBattlePlayback.OWNER_CPU, monsterID):
		return
	var selected := sim.selectPartyMember(monsterID, "cpu")
	if not bool(selected.get("success", false)):
		playback.release(HexBattlePlayback.OWNER_CPU, monsterID)
		return
	if hud != null:
		hud.showParty(sim, int(sim.state.activePartyID), monsterID, false)
		_selectUnit(monsterID)
	var deliberation := sim.beginTurnDeliberation(monsterID)
	if deliberation == null:
		# Nothing this member can do. Close its turn exactly as the simulator's contract requires
		# of a caller that gets nothing back.
		sim.finishTurn(monsterID, "cpu")
		playback.release(HexBattlePlayback.OWNER_CPU, monsterID)
		return
	_deliberation = deliberation
	_deliberatingMemberID = monsterID
	# Low priority is deliberate: rendering is the foreground workload. The task only reads the
	# headless battle model and writes its private deliberation cursor/result.
	_deliberationTaskID = WorkerThreadPool.add_task(
		Callable(deliberation, "run"), false, "Hex battle CPU deliberation")


## Polling a worker is constant-time. The finished proposal is applied here, on the main thread,
## which keeps event order, replay history and every scene-tree mutation exactly where they were.
## A paused battle may finish thinking in the background, but never applies that result until
## resumed. Retired tasks belong to torn-down battles and are only reaped, never observed.
func _process(_delta: float) -> void:
	_collectRetiredDeliberationTasks()
	_refreshHud()
	if _deliberation == null or sim == null:
		return
	if playback == null or playback.isPaused():
		return
	if _deliberationTaskID >= 0:
		if not WorkerThreadPool.is_task_completed(_deliberationTaskID):
			return
		var taskError := WorkerThreadPool.wait_for_task_completion(_deliberationTaskID)
		_deliberationTaskID = -1
		if taskError != OK or not _deliberation.isFinished():
			push_error("CPU deliberation worker failed; completing this turn with frame slices.")
			if not _deliberation.step(DELIBERATION_BUDGET_MSEC):
				return
	elif not _deliberation.step(DELIBERATION_BUDGET_MSEC):
		# Worker-pool submission can return an invalid id. The old deterministic scheduler is a
		# safe fallback for that exceptional path, not the normal rendering path.
		return
	var monsterID := _deliberatingMemberID
	var finished := _deliberation
	_deliberation = null
	_deliberatingMemberID = -1
	sim.applyDeliberatedTurn(monsterID, finished)
	sim.finishTurn(monsterID, "cpu")
	playback.release(HexBattlePlayback.OWNER_CPU, monsterID)
	_checkFinished()


## A task from a battle being torn down retains its read-only state until it naturally completes.
## Dropping the current IDs prevents its result from ever reaching a replacement battle. Waiting
## here would reintroduce the exact UI freeze this worker boundary exists to remove.
func _retireDeliberationTask() -> void:
	if _deliberationTaskID < 0:
		return
	_retiredDeliberationTaskIDs.append(_deliberationTaskID)
	_deliberationTaskID = -1


func _collectRetiredDeliberationTasks() -> void:
	for index in range(_retiredDeliberationTaskIDs.size() - 1, -1, -1):
		var taskID := _retiredDeliberationTaskIDs[index]
		if not WorkerThreadPool.is_task_completed(taskID):
			continue
		WorkerThreadPool.wait_for_task_completion(taskID)
		_retiredDeliberationTaskIDs.remove_at(index)


# --- player input -----------------------------------------------------------

## The player picked a member. This is where a player member turn is opened, and the only place.
func _onHudMemberSelected(monsterID: int) -> void:
	if lifecycle != Lifecycle.BATTLE or sim == null or playback == null:
		return
	if _commandsLocked():
		return
	if sim.state.activePartyID == -1:
		return
	var party = sim.state.parties.get(int(sim.state.activePartyID))
	if party == null or party.controller != "player":
		return
	# Refused rather than queued: a click arriving while CPU deliberation holds the schedule is
	# input into a party that is not currently the player's to command.
	if not playback.claim(HexBattlePlayback.OWNER_PLAYER, monsterID):
		return
	var selected := sim.selectPartyMember(monsterID, "player")
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
	if hud != null:
		hud.showParty(sim, int(sim.state.activePartyID), monsterID, true)
		# The member whose turn it is becomes the inspected unit, so the readout and STATUS answer
		# for them until the player points at someone else.
		_selectUnit(monsterID)
	memberInput.begin()


func _onMenuChanged(model: Dictionary) -> void:
	if hud != null:
		hud.showCommands(model)


func _onMenuDismissed() -> void:
	if hud != null:
		hud.hideCommands()


func _onMemberStatus(text: String) -> void:
	_setStatus(text)


func _onAimChanged(model: Dictionary) -> void:
	if hud != null:
		hud.showAim(model)


func _onHudCommandChosen(commandID: String) -> void:
	if memberInput != null and not _commandsLocked():
		memberInput.chooseCommand(commandID)


func _onHudCommandCancelled() -> void:
	if memberInput != null and not _commandsLocked():
		memberInput.cancel()


func _onMemberTurnFinished(monsterID: int) -> void:
	memberTurn = null
	memberInput = null
	if hud != null:
		hud.hideCommands()
		hud.showAim({})
	playback.release(HexBattlePlayback.OWNER_PLAYER, monsterID)
	if hud != null and sim != null and sim.state.activePartyID != -1:
		hud.showParty(sim, int(sim.state.activePartyID), -1, true)
	_checkFinished()


## End Party converts every remaining eligible member's turn into a wait, in the simulator's own
## deterministic order. The controller does not iterate members itself -- that order is HXB-6's.
func _onHudEndParty() -> void:
	if lifecycle != Lifecycle.BATTLE or sim == null or playback == null:
		return
	if _commandsLocked():
		return
	if not playback.isIdle():
		return
	if sim.state.activePartyID == -1:
		return
	sim.endPartyActivation("player")
	if hud != null:
		hud.clearParty()
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
	# A right click that never became a pan still cancels the command menu; a right drag pans.
	if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_RIGHT:
		if event.pressed:
			_rightPressPosition = event.position
		elif _rightPressPosition.x >= 0.0:
			var tapped: bool = event.position.distance_to(_rightPressPosition) <= RIGHT_TAP_SLOP
			_rightPressPosition = Vector2(-1.0, -1.0)
			if tapped and hud != null and hud.commandMenu.visible \
					and (memberInput == null or not memberInput.isAiming()):
				battleCamera.cancelDrag()
				hud.commandMenu.cancel()
				get_viewport().set_input_as_handled()
				return
	if battleCamera.handleInput(event, get_viewport().get_visible_rect().size.y):
		_hoverUnit(-1)
		if adapter != null and adapter.boardView != null:
			adapter.boardView.clearHover()
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
	if lifecycle == Lifecycle.BATTLE:
		_handleMemberInput(event)


## Input reaches a member turn only while one is open, which is only ever true for the player's
## own party -- `_onHudMemberSelected` is the single place a turn is opened and it refuses any
## other party. There is no second condition to re-check here.
func _handleMemberInput(event: InputEvent) -> void:
	if memberInput == null or memberTurn == null or memberTurn.isFinished():
		return
	if _commandsLocked():
		return

	# At the menu the keyboard drives the command rail: arrows move its focus, Enter carries out
	# the focused plate, Escape closes an open spell window. Only while aiming do the same keys
	# step the board cursor and confirm.
	if event is InputEventKey and event.pressed and not memberInput.isAiming():
		if hud != null and hud.handleKey(event):
			get_viewport().set_input_as_handled()
		return

	if event is InputEventKey and event.pressed and not event.echo:
		match event.keycode:
			KEY_ENTER, KEY_KP_ENTER, KEY_SPACE:
				memberInput.confirm()
				get_viewport().set_input_as_handled()
				return
			KEY_ESCAPE:
				if memberInput.cancel():
					get_viewport().set_input_as_handled()
				return
		var direction := _directionFor(event.keycode)
		if direction != Vector2.ZERO:
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
## the battle is saying rather than being replaced by the first "Your party is up."
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
## member selection, no menu choice, no aim, no End Party. The camera and inspection still work.
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
