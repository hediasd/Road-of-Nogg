## The authored terrain under the hex battle board.
##
## What this proves: a battle on hexmap puts the exported scene inside the stage's own world at the
## origin; three known cells sit where the editor's grid and the art's region put them; the board
## switches to its outline look while its pick bodies still answer; a cell and a unit under the
## pointer still resolve through the stage at both window sizes and under the harshest preset; a map
## that cannot show its terrain still starts and says why; and teardown leaves no terrain behind.
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

	# The board over terrain: fill hidden, outlines drawn, bodies still live.
	_require(boardView.isOverTerrain(), "the board did not switch to its over-terrain look")
	var outlines := boardView.outlineMesh()
	_require(outlines != null and outlines.is_inside_tree() and outlines.visible,
		"the over-terrain outline mesh is missing")
	if outlines != null:
		_require(outlines.global_position.y + boardView.OUTLINE_LIFT > groundTop,
			"the outlines are not above the ground")
	var surface := boardView.getSurface(PICK_CELLS[0])
	_require(surface != null and not surface.visible, "the grey fill is still drawn over terrain")

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
	var presets := [stage.renderer.PRESET_NONE, stage.renderer.PRESET_DITHERED_HORIZON]
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
			stage.renderer.set_preset(preset, false)
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
## normal state. Whether a battle can reach the stage with it depends on BattleMapFactory, which
## refuses such a map at load today; this records which, and runs the full start when it can.
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
	if not bool(factory.get("success", false)):
		# Outside the board and stage. Evidence, not a failure, so the probe starts asserting the full
		# start on its own once the factory accepts a declared scene that has not been exported.
		_evidence["absent_factory"] = "refused: %s" % str(factory.get("error", ""))
		print("HXB_BOARD_TERRAIN_FACTORY_REFUSES_ABSENT_SCENE %s" % str(factory.get("error", "")))
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
