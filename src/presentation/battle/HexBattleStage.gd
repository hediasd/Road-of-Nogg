## Owns the hex battle's isolated render world and its screen/world conversion boundary.
## Native-resolution UI is deliberately parented beside this node, never below `worldRoot()`.

class_name HexBattleStage
extends Node

const RetroRenderControllerScript = preload("res://src/presentation/RetroRenderController.gd")
const BattleEnvironmentFactoryScript = preload("res://src/presentation/BattleEnvironmentFactory.gd")
const HexGraphicsPanelScript = preload("res://src/presentation/battle/ui/HexGraphicsPanel.gd")
const SKY_SHADER = preload("res://assets/textures/sky/retro_sky_2d.gdshader")

const LIGHT_ROTATION := Vector3(-45.0, 45.0, 0.0)
const LIGHT_COLOR := Color.WHITE
const LIGHT_ENERGY := 1.0

var renderer: RetroRenderController
var graphicsPanel: HexGraphicsPanel
var environment: WorldEnvironment
var light: DirectionalLight3D

var _camera: HexBattleCamera
var _disposed := false


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
