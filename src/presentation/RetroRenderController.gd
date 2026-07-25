## Owns the isolated 3D render target and persisted retro presentation options.
## Simulation and native-resolution UI remain outside this viewport.

class_name RetroRenderController
extends RefCounted

const BattleMeshFactoryScript = preload("res://src/presentation/BattleMeshFactory.gd")
const CRT_DISPLAY_SHADER = preload("res://assets/shaders/crt_display.gdshader")
const SETTINGS_PATH := "user://rendering.cfg"
const MIN_VIEWPORT_SIZE := Vector2i(2, 2)
const PRESET_CLEAN := "clean"
const PRESET_RETRO_LIGHT := "retro_light"
const PRESET_PS1_SOFT := "ps1_soft"
const PRESET_PS1_CLASSIC := "ps1_classic"
const PRESET_CRT := "crt"
const CRT_SCANLINE := "scanline"
const CRT_MASK := "mask"
const CRT_VIGNETTE := "vignette"
const CRT_FLICKER := "flicker"
const CRT_COLOR_BLEED := "color_bleed"

var host: Node
var world_viewport: SubViewport
var world_root: Node3D
var display_layer: CanvasLayer
var world_texture: TextureRect
var crt_overlay: ColorRect
var crt_material: ShaderMaterial
var render_preset: String = PRESET_PS1_SOFT
var render_size := Vector2i(480, 360)
var retro_enabled: bool = true
var crt_enabled: bool = false
var vertex_snap_enabled: bool = false
var affine_mapping_enabled: bool = true
var crt_scanline_strength: float = 0.22
var crt_mask_strength: float = 0.1
var crt_vignette_strength: float = 0.2
var crt_flicker_strength: float = 0.02
var crt_color_bleed: float = 0.8


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

	crt_overlay = ColorRect.new()
	crt_overlay.name = "CRTOverlay"
	crt_overlay.mouse_filter = Control.MOUSE_FILTER_IGNORE
	crt_overlay.set_anchors_preset(Control.PRESET_FULL_RECT)
	crt_material = ShaderMaterial.new()
	crt_material.shader = CRT_DISPLAY_SHADER
	crt_overlay.material = crt_material
	display_layer.add_child(crt_overlay)

	host.get_viewport().size_changed.connect(_on_main_viewport_size_changed)


func set_preset(preset: String, persist: bool = true) -> void:
	if not _apply_preset_values(preset):
		push_warning("Unknown rendering preset '%s'; using PS1 Soft." % preset)
		_apply_preset_values(PRESET_PS1_SOFT)
	_apply_settings(persist)


func set_features(vertexSnap: bool, affineMapping: bool, persist: bool = true) -> void:
	vertex_snap_enabled = vertexSnap
	affine_mapping_enabled = affineMapping
	_apply_settings(persist)


func set_crt_parameter(parameter: String, value: float, persist: bool = true) -> void:
	match parameter:
		CRT_SCANLINE:
			crt_scanline_strength = clampf(value, 0.0, 0.5)
		CRT_MASK:
			crt_mask_strength = clampf(value, 0.0, 0.3)
		CRT_VIGNETTE:
			crt_vignette_strength = clampf(value, 0.0, 0.6)
		CRT_FLICKER:
			crt_flicker_strength = clampf(value, 0.0, 0.1)
		CRT_COLOR_BLEED:
			crt_color_bleed = clampf(value, 0.0, 4.0)
		_:
			push_warning("Unknown CRT parameter '%s'." % parameter)
			return
	_apply_crt_parameters()
	if persist:
		_save_settings()


func get_crt_parameter(parameter: String) -> float:
	match parameter:
		CRT_SCANLINE:
			return crt_scanline_strength
		CRT_MASK:
			return crt_mask_strength
		CRT_VIGNETTE:
			return crt_vignette_strength
		CRT_FLICKER:
			return crt_flicker_strength
		CRT_COLOR_BLEED:
			return crt_color_bleed
	return 0.0


func _apply_crt_parameters() -> void:
	if crt_material == null:
		return
	crt_material.set_shader_parameter("scanline_strength", crt_scanline_strength)
	crt_material.set_shader_parameter("mask_strength", crt_mask_strength)
	crt_material.set_shader_parameter("vignette_strength", crt_vignette_strength)
	crt_material.set_shader_parameter("flicker_strength", crt_flicker_strength)
	crt_material.set_shader_parameter("color_bleed", crt_color_bleed)


func _apply_preset_values(preset: String) -> bool:
	render_preset = preset
	match render_preset:
		PRESET_CLEAN:
			retro_enabled = false
			crt_enabled = false
			vertex_snap_enabled = false
			affine_mapping_enabled = false
		PRESET_RETRO_LIGHT:
			retro_enabled = true
			crt_enabled = false
			render_size = Vector2i(640, 480)
			vertex_snap_enabled = false
			affine_mapping_enabled = false
		PRESET_PS1_SOFT:
			retro_enabled = true
			crt_enabled = false
			render_size = Vector2i(480, 360)
			vertex_snap_enabled = false
			affine_mapping_enabled = true
		PRESET_PS1_CLASSIC:
			retro_enabled = true
			crt_enabled = false
			render_size = Vector2i(320, 240)
			vertex_snap_enabled = true
			affine_mapping_enabled = true
		PRESET_CRT:
			retro_enabled = true
			crt_enabled = true
			render_size = Vector2i(640, 480)
			vertex_snap_enabled = false
			affine_mapping_enabled = false
		_:
			return false
	return true


func _apply_settings(persist: bool) -> void:
	_resize_world_viewport()
	world_texture.texture_filter = (
		CanvasItem.TEXTURE_FILTER_NEAREST
		if retro_enabled else
		CanvasItem.TEXTURE_FILTER_LINEAR
	)
	crt_overlay.visible = crt_enabled
	_apply_crt_parameters()
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
		world_viewport.size = render_size
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
	if not config.has_section_key("rendering", "render_preset"):
		return
	var savedPreset = str(config.get_value(
		"rendering",
		"render_preset",
		PRESET_PS1_SOFT
	))
	if not _apply_preset_values(savedPreset):
		_apply_preset_values(PRESET_PS1_SOFT)
	vertex_snap_enabled = bool(config.get_value(
		"rendering",
		"vertex_snap_enabled",
		vertex_snap_enabled
	))
	affine_mapping_enabled = bool(config.get_value(
		"rendering",
		"affine_mapping_enabled",
		affine_mapping_enabled
	))
	crt_scanline_strength = clampf(float(config.get_value(
		"crt", "scanline_strength", crt_scanline_strength
	)), 0.0, 0.5)
	crt_mask_strength = clampf(float(config.get_value(
		"crt", "mask_strength", crt_mask_strength
	)), 0.0, 0.3)
	crt_vignette_strength = clampf(float(config.get_value(
		"crt", "vignette_strength", crt_vignette_strength
	)), 0.0, 0.6)
	crt_flicker_strength = clampf(float(config.get_value(
		"crt", "flicker_strength", crt_flicker_strength
	)), 0.0, 0.1)
	crt_color_bleed = clampf(float(config.get_value(
		"crt", "color_bleed", crt_color_bleed
	)), 0.0, 4.0)


func _save_settings() -> void:
	var config = ConfigFile.new()
	config.set_value("rendering", "render_preset", render_preset)
	config.set_value("rendering", "retro_enabled", retro_enabled)
	config.set_value("rendering", "vertex_snap_enabled", vertex_snap_enabled)
	config.set_value("rendering", "affine_mapping_enabled", affine_mapping_enabled)
	config.set_value("crt", "scanline_strength", crt_scanline_strength)
	config.set_value("crt", "mask_strength", crt_mask_strength)
	config.set_value("crt", "vignette_strength", crt_vignette_strength)
	config.set_value("crt", "flicker_strength", crt_flicker_strength)
	config.set_value("crt", "color_bleed", crt_color_bleed)
	var error = config.save(SETTINGS_PATH)
	if error != OK:
		push_warning("Could not save rendering settings: %s" % error_string(error))
