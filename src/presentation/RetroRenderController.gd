## Owns the isolated 3D render target and persisted retro presentation options.
## Simulation and native-resolution UI remain outside this viewport.

class_name RetroRenderController
extends RefCounted

const BattleMeshFactoryScript = preload("res://src/presentation/BattleMeshFactory.gd")
const SETTINGS_PATH := "user://rendering.cfg"
const RETRO_SIZE := Vector2i(320, 240)
const MIN_VIEWPORT_SIZE := Vector2i(2, 2)

var host: Node
var world_viewport: SubViewport
var world_root: Node3D
var display_layer: CanvasLayer
var world_texture: TextureRect
var retro_enabled: bool = true
var vertex_snap_enabled: bool = true
var affine_mapping_enabled: bool = true


func _init(_host: Node) -> void:
	host = _host
	_load_settings()
	_build_render_target()
	_apply_settings(false)


func _build_render_target() -> void:
	world_viewport = SubViewport.new()
	world_viewport.name = "BattleWorldViewport"
	world_viewport.own_world_3d = true
	world_viewport.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	world_viewport.msaa_3d = Viewport.MSAA_DISABLED
	world_viewport.screen_space_aa = Viewport.SCREEN_SPACE_AA_DISABLED
	host.add_child(world_viewport)

	world_root = Node3D.new()
	world_root.name = "BattleWorld"
	world_viewport.add_child(world_root)

	display_layer = CanvasLayer.new()
	display_layer.name = "BattleWorldDisplay"
	display_layer.layer = -20
	host.add_child(display_layer)

	var backdrop = ColorRect.new()
	backdrop.name = "Letterbox"
	backdrop.color = Color.BLACK
	backdrop.mouse_filter = Control.MOUSE_FILTER_IGNORE
	backdrop.set_anchors_preset(Control.PRESET_FULL_RECT)
	display_layer.add_child(backdrop)

	world_texture = TextureRect.new()
	world_texture.name = "WorldTexture"
	world_texture.mouse_filter = Control.MOUSE_FILTER_IGNORE
	world_texture.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	world_texture.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	world_texture.set_anchors_preset(Control.PRESET_FULL_RECT)
	world_texture.texture = world_viewport.get_texture()
	display_layer.add_child(world_texture)

	host.get_viewport().size_changed.connect(_on_main_viewport_size_changed)


func set_options(retro: bool, vertexSnap: bool, affineMapping: bool, persist: bool = true) -> void:
	retro_enabled = retro
	vertex_snap_enabled = vertexSnap
	affine_mapping_enabled = affineMapping
	_apply_settings(persist)


func _apply_settings(persist: bool) -> void:
	_resize_world_viewport()
	world_texture.texture_filter = (
		CanvasItem.TEXTURE_FILTER_NEAREST
		if retro_enabled else
		CanvasItem.TEXTURE_FILTER_LINEAR
	)
	BattleMeshFactoryScript.configureRetro(
		vertex_snap_enabled,
		affine_mapping_enabled,
		Vector2(world_viewport.size)
	)
	BattleMeshFactoryScript.updateMaterialsRecursive(world_root)
	if persist:
		_save_settings()


func _resize_world_viewport() -> void:
	if retro_enabled:
		world_viewport.size = RETRO_SIZE
		return
	var mainSize = Vector2i(host.get_viewport().get_visible_rect().size)
	world_viewport.size = Vector2i(
		maxi(mainSize.x, MIN_VIEWPORT_SIZE.x),
		maxi(mainSize.y, MIN_VIEWPORT_SIZE.y)
	)


func _on_main_viewport_size_changed() -> void:
	_resize_world_viewport()
	BattleMeshFactoryScript.configureRetro(
		vertex_snap_enabled,
		affine_mapping_enabled,
		Vector2(world_viewport.size)
	)
	BattleMeshFactoryScript.updateMaterialsRecursive(world_root)


func get_display_rect() -> Rect2:
	var screenSize = host.get_viewport().get_visible_rect().size
	if screenSize.x <= 0.0 or screenSize.y <= 0.0:
		return Rect2()
	var worldAspect = float(world_viewport.size.x) / float(world_viewport.size.y)
	var screenAspect = screenSize.x / screenSize.y
	var displaySize: Vector2
	if screenAspect > worldAspect:
		displaySize = Vector2(screenSize.y * worldAspect, screenSize.y)
	else:
		displaySize = Vector2(screenSize.x, screenSize.x / worldAspect)
	return Rect2((screenSize - displaySize) * 0.5, displaySize)


func screen_to_world(screenPosition: Vector2) -> Vector2:
	var displayRect = get_display_rect()
	if not displayRect.has_point(screenPosition) or displayRect.size.x <= 0.0 or displayRect.size.y <= 0.0:
		return Vector2(-1, -1)
	var normalized = (screenPosition - displayRect.position) / displayRect.size
	return normalized * Vector2(world_viewport.size)


func world_to_screen(worldPosition: Vector2) -> Vector2:
	var displayRect = get_display_rect()
	if world_viewport.size.x <= 0 or world_viewport.size.y <= 0:
		return Vector2(-1, -1)
	var normalized = worldPosition / Vector2(world_viewport.size)
	return displayRect.position + normalized * displayRect.size


func screen_motion_scale() -> Vector2:
	var displayRect = get_display_rect()
	if displayRect.size.x <= 0.0 or displayRect.size.y <= 0.0:
		return Vector2.ONE
	return Vector2(world_viewport.size) / displayRect.size


func _load_settings() -> void:
	var config = ConfigFile.new()
	if config.load(SETTINGS_PATH) != OK:
		return
	retro_enabled = bool(config.get_value("rendering", "retro_enabled", true))
	vertex_snap_enabled = bool(config.get_value("rendering", "vertex_snap_enabled", true))
	affine_mapping_enabled = bool(config.get_value("rendering", "affine_mapping_enabled", true))


func _save_settings() -> void:
	var config = ConfigFile.new()
	config.set_value("rendering", "retro_enabled", retro_enabled)
	config.set_value("rendering", "vertex_snap_enabled", vertex_snap_enabled)
	config.set_value("rendering", "affine_mapping_enabled", affine_mapping_enabled)
	var error = config.save(SETTINGS_PATH)
	if error != OK:
		push_warning("Could not save rendering settings: %s" % error_string(error))
