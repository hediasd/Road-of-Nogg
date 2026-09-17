## The authored terrain under the hex battle board.
##
## What this proves: a battle on hexmap puts the exported scene inside the stage's own world at the
## origin; three known cells sit where the editor's grid and the art's region put them; the board
## switches to its alpha-clean battle material and compact slab while its pick bodies still answer;
## every unit receives one contact shadow and one captain per team receives a quiet base finish;
## mouse orbit,
## pan, zoom and reset keep the same projection contract; a cell and a unit under the pointer still
## resolve through the stage at both window sizes and under the harshest preset; a map that cannot
## show its terrain still starts and says why; and teardown leaves no terrain behind.
##
## What it cannot prove: that the board reads well over the art, or that markers stay legible.
## Those are the cycle's rendered checks, and so is how the terrain is lit.
##
## The generated scene is gitignored. On a checkout without it, export hexmap first; see
## docs/DEVELOPMENT.md, "Exporting a map's battle products without the editor".

extends SceneTree

const HexBattleControllerScript = preload("res://src/systems/hex_battle/HexBattleController.gd")
const StageScript = preload("res://src/presentation/battle/HexBattleStage.gd")
const BoardViewScript = preload("res://src/presentation/battle/HexBattleBoardView.gd")
const LayoutScript = preload("res://src/presentation/battle/HexBattleLayout.gd")
const BattleMapFactoryScript = preload("res://src/factories/BattleMapFactory.gd")
const WorldMapHexGridScript = preload("res://src/presentation/worldmap/editor/WorldMapHexGrid.gd")

const HEXMAP_SCENARIO := "res://data/battle/scenarios/hexmap_player_cpu.json"
const HEXMAP_MAP := "res://data/battle/maps/hexmap.json"
const HEADLESS_SCENARIO := "res://data/battle/scenarios/technical_hxb_contract_player_cpu.json"
## A real exported scene for a different lattice (20x10 against hexmap's 15x11).
const FOREIGN_SCENE := "res://scenes/worldmap/generated/proving_ground.tscn"
const ABSENT_SCENE := "res://scenes/worldmap/generated/fhb7_probe_absent.tscn"
const FIXTURE_DIR := "user://fhb7_board_terrain"
const SEED := 42

## Corners and a middle cell. (0, 0) is the art's own origin corner, (7, 5) an odd column that
## takes the half-cell drop, (14, 10) the far corner, also odd.
const ALIGNMENT_CELLS: Array[Vector2i] = [Vector2i(0, 0), Vector2i(7, 5), Vector2i(14, 10)]
## Interior cells for screen picking, so none can fall outside a framed view.
const PICK_CELLS: Array[Vector2i] = [Vector2i(3, 3), Vector2i(7, 5), Vector2i(11, 7)]
const SCREENS: Array[Vector2i] = [Vector2i(1280, 720), Vector2i(1920, 1080)]
const EPSILON := 0.0001

var failures: Array[String] = []
var _controller: HexBattleController
var _evidence: Dictionary = {}


func _init() -> void:
	process_frame.connect(_run, CONNECT_ONE_SHOT)


func _run() -> void:
	root.size = SCREENS[0]
	_controller = HexBattleControllerScript.new()
	root.add_child(_controller)
	await _frames(1)

	await _checkAuthoredTerrain()
	await _checkHeadlessOnlyMap()
	await _checkUndrawableSceneStillStarts()
	await _checkAbsentScene()
	await _checkTeardown()
	_report()


func _report() -> void:
	print("HXB_BOARD_TERRAIN_EVIDENCE %s" % JSON.stringify(_evidence))
	if _controller != null:
		_controller.teardownBattle()
	if not failures.is_empty():
		for failure: String in failures:
			printerr("HXB_BOARD_TERRAIN_FAILURE: %s" % failure)
		quit(1)
		return
	print("HXB_BOARD_TERRAIN_OK")
	quit(0)


func _require(condition: bool, message: String) -> void:
	if not condition and not failures.has(message):
		failures.append(message)


func _frames(count: int) -> void:
	for _index in range(count):
		await process_frame


func _physicsFrames(count: int) -> void:
	for _index in range(count):
		await physics_frame


# --- authored terrain ---------------------------------------------------------

func _checkAuthoredTerrain() -> void:
	var started := _controller.startBattle(HEXMAP_SCENARIO, SEED)
	_require(bool(started.get("ok", false)), "hexmap did not start: %s" % str(started))
	if not bool(started.get("ok", false)):
		return
	# Freeze the battle so nothing moves while cells and units are picked.
	_controller.togglePause()
	await _frames(2)
	await _physicsFrames(2)

	var stage: HexBattleStage = _controller.stage
	var map := _controller.map
	var terrain: Node3D = stage.terrainRoot()
	var report: Dictionary = started.get("terrain", {})
	_evidence["hexmap_terrain"] = report
	_require(str(report.get("status", "")) == StageScript.TERRAIN_LOADED,
		"hexmap terrain did not load: %s (re-export hexmap if the scene is missing)" % str(report))
	_require(_controller.terrainNotice().is_empty(), "a loaded terrain still showed a notice")
	if terrain == null:
		return

	# Inside the stage's isolated world, at the origin, uncorrected.
	_require(terrain.get_parent() == stage.worldRoot(), "terrain is not under the stage world root")
	_require(terrain.get_world_3d() == stage.renderer.world_viewport.find_world_3d() \
			and terrain.get_world_3d() != root.find_world_3d(),
		"terrain is not in the stage's own World3D")
	_require(terrain.global_transform.is_equal_approx(Transform3D.IDENTITY),
		"terrain was offset: %s" % str(terrain.global_transform))
	_require(_countNamed(root, StageScript.TERRAIN_NODE_NAME) == 1,
		"expected exactly one terrain in the tree")

	var ground := terrain.get_node_or_null("Ground") as MeshInstance3D
	_require(ground != null, "the exported scene has no Ground")
	if ground == null:
		return
	var material := ground.material_override as ShaderMaterial
	_require(material != null, "the exported ground lost its material")
	if material == null:
		return
	var regionOrigin: Vector2 = material.get_shader_parameter("region_origin")
	var regionSize: Vector2 = material.get_shader_parameter("region_size")
	var lattice := WorldMapHexGridScript.latticeExtent(map.boardSize.x, map.boardSize.y)
	_evidence["region"] = {"origin": str(regionOrigin), "size": str(regionSize),
		"lattice": str(lattice)}
	_require(regionOrigin.is_equal_approx(Vector2.ZERO), "the art region does not start at 0,0")
	_require(regionSize.is_equal_approx(lattice),
		"the art region %s is not the map's lattice %s" % [regionSize, lattice])

	var layout := LayoutScript.new(map)
	var boardView: HexBattleBoardView = _controller.adapter.boardView
	var alignment: Array = []
	for cell: Vector2i in ALIGNMENT_CELLS:
		_require(map.containsCell(cell), "alignment cell %s is not on hexmap" % cell)
		var center := layout.cellCenter(cell)
		var editorCentre := WorldMapHexGridScript.cellCentre(cell)
		_require(is_equal_approx(center.x, editorCentre.x) and is_equal_approx(center.z, editorCentre.y),
			"cell %s: battle centre %s is not the editor's %s" % [cell, center, editorCentre])
		# Where the ground shader samples the art for this point, as a fraction of the region.
		var uv := (Vector2(center.x, center.z) - regionOrigin) / regionSize
		var expectedUV := editorCentre / lattice
		_require(uv.is_equal_approx(expectedUV) and uv.x > 0.0 and uv.x < 1.0 \
				and uv.y > 0.0 and uv.y < 1.0,
			"cell %s samples the art at %s, not the editor's %s" % [cell, uv, expectedUV])
		# Straight down onto the cell: the pick body still answers with terrain present.
		var hit := _castDown(stage, center, BoardViewScript.PICK_COLLISION_LAYER)
		_require(_coordOf(hit) == cell, "a ray straight down on %s hit %s" % [cell, _coordOf(hit)])
		alignment.append({"cell": str(cell), "centre": str(center), "uv": str(uv)})
	_evidence["alignment"] = alignment

	# Nothing in the terrain rises above the board, and the lattice sits above the ground.
	var groundTop := (ground.global_transform * ground.get_aabb()).end.y
	var lowestCell := INF
	for cell: Vector2i in map.validCells():
		lowestCell = minf(lowestCell, layout.cellCenter(cell).y)
	_require(groundTop <= lowestCell + EPSILON,
		"the ground top %.4f is above the lowest cell %.4f" % [groundTop, lowestCell])

	# The board over terrain: fallback fill hidden, passive grid moved to the terrain shader, compact
	# slab beneath it, and pick bodies still live.
	_require(boardView.isOverTerrain(), "the board did not switch to its over-terrain look")
	_require(boardView.outlineMesh() == null, "the legacy world-space outline mesh still exists")
	var slab := boardView.boardSlab()
	_require(slab != null and slab.is_inside_tree() and slab.visible,
		"the compact board slab is missing")
	if slab != null:
		var slabBounds := slab.global_transform * slab.get_aabb()
		_require(slabBounds.end.y > groundTop + 0.05,
			"the raised rim does not rise above the terrain: %.4f / %.4f" % [
				slabBounds.end.y, groundTop])
		_require(slabBounds.position.y < groundTop - 0.5,
			"the floating board wall is too shallow: %s" % str(slabBounds.size))
		var maximumBoardSize := regionSize + Vector2.ONE * (
			boardView.BOARD_TOTAL_MARGIN * 2.0 + 0.1)
		_require(slabBounds.size.x <= maximumBoardSize.x \
				and slabBounds.size.z <= maximumBoardSize.y,
			"the raised board extends beyond its authored rim: %s" % str(slabBounds.size))
		_require(slabBounds.size.x > regionSize.x + boardView.BOARD_RIM_WIDTH \
				and slabBounds.size.z > regionSize.y + boardView.BOARD_RIM_WIDTH,
			"the raised board rim is not broad enough: %s" % str(slabBounds.size))
	var surface := boardView.getSurface(PICK_CELLS[0])
	_require(surface != null and not surface.visible, "the grey fill is still drawn over terrain")
	_require(stage.battleTerrainMaterial() == material,
		"the ground does not use the battle-only terrain material")
	_require(material.get_shader_parameter("terrain_texture") != null,
		"the battle material has no painted texture")
	_require((material.get_shader_parameter("hex_lattice") as Vector2).is_equal_approx(
			Vector2(map.boardSize)), "the battle material has the wrong hex lattice")
	_require(is_equal_approx(float(material.get_shader_parameter("grid_line_px")),
			StageScript.TERRAIN_GRID_LINE_PX), "the passive grid is not one screen pixel")
	var gridColor: Color = material.get_shader_parameter("grid_color")
	_require(gridColor.a <= 0.15, "the passive grid is too opaque: %.3f" % gridColor.a)
	_require(is_equal_approx(float(material.get_shader_parameter("alpha_cutoff")),
			StageScript.TERRAIN_ALPHA_CUTOFF), "transparent texture gaps are not clipped")
	var plane := ground.mesh as PlaneMesh
	if plane != null:
		_require(plane.size.is_equal_approx(regionSize),
			"the flat exported ground still has its giant fog plane: %s" % str(plane.size))

	# Quiet hover is one reused marker, not a permanent second grid.
	boardView.showHover(PICK_CELLS[0])
	_require(boardView.hoveredCell() == PICK_CELLS[0] \
			and boardView.get_node_or_null(boardView.HOVER_NODE_NAME) != null,
		"the quiet cell hover did not appear")
	boardView.clearHover()
	_require(boardView.hoveredCell() == Vector2i(-1, -1), "the quiet cell hover did not clear")

	_checkUnitDecorators()
	await _checkCameraControls()

	# Anything in the terrain that collides would sit in front of the pick bodies. It must not.
	var unmasked := _castDown(stage, layout.cellCenter(PICK_CELLS[1]), 0xFFFFFFFF)
	_require(_coordOf(unmasked) == PICK_CELLS[1],
		"an unmasked ray hit something other than the board: %s" % str(unmasked.get("collider")))

	await _checkScreenPicking(stage, layout)
	root.size = SCREENS[0]
	stage.renderer.set_preset(stage.renderer.PRESET_NONE, false)
	await _frames(2)


## Through the stage's projection at both sizes and both presets: the controller's own cell pick,
## a physics ray from the stage's picking ray, and the unit a hover would inspect.
func _checkScreenPicking(stage: HexBattleStage, layout: HexBattleLayout) -> void:
	var presets := [stage.renderer.PRESET_NONE, "harsh"]
	var unitID := -1
	for value in _controller.adapter.shownModelIDs():
		unitID = int(value)
		break
	_require(unitID != -1, "no unit is shown on the hexmap board")
	var picks: Array = []
	for size: Vector2i in SCREENS:
		root.size = size
		await _frames(2)
		for preset in presets:
			_applyLook(stage.renderer, preset)
			await _frames(2)
			await _physicsFrames(1)
			for cell: Vector2i in PICK_CELLS:
				var point := stage.projectWorldToScreen(layout.cellCenter(cell))
				var label := "%s at %s / %s" % [cell, size, preset]
				_require(point.x >= 0.0 and stage.displayRect().has_point(point),
					"%s projected off the display" % label)
				_require(_controller._cellAtPoint(point) == cell,
					"the controller picked %s for %s" % [_controller._cellAtPoint(point), label])
				var ray := stage.pickingRay(point)
				_require(not ray.is_empty(), "no picking ray for %s" % label)
				if not ray.is_empty():
					var query := PhysicsRayQueryParameters3D.create(
						ray["origin"], ray["end"], BoardViewScript.PICK_COLLISION_LAYER)
					var hit: Dictionary = (ray["space"] as PhysicsDirectSpaceState3D).intersect_ray(query)
					_require(_coordOf(hit) == cell,
						"the stage ray hit %s for %s" % [_coordOf(hit), label])
			if unitID != -1:
				var unitCell := _controller.adapter.displayedPosition(unitID)
				var unitPoint := stage.projectWorldToScreen(layout.cellCenter(unitCell))
				_require(_controller._unitAtPoint(unitPoint) == unitID,
					"hovering unit %d's cell %s at %s / %s picked %d" % [
						unitID, unitCell, size, preset, _controller._unitAtPoint(unitPoint)])
			picks.append("%s/%s" % [size, preset])
	_evidence["screen_picks"] = picks


func _checkUnitDecorators() -> void:
	var shadows := 0
	var captainBases := 0
	var teamIDs: Dictionary = {}
	for value in _controller.adapter.shownModelIDs():
		var monsterID := int(value)
		var model := _controller.adapter.modelFor(monsterID)
		_require(model != null, "shown unit %d has no model" % monsterID)
		if model == null:
			continue
		_require(model.scale.is_equal_approx(
			Vector3.ONE * _controller.adapter.UNIT_PRESENTATION_SCALE),
			"unit %d does not retain the battle presentation scale" % monsterID)
		var modelBase := model.get_node_or_null("ModelBase") as Node3D
		_require(modelBase != null, "unit %d has no model base" % monsterID)
		if modelBase != null:
			_require(modelBase.scale.is_equal_approx(Vector3(
				_controller.adapter.UNIT_BASE_WIDTH_SCALE, 1.0,
				_controller.adapter.UNIT_BASE_WIDTH_SCALE)),
				"unit %d does not retain the slightly wider battle base" % monsterID)
		var shadow := model.get_node_or_null(_controller.adapter.GROUND_SHADOW_NAME)
		_require(shadow != null, "unit %d has no contact shadow" % monsterID)
		if shadow != null:
			shadows += 1
		var party: BattleParty = _controller.sim.state.partyForMember(monsterID)
		if party != null:
			teamIDs[party.teamID] = true
		var isCaptain := _controller.adapter.isTeamCaptain(monsterID)
		var markedCaptain := bool(model.get_meta(_controller.adapter.TEAM_CAPTAIN_META, false))
		_require(isCaptain == markedCaptain,
			"unit %d's team-captain marker disagrees with selection" % monsterID)
		_require(model.get_node_or_null("CommanderAccent") == null,
			"unit %d still has the retired extra commander ring" % monsterID)
		if markedCaptain:
			captainBases += 1
	_evidence["unit_decorators"] = {
		"models": _controller.adapter.shownModelIDs().size(),
		"shadows": shadows,
		"captain_bases": captainBases,
		"teams": teamIDs.size(),
	}
	_require(captainBases == teamIDs.size(),
		"expected one shaded captain base per team, found %d for %d teams" % [
			captainBases, teamIDs.size()])


func _checkCameraControls() -> void:
	var battleCamera: HexBattleCamera = _controller.battleCamera
	_require(battleCamera.camera.projection == Camera3D.PROJECTION_ORTHOGONAL,
		"the battle camera did not open in orthographic projection")
	_require(battleCamera.camera.position.length() \
		>= battleCamera.ORTHOGRAPHIC_CAMERA_DISTANCE - 0.01,
		"the orthographic camera is not safely behind the rotating board")
	var originalYaw := battleCamera.yaw()
	var originalPitch := battleCamera.pitchDegrees()
	var originalSize := battleCamera.orthographicSize()
	var originalFocus := battleCamera.focus()

	var middlePress := InputEventMouseButton.new()
	middlePress.button_index = MOUSE_BUTTON_MIDDLE
	middlePress.pressed = true
	_require(battleCamera.handleInput(middlePress, float(SCREENS[0].y)),
		"middle press was not owned by the camera")
	var orbitMotion := InputEventMouseMotion.new()
	orbitMotion.relative = Vector2(24.0, 12.0)
	_require(battleCamera.handleInput(orbitMotion, float(SCREENS[0].y)),
		"middle drag was not owned by the camera")
	await _frames(2)
	_require(not is_equal_approx(battleCamera.yaw(), originalYaw) \
			and not is_equal_approx(battleCamera.pitchDegrees(), originalPitch),
		"middle drag did not orbit and pitch")
	var middleRelease := InputEventMouseButton.new()
	middleRelease.button_index = MOUSE_BUTTON_MIDDLE
	middleRelease.pressed = false
	battleCamera.handleInput(middleRelease, float(SCREENS[0].y))

	var rightPress := InputEventMouseButton.new()
	rightPress.button_index = MOUSE_BUTTON_RIGHT
	rightPress.pressed = true
	battleCamera.handleInput(rightPress, float(SCREENS[0].y))
	var panMotion := InputEventMouseMotion.new()
	panMotion.relative = Vector2(18.0, -10.0)
	battleCamera.handleInput(panMotion, float(SCREENS[0].y))
	await _frames(2)
	_require(not battleCamera.focus().is_equal_approx(originalFocus), "right drag did not pan")
	var rightRelease := InputEventMouseButton.new()
	rightRelease.button_index = MOUSE_BUTTON_RIGHT
	rightRelease.pressed = false
	battleCamera.handleInput(rightRelease, float(SCREENS[0].y))

	var wheel := InputEventMouseButton.new()
	wheel.button_index = MOUSE_BUTTON_WHEEL_UP
	wheel.pressed = true
	battleCamera.handleInput(wheel, float(SCREENS[0].y))
	_require(battleCamera.orthographicSize() < originalSize, "wheel up did not zoom in")

	battleCamera.resetView()
	await create_timer(battleCamera.CAMERA_EASE_SECONDS + 0.05).timeout
	_require(is_equal_approx(battleCamera.yaw(), originalYaw), "camera reset did not restore yaw")
	_require(is_equal_approx(battleCamera.pitchDegrees(), originalPitch),
		"camera reset did not restore pitch")
	_require(is_equal_approx(battleCamera.orthographicSize(), originalSize),
		"camera reset did not restore zoom")
	_require(battleCamera.focus().is_equal_approx(originalFocus),
		"camera reset did not restore focus")
	_evidence["camera_mouse"] = "orbit/pitch, pan, wheel zoom, eased reset"


# --- maps without drawable terrain ----------------------------------------------

## A technical map declares no scene. It starts on the grey board and says nothing about terrain.
func _checkHeadlessOnlyMap() -> void:
	var started := _controller.startBattle(HEADLESS_SCENARIO, SEED)
	_require(bool(started.get("ok", false)), "the headless-only map did not start")
	if not bool(started.get("ok", false)):
		return
	await _frames(2)
	var report: Dictionary = started.get("terrain", {})
	_evidence["headless_only"] = report
	_require(str(report.get("status", "")) == StageScript.TERRAIN_HEADLESS_ONLY,
		"a map with no declared scene reported %s" % str(report))
	_require(_controller.terrainNotice().is_empty(), "a headless-only map showed a terrain notice")
	_require(_controller.stage.terrainRoot() == null, "a headless-only map drew terrain")
	_require(not _controller.adapter.boardView.isOverTerrain(),
		"a headless-only board switched to the over-terrain look")
	_require(_controller.adapter.boardView.boardSlab() != null,
		"a headless-only board has no compact slab")
	var cell: Vector2i = _controller.map.validCells()[0]
	var surface := _controller.adapter.boardView.getSurface(cell)
	_require(surface != null and surface.visible, "the grey board is not drawn without terrain")


## A map naming a scene that exists but cannot line up with it. Reachable through the real factory
## today, so it is the case that proves a battle starts, keeps the grey board, still picks, and
## keeps saying why after the battle's own status lines arrive.
func _checkUndrawableSceneStillStarts() -> void:
	var paths := _writeFixture("mismatched", FOREIGN_SCENE)
	if paths.is_empty():
		return
	var started := _controller.startBattle(paths["scenario"], SEED)
	_require(bool(started.get("ok", false)),
		"a map whose scene cannot be drawn refused to start: %s" % str(started))
	if not bool(started.get("ok", false)):
		return
	_controller.togglePause()
	await _frames(2)
	await _physicsFrames(2)
	var report: Dictionary = started.get("terrain", {})
	_evidence["mismatched"] = report
	var notice := _controller.terrainNotice()
	_require(str(report.get("status", "")) == StageScript.TERRAIN_MISMATCHED,
		"a scene for another lattice reported %s" % str(report))
	_require(notice.contains("Re-export") and notice.contains(FOREIGN_SCENE),
		"the notice does not say what to re-export: '%s'" % notice)
	_require(_controller.hud.statusText().contains(notice), "the status line does not show the notice")
	_controller._setStatus("Your party is up.")
	_require(_controller.hud.statusText().contains("Your party is up.") \
			and _controller.hud.statusText().contains(notice),
		"a battle status line replaced the terrain notice")
	_require(_controller.stage.terrainRoot() == null and _countNamed(root, StageScript.TERRAIN_NODE_NAME) == 0,
		"a mismatched scene was put in the world")
	_require(not _controller.adapter.boardView.isOverTerrain(), "the board left its grey look")
	var layout := LayoutScript.new(_controller.map)
	var cell := PICK_CELLS[1]
	var point := _controller.stage.projectWorldToScreen(layout.cellCenter(cell))
	_require(_controller._cellAtPoint(point) == cell, "picking failed on the grey fallback board")
	_require(_coordOf(_castDown(_controller.stage, layout.cellCenter(cell),
			BoardViewScript.PICK_COLLISION_LAYER)) == cell,
		"the grey fallback board's pick body did not answer")


## A map naming a scene that is not on disk: the fresh-checkout case. The stage handles it as a
## normal state, and BattleMapFactory accepts such a map, so this runs the full start.
func _checkAbsentScene() -> void:
	_require(not ResourceLoader.exists(ABSENT_SCENE), "the absent probe scene exists")
	var loaded := BattleMapFactoryScript.loadFromPath(HEXMAP_MAP)
	if not bool(loaded.get("success", false)):
		failures.append("hexmap did not load for the absent-scene check")
		return
	var map: BattleMapDefinition = loaded["definition"]
	map.visualScenePath = ABSENT_SCENE
	var stage := StageScript.new()
	root.add_child(stage)
	await _frames(1)
	var report := stage.loadTerrain(map)
	_evidence["absent_stage"] = report
	_require(str(report.get("status", "")) == StageScript.TERRAIN_MISSING,
		"an absent scene reported %s" % str(report))
	_require(str(report.get("notice", "")).contains("Re-export map 'hexmap'"),
		"the absent-scene notice does not name the map to re-export")
	_require(not stage.hasTerrain(), "an absent scene left a terrain node")
	stage.dispose()
	await _frames(2)

	var paths := _writeFixture("absent", ABSENT_SCENE)
	if paths.is_empty():
		return
	var factory := BattleMapFactoryScript.loadFromPath(paths["map"])
	_require(bool(factory.get("success", false)),
		"the factory refused a map with an absent scene: %s" % str(factory.get("error", "")))
	if not bool(factory.get("success", false)):
		_evidence["absent_factory"] = "refused: %s" % str(factory.get("error", ""))
		return
	_evidence["absent_factory"] = "accepted"
	var started := _controller.startBattle(paths["scenario"], SEED)
	_require(bool(started.get("ok", false)), "a map with an unexported scene refused to start")
	if bool(started.get("ok", false)):
		await _frames(2)
		_require(str((started.get("terrain", {}) as Dictionary).get("status", "")) \
				== StageScript.TERRAIN_MISSING, "an unexported scene did not report missing")
		_require(_controller.hud.statusText().contains("Re-export"),
			"the status line does not say to re-export")


# --- teardown -----------------------------------------------------------------

func _checkTeardown() -> void:
	for _index in range(2):
		var started := _controller.startBattle(HEXMAP_SCENARIO, SEED)
		_require(bool(started.get("ok", false)), "hexmap did not restart")
		await _frames(3)
		_require(_countNamed(root, StageScript.TERRAIN_NODE_NAME) == 1,
			"a restart left %d terrains" % _countNamed(root, StageScript.TERRAIN_NODE_NAME))
	_controller.returnToSetup()
	await _frames(3)
	_require(_countNamed(root, StageScript.TERRAIN_NODE_NAME) == 0, "terrain survived return to setup")
	_require(_controller.terrainNotice().is_empty(), "a terrain notice survived return to setup")


# --- helpers ------------------------------------------------------------------

func _castDown(stage: HexBattleStage, point: Vector3, mask: int) -> Dictionary:
	var space := stage.worldRoot().get_world_3d().direct_space_state
	var query := PhysicsRayQueryParameters3D.create(
		point + Vector3(0.0, 50.0, 0.0), point - Vector3(0.0, 50.0, 0.0), mask)
	return space.intersect_ray(query)


func _coordOf(hit: Dictionary) -> Vector2i:
	var collider = hit.get("collider")
	if collider is Node and (collider as Node).has_meta(BoardViewScript.BATTLE_COORD_META):
		return (collider as Node).get_meta(BoardViewScript.BATTLE_COORD_META)
	return Vector2i(-1, -1)


func _countNamed(node: Node, wanted: String) -> int:
	var result := 1 if node.name == wanted else 0
	for child: Node in node.get_children():
		result += _countNamed(child, wanted)
	return result


## Copies of hexmap and its player scenario under user://, with the map naming `scenePath`.
func _writeFixture(tag: String, scenePath: String) -> Dictionary:
	DirAccess.make_dir_recursive_absolute(FIXTURE_DIR)
	var mapRaw := _readArray(HEXMAP_MAP)
	var scenarioRaw := _readArray(HEXMAP_SCENARIO)
	if mapRaw.is_empty() or scenarioRaw.is_empty():
		failures.append("could not read the hexmap fixtures")
		return {}
	var mapPath := "%s/%s_map.json" % [FIXTURE_DIR, tag]
	var scenarioPath := "%s/%s_scenario.json" % [FIXTURE_DIR, tag]
	(mapRaw[0]["SOURCE"] as Dictionary)["VISUAL_SCENE_PATH"] = scenePath
	(scenarioRaw[0]["MAP"] as Dictionary)["PATH"] = mapPath
	scenarioRaw[0]["NAME"] = "fhb7_%s" % tag
	if not _writeJson(mapPath, mapRaw) or not _writeJson(scenarioPath, scenarioRaw):
		failures.append("could not write the %s fixture" % tag)
		return {}
	return {"map": mapPath, "scenario": scenarioPath}


func _readArray(path: String) -> Array:
	var file := FileAccess.open(path, FileAccess.READ)
	if file == null:
		return []
	var parsed = JSON.parse_string(file.get_as_text())
	return parsed if parsed is Array else []


func _writeJson(path: String, value) -> bool:
	var file := FileAccess.open(path, FileAccess.WRITE)
	if file == null:
		return false
	file.store_string(JSON.stringify(value, "\t"))
	return true


## The harshest look the drawer can reach: CRT at the smallest low-res target. The named retro
## presets it replaces are gone; this is what a projection has to survive now.
func _applyLook(renderer, look: String) -> void:
	if look == "harsh":
		renderer.set_preset(renderer.PRESET_SATURATED_CRT, false)
		renderer.set_low_res(true, Vector2i(320, 240), false)
		renderer.set_features(true, true, false)
	else:
		renderer.set_preset(look, false)
