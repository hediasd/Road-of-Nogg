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

## Passive terrain chrome. One analytic screen pixel at low opacity; active hover, cursor and
## tactical ranges are allowed to be stronger because they communicate state.
const TERRAIN_GRID_LINE_PX := 1.0
const TERRAIN_GRID_COLOR := Color(0.025, 0.035, 0.045, 0.13)
const TERRAIN_ALPHA_CUTOFF := 0.5

## A battle is not a world-map vista. Its material clips the exported region to real painted
## pixels and draws the hex lattice analytically, while leaving the shared world-map shader and
## every explorer/editor caller untouched.
const BATTLE_GROUND_SHADER_CODE := """
shader_type spatial;
render_mode unshaded, cull_disabled, depth_draw_opaque, shadows_disabled;

uniform sampler2D terrain_texture : source_color, filter_nearest, repeat_disable;
uniform vec2 region_origin = vec2(0.0);
uniform vec2 region_size = vec2(1.0);
uniform vec2 hex_lattice = vec2(0.0);
uniform vec4 grid_color : source_color = vec4(0.025, 0.035, 0.045, 0.13);
uniform float grid_line_px = 1.0;
uniform float alpha_cutoff = 0.5;

varying vec3 world_position;

vec2 hex_nearest_axial(vec2 p) {
	vec2 centred = p - vec2(1.0, 1.0);
	float qf = centred.x / 1.5;
	float rf = (centred.y - qf) / 2.0;
	float xf = qf;
	float zf = rf;
	float yf = -xf - zf;
	float rx = round(xf);
	float ry = round(yf);
	float rz = round(zf);
	float dx = abs(rx - xf);
	float dy = abs(ry - yf);
	float dz = abs(rz - zf);
	if (dx > dy && dx > dz) {
		rx = -ry - rz;
	} else if (dy > dz) {
		ry = -rx - rz;
	} else {
		rz = -rx - ry;
	}
	return vec2(rx, rz);
}

vec2 hex_axial_centre(vec2 axial) {
	return vec2(1.5 * axial.x + 1.0, 2.0 * axial.y + axial.x + 1.0);
}

float hex_edge_distance(vec2 local) {
	vec2 q = abs(local);
	float flat_edge = q.y - 1.0;
	float slant = (2.0 * q.x + q.y - 2.0) * 0.4472135955;
	return max(flat_edge, slant);
}

bool hex_in_lattice(vec2 p) {
	vec2 axial = hex_nearest_axial(p);
	float col = axial.x;
	float row = axial.y + floor(axial.x * 0.5);
	return col >= 0.0 && row >= 0.0 && col < hex_lattice.x && row < hex_lattice.y;
}

float line_coverage(float distance_world, float world_px) {
	float distance_px = distance_world / max(world_px, 0.000001);
	return clamp(grid_line_px * 0.5 - distance_px + 0.5, 0.0, 1.0);
}

void vertex() {
	world_position = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
}

void fragment() {
	vec2 local = world_position.xz - region_origin;
	vec2 uv = local / region_size;
	if (uv.x < 0.0 || uv.x > 1.0 || uv.y < 0.0 || uv.y > 1.0) {
		discard;
	}
	vec4 painted = texture(terrain_texture, uv);
	if (painted.a < alpha_cutoff) {
		discard;
	}
	vec3 composed = painted.rgb;
	if (hex_in_lattice(local)) {
		float world_px = max(length(dFdx(world_position.xz)), length(dFdy(world_position.xz)));
		vec2 centre = hex_axial_centre(hex_nearest_axial(local));
		float edge = abs(hex_edge_distance(local - centre));
		float coverage = line_coverage(edge, world_px) * grid_color.a;
		composed = mix(composed, grid_color.rgb, coverage);
	}
	ALBEDO = composed;
}
"""

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
var _battleTerrainMaterial: ShaderMaterial


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
	if not _prepareBattleTerrain(map):
		_clearTerrain()
		return _reportTerrain(TERRAIN_UNREADABLE, path,
			"No terrain: %s has no usable painted ground. Re-export map '%s'." % [path, mapID])
	return _reportTerrain(TERRAIN_LOADED, path, "")


func terrainRoot() -> Node3D:
	return _terrain if is_instance_valid(_terrain) else null


func hasTerrain() -> bool:
	return terrainRoot() != null


func terrainReport() -> Dictionary:
	return _terrainReport.duplicate()


func battleTerrainMaterial() -> ShaderMaterial:
	return _battleTerrainMaterial


## Converts the exported world-map ground into a battle surface on the instance only. A flat
## export loses its 116-unit fog skirt entirely; a sculpted export may retain invisible skirt
## geometry, but the alpha/off-region discard guarantees that it draws nothing outside the map.
func _prepareBattleTerrain(map: BattleMapDefinition) -> bool:
	var ground := _terrain.get_node_or_null("Ground") as MeshInstance3D
	if ground == null:
		return false
	var exportedMaterial := ground.material_override as ShaderMaterial
	if exportedMaterial == null:
		return false
	var texture := exportedMaterial.get_shader_parameter("region_nearest") as Texture2D
	var originValue: Variant = exportedMaterial.get_shader_parameter("region_origin")
	var sizeValue: Variant = exportedMaterial.get_shader_parameter("region_size")
	if texture == null or not originValue is Vector2 or not sizeValue is Vector2:
		return false
	var regionOrigin := originValue as Vector2
	var regionSize := sizeValue as Vector2
	if regionSize.x <= 0.0 or regionSize.y <= 0.0:
		return false

	var shader := Shader.new()
	shader.code = BATTLE_GROUND_SHADER_CODE
	_battleTerrainMaterial = ShaderMaterial.new()
	_battleTerrainMaterial.shader = shader
	_battleTerrainMaterial.set_shader_parameter("terrain_texture", texture)
	_battleTerrainMaterial.set_shader_parameter("region_origin", regionOrigin)
	_battleTerrainMaterial.set_shader_parameter("region_size", regionSize)
	_battleTerrainMaterial.set_shader_parameter("hex_lattice", Vector2(map.boardSize))
	_battleTerrainMaterial.set_shader_parameter("grid_color", TERRAIN_GRID_COLOR)
	_battleTerrainMaterial.set_shader_parameter("grid_line_px", TERRAIN_GRID_LINE_PX)
	_battleTerrainMaterial.set_shader_parameter("alpha_cutoff", TERRAIN_ALPHA_CUTOFF)
	ground.material_override = _battleTerrainMaterial
	ground.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF

	var plane := ground.mesh as PlaneMesh
	if plane != null:
		var cropped := plane.duplicate() as PlaneMesh
		cropped.size = regionSize
		cropped.subdivide_width = 1
		cropped.subdivide_depth = 1
		ground.mesh = cropped
		ground.position = Vector3(
			regionOrigin.x + regionSize.x * 0.5,
			ground.position.y,
			regionOrigin.y + regionSize.y * 0.5)
	return true


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
	_battleTerrainMaterial = null


func attachCamera(value: HexBattleCamera) -> void:
	_camera = value
	if graphicsPanel != null:
		graphicsPanel.attachCamera(_camera)
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
	if graphicsPanel != null:
		graphicsPanel.attachCamera(null)
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
