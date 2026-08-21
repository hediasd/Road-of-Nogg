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
const PRESET_HALFTONE_PRESS := RenderPresetCatalogScript.HALFTONE_PRESS
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
const LOOK_DUOTONE := "duotone"
const CRT_SCANLINE := "scanline"
const CRT_SCANLINE_SIZE := "scanline_size"
const CRT_MASK := "mask"
const CRT_MASK_SIZE := "mask_size"
const CRT_MASK_DOTS := "mask_dots"
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
## Confines the whole display stack — letterbox, world texture, and CRT pass —
## to a sub-rect of the host viewport instead of filling it.
##
## Zero size means "fill the host viewport", which is what every shipping caller
## uses and is bit-identical to the behaviour before this field existed. The VFX
## debug scene sets it so the world occupies a pane beside a fixed menu column,
## and setting it here rather than re-anchoring the nodes from outside is what
## keeps `get_display_rect()` — and therefore `screen_to_world()`,
## `world_to_screen()`, and `screen_motion_scale()`, which all derive from it —
## telling the truth about where the world actually is.
##
## Expressed in host-viewport coordinates, the same space the CanvasLayer
## controls and incoming mouse positions use. Assign through
## `set_display_rect_override()`; the field is not watched.
var display_rect_override := Rect2()
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
## Blend toward the three-stop ink ramp below. Zero is a no-op, so every
## preset that does not name it keeps full colour.
var duotone_strength: float = 0.0
## The ink ramp itself. Preset-owned rather than slider-owned: the graphics
## menu exposes the strength, not the palette.
var duotone_shadow := Color(0.05, 0.03, 0.02)
var duotone_mid := Color(0.85, 0.20, 0.12)
var duotone_paper := Color(1.0, 0.94, 0.87)
var crt_scanline_strength: float = 0.22
var crt_scanline_size: float = 1.0
var crt_mask_strength: float = 0.1
var crt_mask_size: float = 1.0
var crt_mask_dot_strength: float = 0.0
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

	_apply_display_node_rects()
	host.get_viewport().size_changed.connect(_on_main_viewport_size_changed)


## Confines the display stack to `rect`, or restores the full-viewport default
## when `rect` has zero area. Resizes the render target to match, so a
## native-resolution pane renders at pane resolution rather than rendering at
## window resolution and then being letterboxed down to fit.
##
## A host that moves its pane — because the window resized, or because it hid a
## panel — calls this again with the new rect. The field is deliberately not
## watched: recomputing a pane belongs to whoever owns the layout.
func set_display_rect_override(rect: Rect2) -> void:
	display_rect_override = rect
	_resize_world_viewport()
	_apply_display_node_rects()
	BattleMeshFactoryScript.configureRetro(
		vertex_snap_enabled,
		affine_mapping_enabled,
		Vector2(world_viewport.size),
		vertex_snap_strength
	)
	BattleMeshFactoryScript.updateMaterialsRecursive(world_root)


func clear_display_rect_override() -> void:
	set_display_rect_override(Rect2())


## The region the display stack occupies: the override when one is set, the
## whole host viewport otherwise. Distinct from `get_display_rect()`, which is
## the aspect-correct world image *inside* these bounds.
func _display_bounds() -> Rect2:
	if display_rect_override.size.x > 0.0 and display_rect_override.size.y > 0.0:
		return display_rect_override
	return Rect2(Vector2.ZERO, host.get_viewport().get_visible_rect().size)


## Positions the three display controls over `_display_bounds()`.
##
## The CRT overlay moves with them on purpose: it samples `hint_screen_texture`,
## so whatever it covers is what it distorts, and a pane-confined overlay leaves
## surrounding UI undistorted. Its vignette is computed from local `UV`, so it
## centres on the pane rather than on the window. Colour bleed and glow sample a
## few texels outside the rect at its edges — the same thing they already do at
## the window's edges.
func _apply_display_node_rects() -> void:
	var bounds := _display_bounds()
	var filling := not (
		display_rect_override.size.x > 0.0 and display_rect_override.size.y > 0.0
	)
	for control: Control in [
		display_layer.get_node_or_null("Letterbox"), world_texture, crt_overlay
	]:
		if control == null:
			continue
		# `set_anchors_preset` changes anchors and leaves offsets untouched, so
		# restoring the full-rect preset that way would reinterpret a previous
		# override's offsets against the new anchors and leave the control
		# somewhere arbitrary. The `_and_offsets_` variant is the one that
		# actually resets the rect.
		if filling:
			control.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
			continue
		control.set_anchors_and_offsets_preset(Control.PRESET_TOP_LEFT)
		control.position = bounds.position
		control.size = bounds.size


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
		LOOK_DUOTONE:
			duotone_strength = clampf(value, 0.0, 1.0)
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
		LOOK_DUOTONE:
			return duotone_strength
	return 0.0


func set_crt_parameter(parameter: String, value: float, persist: bool = true) -> void:
	match parameter:
		CRT_SCANLINE:
			crt_scanline_strength = clampf(value, 0.0, 0.5)
		CRT_SCANLINE_SIZE:
			crt_scanline_size = clampf(value, 0.5, 4.0)
		CRT_MASK:
			crt_mask_strength = clampf(value, 0.0, 1.0)
		CRT_MASK_SIZE:
			crt_mask_size = clampf(value, 1.0, 6.0)
		CRT_MASK_DOTS:
			crt_mask_dot_strength = clampf(value, 0.0, 1.0)
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
		CRT_MASK_DOTS:
			return crt_mask_dot_strength
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


## Pushes every display uniform to the CRT material.
##
## **Scanline and mask pitch are multiplied by `NoggTheme.ui_scale` here, and
## nowhere else.** The shader spaces both off `FRAGCOORD`, which is in
## device pixels regardless of the stretch mode — measured, not assumed: a
## capture at 1920 x 1080 reports a 2px scanline period under both
## `disabled` and the old `canvas_items` fractional stretch, so switching the
## project to native 1:1 did not move them. That leaves a pitch fixed in device
## pixels at every resolution, which is backwards for the thing it simulates: a
## physical CRT has a fixed scanline *count*, not a fixed pixel pitch, so a
## constant 1px pitch gives 360 lines at 720p and 1080 at 4K — the effect
## quietly dissolving into a flat darkening exactly where the screen is big
## enough to show it off. Scaling by `ui_scale` holds the count at roughly 180
## lines across the whole ladder instead.
##
## **The stored values stay resolution-independent multipliers**, which is why
## the multiply lives here rather than in `set_crt_parameter()`. `1.0` means
## "this project's default look" on any machine, so a settings file or a render
## preset written at 1080p still means the same thing at 720p. Only the number
## handed to the shader carries the resolution in it. The graphics menu's "Line
## size" / "Mask size" sliders are labelled generically and keep working
## unchanged; they now scale the default rather than naming a pixel count.
func _apply_display_parameters() -> void:
	if crt_material == null:
		return
	crt_material.set_shader_parameter("crt_enabled", crt_enabled)
	crt_material.set_shader_parameter("brightness", brightness)
	crt_material.set_shader_parameter("contrast", contrast)
	crt_material.set_shader_parameter("saturation", saturation)
	crt_material.set_shader_parameter("color_levels", color_levels)
	crt_material.set_shader_parameter("dither_strength", dither_strength)
	crt_material.set_shader_parameter("duotone_strength", duotone_strength)
	crt_material.set_shader_parameter("duotone_shadow", duotone_shadow)
	crt_material.set_shader_parameter("duotone_mid", duotone_mid)
	crt_material.set_shader_parameter("duotone_paper", duotone_paper)
	crt_material.set_shader_parameter("scanline_strength", crt_scanline_strength)
	crt_material.set_shader_parameter(
		"scanline_size", crt_scanline_size * float(NoggThemeScript.ui_scale)
	)
	crt_material.set_shader_parameter("mask_strength", crt_mask_strength)
	crt_material.set_shader_parameter(
		"mask_size", crt_mask_size * float(NoggThemeScript.ui_scale)
	)
	crt_material.set_shader_parameter("mask_dot_strength", crt_mask_dot_strength)
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
		PRESET_HALFTONE_PRESS:
			# The reference this chases is a printed panel, not a monitor. Two
			# values carry that: `duotone_strength` replaces the palette with
			# the ink ramp outright, and `crt_mask_dot_strength` turns the
			# phosphor stripe into a dot lattice. Saturation is pulled right
			# down first because the ramp is driven by luminance -- leaving
			# colour up only muddies which stop a pixel lands on.
			retro_enabled = true
			render_size = Vector2i(640, 480)
			nearest_filter_enabled = true
			crt_enabled = true
			brightness = 1.25
			contrast = 1.3
			saturation = 0.3
			color_levels = 6.0
			dither_strength = 0.05
			duotone_strength = 0.92
			duotone_shadow = Color("0d0705")
			duotone_mid = Color("d8321c")
			duotone_paper = Color("ffeede")
			crt_scanline_strength = 0.18
			crt_mask_strength = 0.5
			crt_mask_dot_strength = 0.45
			crt_vignette_strength = 0.22
			crt_flicker_strength = 0.006
			crt_color_bleed = 2.2
			crt_noise_strength = 0.02
			crt_glow_strength = 0.35
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
	duotone_strength = 0.0
	duotone_shadow = Color(0.05, 0.03, 0.02)
	duotone_mid = Color(0.85, 0.20, 0.12)
	duotone_paper = Color(1.0, 0.94, 0.87)
	crt_scanline_strength = 0.22
	crt_scanline_size = 1.0
	crt_mask_strength = 0.1
	crt_mask_size = 1.0
	crt_mask_dot_strength = 0.0
	crt_vignette_strength = 0.2
	crt_flicker_strength = 0.02
	crt_color_bleed = 0.8
	crt_noise_strength = 0.03
	crt_glow_strength = 0.1


func _mark_custom() -> void:
	render_preset = PRESET_CUSTOM

func _apply_settings(persist: bool) -> void:
	_resize_world_viewport()
	_apply_display_node_rects()
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


## The non-retro base is the region the world is actually displayed in: the
## window by default, the pane when an override is set. Rendering a pane at full
## window resolution and then letterboxing it down would resample every frame,
## which is exactly the artefact the retro pipeline exists to avoid.
func _resize_world_viewport() -> void:
	var nativeSize := Vector2i(host.get_window().size)
	if display_rect_override.size.x > 0.0 and display_rect_override.size.y > 0.0:
		nativeSize = Vector2i(display_rect_override.size.round())
	var baseSize = render_size if retro_enabled else nativeSize
	world_viewport.size = Vector2i(
		maxi(roundi(baseSize.x * render_scale), MIN_VIEWPORT_SIZE.x),
		maxi(roundi(baseSize.y * render_scale), MIN_VIEWPORT_SIZE.y)
	)


## A host owning a pane recomputes it and calls `set_display_rect_override()`
## itself; re-applying the stored rect here keeps the controls attached to it in
## the meantime, since they no longer carry anchors that follow the window.
func _on_main_viewport_size_changed() -> void:
	_resize_world_viewport()
	_apply_display_node_rects()
	BattleMeshFactoryScript.configureRetro(
		vertex_snap_enabled,
		affine_mapping_enabled,
		Vector2(world_viewport.size),
		vertex_snap_strength
	)
	BattleMeshFactoryScript.updateMaterialsRecursive(world_root)


## The aspect-correct world image, in host-viewport coordinates. Letterboxed
## within `_display_bounds()` — the whole viewport by default, or the pane when
## a host has set a display-rect override.
func get_display_rect() -> Rect2:
	var bounds := _display_bounds()
	var screenSize := bounds.size
	if screenSize.x <= 0.0 or screenSize.y <= 0.0:
		return Rect2()
	var worldAspect = float(world_viewport.size.x) / float(world_viewport.size.y)
	var screenAspect = screenSize.x / screenSize.y
	var displaySize: Vector2
	if screenAspect > worldAspect:
		displaySize = Vector2(screenSize.y * worldAspect, screenSize.y)
	else:
		displaySize = Vector2(screenSize.x, screenSize.x / worldAspect)
	return Rect2(bounds.position + (screenSize - displaySize) * 0.5, displaySize)


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
	duotone_strength = clampf(float(config.get_value(
		"look", "duotone_strength", duotone_strength
	)), 0.0, 1.0)
	duotone_shadow = Color(config.get_value("look", "duotone_shadow", duotone_shadow))
	duotone_mid = Color(config.get_value("look", "duotone_mid", duotone_mid))
	duotone_paper = Color(config.get_value("look", "duotone_paper", duotone_paper))
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
	)), 0.0, 1.0)
	crt_mask_dot_strength = clampf(float(config.get_value(
		"crt", "mask_dot_strength", crt_mask_dot_strength
	)), 0.0, 1.0)
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
	config.set_value("look", "duotone_strength", duotone_strength)
	config.set_value("look", "duotone_shadow", duotone_shadow)
	config.set_value("look", "duotone_mid", duotone_mid)
	config.set_value("look", "duotone_paper", duotone_paper)
	config.set_value("crt", "scanline_strength", crt_scanline_strength)
	config.set_value("crt", "scanline_size", crt_scanline_size)
	config.set_value("crt", "mask_strength", crt_mask_strength)
	config.set_value("crt", "mask_size", crt_mask_size)
	config.set_value("crt", "mask_dot_strength", crt_mask_dot_strength)
	config.set_value("crt", "vignette_strength", crt_vignette_strength)
	config.set_value("crt", "flicker_strength", crt_flicker_strength)
	config.set_value("crt", "color_bleed", crt_color_bleed)
	config.set_value("crt", "noise_strength", crt_noise_strength)
	config.set_value("crt", "glow_strength", crt_glow_strength)
	var error = config.save(SETTINGS_PATH)
	if error != OK:
		push_warning("Could not save rendering settings: %s" % error_string(error))
