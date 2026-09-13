## Owns the hex battle's isolated render world and its screen/world conversion boundary.
## Native-resolution UI is deliberately parented beside this node, never below `worldRoot()`.

class_name HexBattleStage
extends Node

const RetroRenderControllerScript = preload("res://src/presentation/RetroRenderController.gd")
const BattleEnvironmentFactoryScript = preload("res://src/presentation/BattleEnvironmentFactory.gd")
const HexGraphicsPanelScript = preload("res://src/presentation/battle/ui/HexGraphicsPanel.gd")
const SKY_SHADER = preload("res://assets/textures/sky/retro_sky_2d.gdshader")
const BattleMapAssetManifestScript = preload(
	"res://src/presentation/battle/BattleMapAssetManifest.gd")

const LIGHT_ROTATION := Vector3(-45.0, 45.0, 0.0)
const LIGHT_COLOR := Color.WHITE
const LIGHT_ENERGY := 1.0

const TERRAIN_NODE_NAME := "BattleTerrain"
## What `loadTerrain` found. Only LOADED puts anything in the world. HEADLESS_ONLY is a map that
## declares no scene on purpose and needs no notice; the other three are a map that should have
## terrain and does not, and each carries a notice saying to re-export.
const TERRAIN_LOADED := "loaded"
const TERRAIN_HEADLESS_ONLY := "headless_only"
const TERRAIN_MISSING := "missing"
const TERRAIN_UNREADABLE := "unreadable"
const TERRAIN_MISMATCHED := "mismatched"
## Stamped on every exported scene root by the world-map export. The lattice size is the alignment
## contract: a scene exported for a different lattice cannot line up cell for cell, however it is
## placed, so it is refused rather than drawn wrong.
const SCENE_CELLS_META := "worldmap_cells"

var renderer: RetroRenderController
var graphicsPanel: HexGraphicsPanel
var environment: WorldEnvironment
var light: DirectionalLight3D

var _camera: HexBattleCamera
var _disposed := false
var _terrain: Node3D
var _terrainReport: Dictionary = {}


func _ready() -> void:
	name = "HexBattleStage"
	renderer = RetroRenderControllerScript.new(self)
	_buildSky()
	environment = WorldEnvironment.new()
	environment.name = "BattleEnvironment"
	environment.environment = BattleEnvironmentFactoryScript.createBattleEnvironment()
	renderer.world_root.add_child(environment)
	light = DirectionalLight3D.new()
	light.name = "BattleKeyLight"
	light.rotation_degrees = LIGHT_ROTATION
	light.light_color = LIGHT_COLOR
	light.light_energy = LIGHT_ENERGY
	light.shadow_enabled = false
	renderer.world_root.add_child(light)
	graphicsPanel = HexGraphicsPanelScript.new(renderer)
	add_child(graphicsPanel)


func _buildSky() -> void:
	var skyCanvas := CanvasLayer.new()
	skyCanvas.name = "BattleSky"
	skyCanvas.layer = -1
	renderer.world_viewport.add_child(skyCanvas)
	var background := ColorRect.new()
	background.name = "AnimatedSky"
	background.mouse_filter = Control.MOUSE_FILTER_IGNORE
	background.set_anchors_preset(Control.PRESET_FULL_RECT)
	var material := ShaderMaterial.new()
	material.shader = SKY_SHADER
	background.material = material
	skyCanvas.add_child(background)


func worldRoot() -> Node3D:
	return renderer.world_root if renderer != null else null


## Puts the map's exported scene into this world, at the origin, and reports what happened.
##
## AT THE ORIGIN, WITH NO CORRECTION. `HexBattleLayout` and the editor's `WorldMapHexGrid` place a
## cell at the same region-local X/Z, and the export places its art from the region origin. If the
## two ever disagree the fault is in one of them, and an offset here would hide it.
##
## A MISSING SCENE IS NORMAL. Generated scenes are gitignored, so a fresh checkout has none. The
## battle goes on with the grey board, and the report's `notice` says what to re-export. Returns
## `{status, path, notice}`; `notice` is empty when the terrain loaded or the map has none by design.
func loadTerrain(map: BattleMapDefinition) -> Dictionary:
	_clearTerrain()
	var path := map.visualScenePath if map != null else ""
	var mapID := map.mapID if map != null else ""
	if path.is_empty():
		return _reportTerrain(TERRAIN_HEADLESS_ONLY, path, "")
	if not ResourceLoader.exists(path):
		return _reportTerrain(TERRAIN_MISSING, path,
			"No terrain: %s has not been exported here. Re-export map '%s'." % [path, mapID])
	var packed := load(path) as PackedScene
	var instance: Node = packed.instantiate() if packed != null else null
	if not instance is Node3D or not instance.has_meta(SCENE_CELLS_META):
		if instance != null:
			instance.free()
		return _reportTerrain(TERRAIN_UNREADABLE, path,
			"No terrain: %s is not an exported map scene. Re-export map '%s'." % [path, mapID])
	var sourceMeta := BattleMapAssetManifestScript.SCENE_SOURCE_META
	var expectedSource := BattleMapAssetManifestScript.authoredPathFor(map.sourceID)
	var cellsDisagree: bool = instance.get_meta(SCENE_CELLS_META) != map.boardSize
	var sourceDisagrees := instance.has_meta(sourceMeta) \
		and str(instance.get_meta(sourceMeta)) != expectedSource
	if cellsDisagree or sourceDisagrees:
		instance.free()
		return _reportTerrain(TERRAIN_MISMATCHED, path,
			"No terrain: %s was exported from a different map. Re-export map '%s'." % [path, mapID])
	_terrain = instance as Node3D
	_terrain.name = TERRAIN_NODE_NAME
	_terrain.transform = Transform3D.IDENTITY
	renderer.world_root.add_child(_terrain)
	return _reportTerrain(TERRAIN_LOADED, path, "")


func terrainRoot() -> Node3D:
	return _terrain if is_instance_valid(_terrain) else null


func hasTerrain() -> bool:
	return terrainRoot() != null


func terrainReport() -> Dictionary:
	return _terrainReport.duplicate()


func _reportTerrain(status: String, path: String, notice: String) -> Dictionary:
	_terrainReport = {"status": status, "path": path, "notice": notice}
	if not notice.is_empty():
		push_warning(notice)
	return _terrainReport.duplicate()


func _clearTerrain() -> void:
	if is_instance_valid(_terrain):
		if _terrain.get_parent() != null:
			_terrain.get_parent().remove_child(_terrain)
		_terrain.queue_free()
	_terrain = null
	_terrainReport = {}


func attachCamera(value: HexBattleCamera) -> void:
	_camera = value
	if _camera != null:
		_camera.setScreenConverter(Callable(renderer, "world_to_screen"))


## Projects a 3D point into native host-viewport coordinates. Downstream overlays use this,
## never their own letterbox arithmetic, so every preset and resize shares the same answer.
func projectWorldToScreen(worldPosition: Vector3) -> Vector2:
	if _camera == null or renderer == null:
		return Vector2(-1.0, -1.0)
	var renderPoint := _camera.projectToRenderViewport(worldPosition)
	if renderPoint.x < 0.0:
		return renderPoint
	return renderer.world_to_screen(renderPoint)


## Converts a native host-viewport point to the isolated render viewport. Negative coordinates
## mean the point is in a letterbox margin and must not be picked.
func screenToRenderViewport(screenPosition: Vector2) -> Vector2:
	return renderer.screen_to_world(screenPosition) if renderer != null else Vector2(-1.0, -1.0)


## Builds a ray in the isolated world's physics space. An empty result means letterbox/outside.
func pickingRay(screenPosition: Vector2, length: float = 1000.0) -> Dictionary:
	if _camera == null or renderer == null:
		return {}
	var renderPoint := screenToRenderViewport(screenPosition)
	if renderPoint.x < 0.0:
		return {}
	var origin := _camera.camera.project_ray_origin(renderPoint)
	return {
		"origin": origin,
		"end": origin + _camera.camera.project_ray_normal(renderPoint) * length,
		"space": renderer.world_root.get_world_3d().direct_space_state,
	}


func displayRect() -> Rect2:
	return renderer.get_display_rect() if renderer != null else Rect2()


func dispose() -> void:
	if _disposed:
		return
	_disposed = true
	if _camera != null:
		_camera.setScreenConverter(Callable())
		_camera = null
	if renderer != null and renderer.host != null:
		var viewport := renderer.host.get_viewport()
		if viewport != null and viewport.size_changed.is_connected(
				renderer._on_main_viewport_size_changed):
			viewport.size_changed.disconnect(renderer._on_main_viewport_size_changed)
	# Detach immediately so a same-frame battle restart cannot have two active render worlds;
	# queued deletion still avoids freeing this node during an input/lifecycle callback.
	if get_parent() != null:
		get_parent().remove_child(self)
	queue_free()
