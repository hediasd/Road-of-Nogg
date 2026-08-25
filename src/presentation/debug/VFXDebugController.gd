## Standalone spell-VFX authoring scene using the shipping render pipeline.
##
## Hosts the scene and owns playback, render, and text-specimen policy. The
## surfaces it drives own their own documentation:
##
## - `VfxDebugWorld` — terrain, anchors, footprint guide, camera framing, and
##   the cast context every effect receives.
## - `VfxDebugCapture` — frame capture, contact sheets, golden comparison, and
##   the `--capture-*` / `--golden*` flags.
## - `VfxDebugArguments` — command-line parsing primitives.
## - `VfxDebugHud` — control references and the status readout.
##
## Core shortcuts intentionally use letters because project.godot defines no
## custom input actions and the built-in UI owns Enter, Escape, Space, arrows.
## P play | U pause/resume | T settle | O overlap | C capture | H hide hud | M mode
## X text specimen | R reload glyphs
##
## Every interactive control below is also reachable from the command line, so
## a validation pass is scriptable rather than a sequence of clicks. That parity
## is deliberate: twice now an item has stalled because the harness could not
## produce an observation its own plan asked for.
##
## Scene selection and framing:
##   --effect=<profile id>   catalog entry to open with (default: first entry)
##   --element=<name>        element tint, matching BattleMeshFactory's palette
##                           (default: ice)
##   --radius=<n>            footprint radius in tiles (default 4, UI supports 1-8)
##   --shape=<circle|cross|line>  area shape, matching AREA_SHAPE (default circle)
##   --layers=<a,b,...>      isolate: show only these layers, hide the rest
##   --seed=<n>              pin the seed instead of cycling it
##   --scale=<f>             playback scale
##   --target-body=<standard|wide|tall>  target-body bounds preset
##   --source-distance=<4-10> caster-to-target separation in world units
##   --camera-yaw=<degrees>   orbit the preview camera around both anchors
##   --camera-pitch=<degrees> elevation, 6-84
##   --camera-size=<units>    orthographic size override, for framing one effect
##                           closely enough to judge its geometry.
##                           `--camera-zoom=` is an alias.
##   --camera-focus=<midpoint|caster|target>  what the camera looks at
##                           (default: midpoint, the two-island composition)
##   --comparison-isolation  hide terrain, bases, guides, and the caster proxy;
##                           keep only the target body on the black scene plate
##   --render-resolution=<native|640x480|480x360|320x240>
##                           select the world render resolution
##   --stretch=<native|integer|integer640|legacy_fractional>  how the whole
##                           canvas scales. `native` matches the shipping
##                           project.godot; `legacy_fractional` reproduces the
##                           old fractional-canvas bug for comparison. The specimen reports
##                           the resulting factor. Applied to the live root,
##                           never to project.godot.
##   --retro / --no-retro    enable or disable the retro viewport
##   --crt                    enable the CRT pass
##   --hide-hud              start with the HUD panel hidden (H toggles it).
##                           The world then takes the whole window, so every
##                           documented capture command frames as it always has.
##   --preset=<id>           shipping look preset, from RenderPresetCatalog
##   --tune=NAME=v[,NAME=v]  override the open effect's tunable parameters
##   --tune-load=<path>      load a saved tuning set before applying --tune
##   --pane-aspect=<game|fill>  how the world fills the pane beside the menu.
##                           `game` (default) letterboxes it to the window's own
##                           aspect, so framing judgements transfer to the real
##                           game; `fill` spends the whole pane on pixels.
##
## Text specimen. UI text is composited above the CRT pass rather than through
## it, so whether a face survives a given preset is a question only this scene
## can answer -- it is the one place the shipping render stack and arbitrary
## sample copy meet. Combine with `--hide-hud --capture-at=` for a clean plate:
##   --text                  show the specimen overlay (X toggles it)
##   --text-font=<source|baked|herald_source|herald_baked|game>
##                                     which face to draw with
##   --text-sample=<reference|pangram|charset|battle>  which copy to draw
##   --text-scale=<1-4>      whole-multiple zoom of the design size
##   --text-edge=<shadow|outline|none>  drop shadow (the reference's own
##                           treatment) or a symmetric halo
##   --text-edge-size=<0-3>  shadow offset or halo width, in design pixels
##   --text-backdrop=<scene|window|solid>  what sits behind the text
##   --text-fill=<current|lifted|warm_deep|warm_panel|reference>  candidate
##                           WINDOW_FILL values, for choosing how far to lift
##                           the panel toward the reference's. Only visible
##                           under `--text-backdrop=window`; the status readout
##                           prints the picked Color verbatim.

extends Node3D

const BattleMeshFactoryScript = preload("res://src/presentation/BattleMeshFactory.gd")
const RetroRenderControllerScript = preload("res://src/presentation/RetroRenderController.gd")
const RenderPresetCatalogScript = preload("res://src/presentation/RenderPresetCatalog.gd")
const BattleEnvironmentFactoryScript = preload("res://src/presentation/BattleEnvironmentFactory.gd")
const SpellVfxCatalogScript = preload("res://src/presentation/effects/SpellVfxCatalog.gd")
const VfxPlaybackScript = preload("res://src/presentation/effects/VfxPlayback.gd")
const TextSpecimenScript = preload("res://src/presentation/debug/TextSpecimen.gd")
const NoggThemeScript = preload("res://src/presentation/theme/NoggTheme.gd")
const VfxDebugWorldScript = preload("res://src/presentation/debug/VfxDebugWorld.gd")
const VfxDebugCaptureScript = preload("res://src/presentation/debug/VfxDebugCapture.gd")
const VfxDebugHudScript = preload("res://src/presentation/debug/VfxDebugHud.gd")
const VfxDebugTuningScript = preload("res://src/presentation/debug/VfxDebugTuning.gd")

const _AREA_SHAPES := [
	{"id": "circle", "label": "Circle (diamond)"},
	{"id": "cross", "label": "Cross"},
	{"id": "line", "label": "Line"},
]
const _PANE_ASPECTS := [
	{"id": "game", "label": "Match game aspect"},
	{"id": "fill", "label": "Fill pane"},
]

## Share of the window width the fixed menu column occupies. The world takes
## what is left.
const PANE_MENU_FRACTION := 0.25
## `game` letterboxes the world pane to the window's own aspect, so framing
## judgements made here transfer to the real game; a three-quarter-width pane is
## a shape the game never renders. `fill` spends the whole pane on pixels, which
## is what close inspection of one layer wants.
const PANE_ASPECT_GAME := "game"
const PANE_ASPECT_FILL := "fill"

const _STATE_PLAYING := "playing"
const _STATE_PAUSED := "paused"
const _STATE_STOPPED := "stopped"
const _ELEMENTS: Array[String] = [
	"fire", "water", "ice", "wind", "earth",
	"wood", "thunder", "darkness", "light", "steel", "none"
]
const _RESOLUTION_OPTIONS := [
	{"label": "Native (shipping default)", "size": Vector2i.ZERO},
	{"label": "640 x 480", "size": Vector2i(640, 480)},
	{"label": "480 x 360", "size": Vector2i(480, 360)},
	{"label": "320 x 240", "size": Vector2i(320, 240)}
]

## Candidate answers to "how should the window scale?", applied to the live root
## so the question can be settled by looking instead of by editing
## `project.godot` and relaunching.
##
## **The project default is now the fourth entry, `native`** — the UI scaling correction moved
## `project.godot` to `window/stretch/mode = "disabled"` after this comparison
## found the fractional mode broke UI text at nearly every real window size.
## `NoggTheme.UI_SCALE` (`src/presentation/theme/NoggTheme.gd`) is the
## resolution-aware scale now, applied to design-unit tokens rather than to the
## canvas, so pixel content stays whole without the canvas ever resampling.
##
## The first entry is kept as `legacy_fractional`, not deleted, so the bug this
## cycle fixed stays reproducible on demand rather than becoming a claim nobody
## can check. `canvas_items` + `fractional` scales the whole canvas by
## `window_size / base`, a fraction at nearly every real window size; under the
## project's nearest filter that duplicates some pixel rows and drops others,
## so a one-pixel stroke renders two pixels wide in places and three in others.
##
## The base matters as much as the mode. Integer scaling against the inherited
## 1152 x 648 default is nearly useless at real resolutions: 1920 x 1080 admits
## only x1, because x2 would need 2304 x 1296. A 640 x 360 base divides the
## common 16:9 ladder exactly — x2 at 720p, x3 at 1080p, x4 at 1440p, x6 at 4K —
## which is why pixel-art projects generally author a small base rather than
## inherit a large one. Neither integer preset is what shipped; `NoggTheme`'s
## own token-scaling approach was chosen instead specifically to avoid
## re-authoring every layout at a smaller base — see `docs/UI_DESIGN.md`.
## First entry matches what `project.godot` actually does and is what the HUD
## dropdown shows selected by default (`OptionButton.select()` does not fire
## `item_selected`, so nothing is applied at startup — the live root already
## carries the project setting, and this just keeps the label honest about it).
const _STRETCH_PRESETS := [
	{
		"id": "native",
		"label": "Native 1:1 (project default)",
		"mode": Window.CONTENT_SCALE_MODE_DISABLED,
		"aspect": Window.CONTENT_SCALE_ASPECT_EXPAND,
		"stretch": Window.CONTENT_SCALE_STRETCH_FRACTIONAL,
		"base": Vector2i(1152, 648),
	},
	{
		"id": "integer",
		"label": "Integer, 1152x648 base",
		"mode": Window.CONTENT_SCALE_MODE_CANVAS_ITEMS,
		"aspect": Window.CONTENT_SCALE_ASPECT_EXPAND,
		"stretch": Window.CONTENT_SCALE_STRETCH_INTEGER,
		"base": Vector2i(1152, 648),
	},
	{
		"id": "integer640",
		"label": "Integer, 640x360 base",
		"mode": Window.CONTENT_SCALE_MODE_CANVAS_ITEMS,
		"aspect": Window.CONTENT_SCALE_ASPECT_EXPAND,
		"stretch": Window.CONTENT_SCALE_STRETCH_INTEGER,
		"base": Vector2i(640, 360),
	},
	{
		"id": "legacy_fractional",
		"label": "Legacy fractional (pre-fix, for comparison)",
		"mode": Window.CONTENT_SCALE_MODE_CANVAS_ITEMS,
		"aspect": Window.CONTENT_SCALE_ASPECT_EXPAND,
		"stretch": Window.CONTENT_SCALE_STRETCH_FRACTIONAL,
		"base": Vector2i(1152, 648),
	},
]

var retroRenderer
var world: VfxDebugWorld
var capture: VfxDebugCapture
var hud: VfxDebugHud
var tuning: VfxDebugTuning

var _catalogEntries: Array[Dictionary] = []
var _activePlayback
var _overlapPlaybacks: Array = []
var _playbackState: String = _STATE_STOPPED
var _activeSeed: int = 1
var _activeMode: String = VfxPlaybackScript.MODE_BATTLE
var _layerVisibility: Dictionary = {}
var _syncingScrub: bool = false
var _captureMessage: String = ""
var _worldEnvironment: WorldEnvironment
var _textSpecimen: CanvasLayer
var _paneAspectMode: String = PANE_ASPECT_GAME

@onready var _sceneCasterAnchor: Node3D = $CasterAnchor
@onready var _sceneTargetAnchor: Node3D = $TargetAnchor
@onready var _camera: BattleCameraController = $Camera3D
@onready var _ground: MeshInstance3D = $Ground


func _ready() -> void:
	# Same first-statement call the shipping controller makes, and for the same
	# reason: `ui_scale` must be settled before anything reads a NoggTheme
	# geometry token or builds a Theme. Without it this scene ran at the default
	# x2 no matter its window size, so it silently failed to reproduce what the
	# game does — which made it useless for judging anything that scales,
	# including the CRT pitch this scene is used to tune.
	NoggThemeScript.configure_for_window_height(get_window().size.y)

	retroRenderer = RetroRenderControllerScript.new(self)
	retroRenderer.set_preset(retroRenderer.PRESET_NONE, false)
	_buildBackdrop()
	capture = VfxDebugCaptureScript.new(self)
	hud = VfxDebugHudScript.new($HUD)
	_reparentWorldNodes()
	_configureBattleWorld()
	world = VfxDebugWorldScript.new(
		retroRenderer.world_root,
		_camera,
		_ground,
		_sceneCasterAnchor,
		_sceneTargetAnchor
	)
	world.build()
	tuning = VfxDebugTuningScript.new(hud.tuningControls, _onTunableChanged)
	_configureRenderControls()
	_configurePlaybackControls()
	_configureTargetContextControls()
	_configureTextSpecimen()
	_configureTuningControls()
	BattleMeshFactoryScript.prepareNodeMaterials(retroRenderer.world_root)
	# Before `_applyRenderControls`, which sizes the native render target from
	# whatever region the world ended up occupying.
	_resolvePaneAspectArgument()
	_updatePaneRect()
	_applyRenderControls()
	get_viewport().size_changed.connect(_onWindowResized)
	set_process(true)
	_updateStatus()

	_applyCommandLineOverrides()

	var captureTimes := VfxDebugArguments.normalizedTimes("--capture-at=")
	if not captureTimes.is_empty():
		call_deferred("_runCaptureMode", captureTimes)


func _process(_delta: float) -> void:
	_syncCameraReadouts()
	_pruneFinishedOverlaps()
	if _activePlayback != null and _activePlayback.is_finished():
		_playbackState = _STATE_STOPPED
		hud.pauseButton.disabled = true
		hud.pauseButton.text = "Pause"
	if _activePlayback != null:
		_syncingScrub = true
		hud.scrub.set_value_no_signal(_activePlayback.get_normalized_time())
		_syncingScrub = false
	_updateStatus()


## A drag that began over the pane keeps owning motion and its release even when
## the pointer crosses the menu, matching the shipping rule.
func _input(event: InputEvent) -> void:
	if _camera.isDragging():
		if _camera.handle_input(event, retroRenderer.screen_motion_scale()):
			get_viewport().set_input_as_handled()
			return
	if not (event is InputEventKey) or not event.pressed or event.echo:
		return
	# The hotkeys are bare letters, because project.godot defines no custom
	# input actions. A field that takes typing must therefore win: without this,
	# typing a seed or a radius fires playback and capture instead.
	var focused := get_viewport().gui_get_focus_owner()
	if focused is LineEdit or focused is TextEdit:
		return
	match event.keycode:
		KEY_P:
			_onPlayPressed()
		KEY_U:
			_onPausePressed()
		KEY_T:
			_onSettlePressed()
		KEY_O:
			_onOverlapPressed()
		KEY_C:
			_captureOnce()
		KEY_H:
			_setHudVisible(not hud.isVisible())
		KEY_M:
			hud.modeToggle.set_pressed_no_signal(not hud.modeToggle.button_pressed)
			_updateModeToggleText()
			_updateStatus()
		KEY_X:
			hud.textToggle.button_pressed = not hud.textToggle.button_pressed
		KEY_R:
			_onReloadGlyphsPressed()


## Camera input is claimed only while the pointer is over the world pane, so
## dragging across the menu column cannot orbit the view. `_input` above owns
## the continuation once a drag has started.
func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventMouse:
		if not retroRenderer.get_display_rect().has_point(event.position):
			return
	if _camera.handle_input(event, retroRenderer.screen_motion_scale()):
		get_viewport().set_input_as_handled()


func _exit_tree() -> void:
	_disposeAllPlaybacks()


func _configurePlaybackControls() -> void:
	_catalogEntries = SpellVfxCatalogScript.entries()
	assert(not _catalogEntries.is_empty(), "Spell VFX catalog must contain an effect.")
	for entry: Dictionary in _catalogEntries:
		hud.effectOption.add_item(entry["display_name"])
		hud.effectOption.set_item_metadata(
			hud.effectOption.item_count - 1,
			entry["profile_id"]
		)
	for element: String in _ELEMENTS:
		hud.elementOption.add_item(element.capitalize())
		hud.elementOption.set_item_metadata(hud.elementOption.item_count - 1, element)
	hud.elementOption.select(_ELEMENTS.find("ice"))
	hud.effectOption.select(_resolveInitialEffectIndex())
	_updateModeToggleText()

	hud.effectOption.item_selected.connect(_onEffectSelected)
	hud.elementOption.item_selected.connect(_onElementSelected)
	hud.modeToggle.toggled.connect(_onModeToggled)
	hud.scaleSetting.value_changed.connect(_onScaleChanged)
	hud.cycleSeedButton.pressed.connect(_cycleSeed)
	hud.playButton.pressed.connect(_onPlayPressed)
	hud.pauseButton.pressed.connect(_onPausePressed)
	hud.settleButton.pressed.connect(_onSettlePressed)
	hud.overlapButton.pressed.connect(_onOverlapPressed)
	hud.screenshotButton.pressed.connect(_captureOnce)
	hud.scrub.value_changed.connect(_onScrubChanged)


func _configureTargetContextControls() -> void:
	for preset: Dictionary in VfxDebugWorldScript.TARGET_BODY_PRESETS:
		hud.targetBodyOption.add_item(str(preset["label"]))
		hud.targetBodyOption.set_item_metadata(
			hud.targetBodyOption.item_count - 1, preset["id"]
		)
	hud.targetBodyOption.select(0)
	VfxDebugHudScript.fillOptions(hud.shapeOption, _AREA_SHAPES)
	hud.shapeOption.select(0)
	hud.shapeOption.item_selected.connect(_onShapeSelected)
	hud.sourceDistanceSetting.set_value_no_signal(
		VfxDebugWorldScript.DEFAULT_SOURCE_DISTANCE
	)
	hud.cameraYawSetting.set_value_no_signal(
		VfxDebugWorldScript.DEFAULT_CAMERA_YAW_DEGREES
	)
	hud.cameraPitchSetting.set_value_no_signal(
		rad_to_deg(VfxDebugWorldScript.baseOrbitPitch())
	)
	hud.cameraZoomSetting.set_value_no_signal(world.defaultZoom())
	hud.targetBodyOption.item_selected.connect(_onTargetBodySelected)
	hud.sourceDistanceSetting.value_changed.connect(_onSourceDistanceChanged)
	hud.cameraYawSetting.value_changed.connect(_onCameraOrbitChanged)
	hud.cameraPitchSetting.value_changed.connect(_onCameraOrbitChanged)
	hud.cameraZoomSetting.value_changed.connect(_onCameraOrbitChanged)
	hud.cameraResetButton.pressed.connect(_onCameraResetPressed)
	_applyTargetContextControls()
	_resetCameraFraming()


## The specimen owns its own CanvasLayer at the shipping UI depth, so it
## composites the way the battle HUD composites -- above the CRT pass by
## default, and unaffected by `H` hiding this scene's control panel. That
## separation is deliberate: a capture usually wants the specimen and not the
## controls.
func _configureTextSpecimen() -> void:
	_textSpecimen = TextSpecimenScript.new()
	add_child(_textSpecimen)
	_textSpecimen.visible = false

	for option: Dictionary in TextSpecimenScript.FONT_OPTIONS:
		hud.textFontOption.add_item(option["label"])
		hud.textFontOption.set_item_metadata(hud.textFontOption.item_count - 1, option["id"])
	for option: Dictionary in TextSpecimenScript.SAMPLE_OPTIONS:
		hud.textSampleOption.add_item(option["label"])
		hud.textSampleOption.set_item_metadata(hud.textSampleOption.item_count - 1, option["id"])
	for option: Dictionary in TextSpecimenScript.BACKDROP_OPTIONS:
		hud.textBackdropOption.add_item(option["label"])
		hud.textBackdropOption.set_item_metadata(hud.textBackdropOption.item_count - 1, option["id"])
	for option: Dictionary in TextSpecimenScript.EDGE_OPTIONS:
		hud.textEdgeOption.add_item(option["label"])
		hud.textEdgeOption.set_item_metadata(hud.textEdgeOption.item_count - 1, option["id"])
	for option: Dictionary in TextSpecimenScript.FILL_OPTIONS:
		hud.textFillOption.add_item(option["label"])
		hud.textFillOption.set_item_metadata(hud.textFillOption.item_count - 1, option["id"])
	hud.textFontOption.select(0)
	hud.textSampleOption.select(0)
	hud.textBackdropOption.select(0)
	hud.textEdgeOption.select(0)
	hud.textFillOption.select(TextSpecimenScript.default_fill_index())

	hud.textToggle.toggled.connect(_onTextToggled)
	hud.textFontOption.item_selected.connect(_onTextFontSelected)
	hud.textSampleOption.item_selected.connect(_onTextSampleSelected)
	hud.textScaleSetting.value_changed.connect(_onTextScaleChanged)
	hud.textEdgeOption.item_selected.connect(_onTextEdgeSelected)
	hud.textEdgeSizeSetting.value_changed.connect(_onTextEdgeSizeChanged)
	hud.textBackdropOption.item_selected.connect(_onTextBackdropSelected)
	hud.textFillOption.item_selected.connect(_onTextFillSelected)
	hud.reloadGlyphsButton.pressed.connect(_onReloadGlyphsPressed)


func _onTextToggled(enabled: bool) -> void:
	_textSpecimen.visible = enabled
	_updateStatus()


func _onTextFontSelected(index: int) -> void:
	_textSpecimen.set_font_id(hud.textFontOption.get_item_metadata(index))
	_updateStatus()


func _onTextSampleSelected(index: int) -> void:
	_textSpecimen.set_sample_id(hud.textSampleOption.get_item_metadata(index))
	_updateStatus()


func _onTextScaleChanged(value: float) -> void:
	_textSpecimen.set_specimen_scale(roundi(value))
	_updateStatus()


func _onTextEdgeSelected(index: int) -> void:
	_textSpecimen.set_edge_mode(hud.textEdgeOption.get_item_metadata(index))
	_updateStatus()


func _onTextEdgeSizeChanged(value: float) -> void:
	_textSpecimen.set_edge_size(roundi(value))
	_updateStatus()


func _onTextBackdropSelected(index: int) -> void:
	_textSpecimen.set_backdrop_id(hud.textBackdropOption.get_item_metadata(index))
	_updateStatus()


## Only visible under the `window` backdrop, which is the point: the fill is
## what a shadow has to be legible against, and picking one without the other
## settles nothing.
func _onTextFillSelected(index: int) -> void:
	_textSpecimen.set_fill_id(hud.textFillOption.get_item_metadata(index))
	_updateStatus()


## Re-parses `glyphs.txt` in place. Editing a glyph and pressing R is the whole
## authoring loop for this face; requiring a re-bake and a relaunch between
## every pixel would make drawing 95 glyphs unaffordable.
func _onReloadGlyphsPressed() -> void:
	_textSpecimen.reload_source()
	_updateStatus()


## `--effect=<profile id>` (e.g. `--effect=ice_area_storm`) selects which
## catalog entry the scene opens with -- and, combined with `--capture-at`,
## which effect an unattended capture actually exercises. Previously the only
## way to preview or capture anything but the catalog's first entry was to
## hand-edit this file's `select(0)` call and revert it afterward. Falls back
## to index 0 when the flag is absent or names no matching profile, same as
## the prior hardcoded default.
func _resolveInitialEffectIndex() -> int:
	var requested := VfxDebugArguments.string("--effect=")
	if requested.is_empty():
		return 0
	for index: int in range(_catalogEntries.size()):
		if str(_catalogEntries[index]["profile_id"]) == requested:
			return index
	push_warning("Unknown --effect=%s; falling back to the first catalog entry." % requested)
	return 0


func _onEffectSelected(_index: int) -> void:
	_disposeAllPlaybacks()
	_playbackState = _STATE_STOPPED
	hud.pauseButton.disabled = true
	hud.scrub.set_value_no_signal(0.0)
	_refreshSelectedEffectSurfaces()
	_updateStatus()


## Layer toggles and the tuning roster follow the *selected* effect rather than
## the last one played. Both used to appear only after `Play`, so choosing an
## effect showed an empty Layers box and no parameters until you had already
## run it once — exactly backwards for deciding what to run.
##
## The roster is static per effect, so it needs no instance. The layer names are
## not, so a throwaway playback is built and disposed to ask for them.
func _refreshSelectedEffectSurfaces() -> void:
	var profileId := _selectedProfileId()
	tuning.setEffect(profileId, _tunablesFor(profileId))
	_rebuildLayerToggles(_layerNamesFor(profileId))


func _selectedProfileId() -> String:
	return str(hud.effectOption.get_item_metadata(hud.effectOption.selected))


func _tunablesFor(profileId: String) -> Array[Dictionary]:
	var entry := SpellVfxCatalogScript.resolve(profileId)
	var factory: Callable = entry["factory"]
	var script: Script = factory.get_object() as Script
	if script == null or not script.has_method("tunables"):
		return []
	return script.call("tunables")


## Builds a probe playback purely to read its layer roster, then disposes it.
## Cheap next to a relaunch, and it keeps the toggle row truthful for an effect
## that has not been played yet.
func _layerNamesFor(profileId: String) -> Array[String]:
	var probe: VfxPlayback = SpellVfxCatalogScript.create(
		profileId, retroRenderer.world_root, world.targetAnchor.position,
		BattleMeshFactoryScript.elementColor(
			hud.elementOption.get_item_metadata(hud.elementOption.selected)
		)
	)
	if probe == null:
		return []
	var names: Array[String] = probe.get_layer_names()
	probe.dispose()
	return names


func _onElementSelected(_index: int) -> void:
	_updateStatus()


func _onModeToggled(_enabled: bool) -> void:
	_updateModeToggleText()
	_updateStatus()


func _onScaleChanged(value: float) -> void:
	if _playbackState == _STATE_PLAYING:
		_setAllPlaybackScales(float(value))
	_updateStatus()


func _onTargetBodySelected(_index: int) -> void:
	_applyTargetContextControls()


## Promoted from a command-line-only setting. It drives both the effect's own
## footprint and the on-screen guide, so leaving it out of the panel meant the
## one control that decides which tiles a spell claims could only be exercised
## by relaunching.
func _onShapeSelected(index: int) -> void:
	world.areaShape = str(hud.shapeOption.get_item_metadata(index))
	world.updateFootprintRing()
	_applyFootprintToAll()
	_updateStatus()


func _onSourceDistanceChanged(_value: float) -> void:
	_applyTargetContextControls()


## Editing any of the three orbit fields takes authorship of the view, so it
## reframes rather than merely re-centring. Dragging in the pane writes back to
## the same fields from `_process`, which is what makes them a readout as well
## as a control.
func _onCameraOrbitChanged(_value: float) -> void:
	world.cameraYawDegrees = float(hud.cameraYawSetting.value)
	world.frameCamera(
		deg_to_rad(float(hud.cameraPitchSetting.value)),
		float(hud.cameraZoomSetting.value)
	)
	_updateStatus()


func _onCameraResetPressed() -> void:
	_resetCameraFraming()


## Restores the representative framing and makes it the view a double
## middle-click returns to.
func _resetCameraFraming() -> void:
	_camera.cancelDrag()
	hud.cameraYawSetting.set_value_no_signal(
		VfxDebugWorldScript.DEFAULT_CAMERA_YAW_DEGREES
	)
	hud.cameraPitchSetting.set_value_no_signal(
		rad_to_deg(VfxDebugWorldScript.baseOrbitPitch())
	)
	hud.cameraZoomSetting.set_value_no_signal(world.defaultZoom())
	world.cameraYawDegrees = VfxDebugWorldScript.DEFAULT_CAMERA_YAW_DEGREES
	world.frameCamera(VfxDebugWorldScript.baseOrbitPitch(), world.defaultZoom())
	_updateStatus()


## Mirrors the live orbit back into the panel. Without this the fields would go
## stale the moment the pane is dragged, and the next separation change would
## snap the view back to whatever they still said.
func _syncCameraReadouts() -> void:
	var yawDegrees := wrapf(
		rad_to_deg(_camera.current_yaw - VfxDebugWorldScript.baseOrbitYaw()),
		-180.0, 180.0
	)
	hud.cameraYawSetting.set_value_no_signal(yawDegrees)
	hud.cameraPitchSetting.set_value_no_signal(rad_to_deg(_camera.current_pitch))
	hud.cameraZoomSetting.set_value_no_signal(_camera.size)
	world.cameraYawDegrees = yawDegrees


func _onPlayPressed() -> void:
	_disposeAllPlaybacks()
	if not hud.seedPin.button_pressed:
		_cycleSeed()
	_activeSeed = int(hud.seedSetting.value)
	_activePlayback = _createSelectedPlayback()
	_applyLayerVisibility(_activePlayback)
	_applyFootprintTo(_activePlayback)
	_activePlayback.set_playback_scale(float(hud.scaleSetting.value))
	_activeMode = _selectedMode()
	_activePlayback.play(_activeSeed, _activeMode)
	_playbackState = _STATE_PLAYING
	hud.pauseButton.disabled = false
	hud.pauseButton.text = "Pause"
	hud.scrub.set_value_no_signal(0.0)
	_rebuildLayerToggles(_activePlayback.get_layer_names())
	_updateStatus()


func _onPausePressed() -> void:
	if _activePlayback == null or _activePlayback.is_finished():
		return
	if _playbackState == _STATE_PAUSED:
		_setAllPlaybackScales(float(hud.scaleSetting.value))
		_playbackState = _STATE_PLAYING
		hud.pauseButton.text = "Pause"
	else:
		_setAllPlaybackScales(0.0)
		_playbackState = _STATE_PAUSED
		hud.pauseButton.text = "Resume"
	_updateStatus()


func _onSettlePressed() -> void:
	if _activePlayback == null or _activePlayback.is_finished():
		_onPlayPressed()
	_disposeOverlaps()
	_activePlayback.set_playback_scale(0.0)
	_activePlayback.skip_to_settle()
	_playbackState = _STATE_PAUSED
	hud.pauseButton.disabled = false
	hud.pauseButton.text = "Resume"
	hud.scrub.set_value_no_signal(_activePlayback.get_normalized_time())
	_updateStatus()


func _onScrubChanged(value: float) -> void:
	if _syncingScrub or _activePlayback == null:
		return
	_disposeOverlaps()
	_activePlayback.set_playback_scale(0.0)
	_activePlayback.seek_normalized(value)
	if _activePlayback.is_finished():
		_playbackState = _STATE_STOPPED
		hud.pauseButton.disabled = true
		hud.pauseButton.text = "Pause"
	else:
		_playbackState = _STATE_PAUSED
		hud.pauseButton.disabled = false
		hud.pauseButton.text = "Resume"
	_updateStatus()


func _onOverlapPressed() -> void:
	if not hud.seedPin.button_pressed:
		_cycleSeed()
	var overlapSeed := int(hud.seedSetting.value)
	var overlap = _createSelectedPlayback()
	_applyLayerVisibility(overlap)
	_applyFootprintTo(overlap)
	overlap.set_playback_scale(
		0.0 if _playbackState == _STATE_PAUSED else float(hud.scaleSetting.value)
	)
	overlap.play(overlapSeed, _selectedMode())
	if _playbackState == _STATE_PAUSED:
		overlap.set_playback_scale(0.0)
	_overlapPlaybacks.append(overlap)
	if _activePlayback == null:
		_rebuildLayerToggles(overlap.get_layer_names())
	_updateStatus()


func _createSelectedPlayback() -> VfxPlayback:
	var color := BattleMeshFactoryScript.elementColor(
		hud.elementOption.get_item_metadata(hud.elementOption.selected)
	)
	# Overrides go through the factory, not onto the finished playback: effects
	# build their geometry and bake their shader uniforms inside `createPlayback`,
	# so a rebuild-class value handed over afterwards is consumed by nothing and
	# the panel reports a change that never reached the screen.
	var playback: VfxPlayback = SpellVfxCatalogScript.create(
		_selectedProfileId(),
		retroRenderer.world_root,
		world.targetAnchor.position,
		color,
		tuning.overrides
	)
	playback.configure_cast_context(world.buildCastContext())
	return playback


func _configureTuningControls() -> void:
	hud.tuningExportButton.pressed.connect(_onTuningExportPressed)
	hud.tuningSaveButton.pressed.connect(_onTuningSavePressed)
	hud.tuningLoadButton.pressed.connect(_onTuningLoadPressed)
	hud.tuningResetButton.pressed.connect(_onTuningResetPressed)
	_refreshSelectedEffectSurfaces()


## Rebuilds and re-seeks rather than nudging a uniform, because most of these
## values shape geometry built in `play()`. Determinism is what makes that
## acceptable to watch: the same seed and timestamp reproduce exactly, so the
## replay lands on the frame you were already looking at.
func _onTunableChanged(id: String) -> void:
	if _activePlayback == null or not is_instance_valid(_activePlayback):
		_updateStatus()
		return
	if not tuning.requiresRebuild(id):
		_activePlayback.apply_tunables(tuning.overrides)
		_updateStatus()
		return
	# Explicitly typed: `_activePlayback` is untyped, so the return type of
	# `get_normalized_time()` cannot be inferred at parse time.
	var resumeAt: float = _activePlayback.get_normalized_time()
	var wasPlaying := _playbackState == _STATE_PLAYING
	_replayAtSeed(resumeAt, wasPlaying)


func _replayAtSeed(normalizedTime: float, resumePlaying: bool) -> void:
	_disposeAllPlaybacks()
	_activePlayback = _createSelectedPlayback()
	_applyLayerVisibility(_activePlayback)
	_applyFootprintTo(_activePlayback)
	_activeMode = _selectedMode()
	_activePlayback.play(_activeSeed, _activeMode)
	if resumePlaying:
		_activePlayback.set_playback_scale(float(hud.scaleSetting.value))
		_playbackState = _STATE_PLAYING
	else:
		_activePlayback.set_playback_scale(0.0)
		_activePlayback.seek_normalized(normalizedTime)
		_playbackState = _STATE_PAUSED
	hud.pauseButton.disabled = false
	hud.pauseButton.text = "Pause" if resumePlaying else "Resume"
	_rebuildLayerToggles(_activePlayback.get_layer_names())
	_updateStatus()


## Printed rather than written to a file: the value of an export is that it
## reaches a profile, and the terminal is where the session already is.
func _onTuningExportPressed() -> void:
	var text := tuning.exportText()
	print("VFX_TUNING_EXPORT profile=%s\n%s" % [tuning.profileId(), text])
	_captureMessage = "Tuning exported to stdout (%d changed)." % tuning.overrides.size()
	_updateStatus()


func _onTuningSavePressed() -> void:
	_captureMessage = tuning.save()
	_updateStatus()


func _onTuningLoadPressed() -> void:
	_captureMessage = tuning.load()
	_onTunableChanged("")
	_updateStatus()


func _onTuningResetPressed() -> void:
	tuning.clearOverrides()
	_captureMessage = "Tuning reset to profile defaults."
	_onTunableChanged("")
	_updateStatus()


func _selectedMode() -> String:
	return (
		VfxPlaybackScript.MODE_BATTLE
		if hud.modeToggle.button_pressed
		else VfxPlaybackScript.MODE_REFERENCE
	)


func _updateModeToggleText() -> void:
	hud.modeToggle.text = (
		"Battle speed" if hud.modeToggle.button_pressed else "Reference speed"
	)


func _cycleSeed() -> void:
	var nextSeed := int(hud.seedSetting.value) + 1
	if nextSeed >= 2147483647:
		nextSeed = 1
	hud.seedSetting.set_value_no_signal(nextSeed)
	_updateStatus()


func _setAllPlaybackScales(scale: float) -> void:
	if _activePlayback != null:
		_activePlayback.set_playback_scale(scale)
	for overlap in _overlapPlaybacks:
		if is_instance_valid(overlap):
			overlap.set_playback_scale(scale)


func _disposeAllPlaybacks() -> void:
	if _activePlayback != null and is_instance_valid(_activePlayback):
		_activePlayback.dispose()
	_activePlayback = null
	_disposeOverlaps()


func _disposeOverlaps() -> void:
	for overlap in _overlapPlaybacks:
		if is_instance_valid(overlap):
			overlap.dispose()
	_overlapPlaybacks.clear()


func _pruneFinishedOverlaps() -> void:
	for index in range(_overlapPlaybacks.size() - 1, -1, -1):
		var overlap = _overlapPlaybacks[index]
		if not is_instance_valid(overlap) or overlap.is_finished():
			if is_instance_valid(overlap):
				overlap.dispose()
			_overlapPlaybacks.remove_at(index)


func _rebuildLayerToggles(layerNames: Array[String]) -> void:
	hud.rebuildLayerToggles(layerNames, _layerVisibility, _onLayerToggled)


func _onLayerToggled(visible: bool, layerName: String) -> void:
	_layerVisibility[layerName] = visible
	if _activePlayback != null:
		_activePlayback.set_layer_visible(layerName, visible)
	for overlap in _overlapPlaybacks:
		if is_instance_valid(overlap):
			overlap.set_layer_visible(layerName, visible)
	_updateStatus()


func _applyLayerVisibility(playback) -> void:
	for layerName: String in playback.get_layer_names():
		if not _layerVisibility.has(layerName):
			_layerVisibility[layerName] = true
		playback.set_layer_visible(layerName, bool(_layerVisibility[layerName]))


func _updateStatus() -> void:
	if hud.effectOption.item_count == 0:
		return
	var elapsed := 0.0
	var total := 0.0
	var normalized := 0.0
	var particles := 0
	var instances := 0
	var nodes := 0
	var drawCalls := 0
	var seekExact := true
	if _activePlayback != null and is_instance_valid(_activePlayback):
		elapsed = _activePlayback.get_elapsed_time()
		total = _activePlayback.get_total_duration()
		normalized = _activePlayback.get_normalized_time()
		particles += _activePlayback.get_live_particle_count()
		instances += _activePlayback.get_live_instance_count()
		nodes += _activePlayback.get_live_node_count()
		drawCalls += VfxDebugCaptureScript.estimateDrawCalls(_activePlayback)
		seekExact = _activePlayback.is_particle_seek_exact()
	for overlap in _overlapPlaybacks:
		if is_instance_valid(overlap):
			particles += overlap.get_live_particle_count()
			instances += overlap.get_live_instance_count()
			nodes += overlap.get_live_node_count()
			drawCalls += VfxDebugCaptureScript.estimateDrawCalls(overlap)
			seekExact = seekExact and overlap.is_particle_seek_exact()
	# Explicitly typed: `_textSpecimen` is a plain CanvasLayer to the parser, so
	# the return type of `describe()` cannot be inferred here.
	var specimenLine: String = (
		_textSpecimen.describe() if _textSpecimen != null else ""
	)
	hud.setStatus({
		"effect": hud.effectOption.get_item_text(hud.effectOption.selected),
		"state": _playbackState,
		"mode": _activeMode if _activePlayback != null else _selectedMode(),
		"scale": float(hud.scaleSetting.value),
		"normalized": normalized,
		"elapsed": elapsed,
		"total": total,
		"seed": _activeSeed if _activePlayback != null else int(hud.seedSetting.value),
		"nodes": nodes,
		"particles": particles,
		"instances": instances,
		"draw_calls": drawCalls,
		"overlaps": _overlapPlaybacks.size(),
		"seek_exact": seekExact,
		"target_body": hud.targetBodyOption.get_item_text(hud.targetBodyOption.selected),
		"target_bounds": world.targetBodyBounds.size,
		"radius": world.footprintRadius,
		"shape": world.areaShape,
		"separation": world.sourceDistance,
		"yaw": world.cameraYawDegrees,
		"pitch": rad_to_deg(_camera.current_pitch),
		"zoom": _camera.size,
		"pane_aspect": _paneAspectMode,
		"preset": hud.presetOption.get_item_text(hud.presetOption.selected),
		"render": hud.resolutionOption.get_item_text(hud.resolutionOption.selected),
		"retro": hud.retroToggle.button_pressed,
		"crt": hud.crtToggle.button_pressed,
		"tuning": tuning.describe(),
		"capture_message": _captureMessage,
		"specimen": specimenLine,
	})


## Applied after the controls are built but before any capture, so a scripted
## run sees exactly the state an interactive session would after setting the
## same controls by hand.
func _applyCommandLineOverrides() -> void:
	var radius := VfxDebugArguments.integer(
		"--radius=", VfxDebugWorldScript.DEFAULT_FOOTPRINT_RADIUS
	)
	if radius != VfxDebugWorldScript.DEFAULT_FOOTPRINT_RADIUS:
		hud.radiusSetting.set_value_no_signal(radius)
		world.footprintRadius = maxi(1, radius)

	var shape := VfxDebugArguments.string("--shape=")
	if not shape.is_empty():
		if not VfxDebugHudScript.selectOptionByMetadata(
				hud.shapeOption, shape, _onShapeSelected):
			push_warning("Unknown --shape=%s; keeping circle." % shape)
	world.updateFootprintRing()

	# An effect whose whole palette derives from the element tint has to be
	# judged across several elements, and a sweep is only reproducible if the
	# tint is selectable without touching the dropdown.
	var element := VfxDebugArguments.string("--element=")
	if not element.is_empty():
		if not VfxDebugHudScript.selectOptionByMetadata(
				hud.elementOption, element, _onElementSelected):
			push_warning("Unknown --element=%s; keeping ice." % element)

	var seedValue := VfxDebugArguments.integer("--seed=", -1)
	if seedValue >= 0:
		# Pin, or `_onPlayPressed` would cycle straight past the requested seed.
		hud.seedSetting.set_value_no_signal(seedValue)
		hud.seedPin.set_pressed_no_signal(true)

	var scale := VfxDebugArguments.number("--scale=", -1.0)
	if scale > 0.0:
		hud.scaleSetting.set_value_no_signal(scale)

	var targetBody := VfxDebugArguments.string("--target-body=")
	if not targetBody.is_empty():
		if not VfxDebugHudScript.selectOptionByMetadata(
				hud.targetBodyOption, targetBody, _onTargetBodySelected):
			push_warning("Unknown --target-body=%s; keeping standard." % targetBody)
	var sourceDistance := VfxDebugArguments.number("--source-distance=", -1.0)
	if sourceDistance > 0.0:
		hud.sourceDistanceSetting.set_value_no_signal(sourceDistance)
	var cameraYaw := VfxDebugArguments.number("--camera-yaw=", INF)
	if cameraYaw != INF:
		hud.cameraYawSetting.set_value_no_signal(cameraYaw)
	var cameraPitch := VfxDebugArguments.number("--camera-pitch=", INF)
	if cameraPitch != INF:
		hud.cameraPitchSetting.set_value_no_signal(cameraPitch)
	# Framing overrides: the default two-island composition is deliberately
	# wide, which is right for delivery paths and wrong for judging the
	# geometry of one effect standing on one tile.
	#
	# `--camera-size` is the original spelling and `--camera-zoom` matches what
	# the interactive control is called; both set the orthographic size, and the
	# original keeps precedence so existing capture commands are unaffected.
	var cameraSize := VfxDebugArguments.number("--camera-size=", -1.0)
	if cameraSize <= 0.0:
		cameraSize = VfxDebugArguments.number("--camera-zoom=", -1.0)
	if cameraSize > 0.0:
		world.cameraSizeOverride = cameraSize
		hud.cameraZoomSetting.set_value_no_signal(cameraSize)
	var cameraFocus := VfxDebugArguments.string("--camera-focus=")
	if not cameraFocus.is_empty():
		if cameraFocus in ["midpoint", "caster", "target"]:
			world.cameraFocus = cameraFocus
		else:
			push_warning("Unknown --camera-focus=%s; keeping midpoint." % cameraFocus)
	var comparisonIsolation := VfxDebugArguments.flag("--comparison-isolation")
	world.setComparisonIsolation(comparisonIsolation)
	if comparisonIsolation and _worldEnvironment != null:
		_worldEnvironment.environment.background_mode = Environment.BG_COLOR
		_worldEnvironment.environment.background_color = Color.BLACK
	_applyTargetContextControls()
	# The separation may have moved, so an unrequested zoom follows it rather
	# than keeping the value the default separation produced at build time.
	if cameraSize <= 0.0:
		hud.cameraZoomSetting.set_value_no_signal(world.defaultZoom())
	_onCameraOrbitChanged(0.0)

	var stretch := VfxDebugArguments.string("--stretch=")
	if not stretch.is_empty():
		if not VfxDebugHudScript.selectOptionByMetadata(
				hud.stretchOption, stretch, _onStretchSelected):
			push_warning("Unknown --stretch=%s; keeping native (the project default)." % stretch)

	var preset := VfxDebugArguments.string("--preset=")
	if not preset.is_empty():
		if not VfxDebugHudScript.selectOptionByMetadata(
				hud.presetOption, preset, _onPresetSelected):
			push_warning("Unknown --preset=%s; keeping the current look." % preset)

	var renderResolution := VfxDebugArguments.string("--render-resolution=")
	if not renderResolution.is_empty():
		var renderResolutionValues := {
			"native": Vector2i.ZERO,
			"640x480": Vector2i(640, 480),
			"480x360": Vector2i(480, 360),
			"320x240": Vector2i(320, 240),
		}
		if renderResolutionValues.has(renderResolution):
			var requestedSize: Vector2i = renderResolutionValues[renderResolution]
			for resolutionIndex: int in range(hud.resolutionOption.item_count):
				if hud.resolutionOption.get_item_metadata(resolutionIndex) == requestedSize:
					hud.resolutionOption.select(resolutionIndex)
					_onResolutionSelected(resolutionIndex)
					break
		else:
			push_warning(
				"Unknown --render-resolution=%s; keeping native." % renderResolution)

	if VfxDebugArguments.flag("--no-retro"):
		hud.retroToggle.set_pressed_no_signal(false)
	elif VfxDebugArguments.flag("--retro"):
		hud.retroToggle.set_pressed_no_signal(true)
	if VfxDebugArguments.flag("--crt"):
		hud.crtToggle.set_pressed_no_signal(true)
	if (
		VfxDebugArguments.flag("--retro")
		or VfxDebugArguments.flag("--no-retro")
		or VfxDebugArguments.flag("--crt")
	):
		_applyRenderControls()

	# Scanline and mask pitch are in device pixels, so what they look like
	# depends entirely on the window. Exposing them makes "should these follow
	# the UI scale?" a question answered by capturing both, rather than argued.
	# `set_crt_parameter`, not `set_look_parameter` — the two have separate match
	# statements and the look setter silently ignores a CRT parameter name
	# rather than rejecting it. Passing one to the wrong setter is a no-op that
	# looks exactly like a shader that ignored the value.
	var scanlineSize := VfxDebugArguments.number("--crt-scanline-size=", -1.0)
	if scanlineSize > 0.0:
		retroRenderer.set_crt_parameter(
			retroRenderer.CRT_SCANLINE_SIZE, scanlineSize, false
		)
	var maskSize := VfxDebugArguments.number("--crt-mask-size=", -1.0)
	if maskSize > 0.0:
		retroRenderer.set_crt_parameter(
			retroRenderer.CRT_MASK_SIZE, maskSize, false
		)

	if VfxDebugArguments.flag("--hide-hud"):
		_setHudVisible(false)

	# Tuning last among the effect-shaping flags, so a saved set can be laid
	# down first and individual `--tune=` values then override it — the same
	# order an interactive session would produce by loading then adjusting.
	var tuneLoad := VfxDebugArguments.string("--tune-load=")
	if not tuneLoad.is_empty():
		print("VFX_TUNING %s" % tuning.load(tuneLoad))
	tuning.applyArgument(VfxDebugArguments.string("--tune="))

	_applyTextCommandLineOverrides()


## Routed through the HUD controls rather than straight at the specimen, so a
## scripted run and a hand-driven one cannot diverge: whatever the flags set is
## visible in the panel, and whatever the panel shows is what a flag would have
## produced.
func _applyTextCommandLineOverrides() -> void:
	var face := VfxDebugArguments.string("--text-font=")
	if not face.is_empty():
		if not VfxDebugHudScript.selectOptionByMetadata(
				hud.textFontOption, face, _onTextFontSelected):
			push_warning("Unknown --text-font=%s; keeping the live source face." % face)

	var sample := VfxDebugArguments.string("--text-sample=")
	if not sample.is_empty():
		if not VfxDebugHudScript.selectOptionByMetadata(
				hud.textSampleOption, sample, _onTextSampleSelected):
			push_warning("Unknown --text-sample=%s; keeping the reference sentence." % sample)

	var backdrop := VfxDebugArguments.string("--text-backdrop=")
	if not backdrop.is_empty():
		if not VfxDebugHudScript.selectOptionByMetadata(
				hud.textBackdropOption, backdrop, _onTextBackdropSelected):
			push_warning("Unknown --text-backdrop=%s; keeping the board." % backdrop)

	var fill := VfxDebugArguments.string("--text-fill=")
	if not fill.is_empty():
		if not VfxDebugHudScript.selectOptionByMetadata(
				hud.textFillOption, fill, _onTextFillSelected):
			push_warning("Unknown --text-fill=%s; keeping the current WINDOW_FILL." % fill)

	var textScale := VfxDebugArguments.integer("--text-scale=", -1)
	if textScale > 0:
		hud.textScaleSetting.value = clampi(
			textScale, TextSpecimenScript.MIN_SCALE, TextSpecimenScript.MAX_SCALE
		)

	var edge := VfxDebugArguments.string("--text-edge=")
	if not edge.is_empty():
		if not VfxDebugHudScript.selectOptionByMetadata(
				hud.textEdgeOption, edge, _onTextEdgeSelected):
			push_warning("Unknown --text-edge=%s; keeping the drop shadow." % edge)

	var edgeSize := VfxDebugArguments.integer("--text-edge-size=", -1)
	if edgeSize >= 0:
		hud.textEdgeSizeSetting.value = clampi(
			edgeSize, 0, TextSpecimenScript.MAX_EDGE_SIZE
		)

	# Last, so the overlay is already configured the moment it appears and a
	# capture taken immediately after cannot catch it mid-setup.
	if VfxDebugArguments.flag("--text"):
		hud.textToggle.button_pressed = true


## Isolation runs after `_onPlayPressed`, because that call rebuilds the toggle
## row from the live playback's own layer list — applying it earlier would be
## overwritten.
func _applyLayerIsolation() -> void:
	var requested := VfxDebugArguments.string("--layers=")
	if requested.is_empty() or _activePlayback == null:
		return
	var wanted := requested.split(",", false)
	# Explicitly typed: `_activePlayback` is untyped, so the return type of
	# `get_layer_names()` cannot be inferred at parse time.
	var known: Array[String] = _activePlayback.get_layer_names()
	for name: String in wanted:
		if not known.has(name.strip_edges()):
			push_warning("Unknown --layers entry '%s'; known: %s" % [name, ", ".join(known)])
	for layerName: String in known:
		var visible := false
		for name: String in wanted:
			if name.strip_edges() == layerName:
				visible = true
		_layerVisibility[layerName] = visible
		_activePlayback.set_layer_visible(layerName, visible)
	_rebuildLayerToggles(known)


## Drives the timeline to each requested timestamp and hands the settled frame
## to `VfxDebugCapture`. Orchestration lives here because it is playback
## sequencing; everything downstream of the read-back lives there.
func _runCaptureMode(times: PackedFloat32Array) -> void:
	if capture.isHeadless():
		push_error("--capture-at requires a rendered display; headless capture is unsupported.")
		get_tree().quit(2)
		return
	_onPlayPressed()
	_applyLayerIsolation()

	var prefix := capture.capturePrefix()
	var single := times.size() == 1
	var frames: Array[Image] = []
	var lastError := OK

	for index: int in range(times.size()):
		var normalizedTime := times[index]
		# Replay from zero before every seek, so each frame is the *first* seek
		# of a fresh timeline. Measured: repeated seeks within one process do
		# not reproduce — a second seek drifts run to run and differs from a
		# solo capture of the same timestamp, because `GPUParticles3D.restart()`
		# plus `request_particles_process()` is serviced asynchronously and how
		# many real frames elapse in between varies. Replaying costs a few
		# milliseconds per frame and makes a series byte-reproducible, which is
		# what golden comparison depends on.
		_activePlayback.play(_activeSeed, _activeMode)
		_activePlayback.set_playback_scale(0.0)
		_activePlayback.seek_normalized(normalizedTime)
		_playbackState = _STATE_PAUSED if normalizedTime < 1.0 else _STATE_STOPPED
		_updateStatus()
		await capture.settle()
		var image := capture.readViewportImage()
		frames.append(image)
		var name := capture.frameName(prefix, normalizedTime, single)
		var error := capture.writeFrame(image, capture.framePath(prefix, name, single))
		if error != OK:
			lastError = error
		capture.checkGolden(name, image)

	if VfxDebugArguments.flag("--capture-sheet") and frames.size() > 1:
		var sheetPath := "%s_sheet.png" % prefix
		var sheetError := capture.writeContactSheet(frames, sheetPath)
		if sheetError != OK:
			lastError = sheetError
		print("VFX_DEBUG_SHEET path=%s error=%d frames=%d" % [
			ProjectSettings.globalize_path(sheetPath), sheetError, frames.size()
		])

	if capture.goldenFailures > 0:
		print("VFX_GOLDEN_RESULT failures=%d" % capture.goldenFailures)
		get_tree().quit(VfxDebugCaptureScript.EXIT_GOLDEN_FAILED)
		return
	get_tree().quit(lastError)


## The interactive `C` / "Capture" path. Never quits — an unattended run uses
## `--capture-at`, which owns its own exit codes.
func _captureOnce() -> void:
	_captureMessage = await capture.captureOnce()
	_updateStatus()


func _configureRenderControls() -> void:
	for optionIndex in range(_RESOLUTION_OPTIONS.size()):
		var option: Dictionary = _RESOLUTION_OPTIONS[optionIndex]
		hud.resolutionOption.add_item(option["label"])
		hud.resolutionOption.set_item_metadata(optionIndex, option["size"])
	hud.resolutionOption.select(0)
	# The shipping look presets, so this scene judges effects under the same
	# named treatments the game offers rather than under a local approximation
	# of them. `RenderPresetCatalog` owns the roster; selecting one applies its
	# whole bundle — resolution, colour, CRT — and the toggles below then report
	# what it produced.
	for preset: Dictionary in RenderPresetCatalogScript.PRESETS:
		hud.presetOption.add_item(str(preset["label"]))
		hud.presetOption.set_item_metadata(hud.presetOption.item_count - 1, preset["id"])
	_selectPresetOption(retroRenderer.render_preset)
	hud.presetOption.item_selected.connect(_onPresetSelected)
	for preset: Dictionary in _STRETCH_PRESETS:
		hud.stretchOption.add_item(preset["label"])
		hud.stretchOption.set_item_metadata(hud.stretchOption.item_count - 1, preset["id"])
	hud.stretchOption.select(0)
	hud.stretchOption.item_selected.connect(_onStretchSelected)
	VfxDebugHudScript.fillOptions(hud.paneAspectOption, _PANE_ASPECTS)
	hud.paneAspectOption.select(0)
	hud.paneAspectOption.item_selected.connect(_onPaneAspectSelected)
	hud.retroToggle.set_pressed_no_signal(true)
	hud.crtToggle.set_pressed_no_signal(false)
	hud.radiusSetting.set_value_no_signal(VfxDebugWorldScript.DEFAULT_FOOTPRINT_RADIUS)
	hud.resolutionOption.item_selected.connect(_onResolutionSelected)
	hud.retroToggle.toggled.connect(_onRenderToggleChanged)
	hud.crtToggle.toggled.connect(_onRenderToggleChanged)
	hud.radiusSetting.value_changed.connect(_onRadiusChanged)


func _selectPresetOption(presetId: String) -> void:
	for index: int in range(hud.presetOption.item_count):
		if str(hud.presetOption.get_item_metadata(index)) == presetId:
			hud.presetOption.select(index)
			return


## Applies a shipping preset wholesale, then reads back what it set so the
## individual controls stay honest about the live state.
func _onPresetSelected(index: int) -> void:
	retroRenderer.set_preset(str(hud.presetOption.get_item_metadata(index)), false)
	hud.retroToggle.set_pressed_no_signal(retroRenderer.retro_enabled)
	hud.crtToggle.set_pressed_no_signal(retroRenderer.crt_enabled)
	_selectResolutionOption(retroRenderer.render_size)
	_applyRenderControls()


func _selectResolutionOption(size: Vector2i) -> void:
	for index: int in range(hud.resolutionOption.item_count):
		if hud.resolutionOption.get_item_metadata(index) == size:
			hud.resolutionOption.select(index)
			return


## Resolution and retro are separate settings and are no longer welded together.
## Selecting "Native" used to silently switch the retro viewport off, which made
## the pair impossible to exercise independently — and made "native render, retro
## materials" unreachable from the panel despite being a real combination.
func _onResolutionSelected(_index: int) -> void:
	_applyRenderControls()


func _onPaneAspectSelected(index: int) -> void:
	_paneAspectMode = str(hud.paneAspectOption.get_item_metadata(index))
	_updatePaneRect()
	_applyRenderControls()


## Applied to the live root window rather than to `project.godot`. Changing the
## project setting is a decision affecting every screen in the game; this makes
## the consequences visible first, and the specimen's pixel-exactness readout
## reports the resulting factor immediately.
func _onStretchSelected(index: int) -> void:
	var id: String = hud.stretchOption.get_item_metadata(index)
	for preset: Dictionary in _STRETCH_PRESETS:
		if preset["id"] != id:
			continue
		var root := get_tree().root
		root.content_scale_mode = preset["mode"]
		root.content_scale_aspect = preset["aspect"]
		root.content_scale_stretch = preset["stretch"]
		root.content_scale_size = preset["base"]
		break
	# Changing the content scale changes the text server's font oversampling,
	# which clears cached glyph data. A dynamic face re-rasterizes itself from
	# the TTF it still holds; a bitmap face assembled in memory has no source to
	# regenerate from, so its glyphs are simply gone and every string falls back
	# to a system font. Rebuilding is the only recovery — see the note in
	# `NoggBitmapFont`.
	#
	# Deferred, because the engine services the scale change (and the cache
	# clear it causes) after this call returns. Rebuilding inline produces a
	# correct font that is then immediately cleared, and the text server logs a
	# run of null-font-data errors while shaping against the corpse.
	if _textSpecimen != null:
		_textSpecimen.call_deferred("reload_source")
	_updateStatus()


func _onRenderToggleChanged(_enabled: bool) -> void:
	_applyRenderControls()


func _onRadiusChanged(value: float) -> void:
	world.footprintRadius = maxi(1, roundi(value))
	world.updateFootprintRing()
	_applyFootprintToAll()
	_updateStatus()


func _applyFootprintToAll() -> void:
	_applyFootprintTo(_activePlayback)
	for overlap in _overlapPlaybacks:
		_applyFootprintTo(overlap)


## No-op for playbacks (like the generic aura) that don't expose a footprint.
## The guide always draws the diamond `ShapeCaster.getCircle` shape, which is
## every carrier's shape except `cross`/`line` — see `IceStormEffect._isDiamondShape`.
func _applyFootprintTo(playback) -> void:
	if playback != null and is_instance_valid(playback) and playback.has_method("setFootprint"):
		playback.call("setFootprint", world.footprintRadius, 0.0, world.areaShape)


func _applyTargetContextControls() -> void:
	var preset: Dictionary = VfxDebugWorldScript.TARGET_BODY_PRESETS[
		hud.targetBodyOption.selected
	]
	world.targetBodyBounds = preset["bounds"]
	world.sourceDistance = float(hud.sourceDistanceSetting.value)
	world.cameraYawDegrees = float(hud.cameraYawSetting.value)
	world.apply()
	_updateStatus()


## A black plate under everything, so the window has no undefined region once
## the world stops filling it. `RetroRenderController`'s own letterbox now
## tracks the world rect rather than the screen, which is right — it is the
## world's letterbox — and leaves the area beside and around the pane to this.
##
## Below `CRT_LAYER` so it never reaches the CRT pass: it is furniture, not
## something the shipping pipeline would ever draw.
func _buildBackdrop() -> void:
	var backdropLayer := CanvasLayer.new()
	backdropLayer.name = "SceneBackdrop"
	backdropLayer.layer = NoggThemeScript.CRT_LAYER - 10
	add_child(backdropLayer)
	var plate := ColorRect.new()
	plate.name = "BackdropPlate"
	plate.color = Color.BLACK
	plate.mouse_filter = Control.MOUSE_FILTER_IGNORE
	plate.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	backdropLayer.add_child(plate)


func _resolvePaneAspectArgument() -> void:
	var requested := VfxDebugArguments.string("--pane-aspect=")
	if requested.is_empty():
		return
	if requested in [PANE_ASPECT_GAME, PANE_ASPECT_FILL]:
		_paneAspectMode = requested
	else:
		push_warning("Unknown --pane-aspect=%s; keeping game aspect." % requested)


## Hiding the menu gives the world the whole window, which is what `--hide-hud`
## captures have always framed. Under the default game aspect that makes the
## override exactly the full window, so every documented capture command still
## produces the framing it did before this scene grew a pane.
func _setHudVisible(visible: bool) -> void:
	hud.setVisible(visible)
	_updatePaneRect()
	_applyRenderControls()


func _onWindowResized() -> void:
	_updatePaneRect()
	_applyRenderControls()


## The region the world occupies. Empty means "the whole window", which is what
## `RetroRenderController` treats as no override at all.
func _paneBounds() -> Rect2:
	var windowSize := get_viewport().get_visible_rect().size
	if windowSize.x <= 0.0 or windowSize.y <= 0.0 or not hud.isVisible():
		return Rect2()
	var menuWidth := floorf(windowSize.x * PANE_MENU_FRACTION)
	var pane := Rect2(menuWidth, 0.0, windowSize.x - menuWidth, windowSize.y)
	if _paneAspectMode == PANE_ASPECT_FILL:
		return pane
	return _inscribeAspect(pane, windowSize.x / windowSize.y)


## The largest rect of `aspect` that fits inside `bounds`, centred.
static func _inscribeAspect(bounds: Rect2, aspect: float) -> Rect2:
	var height := bounds.size.y
	var width := height * aspect
	if width > bounds.size.x:
		width = bounds.size.x
		height = width / aspect
	var size := Vector2(width, height)
	return Rect2(bounds.position + (bounds.size - size) * 0.5, size)


func _updatePaneRect() -> void:
	retroRenderer.set_display_rect_override(_paneBounds())


func _applyRenderControls() -> void:
	var selectedSize: Vector2i = hud.resolutionOption.get_item_metadata(
		hud.resolutionOption.selected
	)
	var paneBounds := _paneBounds()
	var nativeSize := (
		Vector2i(paneBounds.size.round())
		if paneBounds.size.x > 0.0 and paneBounds.size.y > 0.0
		else get_window().size
	)
	retroRenderer.render_size = (
		selectedSize if selectedSize != Vector2i.ZERO else nativeSize
	)
	retroRenderer.retro_enabled = hud.retroToggle.button_pressed
	retroRenderer.crt_enabled = hud.crtToggle.button_pressed
	retroRenderer.set_look_parameter(
		retroRenderer.LOOK_RENDER_SCALE,
		retroRenderer.get_look_parameter(retroRenderer.LOOK_RENDER_SCALE),
		false
	)
	_updateStatus()


func _reparentWorldNodes() -> void:
	for worldNode: Node3D in [
		_camera, $DirectionalLight, _ground, _sceneCasterAnchor, _sceneTargetAnchor
	]:
		worldNode.reparent(retroRenderer.world_root, false)


func _configureBattleWorld() -> void:
	_worldEnvironment = WorldEnvironment.new()
	_worldEnvironment.name = "WorldEnvironment"
	_worldEnvironment.environment = BattleEnvironmentFactoryScript.createBattleEnvironment()
	retroRenderer.world_root.add_child(_worldEnvironment)
	_camera.projection = Camera3D.PROJECTION_ORTHOGONAL
	_camera.size = VfxDebugWorldScript.REPRESENTATIVE_CAMERA_SIZE
	_camera.current = true
