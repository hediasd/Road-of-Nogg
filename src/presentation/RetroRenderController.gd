## Owns the isolated 3D render target and persisted retro presentation options.
## Simulation and native-resolution UI remain outside this viewport.

class_name RetroRenderController
extends RefCounted

const BattleMeshFactoryScript = preload("res://src/presentation/BattleMeshFactory.gd")
const RenderPresetCatalogScript = preload("res://src/presentation/RenderPresetCatalog.gd")
const NoggThemeScript = preload("res://src/presentation/theme/NoggTheme.gd")
const CRT_DISPLAY_SHADER = preload("res://assets/shaders/crt_display.gdshader")
const SETTINGS_PATH := "user://rendering.cfg"
const MIN_VIEWPORT_SIZE := Vector2i(2, 2)
const PRESET_NONE := RenderPresetCatalogScript.NONE
const PRESET_DITHERED_HORIZON := RenderPresetCatalogScript.DITHERED_HORIZON
const PRESET_TACTICAL_SOFT := RenderPresetCatalogScript.TACTICAL_SOFT
const PRESET_SATURATED_CRT := RenderPresetCatalogScript.SATURATED_CRT
const PRESET_TACTICS_CLASSIC := RenderPresetCatalogScript.TACTICS_CLASSIC
const PRESET_WEATHERED_STONE := RenderPresetCatalogScript.WEATHERED_STONE
const PRESET_FOGGY_SURVIVAL := RenderPresetCatalogScript.FOGGY_SURVIVAL
const PRESET_TROPICAL_COLOR := RenderPresetCatalogScript.TROPICAL_COLOR
const PRESET_STEALTH_GREEN := RenderPresetCatalogScript.STEALTH_GREEN
const PRESET_CUSTOM := RenderPresetCatalogScript.CUSTOM
const LOOK_RENDER_SCALE := "render_scale"
const LOOK_SNAP_STRENGTH := "snap_strength"
const LOOK_BRIGHTNESS := "brightness"
const LOOK_CONTRAST := "contrast"
const LOOK_SATURATION := "saturation"
const LOOK_COLOR_LEVELS := "color_levels"
const LOOK_DITHER := "dither"
const CRT_SCANLINE := "scanline"
const CRT_SCANLINE_SIZE := "scanline_size"
const CRT_MASK := "mask"
const CRT_MASK_SIZE := "mask_size"
const CRT_VIGNETTE := "vignette"
const CRT_FLICKER := "flicker"
const CRT_COLOR_BLEED := "color_bleed"
const CRT_NOISE := "noise"
const CRT_GLOW := "glow"

var host: Node
var world_viewport: SubViewport
var world_root: Node3D
var display_layer: CanvasLayer
var world_texture: TextureRect
var crt_overlay_layer: CanvasLayer
var crt_overlay: ColorRect
var crt_material: ShaderMaterial
var ui_through_crt: bool = false
var render_preset: String = PRESET_NONE
var render_size := Vector2i(640, 480)
var retro_enabled: bool = false
var crt_enabled: bool = false
var nearest_filter_enabled: bool = false
var vertex_snap_enabled: bool = false
var vertex_snap_strength: float = 0.0
var affine_mapping_enabled: bool = false
var render_scale: float = 1.0
var brightness: float = 1.0
var contrast: float = 1.0
var saturation: float = 1.0
var color_levels: float = 0.0
var dither_strength: float = 0.0
var crt_scanline_strength: float = 0.22
var crt_scanline_size: float = 1.0
var crt_mask_strength: float = 0.1
var crt_mask_size: float = 1.0
var crt_vignette_strength: float = 0.2
var crt_flicker_strength: float = 0.02
var crt_color_bleed: float = 0.8
var crt_noise_strength: float = 0.03
var crt_glow_strength: float = 0.1


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
	display_layer.layer = NoggThemeScript.CRT_LAYER
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

	# The CRT shader lives in ITS OWN CanvasLayer, separate from display_layer,
	# specifically so its layer number can move independently: below the game
	# UI by default, above it when ui_through_crt is on. It samples
	# hint_screen_texture, so whatever is drawn before it (lower layer) is what
	# it distorts — see docs/UI_DESIGN.md §10 and NoggTheme's layer constants.
	crt_overlay_layer = CanvasLayer.new()
	crt_overlay_layer.name = "CRTOverlayLayer"
	crt_overlay_layer.layer = NoggThemeScript.CRT_OVERLAY_LAYER_DEFAULT
	host.add_child(crt_overlay_layer)

	crt_overlay = ColorRect.new()
	crt_overlay.name = "CRTOverlay"
	crt_overlay.mouse_filter = Control.MOUSE_FILTER_IGNORE
	crt_overlay.set_anchors_preset(Control.PRESET_FULL_RECT)
	crt_material = ShaderMaterial.new()
	crt_material.shader = CRT_DISPLAY_SHADER
	crt_overlay.material = crt_material
	crt_overlay_layer.add_child(crt_overlay)

	host.get_viewport().size_changed.connect(_on_main_viewport_size_changed)


func reset_defaults(persist: bool = true) -> void:
	_apply_preset_values(PRESET_NONE)
	_apply_settings(persist)


func set_preset(preset: String, persist: bool = true) -> void:
	if not _apply_preset_values(preset):
		push_warning("Unknown rendering preset '%s'; using None." % preset)
		_apply_preset_values(PRESET_NONE)
	_apply_settings(persist)


func set_features(vertexSnap: bool, sharpPixels: bool, persist: bool = true) -> void:
	var changed = (
		vertex_snap_enabled != vertexSnap
		or nearest_filter_enabled != sharpPixels
	)
	vertex_snap_enabled = vertexSnap
	nearest_filter_enabled = sharpPixels
	if changed:
		_mark_custom()
	_apply_settings(persist)

func set_look_parameter(parameter: String, value: float, persist: bool = true) -> void:
	var resizeRequired = false
	match parameter:
		LOOK_RENDER_SCALE:
			render_scale = clampf(value, 0.5, 1.5)
			resizeRequired = true
		LOOK_SNAP_STRENGTH:
			vertex_snap_strength = clampf(value, 0.0, 1.0)
		LOOK_BRIGHTNESS:
			brightness = clampf(value, 0.5, 1.5)
		LOOK_CONTRAST:
			contrast = clampf(value, 0.5, 1.5)
		LOOK_SATURATION:
			saturation = clampf(value, 0.0, 2.0)
		LOOK_COLOR_LEVELS:
			color_levels = clampf(value, 0.0, 64.0)
		LOOK_DITHER:
			dither_strength = clampf(value, 0.0, 0.15)
		_:
			push_warning("Unknown look parameter '%s'." % parameter)
			return
	_mark_custom()
	if resizeRequired:
		_apply_settings(persist)
	else:
		_apply_display_parameters()
		BattleMeshFactoryScript.configureRetro(
			vertex_snap_enabled,
			affine_mapping_enabled,
			Vector2(world_viewport.size),
			vertex_snap_strength
		)
		BattleMeshFactoryScript.updateMaterialsRecursive(world_root)
		if persist:
			_save_settings()


func get_look_parameter(parameter: String) -> float:
	match parameter:
		LOOK_RENDER_SCALE:
			return render_scale
		LOOK_SNAP_STRENGTH:
			return vertex_snap_strength
		LOOK_BRIGHTNESS:
			return brightness
		LOOK_CONTRAST:
			return contrast
		LOOK_SATURATION:
			return saturation
		LOOK_COLOR_LEVELS:
			return color_levels
		LOOK_DITHER:
			return dither_strength
	return 0.0


func set_crt_parameter(parameter: String, value: float, persist: bool = true) -> void:
	match parameter:
		CRT_SCANLINE:
			crt_scanline_strength = clampf(value, 0.0, 0.5)
		CRT_SCANLINE_SIZE:
			crt_scanline_size = clampf(value, 0.5, 4.0)
		CRT_MASK:
			crt_mask_strength = clampf(value, 0.0, 0.3)
		CRT_MASK_SIZE:
			crt_mask_size = clampf(value, 1.0, 6.0)
		CRT_VIGNETTE:
			crt_vignette_strength = clampf(value, 0.0, 0.6)
		CRT_FLICKER:
			crt_flicker_strength = clampf(value, 0.0, 0.1)
		CRT_COLOR_BLEED:
			crt_color_bleed = clampf(value, 0.0, 4.0)
		CRT_NOISE:
			crt_noise_strength = clampf(value, 0.0, 0.2)
		CRT_GLOW:
			crt_glow_strength = clampf(value, 0.0, 0.5)
		_:
			push_warning("Unknown CRT parameter '%s'." % parameter)
			return
	_mark_custom()
	_apply_display_parameters()
	if persist:
		_save_settings()


## Moves the CRT shader's own layer above or below the game UI (item 2). The
## dev canvas (`NoggTheme.DEV_LAYER`) is always the topmost of the three, so it
## is never affected by this toggle either way.
func set_ui_through_crt(enabled: bool, persist: bool = true) -> void:
	ui_through_crt = enabled
	crt_overlay_layer.layer = (
		NoggThemeScript.CRT_OVERLAY_LAYER_THROUGH_UI if enabled
		else NoggThemeScript.CRT_OVERLAY_LAYER_DEFAULT
	)
	if persist:
		_save_settings()


func get_crt_parameter(parameter: String) -> float:
	match parameter:
		CRT_SCANLINE:
			return crt_scanline_strength
		CRT_SCANLINE_SIZE:
			return crt_scanline_size
		CRT_MASK:
			return crt_mask_strength
		CRT_MASK_SIZE:
			return crt_mask_size
		CRT_VIGNETTE:
			return crt_vignette_strength
		CRT_FLICKER:
			return crt_flicker_strength
		CRT_COLOR_BLEED:
			return crt_color_bleed
		CRT_NOISE:
			return crt_noise_strength
		CRT_GLOW:
			return crt_glow_strength
	return 0.0


func _apply_display_parameters() -> void:
	if crt_material == null:
		return
	crt_material.set_shader_parameter("crt_enabled", crt_enabled)
	crt_material.set_shader_parameter("brightness", brightness)
	crt_material.set_shader_parameter("contrast", contrast)
	crt_material.set_shader_parameter("saturation", saturation)
	crt_material.set_shader_parameter("color_levels", color_levels)
	crt_material.set_shader_parameter("dither_strength", dither_strength)
	crt_material.set_shader_parameter("scanline_strength", crt_scanline_strength)
	crt_material.set_shader_parameter("scanline_size", crt_scanline_size)
	crt_material.set_shader_parameter("mask_strength", crt_mask_strength)
	crt_material.set_shader_parameter("mask_size", crt_mask_size)
	crt_material.set_shader_parameter("vignette_strength", crt_vignette_strength)
	crt_material.set_shader_parameter("flicker_strength", crt_flicker_strength)
	crt_material.set_shader_parameter("color_bleed", crt_color_bleed)
	crt_material.set_shader_parameter("noise_strength", crt_noise_strength)
	crt_material.set_shader_parameter("glow_strength", crt_glow_strength)


func _apply_preset_values(preset: String) -> bool:
	var normalizedPreset = RenderPresetCatalogScript.normalize_legacy(preset)
	if not RenderPresetCatalogScript.has(normalizedPreset):
		return false
	if normalizedPreset == PRESET_CUSTOM:
		render_preset = PRESET_CUSTOM
		return true

	_set_neutral_values()
	render_preset = normalizedPreset
	match render_preset:
		PRESET_NONE:
			pass
		PRESET_DITHERED_HORIZON:
			retro_enabled = true
			render_size = Vector2i(320, 240)
			nearest_filter_enabled = true
			vertex_snap_enabled = true
			vertex_snap_strength = 0.7
			affine_mapping_enabled = true
			brightness = 0.78
			contrast = 1.25
			saturation = 0.75
			color_levels = 16.0
			dither_strength = 0.065
		PRESET_TACTICAL_SOFT:
			retro_enabled = true
			render_size = Vector2i(480, 360)
			contrast = 0.95
			saturation = 1.1
			color_levels = 32.0
			dither_strength = 0.01
		PRESET_SATURATED_CRT:
			retro_enabled = true
			render_size = Vector2i(640, 480)
			nearest_filter_enabled = true
			crt_enabled = true
			brightness = 1.1
			contrast = 1.15
			saturation = 1.25
			crt_scanline_strength = 0.4
			crt_mask_strength = 0.18
			crt_vignette_strength = 0.16
			crt_flicker_strength = 0.012
			crt_color_bleed = 1.5
			crt_noise_strength = 0.035
			crt_glow_strength = 0.25
		PRESET_TACTICS_CLASSIC:
			retro_enabled = true
			render_size = Vector2i(320, 240)
			nearest_filter_enabled = true
			contrast = 1.05
			saturation = 0.95
			color_levels = 32.0
			dither_strength = 0.025
		PRESET_WEATHERED_STONE:
			retro_enabled = true
			render_size = Vector2i(320, 240)
			nearest_filter_enabled = true
			vertex_snap_enabled = true
			vertex_snap_strength = 0.65
			affine_mapping_enabled = true
			brightness = 0.82
			contrast = 1.28
			saturation = 0.65
			color_levels = 18.0
			dither_strength = 0.08
		PRESET_FOGGY_SURVIVAL:
			retro_enabled = true
			render_size = Vector2i(480, 360)
			brightness = 0.72
			contrast = 0.9
			saturation = 0.35
			color_levels = 24.0
			dither_strength = 0.06
		PRESET_TROPICAL_COLOR:
			retro_enabled = true
			render_size = Vector2i(480, 360)
			brightness = 1.05
			contrast = 1.05
			saturation = 1.35
			dither_strength = 0.01
		PRESET_STEALTH_GREEN:
			retro_enabled = true
			render_size = Vector2i(320, 240)
			nearest_filter_enabled = true
			vertex_snap_enabled = true
			vertex_snap_strength = 0.45
			affine_mapping_enabled = true
			brightness = 0.9
			contrast = 1.18
			saturation = 0.75
			color_levels = 24.0
			dither_strength = 0.05
	return true


func _set_neutral_values() -> void:
	render_size = Vector2i(640, 480)
	retro_enabled = false
	crt_enabled = false
	nearest_filter_enabled = false
	vertex_snap_enabled = false
	vertex_snap_strength = 0.0
	affine_mapping_enabled = false
	render_scale = 1.0
	brightness = 1.0
	contrast = 1.0
	saturation = 1.0
	color_levels = 0.0
	dither_strength = 0.0
	crt_scanline_strength = 0.22
	crt_scanline_size = 1.0
	crt_mask_strength = 0.1
	crt_mask_size = 1.0
	crt_vignette_strength = 0.2
	crt_flicker_strength = 0.02
	crt_color_bleed = 0.8
	crt_noise_strength = 0.03
	crt_glow_strength = 0.1


func _mark_custom() -> void:
	render_preset = PRESET_CUSTOM

func _apply_settings(persist: bool) -> void:
	_resize_world_viewport()
	world_texture.texture_filter = (
		CanvasItem.TEXTURE_FILTER_NEAREST
		if nearest_filter_enabled else
		CanvasItem.TEXTURE_FILTER_LINEAR
	)
	crt_overlay.visible = true
	crt_overlay_layer.layer = (
		NoggThemeScript.CRT_OVERLAY_LAYER_THROUGH_UI if ui_through_crt
		else NoggThemeScript.CRT_OVERLAY_LAYER_DEFAULT
	)
	_apply_display_parameters()
	BattleMeshFactoryScript.configureRetro(
		vertex_snap_enabled,
		affine_mapping_enabled,
		Vector2(world_viewport.size),
		vertex_snap_strength
	)
	BattleMeshFactoryScript.updateMaterialsRecursive(world_root)
	if persist:
		_save_settings()


func _resize_world_viewport() -> void:
	var baseSize = render_size if retro_enabled else Vector2i(
		host.get_window().size
	)
	world_viewport.size = Vector2i(
		maxi(roundi(baseSize.x * render_scale), MIN_VIEWPORT_SIZE.x),
		maxi(roundi(baseSize.y * render_scale), MIN_VIEWPORT_SIZE.y)
	)


func _on_main_viewport_size_changed() -> void:
	_resize_world_viewport()
	BattleMeshFactoryScript.configureRetro(
		vertex_snap_enabled,
		affine_mapping_enabled,
		Vector2(world_viewport.size),
		vertex_snap_strength
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
		PRESET_NONE
	))
	if not _apply_preset_values(savedPreset):
		_apply_preset_values(PRESET_NONE)
	# Not gated on PRESET_CUSTOM like the look/CRT values below: whether the UI
	# takes the CRT pass is orthogonal to which visual preset is active, not a
	# property of the preset itself.
	#
	# Set directly rather than via set_ui_through_crt(): _load_settings() runs
	# in _init() BEFORE _build_render_target(), so crt_overlay_layer does not
	# exist yet. _apply_settings() (which runs after the build) is what
	# applies this value to the actual node — the same split every other
	# loaded-then-applied setting here already follows.
	ui_through_crt = bool(config.get_value(
		"rendering", "ui_through_crt", ui_through_crt
	))
	if render_preset != PRESET_CUSTOM:
		return
	retro_enabled = bool(config.get_value(
		"rendering",
		"retro_enabled",
		retro_enabled
	))
	crt_enabled = bool(config.get_value(
		"rendering",
		"crt_enabled",
		crt_enabled
	))
	render_size = Vector2i(
		int(config.get_value("rendering", "render_width", render_size.x)),
		int(config.get_value("rendering", "render_height", render_size.y))
	)
	vertex_snap_enabled = bool(config.get_value(
		"rendering",
		"vertex_snap_enabled",
		vertex_snap_enabled
	))
	nearest_filter_enabled = bool(config.get_value(
		"rendering",
		"nearest_filter_enabled",
		nearest_filter_enabled
	))
	vertex_snap_strength = clampf(float(config.get_value(
		"look", "vertex_snap_strength", vertex_snap_strength
	)), 0.0, 1.0)
	render_scale = clampf(float(config.get_value(
		"look", "render_scale", render_scale
	)), 0.5, 1.5)
	brightness = clampf(float(config.get_value(
		"look", "brightness", brightness
	)), 0.5, 1.5)
	contrast = clampf(float(config.get_value(
		"look", "contrast", contrast
	)), 0.5, 1.5)
	saturation = clampf(float(config.get_value(
		"look", "saturation", saturation
	)), 0.0, 2.0)
	color_levels = clampf(float(config.get_value(
		"look", "color_levels", color_levels
	)), 0.0, 64.0)
	dither_strength = clampf(float(config.get_value(
		"look", "dither_strength", dither_strength
	)), 0.0, 0.15)
	affine_mapping_enabled = bool(config.get_value(
		"rendering",
		"affine_mapping_enabled",
		affine_mapping_enabled
	))
	crt_scanline_strength = clampf(float(config.get_value(
		"crt", "scanline_strength", crt_scanline_strength
	)), 0.0, 0.5)
	crt_scanline_size = clampf(float(config.get_value(
		"crt", "scanline_size", crt_scanline_size
	)), 0.5, 4.0)
	crt_mask_strength = clampf(float(config.get_value(
		"crt", "mask_strength", crt_mask_strength
	)), 0.0, 0.3)
	crt_mask_size = clampf(float(config.get_value(
		"crt", "mask_size", crt_mask_size
	)), 1.0, 6.0)
	crt_vignette_strength = clampf(float(config.get_value(
		"crt", "vignette_strength", crt_vignette_strength
	)), 0.0, 0.6)
	crt_flicker_strength = clampf(float(config.get_value(
		"crt", "flicker_strength", crt_flicker_strength
	)), 0.0, 0.1)
	crt_color_bleed = clampf(float(config.get_value(
		"crt", "color_bleed", crt_color_bleed
	)), 0.0, 4.0)
	crt_noise_strength = clampf(float(config.get_value(
		"crt", "noise_strength", crt_noise_strength
	)), 0.0, 0.2)
	crt_glow_strength = clampf(float(config.get_value(
		"crt", "glow_strength", crt_glow_strength
	)), 0.0, 0.5)


func _save_settings() -> void:
	var config = ConfigFile.new()
	config.set_value("rendering", "render_preset", render_preset)
	config.set_value("rendering", "retro_enabled", retro_enabled)
	config.set_value("rendering", "crt_enabled", crt_enabled)
	config.set_value("rendering", "render_width", render_size.x)
	config.set_value("rendering", "render_height", render_size.y)
	config.set_value("rendering", "vertex_snap_enabled", vertex_snap_enabled)
	config.set_value("rendering", "nearest_filter_enabled", nearest_filter_enabled)
	config.set_value("rendering", "affine_mapping_enabled", affine_mapping_enabled)
	config.set_value("rendering", "ui_through_crt", ui_through_crt)
	config.set_value("look", "render_scale", render_scale)
	config.set_value("look", "vertex_snap_strength", vertex_snap_strength)
	config.set_value("look", "brightness", brightness)
	config.set_value("look", "contrast", contrast)
	config.set_value("look", "saturation", saturation)
	config.set_value("look", "color_levels", color_levels)
	config.set_value("look", "dither_strength", dither_strength)
	config.set_value("crt", "scanline_strength", crt_scanline_strength)
	config.set_value("crt", "scanline_size", crt_scanline_size)
	config.set_value("crt", "mask_strength", crt_mask_strength)
	config.set_value("crt", "mask_size", crt_mask_size)
	config.set_value("crt", "vignette_strength", crt_vignette_strength)
	config.set_value("crt", "flicker_strength", crt_flicker_strength)
	config.set_value("crt", "color_bleed", crt_color_bleed)
	config.set_value("crt", "noise_strength", crt_noise_strength)
	config.set_value("crt", "glow_strength", crt_glow_strength)
	var error = config.save(SETTINGS_PATH)
	if error != OK:
		push_warning("Could not save rendering settings: %s" % error_string(error))
