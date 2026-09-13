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

enum Lifecycle { SETUP, BATTLE, COMPLETE }

## How often the loop re-checks whether it may advance. A timer rather than `_process` so a
## battle that is waiting on playback is not re-evaluated sixty times a second for no reason.
const ADVANCE_INTERVAL_SECONDS := 0.05

## Frame budget for CPU deliberation, in milliseconds. Deliberation is resumable by design
## (HXB-8), so it is stepped rather than run to completion, and the battle stays responsive while
## a CPU party thinks.
const DELIBERATION_BUDGET_MSEC := 4.0

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
var _deliberation: CommandDeliberation = null
var _deliberatingMemberID := -1
var _scenarioPath := ""


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


func returnToSetup() -> void:
	teardownBattle()
	_enterSetup()


func _onBattleRequested(scenarioPath: String, seedValue: int) -> void:
	var started := startBattle(scenarioPath, seedValue)
	if not started.get("ok", false):
		setupUI.setVisibleUI(true)


## Builds a battle from a scenario. Returns a result rather than reporting through a status line,
## so the scene probe can assert WHY a start was refused.
func startBattle(scenarioPath: String, seedValue: int) -> Dictionary:
	teardownBattle()

	var loaded := BattleScenarioFactoryScript.loadFromPath(scenarioPath)
	if not loaded["success"]:
		return {"ok": false, "error": str(loaded.get("error", "scenario_unreadable"))}
	var scenario: BattleScenario = loaded["scenario"]

	var config: BattleSetupConfig = BattleSetupConfigScript.new()
	config.scenarioPath = scenarioPath
	config.seed = seedValue
	var validation := config.validate()
	if not validation.success:
		return {"ok": false, "error": "invalid_setup"}

	var stateResult := BattleSetupFactoryScript.createHexState(config)
	if not stateResult["success"]:
		return {"ok": false, "error": str(stateResult.get("error", "state_failed"))}

	_scenarioPath = scenarioPath
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
	hud.bind(sim, adapter)

	playback = HexBattlePlaybackScript.new(adapter)
	cursor = HexBattleCursorScript.new()

	setupUI.setVisibleUI(false)
	lifecycle = Lifecycle.BATTLE
	sim.startBattle()
	_advanceTimer.start()
	return {"ok": true, "scenario": scenarioPath}


# --- the loop ---------------------------------------------------------------

## The only place a party activation or a member turn is started.
func _advance() -> void:
	if lifecycle != Lifecycle.BATTLE or sim == null or playback == null:
		return
	if not playback.canAdvance():
		return
	if sim.state.battleOutcome != -1:
		_finishBattle()
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
			_finishBattle()
		return
	_onActivationOpened(int(opened.get("party_id", -1)))


func _onActivationOpened(partyID: int) -> void:
	var party = sim.state.parties.get(partyID)
	if party == null:
		return
	if hud != null:
		hud.showParty(sim, partyID, -1, party.controller == "player")
		hud.setStatus(
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
		hud.setActor(monsterID)
	var deliberation := sim.beginTurnDeliberation(monsterID)
	if deliberation == null:
		# Nothing this member can do. Close its turn exactly as the simulator's contract requires
		# of a caller that gets nothing back.
		sim.finishTurn(monsterID, "cpu")
		playback.release(HexBattlePlayback.OWNER_CPU, monsterID)
		return
	_deliberation = deliberation
	_deliberatingMemberID = monsterID


## Deliberation is stepped under a frame budget rather than run to completion, which is what
## HXB-8 made it resumable for.
func _process(_delta: float) -> void:
	_refreshHud()
	if _deliberation == null or sim == null:
		return
	if not _deliberation.step(DELIBERATION_BUDGET_MSEC):
		return
	var monsterID := _deliberatingMemberID
	var finished := _deliberation
	_deliberation = null
	_deliberatingMemberID = -1
	sim.applyDeliberatedTurn(monsterID, finished)
	sim.finishTurn(monsterID, "cpu")
	playback.release(HexBattlePlayback.OWNER_CPU, monsterID)
	_checkFinished()


# --- player input -----------------------------------------------------------

## The player picked a member. This is where a player member turn is opened, and the only place.
func _onHudMemberSelected(monsterID: int) -> void:
	if lifecycle != Lifecycle.BATTLE or sim == null or playback == null:
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
		hud.setActor(monsterID)
	memberInput.begin()


func _onMenuChanged(model: Dictionary) -> void:
	if hud != null:
		hud.showCommands(model)


func _onMenuDismissed() -> void:
	if hud != null:
		hud.hideCommands()


func _onMemberStatus(text: String) -> void:
	if hud != null:
		hud.setStatus(text)


func _onAimChanged(model: Dictionary) -> void:
	if hud != null:
		hud.showAim(model)


func _onHudCommandChosen(commandID: String) -> void:
	if memberInput != null:
		memberInput.chooseCommand(commandID)


func _onHudCommandCancelled() -> void:
	if memberInput != null:
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
		hud.setHover(-1)
	hud.refresh()


## Inspection first, then camera, then the member turn. Both devices reach the same cursor -- see
## `HexBattleMemberInput` for why neither locks the other out.
##
## INSPECTION NEVER CONSUMES AN EVENT. Hover and click only tell the HUD which unit to read out, and
## the same event then continues to the aim, so pointing at a unit while aiming both aims at it and
## shows it. A click reaches inspection only when nobody is aiming, where a board click had no
## meaning before. GUI controls consume their own clicks before this runs, so a click on a panel
## row never inspects the unit behind it.
func _unhandled_input(event: InputEvent) -> void:
	if lifecycle != Lifecycle.BATTLE or battleCamera == null:
		return
	if hud != null:
		if event is InputEventMouseMotion:
			hud.setHover(_unitAtPoint(event.position))
		elif event is InputEventMouseButton and event.pressed \
				and event.button_index == MOUSE_BUTTON_LEFT \
				and (memberInput == null or not memberInput.isAiming()):
			hud.commitInspection(_unitAtPoint(event.position))
	if event is InputEventMouseButton and event.pressed:
		match event.button_index:
			MOUSE_BUTTON_WHEEL_UP:
				battleCamera.zoom(-1.0)
				get_viewport().set_input_as_handled()
				return
			MOUSE_BUTTON_WHEEL_DOWN:
				battleCamera.zoom(1.0)
				get_viewport().set_input_as_handled()
				return
	elif event is InputEventKey and event.pressed and not event.echo:
		match event.keycode:
			KEY_Q:
				battleCamera.orbitDetent(-1)
				get_viewport().set_input_as_handled()
				return
			KEY_E:
				battleCamera.orbitDetent(1)
				get_viewport().set_input_as_handled()
				return
	_handleMemberInput(event)


## Input reaches a member turn only while one is open, which is only ever true for the player's
## own party -- `_onHudMemberSelected` is the single place a turn is opened and it refuses any
## other party. There is no second condition to re-check here.
func _handleMemberInput(event: InputEvent) -> void:
	if memberInput == null or memberTurn == null or memberTurn.isFinished():
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


# --- completion -------------------------------------------------------------

func _onPlaybackDrained() -> void:
	# The drain signal does not itself start anything; it only lets the timer's next tick find
	# the gate open. One starter, and it is `_advance`.
	if lifecycle == Lifecycle.BATTLE:
		_checkFinished()


func _checkFinished() -> void:
	if sim != null and sim.state.battleOutcome != -1:
		_finishBattle()


func _finishBattle() -> void:
	if lifecycle == Lifecycle.COMPLETE:
		return
	lifecycle = Lifecycle.COMPLETE
	_advanceTimer.stop()
	if playback != null:
		playback.finish()
	if hud != null:
		hud.clearParty()
		hud.setStatus("Battle complete. Team %d wins." % int(sim.state.battleOutcome))


func _exit_tree() -> void:
	teardownBattle()
