extends SceneTree

const AdapterScript = preload("res://src/presentation/battle/HexBattleVisualAdapter.gd")
const ScreenCuesScript = preload(
	"res://src/presentation/battle/ui/side_turn/SideTurnScreenCues.gd")
const BattleSetupConfigScript = preload("res://src/battle_sim/BattleSetupConfig.gd")
const BattleSetupFactoryScript = preload("res://src/battle_sim/BattleSetupFactory.gd")
const BattleScenarioFactoryScript = preload("res://src/factories/BattleScenarioFactory.gd")
const BattleSimulatorScript = preload("res://src/battle_sim/BattleSimulator.gd")

const SCENARIO := "res://data/battle/scenarios/technical_hxb_contract_cpu_cpu.json"

var failures: Array[String] = []
var _world: Node3D
var _adapter
var _cues


func _init() -> void:
	_world = Node3D.new()
	root.add_child(_world)
	process_frame.connect(_run, CONNECT_ONE_SHOT)


func _run() -> void:
	var loaded := BattleScenarioFactoryScript.loadFromPath(SCENARIO)
	_require(bool(loaded.get("success", false)), "scenario did not load")
	if failures.is_empty():
		var config := BattleSetupConfigScript.new()
		config.scenarioPath = SCENARIO
		config.seed = 20260916
		var built := BattleSetupFactoryScript.createHexState(config)
		_require(bool(built.get("success", false)), "state did not build")
		if bool(built.get("success", false)):
			_checkWorldCues(loaded["scenario"], built["state"])
			await _checkScreenCues()
	_finish()


func _checkWorldCues(scenario, state) -> void:
	var sim = BattleSimulatorScript.new(20260916)
	sim.configureHexState(state, scenario, {"scenarioPath": SCENARIO})
	_adapter = AdapterScript.new(_world, scenario.battleMap, sim.state)
	_adapter.connectToEvents(sim.events)
	sim.emitInitialBoard()
	var ids: Array = _adapter.shownModelIDs()
	_require(ids.size() >= 2, "fixture did not render enough unit models")
	if ids.size() < 2:
		return
	var spentID := int(ids[0])
	var targetID := int(ids[1])
	var model: Node3D = _adapter.modelFor(spentID)
	var mesh := _firstUnitMesh(model)
	var authoredMaterial: Material = mesh.material_override if mesh != null else null
	_adapter.setUnitSpent(spentID, true)
	_require(_adapter.isUnitSpent(spentID), "spent state was not retained")
	# Even and hue-preserving: one per-instance multiply inside the unit's own shading, applied to
	# every retro-shaded mesh of the model including its base, not a screen-read hull over part of
	# it. The base carrying the same value is what makes the darkening even across the whole model.
	_require(is_equal_approx(_adapter.unitDarken(spentID), AdapterScript.SPENT_DARKEN),
		"spent unit was not darkened")
	_require(is_equal_approx(_meshDarken(mesh), AdapterScript.SPENT_DARKEN),
		"the unit's own mesh did not carry the darkening")
	_require(_darkenedMeshCount(model) == _retroMeshCount(model),
		"the darkening reached only part of the model")
	_require(mesh == null or mesh.material_override == authoredMaterial,
		"spent treatment replaced the unit's authored material")
	_require(mesh == null or mesh.material_overlay == null,
		"spent treatment took the overlay slot the hover outline owns")
	_require(AdapterScript.SPENT_DARKEN < 1.0,
		"a fully black spent unit would lose its silhouette")
	_adapter.setHoveredUnit(spentID)
	_require(mesh != null and mesh.material_overlay is ShaderMaterial
			and (mesh.material_overlay as ShaderMaterial).shader == _adapter.UnitOutlineShader,
		"hover did not outline the spent unit")
	_require(is_equal_approx(
			float((mesh.material_overlay as ShaderMaterial).get_shader_parameter("width_px")),
			AdapterScript.OUTLINE_WIDTH_PX),
		"hover outline did not use the authored thick screen-pixel width")
	_require(AdapterScript.UnitOutlineShader.code.contains("ALPHA = outline_color.a"),
		"hover outline did not render after opaque components had populated depth")
	_require(is_equal_approx(_adapter.unitDarken(spentID), AdapterScript.SPENT_DARKEN),
		"hovering a spent unit took its darkening away")
	_adapter.setHoveredUnit(-1)
	_adapter.setUnitSpent(spentID, false)
	_require(is_equal_approx(_adapter.unitDarken(spentID), 0.0)
			and _darkenedMeshCount(model) == 0,
		"clearing spent did not restore the original presentation")

	# The timing rule: the simulation spending a unit must not darken it. Only playback may, and
	# the queue is what says when playback has reached it.
	sim.events.unit_spent.emit(int(sim.state.activeSideID), spentID)
	_require(is_equal_approx(_adapter.unitDarken(spentID), 0.0),
		"a unit darkened the instant the simulation spent it, before playback reached the action")
	_require(_adapter.queuedAnimationCount() > 0 or _adapter.isAnimationBusy(),
		"spending a unit queued no darkening for playback to reach")

	_adapter.setTargetedUnit(targetID)
	_require(_adapter.targetedUnit() == targetID, "sword target was not retained")
	var targetModel: Node3D = _adapter.modelFor(targetID)
	_require(targetModel.get_node_or_null("TargetSword") != null,
		"sword marker was not parented to its target model")
	_adapter.setTargetedUnit(-1)
	_require(_adapter.targetedUnit() == -1, "sword target did not clear")

	var region: Array = scenario.battleMap.validCells().slice(0, 7)
	_adapter.show_movement_options(region)
	_require(_adapter.layerCellCount(AdapterScript.LAYER_REACH) == region.size(),
		"reachable region lost its logical cell count")
	_require((_adapter._layers[AdapterScript.LAYER_REACH] as Array).size() == 1,
		"reachable cells were not consolidated into one region mesh")


## The turn heading over the middle of the screen: NEXT TURN first, then TURN #n, each growing
## from no height to full. Checked through the values the animation drives rather than by looking
## at pixels, which a headless probe has none of.
func _checkTurnAnnouncement() -> void:
	var announcement = _cues._announcement
	_cues.showTurnAnnouncement(7)
	_require(announcement.visible, "the turn heading did not appear")
	_require(_cues.announcedText() == "NEXT TURN",
		"the turn heading did not open with NEXT TURN, got '%s'" % _cues.announcedText())
	_require(announcement.scale.y < 1.0, "the heading did not grow from no height")
	_require(is_equal_approx(announcement.scale.x, 1.0),
		"the heading grew horizontally as well as vertically")
	await create_timer(
		announcement.GROW_SECONDS + announcement.HOLD_SECONDS
			+ announcement.COLLAPSE_SECONDS + 0.08).timeout
	_require(_cues.announcedText() == "TURN #7",
		"the heading did not follow with the turn number, got '%s'" % _cues.announcedText())
	_cues.hideTurnAnnouncement()
	_require(not announcement.visible, "the turn heading did not clear on request")


func _checkScreenCues() -> void:
	_cues = ScreenCuesScript.new()
	root.add_child(_cues)
	_cues.setProjector(func(world: Vector3): return Vector2(400.0 + world.x, 100.0 + world.z))
	_cues.showTurnBanner(true)
	_require(_cues._banner._label.theme_type_variation == &"",
		"turn notice did not inherit the standard Terminal label style")
	_require(_cues._banner.visible, "turn notice did not appear at side start")
	await _checkTurnAnnouncement()
	_cues.showActionArc(Vector3.ZERO, {
		"magic": false, "item": true, "status": true, "wait": true,
	}, ["magic"], true)
	_require(_cues.actionArcFlipped(), "arc did not flip below a unit near the top edge")
	_cues.setAiming(true)
	_require(_cues._arc.modulate.a < 0.5, "aiming did not fade the action arc")
	var forecast := {
		"available": true, "minimum": 12, "maximum": 18,
		"critical_chance": 0.1, "exact": false,
		"target_hitpoints": 15, "possibly_lethal": true,
	}
	_cues.showForecasts([
		{"monster_id": 1, "name": "One", "world_anchor": Vector3.ZERO,
			"forecast": forecast},
		{"monster_id": 2, "name": "Two", "world_anchor": Vector3.ONE,
			"forecast": forecast},
	])
	_require(_cues.previewCount() == 2, "multiple forecast boxes were not retained")
	_cues.setReadyCount(2)
	_cues._endButton._onPressed()
	_require(_cues.endTurnConfirming(), "End turn did not ask before skipping ready units")
	await create_timer(
		_cues._banner.ENTER_SECONDS + _cues._banner.HOLD_SECONDS
			+ _cues._banner.EXIT_SECONDS + 0.05).timeout
	_require(not _cues._banner.visible, "turn notice did not dismiss itself after its entrance")


## The darkening on one mesh, or 0.0 where the parameter was never set.
func _meshDarken(mesh: MeshInstance3D) -> float:
	if mesh == null:
		return 0.0
	var value = mesh.get_instance_shader_parameter(BattleMeshFactory.UNIT_DARKEN_PARAM)
	return float(value) if value != null else 0.0


## How many of the model's meshes carry a darkening right now, and how many could.
func _darkenedMeshCount(model: Node3D) -> int:
	var count := 0
	for node in model.find_children("*", "MeshInstance3D", true, false):
		if _meshDarken(node as MeshInstance3D) > 0.0:
			count += 1
	return count


func _retroMeshCount(model: Node3D) -> int:
	var count := 0
	for node in model.find_children("*", "MeshInstance3D", true, false):
		if BattleMeshFactory._hasRetroShader(node as MeshInstance3D):
			count += 1
	return count


func _firstUnitMesh(model: Node3D) -> MeshInstance3D:
	if model == null:
		return null
	for node in model.find_children("*", "MeshInstance3D", true, false):
		var mesh := node as MeshInstance3D
		if not _adapter._isUnitChrome(mesh, model):
			return mesh
	return null


func _require(condition: bool, message: String) -> void:
	if not condition:
		failures.append(message)


func _finish() -> void:
	if _adapter != null:
		_adapter.dispose()
	if not failures.is_empty():
		for failure: String in failures:
			printerr("STB_BOARD_CUES_FAILURE: %s" % failure)
		quit(1)
		return
	print("STB_BOARD_CUES_OK")
	quit(0)
