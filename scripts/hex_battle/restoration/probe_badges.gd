## HPR-5: status badge rows appear, tick and leave when their feedback plays, follow their models
## at native resolution, and never outlive a unit or the adapter.
##
## Proves structure, ordering and projection arithmetic only. Legibility, hover feel, crowding
## and rotation are HPR-8's rendered-window judgement, not this probe's.
##
## Phases:
##   A  a paused synthetic sequence: apply, tick and remove on one unit between timed strikes,
##      then a defeat and a withdrawal of units wearing rows
##   B  under a real HexBattleStage: native layer and layering, projection from the model's bounds,
##      a row following a walking model, offscreen and behind-camera hiding, overlap, hover
##   C  recovery converging rows on authoritative state
##   D  a whole CPU battle drained: rows match displayed effects and no removed unit has one
##   E  disposal removes the layer and every row
extends SceneTree

const AdapterScript = preload("res://src/presentation/battle/HexBattleVisualAdapter.gd")
const BadgesScript = preload("res://src/presentation/battle/HexBattleUnitBadges.gd")
const BattleSetupConfigScript = preload("res://src/battle_sim/BattleSetupConfig.gd")
const BattleSetupFactoryScript = preload("res://src/battle_sim/BattleSetupFactory.gd")
const BattleScenarioFactoryScript = preload("res://src/factories/BattleScenarioFactory.gd")
const BattleSimulatorScript = preload("res://src/battle_sim/BattleSimulator.gd")
const StageScript = preload("res://src/presentation/battle/HexBattleStage.gd")
const CameraScript = preload("res://src/presentation/battle/HexBattleCamera.gd")
const HudScript = preload("res://src/presentation/battle/HexBattleHud.gd")
const MonsterModelFactoryScript = preload("res://src/presentation/MonsterModelFactory.gd")
const NoggThemeScript = preload("res://src/presentation/theme/NoggTheme.gd")

const SCENARIO := "res://data/battle/scenarios/technical_hxb_contract_cpu_cpu.json"
const SEED := 404
const DRAIN_TIMEOUT_MS := 20000

var failures: Array[String] = []
var world: Node3D
var sim
var adapter
var scenario


func _init() -> void:
	process_frame.connect(_run, CONNECT_ONE_SHOT)


func _run() -> void:
	world = Node3D.new()
	world.name = "ProbeWorld"
	root.add_child(world)
	var camera := Camera3D.new()
	camera.position = Vector3(0.0, 18.0, 14.0)
	world.add_child(camera)
	camera.look_at_from_position(camera.position, Vector3.ZERO)
	camera.current = true

	if not _build(world):
		return _finish()
	await _phaseEventTime()
	await _phaseDispose()
	await _phaseStage()
	_finish()


# --- A: event time ----------------------------------------------------------

func _phaseEventTime() -> void:
	var ids: Array = sim.state.getAliveMonsterIDs()
	_require(ids.size() >= 3, "fixture needs three living monsters")
	if ids.size() < 3:
		return
	var sourceID := int(ids[0])
	var targetID := int(ids[1])
	var reserveID := int(ids[2])
	var targetPos: Vector2i = sim.state.getMonsterPosition(targetID)
	var hp := int(sim.state.getMonster(targetID).hitpoints)
	var badges = adapter.statusBadges()
	_require(badges != null and badges.is_inside_tree(), "badge layer did not join the tree")
	_require(badges.get_viewport() == root, "bare-world badge layer is not in the root viewport")

	adapter.queue().setPaused(true)
	sim.events.effect_applied.emit(targetID, "burn", 3, sourceID, "Smoke Tower")
	sim.events.monster_attacked.emit(sourceID, targetPos, targetID, 1, hp - 1)
	sim.events.effect_ticked.emit(targetID, "burn", 2)
	sim.events.monster_attacked.emit(sourceID, targetPos, targetID, 1, hp - 2)
	sim.events.effect_removed.emit(targetID, "burn")
	sim.events.monster_attacked.emit(sourceID, targetPos, targetID, 1, hp - 3)
	sim.events.effect_applied.emit(reserveID, "poison", 4, sourceID, "Smoke Tower")
	sim.events.effect_applied.emit(sourceID, "slow", 2, reserveID, "Smoke Tower")
	sim.events.monster_attacked.emit(sourceID, targetPos, targetID, 1, hp - 4)
	sim.events.monster_defeated.emit(reserveID, sourceID)
	sim.events.party_withdrawn.emit(99, [sourceID])

	_require(badges.rowCount() == 0 and badges.createdCount() == 0,
		"a row appeared from an effect event before its display action played")

	adapter.queue().setPaused(false)
	# First strike: the apply has played, the tick has not.
	await _waitActive("bump", 1)
	var row: Control = badges.rowFor(targetID)
	_require(row != null, "applied effect did not create a row when it played")
	_require(_durations(row) == [3], "applied row durations %s, expected [3]" % [_durations(row)])
	# Second strike: the tick has played.
	await _waitActive("bump", 3)
	row = badges.rowFor(targetID)
	_require(row != null and _durations(row) == [2],
		"ticked row durations %s, expected [2]" % [_durations(row)])
	_require(badges.createdCount() == 1, "a tick rebuilt the row instead of updating it")
	# Third strike: the removal has played.
	await _waitActive("bump", 5)
	_require(badges.rowFor(targetID) == null, "removed effect left its row")
	_require(badges.removedCount() == 1, "effect removal count %d, expected 1" % badges.removedCount())
	# Fourth strike: both new rows are up, neither unit has started leaving.
	await _waitActive("bump", 8)
	_require(badges.rowFor(reserveID) != null and badges.rowFor(sourceID) != null,
		"rows for the units about to leave were not shown")
	_require(badges.rowCount() == 2, "row count %d before removals, expected 2" % badges.rowCount())
	# The defeat is playing: its row is gone although the model is still collapsing.
	await _waitActive("defeat", 9)
	_require(adapter.modelFor(reserveID) != null, "defeat freed the model before its playback")
	_require(badges.rowFor(reserveID) == null, "a row rode a collapsing unit")
	await _waitActive("defeat", 10)
	_require(badges.rowFor(sourceID) == null, "a row rode a withdrawing unit")
	await _drain()
	_require(badges.rowCount() == 0, "rows survived the removals")
	_require(badges.createdCount() == 3 and badges.removedCount() == 3,
		"row counts created=%d removed=%d, expected 3 and 3"
		% [badges.createdCount(), badges.removedCount()])
	badges.update(0.016, null)
	_require(badges.rowFor(reserveID) == null and badges.rowFor(sourceID) == null,
		"placement pass resurrected a row for a removed unit")
	print("HPR_BADGES_EVENT_TIME created=%d removed=%d" % [badges.createdCount(), badges.removedCount()])


# --- B: stage ---------------------------------------------------------------

func _phaseStage() -> void:
	var stage = StageScript.new()
	root.add_child(stage)
	await process_frame
	var boardRoot := Node3D.new()
	stage.worldRoot().add_child(boardRoot)
	if not _build(boardRoot):
		return
	var camera = CameraScript.new()
	stage.worldRoot().add_child(camera)
	stage.attachCamera(camera)
	camera.frameMap(scenario.battleMap, adapter.layout)
	camera.camera.current = true
	var hud = HudScript.new()
	root.add_child(hud)
	await process_frame
	await process_frame

	var badges = adapter.statusBadges()
	_require(badges.get_viewport() == root, "stage badge layer is not native resolution")
	_require(not stage.renderer.world_viewport.is_ancestor_of(badges),
		"badge layer is parented under the isolated render viewport")
	_require(badges.layer > NoggThemeScript.CRT_OVERLAY_LAYER_DEFAULT
		and badges.layer > NoggThemeScript.CRT_LAYER and badges.layer < hud.layer,
		"badge layer %d is not between the world image and the HUD (%d)" % [badges.layer, hud.layer])

	var ids: Array = sim.state.getAliveMonsterIDs()
	var walkerID := int(ids[0])
	var neighbourID := int(ids[1])
	sim.events.effect_applied.emit(walkerID, "burn", 3, walkerID, "Smoke Tower")
	await _drain()
	badges.update(0.0, null)
	var walker: Node3D = adapter.modelFor(walkerID)
	var row: Control = badges.rowFor(walkerID)
	_require(row != null and row.visible, "an on-screen unit's row is not visible")
	if row == null or walker == null:
		return

	# Anchor: the top of the model's own bounds, projected through the stage.
	var accumulated := {"has_bounds": false, "bounds": AABB()}
	MonsterModelFactoryScript.accumulateVisualBounds(walker, Transform3D.IDENTITY, accumulated)
	_require(accumulated["has_bounds"], "walker model has no measurable bounds")
	var measured: AABB = accumulated["bounds"]
	var boundsTop: float = measured.end.y
	_require(is_equal_approx(BadgesScript.anchorHeight(walker), maxf(boundsTop + 0.28, 0.75)),
		"row anchor is not derived from the model's bounds")
	_requirePlacedOver(badges, walker, row, "at rest")

	# Follow a walk, mid-tween and at the end.
	var start: Vector2i = sim.state.getMonsterPosition(walkerID)
	var far := _farthestEmptyCell(start)
	var startScreen: Vector2 = row.position
	var startWorld: Vector3 = adapter.worldPositionOf(start)
	var farWorld: Vector3 = adapter.worldPositionOf(far)
	sim.events.monster_moved.emit(walkerID, [start, far])
	var began := Time.get_ticks_msec()
	while Time.get_ticks_msec() - began < DRAIN_TIMEOUT_MS:
		if _midWalk(walker, startWorld, farWorld):
			break
		await process_frame
	_require(_midWalk(walker, startWorld, farWorld), "never observed the model mid-walk")
	badges.update(0.0, null)
	_requirePlacedOver(badges, walker, row, "mid-walk")
	await _drain()
	badges.update(0.0, null)
	_requirePlacedOver(badges, walker, row, "after walk")
	_require(row.position.distance_to(startScreen) > 1.0, "row did not move with its model")

	# Offscreen and behind the camera hide the row; returning shows it again.
	var home := walker.position
	walker.position = home + Vector3(4000.0, 0.0, 0.0)
	badges.update(0.0, null)
	_require(not row.visible, "a row for an offscreen model stayed visible")
	walker.global_position = camera.camera.global_position \
		+ camera.camera.global_transform.basis.z * 20.0
	badges.update(0.0, null)
	_require(not row.visible, "a row for a model behind the camera stayed visible")
	walker.position = home
	badges.update(0.0, null)
	_require(row.visible, "row did not return when its model came back on screen")

	# Overlap: two rows over the same point are pushed apart vertically, never sideways. Both stand
	# on the map's centre cell so a screen edge cannot be what blocks the search.
	sim.events.effect_applied.emit(neighbourID, "poison", 2, walkerID, "Smoke Tower")
	await _drain()
	var centre: Vector3 = adapter.worldPositionOf(_centreCell())
	walker.position = centre
	var neighbour: Node3D = adapter.modelFor(neighbourID)
	var neighbourRow: Control = badges.rowFor(neighbourID)
	_require(neighbourRow != null, "neighbour row missing")
	if neighbour != null and neighbourRow != null:
		var neighbourHome := neighbour.position
		neighbour.position = centre
		badges.update(0.0, null)
		_require(row.visible and neighbourRow.visible, "centre rows are not visible")
		_require(not Rect2(row.position, row.size).intersects(
			Rect2(neighbourRow.position, neighbourRow.size)), "rows over the same unit point overlap")
		_require(absf((row.position.x + row.size.x * 0.5)
			- (neighbourRow.position.x + neighbourRow.size.x * 0.5)) <= 1.0,
			"declutter moved a row sideways off its unit")
		neighbour.position = neighbourHome
		badges.update(0.0, null)

	# Hover: the pointer over the resting rect grows that badge; leaving shrinks it back.
	badges.update(0.0, row.position + row.size * 0.5)
	for step in range(20):
		badges.update(0.02, row.position + row.size * 0.5)
	_require(int(row.get("_hovered")) == 0, "pointer over a badge did not hover it")
	_require(float((row.get("_scales") as Array)[0]) > 1.0, "hovered badge did not grow")
	for step in range(20):
		badges.update(0.02, null)
	_require(int(row.get("_hovered")) == -1, "leaving the row did not clear hover")
	walker.position = home

	await _phaseRecovery()
	await _phaseRealBattle(stage, boardRoot, camera)
	hud.queue_free()
	stage.dispose()
	await process_frame


# --- C: recovery ------------------------------------------------------------

func _phaseRecovery() -> void:
	var badges = adapter.statusBadges()
	var id := -1
	for value in sim.state.monsterPositions.keys():
		if adapter.modelFor(int(value)) != null:
			id = int(value)
			break
	adapter.queue().setPaused(true)
	# A synthetic event the simulation never applied: recovery must drop the displayed row
	# for it rather than keep it.
	sim.events.effect_applied.emit(id, "haste", 3, id, "Smoke Tower")
	adapter.queue().setPaused(false)
	await _drain()
	_require(badges.rowFor(id) != null, "recovery setup row not shown")
	adapter.recoverPlayback()
	_requireRowsMatchDisplay("recovery")
	_require(badges.rowFor(id) == null, "recovery kept a row the simulation never had")


# --- D: a real battle -------------------------------------------------------

func _phaseRealBattle(stage, boardRoot: Node3D, camera) -> void:
	await _phaseDispose()
	# Rebuild on the same stage so the whole battle projects through it.
	for child in boardRoot.get_children():
		child.queue_free()
	await process_frame
	if not _build(boardRoot):
		return
	camera.frameMap(scenario.battleMap, adapter.layout)
	var applied := [0]
	sim.events.effect_applied.connect(func(_a, _b, _c, _d, _e): applied[0] += 1)
	sim.startBattle()
	sim.runFullBattle(60)
	_require(applied[0] > 0, "the real battle applied no effects, so badges went unexercised")
	var maxRows := 0
	var began := Time.get_ticks_msec()
	while adapter.isAnimationBusy():
		maxRows = maxi(maxRows, adapter.statusBadges().rowCount())
		adapter.skipCurrentAnimation()
		if Time.get_ticks_msec() - began > DRAIN_TIMEOUT_MS * 6:
			failures.append("real battle playback did not drain in time")
			break
		await process_frame
	adapter.statusBadges().update(0.016, null)
	_requireRowsMatchDisplay("real battle")
	for value in sim.state.monsters.keys():
		var id := int(value)
		if not sim.state.monsterPositions.has(id):
			_require(adapter.statusBadges().rowFor(id) == null,
				"real battle: removed unit %d kept a row" % id)
		elif adapter.statusBadges().rowFor(id) != null:
			_require(adapter.displayedEffects(id).size() == sim.state.getActiveEffects(id).size(),
				"real battle: unit %d row diverged from final state" % id)
	print("HPR_BADGES_MATRIX applied=%d max_rows=%d created=%d removed=%d final_rows=%d" % [
		applied[0], maxRows, adapter.statusBadges().createdCount(),
		adapter.statusBadges().removedCount(), adapter.statusBadges().rowCount()])
	await _phaseDispose()


# --- E: disposal ------------------------------------------------------------

func _phaseDispose() -> void:
	var badges = adapter.statusBadges()
	var rows: int = badges.rowCount()
	var removedBefore: int = badges.removedCount()
	adapter.dispose()
	_require(adapter.statusBadges() == null, "disposed adapter still exposes its badges")
	_require(badges.isDisposed() and badges.rowCount() == 0, "disposal kept rows")
	_require(badges.removedCount() == removedBefore + rows,
		"teardown removed %d rows, expected %d" % [badges.removedCount() - removedBefore, rows])
	sim.events.effect_applied.emit(0, "burn", 3, 0, "Smoke Tower")
	await process_frame
	await process_frame
	_require(_countNamed(root, "HexStatusBadges") == 0, "badge layer survived disposal")
	_require(_countNamed(root, "StatusBadgeRoot") == 0, "badge row root survived disposal")


# --- helpers ----------------------------------------------------------------

func _build(parent: Node3D) -> bool:
	var loaded := BattleScenarioFactoryScript.loadFromPath(SCENARIO)
	if not loaded["success"]:
		failures.append("scenario load failed")
		return false
	scenario = loaded["scenario"]
	var config: BattleSetupConfig = BattleSetupConfigScript.new()
	config.scenarioPath = SCENARIO
	config.seed = SEED
	var stateResult := BattleSetupFactoryScript.createHexState(config)
	if not stateResult["success"]:
		failures.append("state build failed")
		return false
	sim = BattleSimulatorScript.new(SEED)
	sim.configureHexState(stateResult["state"], scenario, {"scenarioPath": SCENARIO})
	adapter = AdapterScript.new(parent, scenario.battleMap, sim.state)
	adapter.connectToEvents(sim.events)
	sim.emitInitialBoard()
	return true


## The row sits centred over the projection of the model's live anchor, lifted by the theme lift.
func _requirePlacedOver(badges, model: Node3D, row: Control, label: String) -> void:
	var anchor: Vector2 = badges.projectedAnchor(model)
	_require(anchor.x >= 0.0, "%s: anchor did not project" % label)
	var centreX := row.position.x + row.size.x * 0.5
	var bottom := row.position.y + row.size.y
	_require(absf(centreX - anchor.x) <= 1.0,
		"%s: row centre x %.1f is not over anchor x %.1f" % [label, centreX, anchor.x])
	_require(absf(bottom - (anchor.y - NoggThemeScript.STATUS_BADGE_LIFT)) <= 1.0,
		"%s: row bottom %.1f is not lifted above anchor y %.1f" % [label, bottom, anchor.y])


## Every rendered unit has a row exactly when it has displayed effects, with the same count.
func _requireRowsMatchDisplay(label: String) -> void:
	var badges = adapter.statusBadges()
	var expected := 0
	for value in sim.state.monsters.keys():
		var id := int(value)
		var shown: bool = adapter.modelFor(id) != null and adapter.displayedRemovalReason(id) == ""
		var effects: Array = adapter.displayedEffects(id)
		var row: Control = badges.rowFor(id)
		if shown and not effects.is_empty():
			expected += 1
			_require(row != null, "%s: unit %d has displayed effects but no row" % [label, id])
			if row != null:
				_require(_durations(row).size() == mini(effects.size(),
					NoggThemeScript.STATUS_BADGE_MAX_VISIBLE),
					"%s: unit %d row size diverged from displayed effects" % [label, id])
		else:
			_require(row == null, "%s: unit %d has a row with nothing to show" % [label, id])
	_require(badges.rowCount() == expected,
		"%s: %d rows, expected %d" % [label, badges.rowCount(), expected])


func _durations(row: Control) -> Array:
	var result: Array = []
	if row == null:
		return result
	for entry in row.get("_entries"):
		result.append(int(entry["duration"]))
	return result


## Waits until `kind` is the active action with exactly `finished` actions already on the timeline.
func _waitActive(kind: String, finished: int) -> void:
	var began := Time.get_ticks_msec()
	while Time.get_ticks_msec() - began < DRAIN_TIMEOUT_MS:
		if adapter.queue().activeActionKind() == kind and adapter.feedbackTimeline().size() == finished:
			return
		await process_frame
	failures.append("never reached active %s after %d finished actions (active %s, timeline %d)"
		% [kind, finished, adapter.queue().activeActionKind(), adapter.feedbackTimeline().size()])


func _drain() -> void:
	var began := Time.get_ticks_msec()
	while adapter.isAnimationBusy():
		if Time.get_ticks_msec() - began > DRAIN_TIMEOUT_MS:
			failures.append("visual queue did not drain in time")
			return
		await process_frame


func _midWalk(model: Node3D, startWorld: Vector3, endWorld: Vector3) -> bool:
	return adapter.queue().activeActionKind() == "move" \
		and not model.position.is_equal_approx(startWorld) \
		and not model.position.is_equal_approx(endWorld)


func _centreCell() -> Vector2i:
	var cells: Array = sim.state.battleMap.validCells()
	var total := Vector3.ZERO
	for cell in cells:
		total += adapter.worldPositionOf(cell)
	var mean := total / float(maxi(cells.size(), 1))
	var best: Vector2i = cells[0]
	for cell in cells:
		if adapter.worldPositionOf(cell).distance_to(mean) \
				< adapter.worldPositionOf(best).distance_to(mean):
			best = cell
	return best


func _farthestEmptyCell(from: Vector2i) -> Vector2i:
	var best := from
	var bestDistance := -1.0
	for cell in sim.state.battleMap.validCells():
		if sim.state.board.at(cell) != 0:
			continue
		var distance := Vector2(cell - from).length()
		if distance > bestDistance:
			bestDistance = distance
			best = cell
	return best


func _countNamed(node: Node, wanted: String) -> int:
	var total := 1 if node.name == wanted and not node.is_queued_for_deletion() else 0
	for child in node.get_children():
		total += _countNamed(child, wanted)
	return total


func _require(condition: bool, message: String) -> void:
	if not condition:
		failures.append(message)


func _finish() -> void:
	if failures.is_empty():
		print("HPR_BADGES_OK")
		quit(0)
		return
	for failure in failures:
		printerr("HPR_BADGES_FAILURE: %s" % failure)
	quit(1)
