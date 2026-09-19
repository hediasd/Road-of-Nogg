## HPR-4: combat events reach the screen once, in order, and never ahead of their impact.
##
## Proves structure, ordering and state consistency only. Whether any of it LOOKS right is HPR-8's
## rendered-window judgement, not this probe's.
##
## Phases:
##   A  a paused synthetic sequence (move, attack, two-target cast, heal, status rows, status tick,
##      passive, miss, lethal removal, withdrawal), then its ordered playback
##   B  skip during a cast
##   C  recovery converging on authoritative state
##   D  under a real HexBattleStage, damage numbers are native UI outside the isolated viewport
##   E  a whole CPU battle's real events, drained, converge on the final state
##   F  disposal leaves nothing listening or rendering
extends SceneTree

const AdapterScript = preload("res://src/presentation/battle/HexBattleVisualAdapter.gd")
const BattleSetupConfigScript = preload("res://src/battle_sim/BattleSetupConfig.gd")
const BattleSetupFactoryScript = preload("res://src/battle_sim/BattleSetupFactory.gd")
const BattleScenarioFactoryScript = preload("res://src/factories/BattleScenarioFactory.gd")
const BattleSimulatorScript = preload("res://src/battle_sim/BattleSimulator.gd")
const StageScript = preload("res://src/presentation/battle/HexBattleStage.gd")
const CameraScript = preload("res://src/presentation/battle/HexBattleCamera.gd")

const SCENARIO := "res://data/battle/scenarios/technical_hxb_contract_cpu_cpu.json"
const SEED := 404
const SPELL := "Ice Plow"
## Real-time bound per drain. Holds are timer-driven, so a frame count would mean nothing.
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
	await _phaseOrdering()
	await _phaseSkip()
	_phaseRecovery()
	await _phaseDispose(adapter)
	await _phaseStage()
	await _phaseRealBattle()
	_finish()


# --- A: ordering ------------------------------------------------------------

func _phaseOrdering() -> void:
	var ids: Array = sim.state.getAliveMonsterIDs()
	_require(ids.size() >= 3, "fixture needs three living monsters")
	if ids.size() < 3:
		return
	var sourceID := int(ids[0])
	var targetID := int(ids[1])
	var reserveID := int(ids[2])
	var sourcePos: Vector2i = sim.state.getMonsterPosition(sourceID)
	var targetPos: Vector2i = sim.state.getMonsterPosition(targetID)
	var reservePos: Vector2i = sim.state.getMonsterPosition(reserveID)
	var walkTo := _emptyCell([targetPos, reservePos, sourcePos])
	var emptyCell := _emptyCell([targetPos, reservePos, sourcePos, walkTo])
	var targetHP := int(sim.state.getMonster(targetID).hitpoints)
	var reserveHP := int(sim.state.getMonster(reserveID).hitpoints)
	var before := _authoritativeSnapshot()

	adapter.queue().setPaused(true)
	sim.events.monster_moved.emit(sourceID, [sourcePos, walkTo])
	sim.events.monster_attacked.emit(sourceID, targetPos, targetID, 3, targetHP - 3)
	sim.events.spell_cast_started.emit(sourceID, targetPos, SPELL, "ice", 2, 1, "circle",
		[targetPos, reservePos, emptyCell], [targetID, reserveID])
	sim.events.monster_cast_spell.emit(sourceID, targetPos, targetID, SPELL,
		[{"damage": 2, "element": "ice"}, {"damage": 2, "element": "ice"}], targetHP - 7)
	sim.events.monster_cast_spell.emit(sourceID, targetPos, reserveID, SPELL,
		[{"damage": 4, "element": "ice"}], reserveHP - 4)
	sim.events.monster_healed.emit(sourceID, targetPos, targetID, "Timeoff", 2, targetHP - 5)
	sim.events.effect_applied.emit(targetID, "burn", 3, sourceID, "Smoke Tower")
	sim.events.effect_ticked.emit(targetID, "burn", 2)
	sim.events.status_damage_dealt.emit(targetID, "burn", 1, targetHP - 6)
	sim.events.passive_triggered.emit(reserveID, "Retaliation", "ON_TARGETED")
	sim.events.passive_aoe_damage.emit(reserveID, "Retaliation", targetID, "fire", 2, targetHP - 8)
	sim.events.effect_removed.emit(targetID, "burn")
	sim.events.monster_attacked.emit(sourceID, emptyCell, -1, 0, 0)
	sim.events.monster_defeated.emit(targetID, sourceID)
	sim.events.party_withdrawn.emit(99, [sourceID])

	_require(adapter.displayedHitpoints(targetID) == targetHP,
		"displayed HP read future event state while playback was paused")
	_require(adapter.modelFor(targetID) != null and adapter.modelFor(sourceID) != null,
		"defeat or withdrawal removed a model before its queued impacts")
	_require(adapter.feedbackAttachedCount("cast") == 1,
		"one spell_cast_started did not create exactly one cast carrier")
	_require(adapter.feedbackAttachedCount("strike") == 4,
		"expected four strikes: attack, two per-target spell hits, one miss")
	_require(adapter.pendingFeedbackPayloadCount() == 13,
		"expected 13 queued payloads (passive_triggered is a no-op), got %d"
		% adapter.pendingFeedbackPayloadCount())
	_require(adapter.queuedAnimationCount() == 14, "move plus 13 feedback actions were not queued")

	adapter.queue().setPaused(false)
	var began := Time.get_ticks_msec()
	while adapter.queue().activeActionKind() != "bump" \
			and Time.get_ticks_msec() - began < DRAIN_TIMEOUT_MS:
		await process_frame
	# The number answers the impact, not the wind-up, so the lunge has to
	# travel before it is thrown: absent as the bump starts, present once the
	# bump lands. Checking both ends pins the beat it is thrown on, where
	# checking only that it arrives would pass again if it moved back to frame
	# zero.
	var numberRoot: Control = adapter.damageNumberRoot()
	_require(numberRoot == null or numberRoot.get_child_count() == 0,
		"the number was thrown as the lunge began, not where it landed")
	_require(await _awaitNumber(),
		"the first strike did not spawn a damage number")
	var maxLiveCasts := await _drain(true)
	_require(maxLiveCasts == 1, "cast playback count while draining was %d, not 1" % maxLiveCasts)

	var timeline: Array = adapter.feedbackTimeline()
	var expected := [
		["strike", targetID, targetHP - 3, true],
		["cast", -1, -1, false],
		["strike", targetID, targetHP - 7, true],
		["strike", reserveID, reserveHP - 4, true],
		["number", targetID, targetHP - 5, true],
		["display", targetID, targetHP - 5, true],
		["display", targetID, targetHP - 5, true],
		["number", targetID, targetHP - 6, true],
		["number", targetID, targetHP - 8, true],
		["display", targetID, targetHP - 8, true],
		["strike", -1, -1, false],
		["removal", targetID, targetHP - 8, false],
		["removal", sourceID, int(sim.state.getMonster(sourceID).hitpoints), false],
	]
	_require(timeline.size() == expected.size(),
		"timeline length %d, expected %d" % [timeline.size(), expected.size()])
	for index in range(mini(timeline.size(), expected.size())):
		var row: Dictionary = timeline[index]
		var want: Array = expected[index]
		var got := [row["type"], row["target_id"], row["displayed_hp"], row["target_rendered"]]
		if row["type"] == "cast":
			got = ["cast", -1, -1, false]
		_require(got == want, "timeline[%d] was %s, expected %s" % [index, got, want])
	_require(adapter.displayedEffects(targetID).is_empty(),
		"effect apply/tick/remove did not converge to no rows")
	_require(adapter.displayedRemovalReason(targetID) == "defeated", "defeat reason lost")
	_require(adapter.displayedRemovalReason(sourceID) == "withdrawn",
		"withdrawal was not distinguished from defeat")
	_require(adapter.displayedRemovalReason(reserveID) == "", "reserve was wrongly removed")
	_require(adapter.modelFor(targetID) == null and adapter.modelFor(sourceID) == null,
		"queued removals left rendered models")
	_require(adapter.modelFor(reserveID) != null, "untouched reserve lost its model")
	_require(adapter.pendingFeedbackPayloadCount() == 0, "drained queue kept orphan payloads")
	_require(_authoritativeSnapshot() == before,
		"synthetic visual events changed authoritative combat state")


# --- B: skip ----------------------------------------------------------------

func _phaseSkip() -> void:
	var reserveID := _firstShown()
	if reserveID < 0:
		failures.append("skip phase has no shown unit")
		return
	var cell: Vector2i = sim.state.getMonsterPosition(reserveID)
	var hp: int = adapter.displayedHitpoints(reserveID)
	adapter.queue().setPaused(true)
	sim.events.spell_cast_started.emit(reserveID, cell, SPELL, "ice", 1, 0, "circle",
		[cell], [reserveID])
	sim.events.monster_cast_spell.emit(reserveID, cell, reserveID, SPELL,
		[{"damage": 1, "element": "ice"}], hp - 1)
	adapter.queue().setPaused(false)
	var began := Time.get_ticks_msec()
	while adapter.queue().activeActionKind() != "cast_area" \
			and Time.get_ticks_msec() - began < DRAIN_TIMEOUT_MS:
		await process_frame
	_require(adapter.queue().activeActionKind() == "cast_area", "cast never became active")
	adapter.skipCurrentAnimation()
	_require(adapter.queue().activeActionKind() == "", "skip did not end the active cast action")
	await _drain(false)
	_require(adapter.displayedHitpoints(reserveID) == hp - 1, "hit after a skipped cast was lost")
	_require(not adapter.isAnimationBusy(), "queue did not drain after skip")


# --- C: recovery ------------------------------------------------------------

func _phaseRecovery() -> void:
	var reserveID := _firstShown()
	adapter.queue().setPaused(true)
	sim.events.monster_attacked.emit(reserveID, sim.state.getMonsterPosition(reserveID),
		reserveID, 1, 0)
	sim.events.monster_defeated.emit(reserveID, reserveID)
	_require(adapter.pendingFeedbackPayloadCount() == 2, "recovery setup did not queue payloads")
	adapter.recoverPlayback()
	adapter.queue().setPaused(false)
	_require(adapter.pendingFeedbackPayloadCount() == 0, "recovery kept orphan payloads")
	_require(not adapter.isAnimationBusy(), "recovery left the queue busy")
	_require(adapter.liveCastEffectCount() == 0, "recovery left cast playback alive")
	_requireConverged("recovery")


# --- D: stage ---------------------------------------------------------------

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
	await process_frame
	await process_frame
	var ids: Array = sim.state.getAliveMonsterIDs()
	var attackerID := int(ids[0])
	var targetID := int(ids[1])
	var targetPos: Vector2i = sim.state.getMonsterPosition(targetID)
	sim.events.monster_attacked.emit(attackerID, targetPos, targetID, 5,
		int(sim.state.getMonster(targetID).hitpoints) - 5)
	await process_frame
	_require(await _awaitNumber(),
		"no damage number spawned under the stage")
	var numberRoot: Control = adapter.damageNumberRoot()
	if numberRoot != null:
		_require(numberRoot.get_viewport() == root,
			"damage numbers render inside a SubViewport, not at native resolution")
		_require(not stage.renderer.world_viewport.is_ancestor_of(numberRoot),
			"damage number layer is parented under the isolated render viewport")
		var number := numberRoot.get_child(0) as Control
		if number != null:
			_require(stage.displayRect().grow(64.0).has_point(number.position),
				"damage number was not placed through the stage projection")
	await _phaseDispose(adapter)
	stage.dispose()
	await process_frame


# --- E: a real battle -------------------------------------------------------

func _phaseRealBattle() -> void:
	var holder := Node3D.new()
	world.add_child(holder)
	if not _build(holder):
		return
	var castEvents := [0]
	var defeatEvents := [0]
	sim.events.spell_cast_started.connect(
		func(_a, _b, _c, _d, _e, _f, _g, _h, _i): castEvents[0] += 1)
	sim.events.monster_defeated.connect(func(_a, _b): defeatEvents[0] += 1)
	sim.startBattle()
	sim.runFullBattle(60)
	_require(castEvents[0] > 0, "the real battle cast no spells, so casts went unexercised")
	_require(adapter.feedbackAttachedCount("cast") == castEvents[0],
		"real battle: %d cast events made %d cast carriers"
		% [castEvents[0], adapter.feedbackAttachedCount("cast")])
	await _drain(false, true)
	_require(not adapter.isAnimationBusy(), "real battle playback never drained")
	_require(adapter.pendingFeedbackPayloadCount() == 0, "real battle kept orphan payloads")
	_requireConverged("real battle")
	print("HPR_FEEDBACK_MATRIX casts=%d defeats=%d strikes=%d numbers=%d removals=%d displays=%d" % [
		castEvents[0], defeatEvents[0], adapter.feedbackAttachedCount("strike"),
		adapter.feedbackAttachedCount("number"), adapter.feedbackAttachedCount("removal"),
		adapter.feedbackAttachedCount("display")])
	await _phaseDispose(adapter)


# --- F: disposal ------------------------------------------------------------

func _phaseDispose(target) -> void:
	var events = sim.events
	var root3d: Node3D = target._root
	target.dispose()
	events.monster_attacked.emit(-1, Vector2i.ZERO, -1, 0, 0)
	_require(target.pendingFeedbackPayloadCount() == 0, "disposed adapter still accepted events")
	_require(not target.isAnimationBusy(), "disposed adapter still reports playback")
	await process_frame
	await process_frame
	_require(_countNamed(root, "HexCombatNumbers") == 0, "damage number layer survived disposal")
	var units := 0
	for child in root3d.get_children():
		if str(child.name).begins_with("Unit_") and not child.is_queued_for_deletion():
			units += 1
	_require(units == 0, "unit models survived disposal")


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


## Every living, positioned unit is rendered where the state says with the state's HP and
## effects; every other unit is gone, with the right reason.
func _requireConverged(label: String) -> void:
	for value in sim.state.monsters.keys():
		var id := int(value)
		var monster = sim.state.getMonster(id)
		var positioned: bool = sim.state.monsterPositions.has(id)
		_require(adapter.displayedHitpoints(id) == int(monster.hitpoints),
			"%s: unit %d displayed HP %d, state %d" % [
				label, id, adapter.displayedHitpoints(id), monster.hitpoints])
		if positioned:
			var model: Node3D = adapter.modelFor(id)
			_require(model != null, "%s: positioned unit %d has no model" % [label, id])
			if model != null:
				_require(model.position.is_equal_approx(
					adapter.worldPositionOf(sim.state.getMonsterPosition(id))),
					"%s: unit %d model is not at its authoritative cell" % [label, id])
			_require(adapter.displayedEffects(id).size() == sim.state.getActiveEffects(id).size(),
				"%s: unit %d displayed effects diverged" % [label, id])
		else:
			_require(adapter.modelFor(id) == null, "%s: removed unit %d kept a model" % [label, id])
			var reason := "withdrawn" if sim.state.isMonsterWithdrawn(id) else "defeated"
			_require(adapter.displayedRemovalReason(id) == reason,
				"%s: unit %d removal reason %s, expected %s" % [
					label, id, adapter.displayedRemovalReason(id), reason])


func _authoritativeSnapshot() -> Dictionary:
	var rows := {}
	for value in sim.state.monsters.keys():
		var id := int(value)
		rows[id] = [int(sim.state.getMonster(id).hitpoints),
			sim.state.getMonsterPosition(id), sim.state.getActiveEffects(id).size()]
	return rows


func _firstShown() -> int:
	for value in sim.state.monsterPositions.keys():
		var id := int(value)
		if adapter.modelFor(id) != null:
			return id
	return -1


func _emptyCell(exclude: Array) -> Vector2i:
	for cell in sim.state.battleMap.validCells():
		if not exclude.has(cell) and sim.state.board.at(cell) == 0:
			return cell
	return exclude[0]


## Drains in real time. `watchCasts` returns the most cast playbacks seen alive at once; `skipAll`
## fast-forwards every action (a long real battle's playback, not its timing, is under test).
func _drain(watchCasts: bool, skipAll: bool = false) -> int:
	var began := Time.get_ticks_msec()
	var maxLive := 0
	while adapter.isAnimationBusy():
		if watchCasts:
			maxLive = maxi(maxLive, adapter.liveCastEffectCount())
		if skipAll:
			adapter.skipCurrentAnimation()
		if Time.get_ticks_msec() - began > DRAIN_TIMEOUT_MS * (6 if skipAll else 1):
			failures.append("visual queue did not drain in time")
			return maxLive
		await process_frame
	return maxLive


func _countNamed(node: Node, wanted: String) -> int:
	var total := 1 if node.name == wanted and not node.is_queued_for_deletion() else 0
	for child in node.get_children():
		total += _countNamed(child, wanted)
	return total


## Waits for a strike's number to be thrown. A caller that read the same frame
## the bump began would race the bump out, since the number is spawned where
## the lunge lands rather than on its first frame.
func _awaitNumber() -> bool:
	var began := Time.get_ticks_msec()
	while Time.get_ticks_msec() - began < DRAIN_TIMEOUT_MS:
		var numbers: Control = adapter.damageNumberRoot()
		if numbers != null and numbers.get_child_count() > 0:
			return true
		await process_frame
	return false


func _require(condition: bool, message: String) -> void:
	if not condition:
		failures.append(message)


func _finish() -> void:
	if failures.is_empty():
		print("HPR_FEEDBACK_OK")
		quit(0)
		return
	for failure in failures:
		printerr("HPR_FEEDBACK_FAILURE: %s" % failure)
	quit(1)
