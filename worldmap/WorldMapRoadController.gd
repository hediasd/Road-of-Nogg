## The road scene: the world map with the road drawn on it, the company panel, and the battles
## fought along it.
##
## OWNERSHIP. The road's state is `RoadState` (road/); this file only asks it to change and redraws
## from it. Every change is saved at once (`RoadSave`), so quitting at any point resumes where the
## player was. The world-map rig is composed exactly as `WorldMapDebugController` composes it --
## SubViewport, `WorldMap.tscn`, the region catalog, a framing preset -- without editing any shared
## world-map class.
##
## A BATTLE. Travel walks the token to the stop, composes the stop's battle (`RoadBattle.compose`),
## writes it under the save directory, and runs `HexBattle.tscn` embedded (see
## `HexBattleController`, EMBEDDING). While it runs the map stops rendering and processing. A
## `RoadBattle.Tally` records defeats from the battle's events; on `battle_completed` the battle
## is summarized and paid immediately, and the result window reports it. Leaving before the end
## pays nothing.
##
## PROBE HOOKS, set before entering the tree: `roadName` (empty: the catalog's first road),
## `saveDirectory`, `autoplay` (the CPU plays the company's side).

extends Node

const RoadReferencesScript = preload("res://content/RoadReferences.gd")
const RoadStateScript = preload("res://road/RoadState.gd")
const RoadRulesScript = preload("res://road/RoadRules.gd")
const RoadBattleScript = preload("res://road/RoadBattle.gd")
const RoadSaveScript = preload("res://road/RoadSave.gd")
const MarkersScript = preload("res://worldmap/WorldMapRoadMarkers.gd")
const PanelScript = preload("res://ui/RoadPanel.gd")
const Uniforms = preload("res://worldmap/WorldMapGroundUniforms.gd")
const FramingCatalog = preload("res://worldmap/WorldMapFramingCatalog.gd")
const RegionCatalog = preload("res://worldmap/WorldMapRegionCatalog.gd")
const WorldMapScene = preload("res://scenes/WorldMap.tscn")

const BATTLE_SCENE := "res://scenes/HexBattle.tscn"
const SETUP_SCENE := "res://scenes/HexBattle.tscn"
const BATTLE_FILE := "battle.json"
## The framing that fits a small region whole. temp2 is 15.5 x 11 tiles.
const FRAMING_PRESET := FramingCatalog.FIT
## The road's own adjustments over that preset, applied to this scene's copy only: a higher camera
## so the whole region fits beside the panel (fog pushed back in proportion), and no clouds,
## because a cloud over a stop hides the very thing the player is choosing between.
const FRAMING_OVERRIDES := {
	Uniforms.K_HEIGHT: 30.0,
	Uniforms.K_FOG_START: 9.0,
	Uniforms.K_FOG_END: 52.0,
	Uniforms.K_CLOUDS: Uniforms.CLOUDS_OFF,
}
## How close, in screen pixels, a click must land to a stop to pick it.
const PICK_RADIUS := 28.0

## For probes: a battle was opened at this stop, and a battle closed with the road's last report.
signal battle_opened(stopIndex: int)
signal battle_closed(report: Dictionary)

var roadName := ""
var saveDirectory := RoadSaveScript.SAVE_DIR
var autoplay := false

var road: Dictionary = {}
var state
var selectedStop := 0
var battle: Node
var panel: CanvasLayer
var markers: Node3D

var _viewport: SubViewport
var _display: TextureRect
var _map: Node3D
var _ground
var _camera
var _sky
var _props
var _clouds
var _framing: Dictionary = {}
var _regionMapPx := Vector2i.ZERO
var _tally
var _battleStop := -1
var _battlePaid := false
var _travelling := false
var _notice := ""


func _ready() -> void:
	_viewport = get_node("World") as SubViewport
	_display = get_node("Display") as TextureRect
	_display.texture = _viewport.get_texture()
	_map = WorldMapScene.instantiate()
	_viewport.add_child(_map)
	_ground = _map.get_node("Ground")
	_camera = _map.get_node("Camera")
	_sky = _map.get_node("Camera/Sky")
	_props = _map.get_node("Props")
	_clouds = _map.get_node("Clouds")
	_camera.current = true

	panel = PanelScript.new()
	add_child(panel)
	panel.field_toggled.connect(_onFieldToggled)
	panel.captain_chosen.connect(_onCaptainChosen)
	panel.ascend_requested.connect(_onAscend)
	panel.stop_stepped.connect(_onStopStepped)
	panel.travel_requested.connect(func() -> void: travelTo(selectedStop))
	panel.new_road_requested.connect(_onNewRoad)
	panel.setup_requested.connect(func() -> void: get_tree().change_scene_to_file(SETUP_SCENE))
	panel.result_closed.connect(_closeBattle)

	var names := RoadReferencesScript.names()
	if roadName.is_empty() and not names.is_empty():
		roadName = names[0]
	var loaded := RoadReferencesScript.loadRoad(roadName)
	if not loaded["success"]:
		_notice = "The road could not be loaded: %s" % str(loaded["error"])
		panel.present({"notice": _notice, "can_travel": false})
		return
	road = loaded["road"]
	_loadRegion(str(road["region"]))

	markers = MarkersScript.new()
	markers.name = "RoadMarkers"
	_map.add_child(markers)
	var stopPositions: Array[Vector2] = []
	for stop: Dictionary in road["stops"]:
		stopPositions.append(stop["position"])
	markers.build(road["start"], stopPositions)

	var saved := RoadSaveScript.read(road, saveDirectory)
	if bool(saved["found"]) and bool(saved["ok"]):
		state = saved["state"]
	else:
		state = RoadStateScript.fromRoad(road)
		if bool(saved["found"]):
			_notice = "Saved progress could not be loaded (%s). Playing on will start the road again." % str(saved["error"])
	selectedStop = mini(state.clearedCount, _stopCount() - 1)
	markers.placeToken(state.position)
	_refresh()


func _process(_delta: float) -> void:
	if road.is_empty() or battle != null:
		return
	# The wind moves the cloud field every frame; its shadows follow, as in the debug scene.
	_ground.setCloudField(_clouds.field())
	_props.setCloudShadows(_ground.cloudShadowTexture(), _ground.regionRect().position, _ground.regionRect().size)


func _unhandled_input(event: InputEvent) -> void:
	var click := event as InputEventMouseButton
	if click == null or not click.pressed or click.button_index != MOUSE_BUTTON_LEFT:
		return
	if road.is_empty() or battle != null or _travelling:
		return
	var picked := stopAtScreen(click.position)
	if picked != -1:
		selectedStop = picked
		_refresh()
		get_viewport().set_input_as_handled()


## The stop whose marker is within PICK_RADIUS of `screenPoint`, or -1.
func stopAtScreen(screenPoint: Vector2) -> int:
	var best := -1
	var bestDistance := PICK_RADIUS
	var positions: Array[Vector3] = markers.stopWorldPositions()
	for index in range(positions.size()):
		var distance := stopScreenPosition(index).distance_to(screenPoint)
		if distance <= bestDistance:
			best = index
			bestDistance = distance
	return best


## Where stop `index` is drawn on screen, through the Display's aspect-kept scaling.
func stopScreenPosition(index: int) -> Vector2:
	var positions: Array[Vector3] = markers.stopWorldPositions()
	var inViewport: Vector2 = _camera.unproject_position(positions[index])
	var rect := _display.get_global_rect()
	var bufferSize := Vector2(_viewport.size)
	var fit := minf(rect.size.x / bufferSize.x, rect.size.y / bufferSize.y)
	var drawn := bufferSize * fit
	return rect.position + (rect.size - drawn) * 0.5 + inViewport * fit


## Walks to an open stop and fights there. Refused while travelling or fighting, or for a locked
## stop.
func travelTo(stopIndex: int) -> void:
	if road.is_empty() or battle != null or _travelling:
		return
	if not state.isStopOpen(stopIndex, _stopCount()):
		return
	selectedStop = stopIndex
	_notice = ""
	_travelling = true
	_refresh()
	markers.journeyTo(stopIndex, _openBattle.bind(stopIndex))


func _openBattle(stopIndex: int) -> void:
	_travelling = false
	var attempt: int = state.beginAttempt(stopIndex)
	var controller := RoadBattleScript.CONTROLLER_CPU if autoplay else RoadBattleScript.CONTROLLER_PLAYER
	var composed := RoadBattleScript.compose(state, road, stopIndex, attempt, controller)
	if not composed["ok"]:
		_fail("This stop's battle could not be built: %s" % str(composed["error"]))
		return
	var path := saveDirectory.path_join(BATTLE_FILE)
	var written := RoadBattleScript.writeScenario(composed["scenario"], path)
	if not written["ok"]:
		_fail(str(written["error"]))
		return
	_save()

	battle = load(BATTLE_SCENE).instantiate()
	battle.embedded = true
	add_child(battle)
	var started: Dictionary = battle.startBattle(path, int(composed["seed"]))
	if not bool(started.get("ok", false)):
		var reason: String = battle.startErrorText(started)
		battle.queue_free()
		battle = null
		_fail(reason)
		return
	_tally = RoadBattleScript.Tally.new()
	_tally.attach(battle.sim.events, battle.sim.state)
	battle.battle_completed.connect(_onBattleCompleted)
	battle.leave_requested.connect(_onBattleLeft)
	_battleStop = stopIndex
	_battlePaid = false
	_showMap(false)
	battle_opened.emit(stopIndex)


func _onBattleCompleted(_outcome: int) -> void:
	if battle == null or _battlePaid:
		return
	var summary := RoadBattleScript.summarize(battle.sim.state, _tally.defeats)
	var clearedBefore: int = state.clearedCount
	var report: Dictionary = state.applyBattle(_battleStop, summary)
	_battlePaid = true
	_save()
	panel.showResult(_resultReport(summary, report, clearedBefore))


func _onBattleLeft(_outcome: int) -> void:
	if not _battlePaid:
		_notice = "The company left the battle. Nothing was earned."
	_closeBattle()


func _closeBattle() -> void:
	panel.hideResult()
	if battle != null:
		battle.queue_free()
		battle = null
	_tally = null
	_showMap(true)
	if _battlePaid and str(state.lastReport.get("outcome", "")) == "won":
		selectedStop = mini(state.clearedCount, _stopCount() - 1)
	_battleStop = -1
	_refresh()
	battle_closed.emit(state.lastReport if _battlePaid else {})


func _onFieldToggled(slot: int) -> void:
	_change(state.toggleFielded(slot))


func _onCaptainChosen(slot: int) -> void:
	_change(state.setCommander(slot))


func _onAscend(slot: int) -> void:
	var result: Dictionary = state.ascend(slot)
	if bool(result["ok"]):
		_notice = "%s ascended into %s." % [str(result["from"]), str(result["to"])]
		_save()
	else:
		_notice = str(result["error"]).capitalize()
	_refresh()


func _onStopStepped(step: int) -> void:
	selectedStop = clampi(selectedStop + step, 0, _stopCount() - 1)
	_refresh()


func _onNewRoad() -> void:
	RoadSaveScript.erase(str(road["name"]), saveDirectory)
	state = RoadStateScript.fromRoad(road)
	selectedStop = 0
	markers.placeToken(-1)
	_notice = "Progress erased. The company is back at the start."
	_refresh()


func _change(result: Dictionary) -> void:
	if bool(result["ok"]):
		_notice = ""
		_save()
	else:
		_notice = str(result["error"]).capitalize() + "."
	_refresh()


func _fail(message: String) -> void:
	_notice = message
	_showMap(true)
	_refresh()


func _save() -> void:
	var written := RoadSaveScript.write(state, saveDirectory)
	if not written["ok"]:
		_notice = "Progress could not be saved: %s" % str(written["error"])


func _refresh() -> void:
	if road.is_empty():
		return
	markers.showState(state.clearedCount, selectedStop)
	panel.present(_panelModel())


func _panelModel() -> Dictionary:
	var company: Array = []
	for slot in range(state.company.size()):
		var monsterName: String = state.monsterOf(slot)
		var belief: int = state.beliefOf(slot)
		var level: int = state.levelOf(slot)
		var toNext := RoadRulesScript.beliefToNextLevel(belief)
		var threshold := RoadRulesScript.ascensionThreshold(monsterName)
		var ascendsInto := RoadRulesScript.ascendedFormOf(monsterName)
		company.append({
			"slot": slot,
			"name": monsterName,
			"level": level,
			"belief": belief,
			"belief_text": ("Belief %d, %d to Lv%d" % [belief, toNext, level + 1]) if toNext > 0
				else ("Belief %d, top level" % belief),
			"fielded": state.isFielded(slot),
			"captain": state.commander == slot,
			"can_ascend": state.canAscend(slot),
			"ascends_into": ascendsInto,
			"ascension_text": ("Ascends at %d Belief" % threshold) if threshold > 0 else "",
		})
	var stop: Dictionary = road["stops"][selectedStop]
	var enemies: Array = []
	for party: Dictionary in stop["enemies"]:
		var members: Array = party["members"]
		for index in range(members.size()):
			var member: Dictionary = members[index]
			enemies.append({"name": member["monster"], "level": member["level"], "captain": index == int(party["commander"])})
	var status := "Locked"
	if selectedStop < state.clearedCount:
		status = "Cleared"
	elif selectedStop == state.clearedCount:
		status = "Next"
	var notice := _notice
	if notice.is_empty() and state.isComplete(_stopCount()):
		notice = "Every stop is cleared. A cleared stop can be fought again."
	return {
		"company": company,
		"field_count": state.fielded.size(),
		"field_size": state.fieldSize,
		"stop": {
			"index": selectedStop,
			"count": _stopCount(),
			"map": str(stop["map_path"]).get_file().get_basename(),
			"status_text": status,
			"enemies": enemies,
		},
		"can_travel": state.isStopOpen(selectedStop, _stopCount()) and not _travelling and battle == null,
		"travel_label": "FIGHT AGAIN" if selectedStop < state.clearedCount else "TRAVEL AND FIGHT",
		"notice": notice,
	}


func _resultReport(summary: Dictionary, report: Dictionary, clearedBefore: int) -> Dictionary:
	var titles := {"won": "VICTORY", "lost": "DEFEAT", "draw": "DRAW"}
	var lines: Array[String] = []
	var units: Dictionary = report.get("units", {})
	var slots := units.keys()
	slots.sort()
	for slot in slots:
		var paid: Dictionary = units[slot]
		var line := "%s  +%d Belief" % [state.monsterOf(int(slot)), int(paid["earned"])]
		if int(paid["level_after"]) > int(paid["level_before"]):
			line += ", now Lv%d" % int(paid["level_after"])
		if bool(paid["can_ascend"]):
			line += ", can ascend"
		lines.append(line)
	if state.clearedCount > clearedBefore:
		lines.append("Stop %d is cleared." % (int(report["stop"]) + 1))
	elif str(summary.get("outcome", "")) != "won":
		lines.append("The company holds at stop %d." % (int(report["stop"]) + 1))
	return {"title": titles.get(str(summary.get("outcome", "")), "BATTLE OVER"), "lines": lines}


## Hides the map while a battle runs, so two 3D worlds never render or process at once.
func _showMap(shown: bool) -> void:
	_display.visible = shown
	_viewport.render_target_update_mode = SubViewport.UPDATE_ALWAYS if shown else SubViewport.UPDATE_DISABLED
	_map.process_mode = Node.PROCESS_MODE_INHERIT if shown else Node.PROCESS_MODE_DISABLED
	panel.setVisibleUI(shown)


## How far right, in world units, to aim the camera so the region centres in the part of the screen
## the panel leaves open. Screen x is world x at the rig's fixed yaw; one screen pixel at the frame
## centre spans `2 * centre_depth * tan(fov / 2) / height` units (the debug scene's drag rule).
func _panelShiftUnits() -> float:
	var window := get_viewport().get_visible_rect().size
	if window.y <= 0.0:
		return 0.0
	var pitch := deg_to_rad(float(_framing[Uniforms.K_PITCH]))
	var centreDepth := float(_framing[Uniforms.K_HEIGHT]) / tan(pitch)
	var unitsPerPixel := (centreDepth * 2.0 * tan(deg_to_rad(float(_framing[Uniforms.K_FOV])) * 0.5)) / window.y
	return panel.coveredWidth() * 0.5 * unitsPerPixel


func _stopCount() -> int:
	return (road["stops"] as Array).size()


## The debug controller's region and framing sequence, without its HUD.
func _loadRegion(regionID: String) -> void:
	var region := RegionCatalog.loadRegion(regionID)
	if region.is_empty():
		_notice = "The world map region '%s' could not be loaded." % regionID
		return
	_framing = Uniforms.completeForRegion(
		FramingCatalog.framingFor(FRAMING_PRESET),
		RegionCatalog.fogColorFor(regionID), RegionCatalog.voidColorFor(regionID))
	_framing.merge(FRAMING_OVERRIDES, true)
	_regionMapPx = region["map_px"]
	var billboard := str(_framing.get(Uniforms.K_BILLBOARD, Uniforms.BILLBOARD_OFF))
	var propCounts: Dictionary = _props.rebuild(region["texture"], regionID, billboard)
	_ground.configure(region["tiles"], propCounts["ground"], _framing, region["fog_color"], region["void_color"])
	_clouds.configure(_regionMapPx, _framing)
	_ground.configureCloudShadows(_regionMapPx, str(_framing[Uniforms.K_CLOUDS]))
	_ground.applyFraming(_framing)
	_camera.applyFraming(_framing)
	_sky.applyFraming(_framing, _camera, get_viewport().get_visible_rect().size)
	var rect: Rect2 = _ground.regionRect()
	_camera.panTo(rect.position + rect.size * 0.5 + Vector2(_panelShiftUnits(), 0.0))
	_props.applyFraming(_framing)
	_clouds.applyFraming(_framing)
	_ground.setCloudField(_clouds.field())
	_props.setCloudShadows(_ground.cloudShadowTexture(), rect.position, rect.size)
	var readout: Dictionary = _camera.framingReadout(Vector2i(get_viewport().get_visible_rect().size))
	var buffer: Vector2 = readout["buffer_size"]
	_viewport.size = Vector2i(maxi(int(buffer.x), 2), maxi(int(buffer.y), 2))
