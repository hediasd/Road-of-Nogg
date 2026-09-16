extends SceneTree

## FHB-1: a hex battle draws its units at start. `BattleSetupFactory.createHexState()` builds a
## `BattleState` directly, correctly -- setup builds a state, it does not narrate one -- but
## nothing then told a connected `HexBattleVisualAdapter` what was on the board, so every hex
## battle started with an empty grey slab and eight monsters nobody could see. The fix is
## `BattleSimulator.emitInitialBoard()`, called once the adapter is listening and before the turn
## loop opens; this probe starts a real scenario through the real scene and asserts every alive
## monster actually got a model, seated where the simulation put it, with no monster announced
## twice.

const BattleScene = preload("res://scenes/battle/HexBattle.tscn")

const SCENARIO := "res://data/battle/scenarios/proving_ground_player_cpu.json"
const SEED := 20260908
const EXPECTED_MEMBER_IDS := [100, 101, 102, 103, 200, 201, 202, 203]

var failures: Array[String] = []


func _init() -> void:
	_run.call_deferred()


func _run() -> void:
	var battle := BattleScene.instantiate()
	root.add_child(battle)
	# One frame is enough for `_ready()` to run and build the foundation the controller needs
	# before `startBattle()` is called directly -- this probe drives the API, not the setup UI's
	# own button, so it does not need the several frames a real click-and-settle flow would.
	await process_frame

	var started: Dictionary = battle.call("startBattle", SCENARIO, SEED)
	_require(bool(started.get("ok", false)), "startBattle refused: %s" % str(started.get("error", "")))
	if not bool(started.get("ok", false)):
		_finish()
		return
	await process_frame

	var sim = battle.get("sim")
	var adapter = battle.get("adapter")
	_require(sim != null, "no simulator after startBattle")
	_require(adapter != null, "no adapter after startBattle")
	if sim == null or adapter == null:
		_finish()
		return

	var state = sim.state
	var aliveIDs: Array = state.getAliveMonsterIDs()
	_require(aliveIDs.size() == EXPECTED_MEMBER_IDS.size(),
		"expected %d alive monsters, found %d" % [EXPECTED_MEMBER_IDS.size(), aliveIDs.size()])
	for expectedID in EXPECTED_MEMBER_IDS:
		_require(aliveIDs.has(expectedID), "member %d is missing from the alive roster" % expectedID)

	# Every alive monster has exactly one model, seated at the cell the simulation actually holds
	# it at -- not the deployment cell from the scenario, which is what a probe reading the
	# scenario file directly could get right by accident even if the wiring were broken.
	var seenNodes: Dictionary = {}
	for monsterID in aliveIDs:
		var model: Node3D = adapter.modelFor(int(monsterID))
		_require(model != null, "monster %d has no model" % monsterID)
		if model == null:
			continue
		_require(not seenNodes.has(model), "monster %d shares a model with another monster" % monsterID)
		seenNodes[model] = true
		var cell: Vector2i = state.getMonsterPosition(int(monsterID))
		var expectedPosition: Vector3 = adapter.worldPositionOf(cell)
		_require(model.position.is_equal_approx(expectedPosition),
			"monster %d model at %s, expected %s (cell %s)" % [
				monsterID, model.position, expectedPosition, cell
			])

	# The count of seated models equals the count of alive monsters exactly -- not merely "at
	# least", which a duplicate-but-also-correct spawn could satisfy.
	_require(seenNodes.size() == aliveIDs.size(),
		"seated %d models against %d alive monsters" % [seenNodes.size(), aliveIDs.size()])

	# Every `Unit_*` child under the adapter's own root is one of the models just checked --
	# nothing extra got added, and nothing bypassed `modelFor`'s bookkeeping.
	# Searched rather than addressed: the board moved under the render stage's own world when the
	# battle gained one, and this probe predates that.
	var boardRoot: Node = battle.find_child("HexBoard", true, false)
	_require(boardRoot != null, "no HexBoard root under the battle scene")
	if boardRoot != null:
		var unitChildren := 0
		for child in boardRoot.get_children():
			if str(child.name).begins_with("Unit_"):
				unitChildren += 1
		_require(unitChildren == aliveIDs.size(),
			"%d Unit_* nodes against %d alive monsters" % [unitChildren, aliveIDs.size()])

	battle.queue_free()
	await process_frame
	_finish()


func _finish() -> void:
	if not failures.is_empty():
		for failure in failures:
			printerr("HXB_BOARD_POPULATION_FAILURE: %s" % failure)
		quit(1)
		return
	print("HXB_BOARD_POPULATION_OK")
	quit(0)


func _require(condition: bool, message: String) -> void:
	if not condition:
		failures.append(message)
