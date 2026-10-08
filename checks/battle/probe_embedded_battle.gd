extends SceneTree

## What this proves: a host can embed the hex battle. An embedded controller never shows the setup
## screen, starts from a scenario path, announces its completion exactly once after playback has
## drained, refuses to restart (by key or by the drawer), offers "Leave battle" in place of Setup,
## and hands the leave decision to the host with the outcome. A standalone controller still opens
## on its setup screen, and offers the road only when the road scene exists.
##
## What it cannot prove: how a host presents any of this. The road scene probe does that.

const ControllerScript = preload("res://battle/HexBattleController.gd")
const PanelScript = preload("res://ui/HexGraphicsPanel.gd")

const SCENARIO := "res://data/scenarios/technical_hxb_contract_cpu_cpu.json"
const SEED := 42
const MAX_FRAMES := 40000
const MARKER := "HXB_EMBEDDED_OK"

var failures: Array[String] = []
var completions: Array[int] = []
var leaves: Array[int] = []


func _init() -> void:
	process_frame.connect(_run, CONNECT_ONE_SHOT)


func _run() -> void:
	await _checkStandalone()
	await _checkEmbedded()
	for failure in failures:
		printerr("HXB_EMBEDDED_FAILURE: %s" % failure)
	if failures.is_empty():
		print(MARKER)
	quit(0 if failures.is_empty() else 1)


func _checkStandalone() -> void:
	var standalone: HexBattleController = ControllerScript.new()
	root.add_child(standalone)
	await _frames(2)
	_require(standalone.setupUI._root.visible, "a standalone battle did not open on its setup screen")
	var roadButton := standalone.setupUI.find_child("RoadButton", true, false)
	_require((roadButton != null) == ResourceLoader.exists(ControllerScript.ROAD_SCENE),
		"the road is offered exactly when its scene exists (button %s, scene %s)" % [
			str(roadButton != null), str(ResourceLoader.exists(ControllerScript.ROAD_SCENE))])
	standalone.queue_free()
	await _frames(2)


func _checkEmbedded() -> void:
	var embedded: HexBattleController = ControllerScript.new()
	embedded.embedded = true
	embedded.battle_completed.connect(func(outcome: int) -> void: completions.append(outcome))
	embedded.leave_requested.connect(func(outcome: int) -> void: leaves.append(outcome))
	root.add_child(embedded)
	await _frames(2)
	_require(not embedded.setupUI._root.visible, "an embedded battle showed the setup screen")
	_require(embedded.setupUI.find_child("RoadButton", true, false) == null, "an embedded battle offered the road")

	var started := embedded.startBattle(SCENARIO, SEED)
	_require(bool(started.get("ok", false)), "the embedded battle did not start: %s" % str(started))
	if not started.get("ok", false):
		return
	_require(not embedded.setupUI._root.visible, "starting an embedded battle showed the setup screen")
	var panel = embedded.stage.graphicsPanel
	_require(panel.leaveLabel == ControllerScript.EMBEDDED_LEAVE_LABEL and not panel.restartAllowed,
		"the drawer was not told it is embedded")
	embedded.playback.setSpeed(4.0)

	var frames := 0
	while embedded.lifecycle != HexBattleController.Lifecycle.COMPLETE:
		frames += 1
		if frames > MAX_FRAMES:
			failures.append("the embedded battle never completed")
			return
		embedded.skipAnimation()
		await process_frame
	await _frames(20)
	_require(completions.size() == 1, "battle_completed fired %d times" % completions.size())
	if completions.size() == 1:
		_require(completions[0] == int(embedded.sim.state.battleOutcome),
			"battle_completed carried %d, the battle ended %d" % [completions[0], int(embedded.sim.state.battleOutcome)])

	var simBefore = embedded.sim
	embedded._onSessionCommand(PanelScript.RESTART)
	var key := InputEventKey.new()
	key.keycode = KEY_R
	key.pressed = true
	_require(not embedded._handleSessionKey(key), "R was handled in an embedded battle")
	await _frames(2)
	_require(embedded.sim == simBefore and embedded.lifecycle == HexBattleController.Lifecycle.COMPLETE,
		"an embedded battle restarted")
	_require(completions.size() == 1, "a refused restart completed the battle again")
	embedded._refreshHud()
	var restartRow: Button = panel.sessionButtons[PanelScript.RESTART]
	var leaveRow: Button = panel.sessionButtons[PanelScript.SETUP]
	_require(restartRow.disabled, "the drawer offered Restart in an embedded battle")
	_require(leaveRow.text == ControllerScript.EMBEDDED_LEAVE_LABEL and not leaveRow.disabled,
		"the drawer's leave row reads '%s'" % leaveRow.text)

	embedded._onSessionCommand(PanelScript.SETUP)
	await _frames(1)
	_require(leaves.size() == 1 and leaves[0] == completions[0],
		"leaving reported %s, expected the outcome %s once" % [str(leaves), str(completions)])
	_require(not embedded.setupUI._root.visible, "leaving an embedded battle showed the setup screen")
	embedded.queue_free()
	await _frames(3)
	print("embedded battle: outcome %d after %d rounds, %d frames" % [
		completions[0] if not completions.is_empty() else -99, int(simBefore.state.roundCount), frames])


func _frames(count: int) -> void:
	for _index in range(count):
		await process_frame


func _require(condition: bool, message: String) -> void:
	if not condition:
		failures.append(message)
