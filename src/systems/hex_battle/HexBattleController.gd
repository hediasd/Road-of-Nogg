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
const HexBattleCursorScript = preload("res://src/presentation/battle/HexBattleCursor.gd")
const HexBattleHudScript = preload("res://src/presentation/battle/HexBattleHud.gd")
const HexBattleSetupUIScript = preload("res://src/presentation/battle/HexBattleSetupUI.gd")
const HexBattlePlaybackScript = preload("res://src/presentation/battle/HexBattlePlayback.gd")
const HexBattleMemberTurnScript = preload("res://src/systems/hex_battle/HexBattleMemberTurn.gd")
const BattleSimulatorScript = preload("res://src/battle_sim/BattleSimulator.gd")
const BattleSetupConfigScript = preload("res://src/battle_sim/BattleSetupConfig.gd")
const BattleSetupFactoryScript = preload("res://src/battle_sim/BattleSetupFactory.gd")
const BattleScenarioFactoryScript = preload("res://src/factories/BattleScenarioFactory.gd")
const BattleEnvironmentFactoryScript = preload(
	"res://src/presentation/BattleEnvironmentFactory.gd")

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
var hud: HexBattleHud
var setupUI: HexBattleSetupUI
var playback: HexBattlePlayback
var cursor: HexBattleCursor
var memberTurn: HexBattleMemberTurn

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
	if adapter != null:
		adapter.disconnectFromEvents()
		adapter.dispose()
		adapter = null
	if hud != null:
		hud.queue_free()
		hud = null
	if battleCamera != null:
		battleCamera.queue_free()
		battleCamera = null
	if _boardRoot != null:
		_boardRoot.queue_free()
		_boardRoot = null
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

	_boardRoot = Node3D.new()
	_boardRoot.name = "HexBoard"
	add_child(_boardRoot)
	# The shared battle environment, reused rather than retuned: it is lighting, not board
	# geometry, and nothing about it assumed a square lattice.
	var worldEnvironment := WorldEnvironment.new()
	worldEnvironment.name = "BattleEnvironment"
	worldEnvironment.environment = BattleEnvironmentFactoryScript.createBattleEnvironment()
	_boardRoot.add_child(worldEnvironment)

	adapter = HexBattleVisualAdapterScript.new(_boardRoot, map, sim.state)
	sim.setVisualAdapter(adapter)
	adapter.connectToEvents(sim.events)
	adapter.animation_queue_drained.connect(_onPlaybackDrained)

	battleCamera = HexBattleCameraScript.new()
	add_child(battleCamera)
	battleCamera.frameMap(map, adapter.layout)
	battleCamera.camera.current = true

	hud = HexBattleHudScript.new()
	add_child(hud)
	hud.member_selected.connect(_onHudMemberSelected)
	hud.end_party_requested.connect(_onHudEndParty)

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
	if hud != null:
		hud.showParty(sim, int(sim.state.activePartyID), monsterID, true)
	memberTurn.begin()


func _onMemberTurnFinished(monsterID: int) -> void:
	memberTurn = null
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


func _unhandled_input(event: InputEvent) -> void:
	if lifecycle != Lifecycle.BATTLE or battleCamera == null:
		return
	if event is InputEventMouseButton and event.pressed:
		match event.button_index:
			MOUSE_BUTTON_WHEEL_UP:
				battleCamera.zoom(-1.0)
				get_viewport().set_input_as_handled()
			MOUSE_BUTTON_WHEEL_DOWN:
				battleCamera.zoom(1.0)
				get_viewport().set_input_as_handled()
	elif event is InputEventKey and event.pressed and not event.echo:
		match event.keycode:
			KEY_Q:
				battleCamera.orbitDetent(-1)
				get_viewport().set_input_as_handled()
			KEY_E:
				battleCamera.orbitDetent(1)
				get_viewport().set_input_as_handled()


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
