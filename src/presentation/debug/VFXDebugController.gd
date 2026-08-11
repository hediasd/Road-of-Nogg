## Standalone spell-VFX authoring scene using the shipping render pipeline.
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
##   --radius=<n>            footprint radius in tiles (default 4, UI supports 1-8)
##   --shape=<circle|cross|line>  area shape, matching AREA_SHAPE (default circle)
##   --layers=<a,b,...>      isolate: show only these layers, hide the rest
##   --seed=<n>              pin the seed instead of cycling it
##   --scale=<f>             playback scale
##   --target-body=<standard|wide|tall>  target-body bounds preset
##   --source-distance=<f>    caster-to-target separation in world units
##   --camera-yaw=<degrees>   orbit the preview camera around both anchors
##   --stretch=<native|integer|integer640|legacy_fractional>  how the whole
##                           canvas scales. `native` matches the shipping
##                           project.godot; `legacy_fractional` reproduces the
##                           old fractional-canvas bug for comparison. The specimen reports
##                           the resulting factor. Applied to the live root,
##                           never to project.godot.
##   --retro / --crt         enable the retro viewport / CRT pass
##   --hide-hud              start with the HUD panel hidden (H toggles it)
##
## Text specimen. UI text is composited above the CRT pass rather than through
## it, so whether a face survives a given preset is a question only this scene
## can answer -- it is the one place the shipping render stack and arbitrary
## sample copy meet. Combine with `--hide-hud --capture-at=` for a clean plate:
##   --text                  show the specimen overlay (X toggles it)
##   --text-font=<source|baked|game>   which face to draw with
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
##
## Capture:
##   --capture-at=<t>[,<t>...]  one or more normalized times; a list captures
##                              the whole series in ONE process rather than
##                              paying a fresh engine boot per frame
##   --capture-out=<prefix>     output path prefix (default user://vfx_debug_capture)
##   --capture-sheet            also tile the series into <prefix>_sheet.png
##   --sheet-scale=<f>          per-frame scale in the sheet (default 0.5)
##
## Golden-frame regression, which the effects' determinism guarantee earns:
##   --golden=<dir>          compare each capture against <dir>/<name>.png and
##                           print MATCH/DIFF/MISSING; exits non-zero on failure
##   --golden-write          write the captures into <dir> as new references
##
## Determinism is what makes the golden comparison meaningful: a given effect,
## seed and timestamp reproduce exactly across processes, so a DIFF is a real
## regression rather than sampling noise.

extends Node3D

const BattleMeshFactoryScript = preload("res://src/presentation/BattleMeshFactory.gd")
const RetroRenderControllerScript = preload("res://src/presentation/RetroRenderController.gd")
const BattleEnvironmentFactoryScript = preload("res://src/presentation/BattleEnvironmentFactory.gd")
const SpellVfxCatalogScript = preload("res://src/presentation/effects/SpellVfxCatalog.gd")
const VfxPlaybackScript = preload("res://src/presentation/effects/VfxPlayback.gd")
const VfxCastContextScript = preload("res://src/presentation/effects/VfxCastContext.gd")
const TextSpecimenScript = preload("res://src/presentation/debug/TextSpecimen.gd")
const NoggThemeScript = preload("res://src/presentation/theme/NoggTheme.gd")

const CAMERA_OFFSET := Vector3(6.0, 15.0, 14.0)
## Meadow and Forest are 16 cells across with two elevation steps, producing
## 16 * 0.95 + (2 * 0.5) * 0.35 through the shipping camera-size formula.
const REPRESENTATIVE_CAMERA_SIZE := 15.55
const DEFAULT_FOOTPRINT_RADIUS := 4
const DEFAULT_SOURCE_DISTANCE := 4.0
const DEFAULT_CAMERA_YAW_DEGREES := 0.0
const DEBUG_CASTER_ID := -1001
const DEBUG_TARGET_ID := -1002
const _TARGET_BODY_PRESETS: Array[Dictionary] = [
	{
		"id": "standard",
		"label": "Standard (0.70 x 1.30 x 0.70)",
		"bounds": VfxCastContext.DEFAULT_TARGET_BODY_BOUNDS,
	},
	{
		"id": "wide",
		"label": "Short / wide (1.20 x 0.90 x 0.95)",
		"bounds": AABB(Vector3(-0.6, 0.2, -0.475), Vector3(1.2, 0.9, 0.95)),
	},
	{
		"id": "tall",
		"label": "Tall / narrow (0.55 x 1.85 x 0.55)",
		"bounds": AABB(Vector3(-0.275, 0.2, -0.275), Vector3(0.55, 1.85, 0.55)),
	},
]
const SCREENSHOT_PATH := "user://vfx_debug_capture.png"
const CAPTURE_PREFIX_DEFAULT := "user://vfx_debug_capture"
## Exit code for a golden-frame mismatch, distinct from the engine's own
## failure codes so a CI caller can tell a regression from a crash.
const EXIT_GOLDEN_FAILED := 3
## Full draw cycles to settle after seeking before a capture is read back.
## Two is enough for the shader uniforms and the draw to land; more does not
## improve stability (measured), because the residual variation is GPU particle
## scheduling rather than anything that settles with time.
const _CAPTURE_SETTLE_FRAMES := 2
## Golden comparison downsamples to this square before differencing. Comparing
## at full resolution is both slow in GDScript and needlessly brittle: it is
## structure — layer positions, palette, footprint shape — that a regression
## test should defend, not the exact pixel a given ember landed on.
const _GOLDEN_COMPARE_SIZE := 256
## Mean per-channel difference (0-255) tolerated before a capture counts as a
## regression.
##
## Calibrated from measurement, not taste. Repeat runs of the *same* effect
## differ by **0.00-0.03** (GPU particle scheduling). Swapping the effect
## entirely — ice storm against fire goldens — scores only **3.2**, because a
## mean taken over the whole frame is heavily diluted by the identical dark
## background and terrain that fill most of it. 0.5 sits roughly 16x above the
## noise and 6x below a total change.
##
## That dilution is this metric's real weakness: an effect occupying a small
## share of the frame produces a small mean even when it changes completely.
## Capture goldens framed so the effect fills a decent portion of the image, and
## treat a diff that is merely *near* tolerance as worth looking at rather than
## as a pass.
const _GOLDEN_TOLERANCE_DEFAULT := 0.5
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
const _UNEVEN_HEIGHTS := [[0, 1, 0], [1, 2, 1], [0, 1, 2]]

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
var _catalogEntries: Array[Dictionary] = []
var _activePlayback
var _overlapPlaybacks: Array = []
var _playbackState: String = _STATE_STOPPED
var _activeSeed: int = 1
var _activeMode: String = VfxPlaybackScript.MODE_BATTLE
var _layerVisibility: Dictionary = {}
var _syncingScrub: bool = false
var _captureUsed: bool = false
var _captureMessage: String = ""
var _footprintRadius: int = DEFAULT_FOOTPRINT_RADIUS
## Matches `data/spells.json`'s `AREA_SHAPE`. Drives both the effect's own
## footprint and the on-screen guide, so the two cannot disagree about which
## tiles a spell claims.
var _areaShape: String = "circle"
var _footprintRing: MeshInstance3D
var _goldenFailures: int = 0
var _textSpecimen: CanvasLayer
var _casterAnchor: Node3D
var _targetAnchor: Node3D
var _targetBodyVisual: MeshInstance3D
var _targetBodyBounds: AABB = VfxCastContext.DEFAULT_TARGET_BODY_BOUNDS

@onready var _sceneCasterAnchor: Node3D = $CasterAnchor
@onready var _sceneTargetAnchor: Node3D = $TargetAnchor
@onready var _camera: Camera3D = $Camera3D
@onready var _statusLabel: Label = $HUD/PanelContainer/Scroll/VBoxContainer/StatusLabel
@onready var _effectOption: OptionButton = $HUD/PanelContainer/Scroll/VBoxContainer/PlaybackGrid/EffectOption
@onready var _elementOption: OptionButton = $HUD/PanelContainer/Scroll/VBoxContainer/PlaybackGrid/ElementOption
@onready var _modeToggle: CheckButton = $HUD/PanelContainer/Scroll/VBoxContainer/PlaybackGrid/ModeToggle
@onready var _scaleSetting: SpinBox = $HUD/PanelContainer/Scroll/VBoxContainer/PlaybackGrid/ScaleSetting
@onready var _seedPin: CheckButton = $HUD/PanelContainer/Scroll/VBoxContainer/PlaybackGrid/SeedRow/SeedPin
@onready var _seedSetting: SpinBox = $HUD/PanelContainer/Scroll/VBoxContainer/PlaybackGrid/SeedRow/SeedSetting
@onready var _cycleSeedButton: Button = $HUD/PanelContainer/Scroll/VBoxContainer/PlaybackGrid/SeedRow/CycleSeedButton
@onready var _playButton: Button = $HUD/PanelContainer/Scroll/VBoxContainer/CoreButtons/PlayButton
@onready var _pauseButton: Button = $HUD/PanelContainer/Scroll/VBoxContainer/CoreButtons/PauseButton
@onready var _settleButton: Button = $HUD/PanelContainer/Scroll/VBoxContainer/CoreButtons/SettleButton
@onready var _overlapButton: Button = $HUD/PanelContainer/Scroll/VBoxContainer/CoreButtons/OverlapButton
@onready var _screenshotButton: Button = $HUD/PanelContainer/Scroll/VBoxContainer/CoreButtons/ScreenshotButton
@onready var _scrub: HSlider = $HUD/PanelContainer/Scroll/VBoxContainer/Scrub
@onready var _layerToggles: GridContainer = $HUD/PanelContainer/Scroll/VBoxContainer/LayerToggles
@onready var _resolutionOption: OptionButton = $HUD/PanelContainer/Scroll/VBoxContainer/Controls/ResolutionOption
@onready var _stretchOption: OptionButton = $HUD/PanelContainer/Scroll/VBoxContainer/Controls/StretchOption
@onready var _retroToggle: CheckButton = $HUD/PanelContainer/Scroll/VBoxContainer/Controls/RetroToggle
@onready var _crtToggle: CheckButton = $HUD/PanelContainer/Scroll/VBoxContainer/Controls/CRTToggle
@onready var _radiusSetting: SpinBox = $HUD/PanelContainer/Scroll/VBoxContainer/Controls/RadiusSetting
@onready var _targetBodyOption: OptionButton = $HUD/PanelContainer/Scroll/VBoxContainer/Controls/TargetBodyOption
@onready var _sourceDistanceSetting: SpinBox = $HUD/PanelContainer/Scroll/VBoxContainer/Controls/SourceDistanceSetting
@onready var _cameraYawSetting: SpinBox = $HUD/PanelContainer/Scroll/VBoxContainer/Controls/CameraYawSetting
@onready var _textToggle: CheckButton = $HUD/PanelContainer/Scroll/VBoxContainer/TextControls/TextToggle
@onready var _textFontOption: OptionButton = $HUD/PanelContainer/Scroll/VBoxContainer/TextControls/TextFontOption
@onready var _textSampleOption: OptionButton = $HUD/PanelContainer/Scroll/VBoxContainer/TextControls/TextSampleOption
@onready var _textScaleSetting: SpinBox = $HUD/PanelContainer/Scroll/VBoxContainer/TextControls/TextScaleSetting
@onready var _textEdgeOption: OptionButton = $HUD/PanelContainer/Scroll/VBoxContainer/TextControls/TextEdgeOption
@onready var _textEdgeSizeSetting: SpinBox = $HUD/PanelContainer/Scroll/VBoxContainer/TextControls/TextEdgeSizeSetting
@onready var _textBackdropOption: OptionButton = $HUD/PanelContainer/Scroll/VBoxContainer/TextControls/TextBackdropOption
@onready var _textFillOption: OptionButton = $HUD/PanelContainer/Scroll/VBoxContainer/TextControls/TextFillOption
@onready var _reloadGlyphsButton: Button = $HUD/PanelContainer/Scroll/VBoxContainer/TextButtons/ReloadGlyphsButton


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
	_reparentWorldNodes()
	_configureBattleWorld()
	_buildTerrainSamples()
	_buildContextAnchors()
	_buildTargetGuides()
	_configureRenderControls()
	_configurePlaybackControls()
	_configureTargetContextControls()
	_configureTextSpecimen()
	BattleMeshFactoryScript.prepareNodeMaterials(retroRenderer.world_root)
	_applyRenderControls()
	set_process(true)
	_updateStatus()

	_applyCommandLineOverrides()

	var captureTimes := _captureTimesArgument()
	if not captureTimes.is_empty():
		call_deferred("_runCaptureMode", captureTimes)


func _process(_delta: float) -> void:
	_pruneFinishedOverlaps()
	if _activePlayback != null and _activePlayback.is_finished():
		_playbackState = _STATE_STOPPED
		_pauseButton.disabled = true
		_pauseButton.text = "Pause"
	if _activePlayback != null:
		_syncingScrub = true
		_scrub.set_value_no_signal(_activePlayback.get_normalized_time())
		_syncingScrub = false
	_updateStatus()


func _input(event: InputEvent) -> void:
	if not (event is InputEventKey) or not event.pressed or event.echo:
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
			_captureOnce(false)
		KEY_H:
			$HUD.visible = not $HUD.visible
		KEY_M:
			_modeToggle.set_pressed_no_signal(not _modeToggle.button_pressed)
			_updateModeToggleText()
			_updateStatus()
		KEY_X:
			_textToggle.button_pressed = not _textToggle.button_pressed
		KEY_R:
			_onReloadGlyphsPressed()


func _exit_tree() -> void:
	_disposeAllPlaybacks()


func _configurePlaybackControls() -> void:
	_catalogEntries = SpellVfxCatalogScript.entries()
	assert(not _catalogEntries.is_empty(), "Spell VFX catalog must contain an effect.")
	for entry: Dictionary in _catalogEntries:
		_effectOption.add_item(entry["display_name"])
		_effectOption.set_item_metadata(
			_effectOption.item_count - 1,
			entry["profile_id"]
		)
	for element: String in _ELEMENTS:
		_elementOption.add_item(element.capitalize())
		_elementOption.set_item_metadata(_elementOption.item_count - 1, element)
	_elementOption.select(_ELEMENTS.find("ice"))
	_effectOption.select(_resolveInitialEffectIndex())
	_updateModeToggleText()

	_effectOption.item_selected.connect(_onEffectSelected)
	_elementOption.item_selected.connect(_onElementSelected)
	_modeToggle.toggled.connect(_onModeToggled)
	_scaleSetting.value_changed.connect(_onScaleChanged)
	_cycleSeedButton.pressed.connect(_cycleSeed)
	_playButton.pressed.connect(_onPlayPressed)
	_pauseButton.pressed.connect(_onPausePressed)
	_settleButton.pressed.connect(_onSettlePressed)
	_overlapButton.pressed.connect(_onOverlapPressed)
	_screenshotButton.pressed.connect(_captureOnce.bind(false))
	_scrub.value_changed.connect(_onScrubChanged)


func _configureTargetContextControls() -> void:
	for preset: Dictionary in _TARGET_BODY_PRESETS:
		_targetBodyOption.add_item(str(preset["label"]))
		_targetBodyOption.set_item_metadata(_targetBodyOption.item_count - 1, preset["id"])
	_targetBodyOption.select(0)
	_sourceDistanceSetting.set_value_no_signal(DEFAULT_SOURCE_DISTANCE)
	_cameraYawSetting.set_value_no_signal(DEFAULT_CAMERA_YAW_DEGREES)
	_targetBodyOption.item_selected.connect(_onTargetBodySelected)
	_sourceDistanceSetting.value_changed.connect(_onSourceDistanceChanged)
	_cameraYawSetting.value_changed.connect(_onCameraYawChanged)
	_applyTargetContextControls()


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
		_textFontOption.add_item(option["label"])
		_textFontOption.set_item_metadata(_textFontOption.item_count - 1, option["id"])
	for option: Dictionary in TextSpecimenScript.SAMPLE_OPTIONS:
		_textSampleOption.add_item(option["label"])
		_textSampleOption.set_item_metadata(_textSampleOption.item_count - 1, option["id"])
	for option: Dictionary in TextSpecimenScript.BACKDROP_OPTIONS:
		_textBackdropOption.add_item(option["label"])
		_textBackdropOption.set_item_metadata(_textBackdropOption.item_count - 1, option["id"])
	for option: Dictionary in TextSpecimenScript.EDGE_OPTIONS:
		_textEdgeOption.add_item(option["label"])
		_textEdgeOption.set_item_metadata(_textEdgeOption.item_count - 1, option["id"])
	for option: Dictionary in TextSpecimenScript.FILL_OPTIONS:
		_textFillOption.add_item(option["label"])
		_textFillOption.set_item_metadata(_textFillOption.item_count - 1, option["id"])
	_textFontOption.select(0)
	_textSampleOption.select(0)
	_textBackdropOption.select(0)
	_textEdgeOption.select(0)
	_textFillOption.select(TextSpecimenScript.default_fill_index())

	_textToggle.toggled.connect(_onTextToggled)
	_textFontOption.item_selected.connect(_onTextFontSelected)
	_textSampleOption.item_selected.connect(_onTextSampleSelected)
	_textScaleSetting.value_changed.connect(_onTextScaleChanged)
	_textEdgeOption.item_selected.connect(_onTextEdgeSelected)
	_textEdgeSizeSetting.value_changed.connect(_onTextEdgeSizeChanged)
	_textBackdropOption.item_selected.connect(_onTextBackdropSelected)
	_textFillOption.item_selected.connect(_onTextFillSelected)
	_reloadGlyphsButton.pressed.connect(_onReloadGlyphsPressed)


func _onTextToggled(enabled: bool) -> void:
	_textSpecimen.visible = enabled
	_updateStatus()


func _onTextFontSelected(index: int) -> void:
	_textSpecimen.set_font_id(_textFontOption.get_item_metadata(index))
	_updateStatus()


func _onTextSampleSelected(index: int) -> void:
	_textSpecimen.set_sample_id(_textSampleOption.get_item_metadata(index))
	_updateStatus()


func _onTextScaleChanged(value: float) -> void:
	_textSpecimen.set_specimen_scale(roundi(value))
	_updateStatus()


func _onTextEdgeSelected(index: int) -> void:
	_textSpecimen.set_edge_mode(_textEdgeOption.get_item_metadata(index))
	_updateStatus()


func _onTextEdgeSizeChanged(value: float) -> void:
	_textSpecimen.set_edge_size(roundi(value))
	_updateStatus()


func _onTextBackdropSelected(index: int) -> void:
	_textSpecimen.set_backdrop_id(_textBackdropOption.get_item_metadata(index))
	_updateStatus()


## Only visible under the `window` backdrop, which is the point: the fill is
## what a shadow has to be legible against, and picking one without the other
## settles nothing.
func _onTextFillSelected(index: int) -> void:
	_textSpecimen.set_fill_id(_textFillOption.get_item_metadata(index))
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
	var requested := _stringArgument("--effect=")
	if requested.is_empty():
		return 0
	for index: int in range(_catalogEntries.size()):
		if str(_catalogEntries[index]["profile_id"]) == requested:
			return index
	push_warning("Unknown --effect=%s; falling back to the first catalog entry." % requested)
	return 0


func _onEffectSelected(_index: int) -> void:
	_disposeAllPlaybacks()
	_rebuildLayerToggles([])
	_playbackState = _STATE_STOPPED
	_pauseButton.disabled = true
	_scrub.set_value_no_signal(0.0)
	_updateStatus()


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


func _onSourceDistanceChanged(_value: float) -> void:
	_applyTargetContextControls()


func _onCameraYawChanged(_value: float) -> void:
	_applyTargetContextControls()


func _onPlayPressed() -> void:
	_disposeAllPlaybacks()
	if not _seedPin.button_pressed:
		_cycleSeed()
	_activeSeed = int(_seedSetting.value)
	_activePlayback = _createSelectedPlayback()
	_applyLayerVisibility(_activePlayback)
	_applyFootprintTo(_activePlayback)
	_activePlayback.set_playback_scale(float(_scaleSetting.value))
	_activeMode = _selectedMode()
	_activePlayback.play(_activeSeed, _activeMode)
	_playbackState = _STATE_PLAYING
	_pauseButton.disabled = false
	_pauseButton.text = "Pause"
	_scrub.set_value_no_signal(0.0)
	_rebuildLayerToggles(_activePlayback.get_layer_names())
	_updateStatus()


func _onPausePressed() -> void:
	if _activePlayback == null or _activePlayback.is_finished():
		return
	if _playbackState == _STATE_PAUSED:
		_setAllPlaybackScales(float(_scaleSetting.value))
		_playbackState = _STATE_PLAYING
		_pauseButton.text = "Pause"
	else:
		_setAllPlaybackScales(0.0)
		_playbackState = _STATE_PAUSED
		_pauseButton.text = "Resume"
	_updateStatus()


func _onSettlePressed() -> void:
	if _activePlayback == null or _activePlayback.is_finished():
		_onPlayPressed()
	_disposeOverlaps()
	_activePlayback.set_playback_scale(0.0)
	_activePlayback.skip_to_settle()
	_playbackState = _STATE_PAUSED
	_pauseButton.disabled = false
	_pauseButton.text = "Resume"
	_scrub.set_value_no_signal(_activePlayback.get_normalized_time())
	_updateStatus()


func _onScrubChanged(value: float) -> void:
	if _syncingScrub or _activePlayback == null:
		return
	_disposeOverlaps()
	_activePlayback.set_playback_scale(0.0)
	_activePlayback.seek_normalized(value)
	if _activePlayback.is_finished():
		_playbackState = _STATE_STOPPED
		_pauseButton.disabled = true
		_pauseButton.text = "Pause"
	else:
		_playbackState = _STATE_PAUSED
		_pauseButton.disabled = false
		_pauseButton.text = "Resume"
	_updateStatus()


func _onOverlapPressed() -> void:
	if not _seedPin.button_pressed:
		_cycleSeed()
	var overlapSeed := int(_seedSetting.value)
	var overlap = _createSelectedPlayback()
	_applyLayerVisibility(overlap)
	_applyFootprintTo(overlap)
	overlap.set_playback_scale(
		0.0 if _playbackState == _STATE_PAUSED else float(_scaleSetting.value)
	)
	overlap.play(overlapSeed, _selectedMode())
	if _playbackState == _STATE_PAUSED:
		overlap.set_playback_scale(0.0)
	_overlapPlaybacks.append(overlap)
	if _activePlayback == null:
		_rebuildLayerToggles(overlap.get_layer_names())
	_updateStatus()


func _createSelectedPlayback() -> VfxPlayback:
	var profileId: String = _effectOption.get_item_metadata(_effectOption.selected)
	var color := BattleMeshFactoryScript.elementColor(
		_elementOption.get_item_metadata(_elementOption.selected)
	)
	var playback: VfxPlayback = SpellVfxCatalogScript.create(
		profileId,
		retroRenderer.world_root,
		_targetAnchor.position,
		color
	)
	playback.configure_cast_context(_buildCastContext())
	return playback


func _buildCastContext() -> VfxCastContext:
	var targetIDs: Array[int] = [DEBUG_TARGET_ID]
	var targetPositions: Array[Vector3] = [_targetAnchor.position]
	var targetBounds: Array[AABB] = [_targetBodyBounds]
	return VfxCastContextScript.create(
		DEBUG_CASTER_ID,
		_casterAnchor.position,
		_targetAnchor.position,
		targetIDs,
		targetPositions,
		targetBounds
	)


func _selectedMode() -> String:
	return (
		VfxPlaybackScript.MODE_BATTLE
		if _modeToggle.button_pressed
		else VfxPlaybackScript.MODE_REFERENCE
	)


func _updateModeToggleText() -> void:
	_modeToggle.text = "Battle speed" if _modeToggle.button_pressed else "Reference speed"


func _cycleSeed() -> void:
	var nextSeed := int(_seedSetting.value) + 1
	if nextSeed >= 2147483647:
		nextSeed = 1
	_seedSetting.set_value_no_signal(nextSeed)
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
	for child: Node in _layerToggles.get_children():
		child.queue_free()
	for layerName: String in layerNames:
		if not _layerVisibility.has(layerName):
			_layerVisibility[layerName] = true
		var toggle := CheckButton.new()
		toggle.text = layerName.capitalize()
		toggle.button_pressed = bool(_layerVisibility[layerName])
		toggle.toggled.connect(_onLayerToggled.bind(layerName))
		_layerToggles.add_child(toggle)


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
	if _effectOption.item_count == 0:
		return
	var elapsed := 0.0
	var total := 0.0
	var normalized := 0.0
	var particles := 0
	var nodes := 0
	var drawCalls := 0
	var seekExact := true
	if _activePlayback != null and is_instance_valid(_activePlayback):
		elapsed = _activePlayback.get_elapsed_time()
		total = _activePlayback.get_total_duration()
		normalized = _activePlayback.get_normalized_time()
		particles += _activePlayback.get_live_particle_count()
		nodes += _activePlayback.get_live_node_count()
		drawCalls += _estimateDrawCalls(_activePlayback)
		seekExact = _activePlayback.is_particle_seek_exact()
	for overlap in _overlapPlaybacks:
		if is_instance_valid(overlap):
			particles += overlap.get_live_particle_count()
			nodes += overlap.get_live_node_count()
			drawCalls += _estimateDrawCalls(overlap)
			seekExact = seekExact and overlap.is_particle_seek_exact()
	var modeLabel := _activeMode if _activePlayback != null else _selectedMode()
	var renderLabel := _resolutionOption.get_item_text(_resolutionOption.selected)
	var captureSuffix := "\n" + _captureMessage if not _captureMessage.is_empty() else ""
	var statusSeed := _activeSeed if _activePlayback != null else int(_seedSetting.value)
	# Explicitly typed: `_textSpecimen` is a plain CanvasLayer to the parser, so
	# the return type of `describe()` cannot be inferred here.
	var specimenLine: String = (
		"\n" + _textSpecimen.describe() if _textSpecimen != null else ""
	)
	_statusLabel.text = (
		"%s / %s\n%s speed @ %.2fx | t %.2f | %.2f / %.2fs\n" +
		"seed %d | nodes %d | particles %d | draw calls ~%d | overlaps %d | flurry: %s\n" +
		"target %s | bounds %.2f x %.2f x %.2f | separation %.2f | yaw %.0f degrees\n" +
		"%s | Retro %s | CRT %s%s%s"
	) % [
		_effectOption.get_item_text(_effectOption.selected),
		_playbackState,
		modeLabel,
		float(_scaleSetting.value),
		normalized,
		elapsed,
		total,
		statusSeed,
		nodes,
		particles,
		drawCalls,
		_overlapPlaybacks.size(),
		"exact" if seekExact else "approx",
		_targetBodyOption.get_item_text(_targetBodyOption.selected),
		_targetBodyBounds.size.x,
		_targetBodyBounds.size.y,
		_targetBodyBounds.size.z,
		float(_sourceDistanceSetting.value),
		float(_cameraYawSetting.value),
		renderLabel,
		"ON" if _retroToggle.button_pressed else "OFF",
		"ON" if _crtToggle.button_pressed else "OFF",
		captureSuffix,
		specimenLine
	]


func _estimateDrawCalls(node: Node) -> int:
	var estimate := 0
	var meshInstance := node as MeshInstance3D
	if meshInstance != null and meshInstance.visible and meshInstance.mesh != null:
		estimate += maxi(meshInstance.mesh.get_surface_count(), 1)
	var particles := node as GPUParticles3D
	if particles != null and particles.visible:
		for passIndex in range(particles.draw_passes):
			var drawMesh := particles.get_draw_pass_mesh(passIndex)
			if drawMesh != null:
				estimate += maxi(drawMesh.get_surface_count(), 1)
	var multiMesh := node as MultiMeshInstance3D
	if multiMesh != null and multiMesh.visible and multiMesh.multimesh != null:
		var mesh := multiMesh.multimesh.mesh
		if mesh != null:
			estimate += maxi(mesh.get_surface_count(), 1)
	for child: Node in node.get_children():
		estimate += _estimateDrawCalls(child)
	return estimate


func _cmdlineArguments() -> PackedStringArray:
	var arguments: PackedStringArray = OS.get_cmdline_args()
	arguments.append_array(OS.get_cmdline_user_args())
	return arguments


## Accepts either a single time or a comma-separated series. A series is
## captured within one process: the engine boot dominates the cost of a single
## capture, so paying it once for five frames instead of five times is the
## difference between a phase sweep being routine and being avoided.
func _captureTimesArgument() -> PackedFloat32Array:
	var times := PackedFloat32Array()
	var raw := _stringArgument("--capture-at=")
	if raw.is_empty():
		return times
	for piece: String in raw.split(",", false):
		var trimmed := piece.strip_edges()
		if trimmed.is_valid_float():
			times.append(clampf(trimmed.to_float(), 0.0, 1.0))
		else:
			push_warning("Invalid --capture-at value: %s" % trimmed)
	return times


func _floatArgument(prefix: String, fallback: float) -> float:
	var raw := _stringArgument(prefix)
	if raw.is_empty():
		return fallback
	if not raw.is_valid_float():
		push_warning("Invalid %s value: %s" % [prefix, raw])
		return fallback
	return raw.to_float()


func _intArgument(prefix: String, fallback: int) -> int:
	var raw := _stringArgument(prefix)
	if raw.is_empty():
		return fallback
	if not raw.is_valid_int():
		push_warning("Invalid %s value: %s" % [prefix, raw])
		return fallback
	return raw.to_int()


## Applied after the controls are built but before any capture, so a scripted
## run sees exactly the state an interactive session would after setting the
## same controls by hand.
func _applyCommandLineOverrides() -> void:
	var radius := _intArgument("--radius=", DEFAULT_FOOTPRINT_RADIUS)
	if radius != DEFAULT_FOOTPRINT_RADIUS:
		_radiusSetting.set_value_no_signal(radius)
		_footprintRadius = maxi(1, radius)

	var shape := _stringArgument("--shape=")
	if not shape.is_empty():
		if shape in ["circle", "cross", "line"]:
			_areaShape = shape
		else:
			push_warning("Unknown --shape=%s; keeping circle." % shape)
	_updateFootprintRing()

	var seedValue := _intArgument("--seed=", -1)
	if seedValue >= 0:
		# Pin, or `_onPlayPressed` would cycle straight past the requested seed.
		_seedSetting.set_value_no_signal(seedValue)
		_seedPin.set_pressed_no_signal(true)

	var scale := _floatArgument("--scale=", -1.0)
	if scale > 0.0:
		_scaleSetting.set_value_no_signal(scale)

	var targetBody := _stringArgument("--target-body=")
	if not targetBody.is_empty():
		if not _selectOptionByMetadata(
				_targetBodyOption, targetBody, _onTargetBodySelected):
			push_warning("Unknown --target-body=%s; keeping standard." % targetBody)
	var sourceDistance := _floatArgument("--source-distance=", -1.0)
	if sourceDistance > 0.0:
		_sourceDistanceSetting.set_value_no_signal(sourceDistance)
	var cameraYaw := _floatArgument("--camera-yaw=", INF)
	if cameraYaw != INF:
		_cameraYawSetting.set_value_no_signal(cameraYaw)
	_applyTargetContextControls()

	var stretch := _stringArgument("--stretch=")
	if not stretch.is_empty():
		if not _selectOptionByMetadata(_stretchOption, stretch, _onStretchSelected):
			push_warning("Unknown --stretch=%s; keeping native (the project default)." % stretch)

	if _hasFlagArgument("--retro"):
		_retroToggle.set_pressed_no_signal(true)
	if _hasFlagArgument("--crt"):
		_crtToggle.set_pressed_no_signal(true)
	if _hasFlagArgument("--retro") or _hasFlagArgument("--crt"):
		_applyRenderControls()

	# Scanline and mask pitch are in device pixels, so what they look like
	# depends entirely on the window. Exposing them makes "should these follow
	# the UI scale?" a question answered by capturing both, rather than argued.
	# `set_crt_parameter`, not `set_look_parameter` — the two have separate match
	# statements and the look setter silently ignores a CRT parameter name
	# rather than rejecting it. Passing one to the wrong setter is a no-op that
	# looks exactly like a shader that ignored the value.
	var scanlineSize := _floatArgument("--crt-scanline-size=", -1.0)
	if scanlineSize > 0.0:
		retroRenderer.set_crt_parameter(
			retroRenderer.CRT_SCANLINE_SIZE, scanlineSize, false
		)
	var maskSize := _floatArgument("--crt-mask-size=", -1.0)
	if maskSize > 0.0:
		retroRenderer.set_crt_parameter(
			retroRenderer.CRT_MASK_SIZE, maskSize, false
		)

	if _hasFlagArgument("--hide-hud"):
		$HUD.visible = false

	_applyTextCommandLineOverrides()


## Routed through the HUD controls rather than straight at the specimen, so a
## scripted run and a hand-driven one cannot diverge: whatever the flags set is
## visible in the panel, and whatever the panel shows is what a flag would have
## produced.
func _applyTextCommandLineOverrides() -> void:
	var face := _stringArgument("--text-font=")
	if not face.is_empty():
		if not _selectOptionByMetadata(_textFontOption, face, _onTextFontSelected):
			push_warning("Unknown --text-font=%s; keeping the live source face." % face)

	var sample := _stringArgument("--text-sample=")
	if not sample.is_empty():
		if not _selectOptionByMetadata(_textSampleOption, sample, _onTextSampleSelected):
			push_warning("Unknown --text-sample=%s; keeping the reference sentence." % sample)

	var backdrop := _stringArgument("--text-backdrop=")
	if not backdrop.is_empty():
		if not _selectOptionByMetadata(_textBackdropOption, backdrop, _onTextBackdropSelected):
			push_warning("Unknown --text-backdrop=%s; keeping the board." % backdrop)

	var fill := _stringArgument("--text-fill=")
	if not fill.is_empty():
		if not _selectOptionByMetadata(_textFillOption, fill, _onTextFillSelected):
			push_warning("Unknown --text-fill=%s; keeping the current WINDOW_FILL." % fill)

	var textScale := _intArgument("--text-scale=", -1)
	if textScale > 0:
		_textScaleSetting.value = clampi(
			textScale, TextSpecimenScript.MIN_SCALE, TextSpecimenScript.MAX_SCALE
		)

	var edge := _stringArgument("--text-edge=")
	if not edge.is_empty():
		if not _selectOptionByMetadata(_textEdgeOption, edge, _onTextEdgeSelected):
			push_warning("Unknown --text-edge=%s; keeping the drop shadow." % edge)

	var edgeSize := _intArgument("--text-edge-size=", -1)
	if edgeSize >= 0:
		_textEdgeSizeSetting.value = clampi(edgeSize, 0, TextSpecimenScript.MAX_EDGE_SIZE)

	# Last, so the overlay is already configured the moment it appears and a
	# capture taken immediately after cannot catch it mid-setup.
	if _hasFlagArgument("--text"):
		_textToggle.button_pressed = true


## Selects the entry whose metadata equals `id` and runs the same handler the
## user's click would have run. Returns false when nothing matches.
func _selectOptionByMetadata(
		option: OptionButton, id: String, handler: Callable) -> bool:
	for index: int in range(option.item_count):
		if str(option.get_item_metadata(index)) == id:
			option.select(index)
			handler.call(index)
			return true
	return false


## Isolation runs after `_onPlayPressed`, because that call rebuilds the toggle
## row from the live playback's own layer list — applying it earlier would be
## overwritten.
func _applyLayerIsolation() -> void:
	var requested := _stringArgument("--layers=")
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


func _stringArgument(prefix: String) -> String:
	for argument: String in _cmdlineArguments():
		if argument.begins_with(prefix):
			return argument.trim_prefix(prefix)
	return ""


func _hasFlagArgument(flag: String) -> bool:
	return _cmdlineArguments().has(flag)


func _runCaptureMode(times: PackedFloat32Array) -> void:
	if DisplayServer.get_name() == "headless":
		push_error("--capture-at requires a rendered display; headless capture is unsupported.")
		get_tree().quit(2)
		return
	_onPlayPressed()
	_applyLayerIsolation()

	var prefix := _stringArgument("--capture-out=")
	if prefix.is_empty():
		prefix = CAPTURE_PREFIX_DEFAULT
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
		# `GPUParticles3D.request_particles_process()` is serviced asynchronously
		# by the rendering server, so a capture taken too eagerly samples a
		# partially-advanced system. Measured: with a single settle frame the
		# same timestamp reproduced only intermittently. Settling across several
		# full draw cycles is what makes the result byte-stable, and byte
		# stability is the whole basis of the golden comparison below.
		for _settle: int in range(_CAPTURE_SETTLE_FRAMES):
			await get_tree().process_frame
			await RenderingServer.frame_post_draw
		var image := get_viewport().get_texture().get_image()
		frames.append(image)
		# A lone capture keeps the historical single-file path so existing
		# invocations and any stored reference paths still resolve.
		var name := (
				prefix.get_file()
				if single
				else "%s_t%s" % [prefix.get_file(), String.num(normalizedTime, 2)])
		var path := "%s.png" % (prefix if single else prefix.get_base_dir().path_join(name))
		var error := image.save_png(path)
		if error != OK:
			lastError = error
		print("VFX_DEBUG_CAPTURE path=%s error=%d" % [
			ProjectSettings.globalize_path(path), error
		])
		_checkGolden(name, image)

	if _hasFlagArgument("--capture-sheet") and frames.size() > 1:
		var sheetPath := "%s_sheet.png" % prefix
		var sheetError := _writeContactSheet(frames, sheetPath)
		if sheetError != OK:
			lastError = sheetError
		print("VFX_DEBUG_SHEET path=%s error=%d frames=%d" % [
			ProjectSettings.globalize_path(sheetPath), sheetError, frames.size()
		])

	if _goldenFailures > 0:
		print("VFX_GOLDEN_RESULT failures=%d" % _goldenFailures)
		get_tree().quit(EXIT_GOLDEN_FAILED)
		return
	get_tree().quit(lastError)


## Tiles the series into one image so a phase sweep can be judged in a single
## look, side by side, instead of by holding four separate frames in memory.
## Four columns keeps a typical sweep on one row; motion reads left to right.
func _writeContactSheet(frames: Array[Image], path: String) -> int:
	var scale := clampf(_floatArgument("--sheet-scale=", 0.5), 0.05, 1.0)
	var cellWidth := maxi(int(float(frames[0].get_width()) * scale), 1)
	var cellHeight := maxi(int(float(frames[0].get_height()) * scale), 1)
	var columns := mini(frames.size(), 4)
	var rows := int(ceil(float(frames.size()) / float(columns)))
	var sheet := Image.create(
			cellWidth * columns, cellHeight * rows, false, Image.FORMAT_RGBA8)
	for index: int in range(frames.size()):
		var cell := frames[index].duplicate() as Image
		cell.resize(cellWidth, cellHeight, Image.INTERPOLATE_BILINEAR)
		cell.convert(Image.FORMAT_RGBA8)
		sheet.blit_rect(
				cell,
				Rect2i(Vector2i.ZERO, cell.get_size()),
				Vector2i((index % columns) * cellWidth, (index / columns) * cellHeight))
	return sheet.save_png(path)


## Compares a capture against a stored reference, or records a new one.
##
## **Tolerance-based, not byte-exact, and that is a measured decision.** The
## GDScript timeline is deterministic — the same effect, seed and timestamp
## produce the same uniforms every run — but `GPUParticles3D` is not: its
## `restart()` / `request_particles_process()` work is scheduled on the
## rendering server, and identical runs were observed producing different
## frames for the same timestamp. Replaying from zero before each seek made it
## much closer, and additional settle frames did not help at all, which is what
## identifies the residue as scheduling rather than a race that time fixes.
##
## So the comparison defends structure instead of pixels: both images are
## downsampled and differenced, and anything under `_GOLDEN_TOLERANCE_DEFAULT`
## passes. That still fails loudly on the regressions worth catching — a wrong
## palette, a dropped layer, a footprint of the wrong shape — while ignoring
## which exact pixel an individual ember landed on.
##
## Raw pixel data is compared rather than encoded PNG bytes, so a future
## encoder change cannot masquerade as a regression.
func _checkGolden(name: String, image: Image) -> void:
	var goldenDir := _stringArgument("--golden=")
	if goldenDir.is_empty():
		return
	var goldenPath := goldenDir.path_join("%s.png" % name)
	if _hasFlagArgument("--golden-write"):
		DirAccess.make_dir_recursive_absolute(goldenDir)
		var writeError := image.save_png(goldenPath)
		print("VFX_GOLDEN name=%s status=%s path=%s" % [
			name,
			"WROTE" if writeError == OK else "WRITE_FAILED",
			ProjectSettings.globalize_path(goldenPath)
		])
		if writeError != OK:
			_goldenFailures += 1
		return
	if not FileAccess.file_exists(goldenPath):
		print("VFX_GOLDEN name=%s status=MISSING path=%s" % [
			name, ProjectSettings.globalize_path(goldenPath)
		])
		_goldenFailures += 1
		return
	var golden := Image.load_from_file(goldenPath)
	if golden == null:
		print("VFX_GOLDEN name=%s status=UNREADABLE path=%s" % [
			name, ProjectSettings.globalize_path(goldenPath)
		])
		_goldenFailures += 1
		return
	var tolerance := _floatArgument("--golden-tolerance=", _GOLDEN_TOLERANCE_DEFAULT)
	var difference := _meanImageDifference(golden, image)
	var matched := difference <= tolerance
	print("VFX_GOLDEN name=%s status=%s diff=%.2f tolerance=%.2f" % [
		name, "MATCH" if matched else "DIFF", difference, tolerance
	])
	if not matched:
		_goldenFailures += 1


## Mean absolute per-channel difference between two images, 0-255, computed on
## a downsampled copy of each. Returns a large sentinel when the images cannot
## be compared at all, so a size or format surprise fails rather than passing
## silently.
func _meanImageDifference(first: Image, second: Image) -> float:
	var a := first.duplicate() as Image
	var b := second.duplicate() as Image
	a.convert(Image.FORMAT_RGBA8)
	b.convert(Image.FORMAT_RGBA8)
	a.resize(_GOLDEN_COMPARE_SIZE, _GOLDEN_COMPARE_SIZE, Image.INTERPOLATE_BILINEAR)
	b.resize(_GOLDEN_COMPARE_SIZE, _GOLDEN_COMPARE_SIZE, Image.INTERPOLATE_BILINEAR)
	var dataA := a.get_data()
	var dataB := b.get_data()
	if dataA.size() != dataB.size() or dataA.is_empty():
		return 255.0
	var total := 0.0
	for index: int in range(dataA.size()):
		total += absf(float(dataA[index]) - float(dataB[index]))
	return total / float(dataA.size())


func _captureOnce(quitAfter: bool = false) -> void:
	if _captureUsed:
		_captureMessage = "Capture skipped: one capture is allowed per process."
		_updateStatus()
		if quitAfter:
			get_tree().quit(1)
		return
	if DisplayServer.get_name() == "headless":
		_captureMessage = "Capture unavailable: run with a rendered display."
		push_error(_captureMessage)
		_updateStatus()
		if quitAfter:
			get_tree().quit(2)
		return
	_captureUsed = true
	_screenshotButton.disabled = true
	await RenderingServer.frame_post_draw
	var error := get_viewport().get_texture().get_image().save_png(SCREENSHOT_PATH)
	var absolutePath := ProjectSettings.globalize_path(SCREENSHOT_PATH)
	_captureMessage = (
		"Capture saved: %s" % absolutePath
		if error == OK
		else "Capture failed with error %d" % error
	)
	print("VFX_DEBUG_CAPTURE path=%s error=%d" % [absolutePath, error])
	_updateStatus()
	if quitAfter:
		get_tree().quit(error)


func _configureRenderControls() -> void:
	for optionIndex in range(_RESOLUTION_OPTIONS.size()):
		var option: Dictionary = _RESOLUTION_OPTIONS[optionIndex]
		_resolutionOption.add_item(option["label"])
		_resolutionOption.set_item_metadata(optionIndex, option["size"])
	_resolutionOption.select(0)
	for preset: Dictionary in _STRETCH_PRESETS:
		_stretchOption.add_item(preset["label"])
		_stretchOption.set_item_metadata(_stretchOption.item_count - 1, preset["id"])
	_stretchOption.select(0)
	_stretchOption.item_selected.connect(_onStretchSelected)
	_retroToggle.set_pressed_no_signal(true)
	_crtToggle.set_pressed_no_signal(false)
	_radiusSetting.set_value_no_signal(DEFAULT_FOOTPRINT_RADIUS)
	_resolutionOption.item_selected.connect(_onResolutionSelected)
	_retroToggle.toggled.connect(_onRenderToggleChanged)
	_crtToggle.toggled.connect(_onRenderToggleChanged)
	_radiusSetting.value_changed.connect(_onRadiusChanged)


func _onResolutionSelected(index: int) -> void:
	_retroToggle.set_pressed_no_signal(index != 0)
	_applyRenderControls()


## Applied to the live root window rather than to `project.godot`. Changing the
## project setting is a decision affecting every screen in the game; this makes
## the consequences visible first, and the specimen's pixel-exactness readout
## reports the resulting factor immediately.
func _onStretchSelected(index: int) -> void:
	var id: String = _stretchOption.get_item_metadata(index)
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
	_footprintRadius = maxi(1, roundi(value))
	_updateFootprintRing()
	_applyFootprintTo(_activePlayback)
	for overlap in _overlapPlaybacks:
		_applyFootprintTo(overlap)
	_updateStatus()


## No-op for playbacks (like the generic aura) that don't expose a footprint.
## The guide always draws the diamond `ShapeCaster.getCircle` shape, which is
## every carrier's shape except `cross`/`line` — see `IceStormEffect._isDiamondShape`.
func _applyFootprintTo(playback) -> void:
	if playback != null and is_instance_valid(playback) and playback.has_method("setFootprint"):
		playback.call("setFootprint", _footprintRadius, 0.0, _areaShape)


func _applyRenderControls() -> void:
	var selectedSize: Vector2i = _resolutionOption.get_item_metadata(
		_resolutionOption.selected
	)
	retroRenderer.render_size = (
		selectedSize if selectedSize != Vector2i.ZERO else get_window().size
	)
	retroRenderer.retro_enabled = _retroToggle.button_pressed
	retroRenderer.crt_enabled = _crtToggle.button_pressed
	retroRenderer.set_look_parameter(
		retroRenderer.LOOK_RENDER_SCALE,
		retroRenderer.get_look_parameter(retroRenderer.LOOK_RENDER_SCALE),
		false
	)
	_updateStatus()


func _reparentWorldNodes() -> void:
	for worldNode: Node3D in [
		_camera, $DirectionalLight, $Ground, _sceneCasterAnchor, _sceneTargetAnchor
	]:
		worldNode.reparent(retroRenderer.world_root, false)
	_casterAnchor = _sceneCasterAnchor
	_targetAnchor = _sceneTargetAnchor


func _configureBattleWorld() -> void:
	var worldEnvironment := WorldEnvironment.new()
	worldEnvironment.name = "WorldEnvironment"
	worldEnvironment.environment = BattleEnvironmentFactoryScript.createBattleEnvironment()
	retroRenderer.world_root.add_child(worldEnvironment)
	_camera.projection = Camera3D.PROJECTION_ORTHOGONAL
	_camera.size = REPRESENTATIVE_CAMERA_SIZE
	_camera.current = true


func _buildTerrainSamples() -> void:
	var previewTerrain := Node3D.new()
	previewTerrain.name = "TerrainSamples"
	retroRenderer.world_root.add_child(previewTerrain)
	for zIndex in range(3):
		for xIndex in range(3):
			_addTerrainColumn(
				previewTerrain, Vector2i(xIndex - 3, zIndex - 1), 0,
				Color(0.22, 0.58, 0.28)
			)
			_addTerrainColumn(
				previewTerrain, Vector2i(xIndex + 1, zIndex - 1),
				int(_UNEVEN_HEIGHTS[zIndex][xIndex]), Color(0.34, 0.48, 0.68)
			)


func _addTerrainColumn(
		parent: Node3D,
		coord: Vector2i,
		height: int,
		baseColor: Color) -> void:
	var column := Node3D.new()
	column.name = "Terrain_%d_%d" % [coord.x, coord.y]
	column.position = Vector3(coord.x, 0.0, coord.y)
	parent.add_child(column)
	for layerIndex in range(height + 1):
		var depth := height - layerIndex
		var blockColor := baseColor.darkened(minf(float(depth) * 0.08, 0.24))
		var block := BattleMeshFactoryScript.createMesh("terrain_block", blockColor)
		block.name = "Layer_%d" % layerIndex
		block.position.y = float(layerIndex) * BattleMeshFactoryScript.TERRAIN_CELL_SIZE.y
		column.add_child(block)


func _buildContextAnchors() -> void:
	assert(_casterAnchor != null and _targetAnchor != null, "VFX anchors must be reparented first.")
	_casterAnchor.name = "CasterAnchor"
	_targetAnchor.name = "TargetAnchor"
	_addAnchorMarker(_casterAnchor, "CasterMarker", Color(0.18, 0.72, 1.0, 0.85))
	_addAnchorMarker(_targetAnchor, "TargetMarker", Color(1.0, 0.55, 0.3, 0.85))

	var casterBase := BattleMeshFactoryScript.createModelBase(Color(0.18, 0.42, 0.95), 0)
	_casterAnchor.add_child(casterBase)
	var casterBody := BattleMeshFactoryScript.createMesh("shape_capsule", Color(0.62, 0.9, 0.95))
	casterBody.name = "CasterBody"
	casterBody.position.y = BattleMeshFactoryScript.BASE_TOTAL_HEIGHT + 0.4
	_casterAnchor.add_child(casterBody)

	var targetBase := BattleMeshFactoryScript.createModelBase(Color(0.9, 0.2, 0.16), 1)
	_targetAnchor.add_child(targetBase)
	_targetBodyVisual = BattleMeshFactoryScript.createMesh("shape_cube", Color(0.82, 0.45, 0.2))
	_targetBodyVisual.name = "TargetBodyBounds"
	_targetAnchor.add_child(_targetBodyVisual)


func _addAnchorMarker(anchor: Node3D, markerName: String, color: Color) -> void:
	var marker := BattleMeshFactoryScript.createMesh("cursor", color)
	marker.name = markerName
	marker.position.y = 0.02
	marker.scale = Vector3(0.18, 0.18, 0.18)
	anchor.add_child(marker)


func _buildTargetGuides() -> void:
	var targetMarker := BattleMeshFactoryScript.createMesh(
		"cursor", Color(0.2, 0.85, 1.0, 0.8)
	)
	targetMarker.name = "TargetCentreMarker"
	targetMarker.position.y = 0.02
	targetMarker.scale = Vector3(0.22, 0.22, 0.22)
	_targetAnchor.add_child(targetMarker)
	_footprintRing = MeshInstance3D.new()
	_footprintRing.name = "FootprintGuide"
	_footprintRing.position.y = 0.035
	# Far more translucent than the outline band this replaced: it now fills the
	# whole footprint rather than tracing its edge, so it has to sit under the
	# effect without competing with it.
	_footprintRing.material_override = BattleMeshFactoryScript.createMaterial(
		Color(0.42, 0.82, 1.0, 0.16), true, 0.6
	)
	_targetAnchor.add_child(_footprintRing)
	_updateFootprintRing()


func _applyTargetContextControls() -> void:
	if _casterAnchor == null or _targetAnchor == null or _targetBodyVisual == null:
		return
	var preset: Dictionary = _TARGET_BODY_PRESETS[_targetBodyOption.selected]
	_targetBodyBounds = preset["bounds"]
	var targetSurfaceY := _surfaceY(0)
	_targetAnchor.position = Vector3(0.0, targetSurfaceY, 0.0)
	_casterAnchor.position = _targetAnchor.position + Vector3(
		-float(_sourceDistanceSetting.value), 0.0, 0.0
	)
	_targetBodyVisual.position = _targetBodyBounds.get_center()
	var bodyMesh := _targetBodyVisual.mesh as BoxMesh
	if bodyMesh != null:
		bodyMesh.size = _targetBodyBounds.size
	_updateCameraFraming()
	_updateStatus()


func _updateCameraFraming() -> void:
	var focus := (_casterAnchor.position + _targetAnchor.position) * 0.5
	focus.y += _targetBodyBounds.get_center().y * 0.5
	var yawRadians := deg_to_rad(float(_cameraYawSetting.value))
	var offset := Vector3(
		CAMERA_OFFSET.x * cos(yawRadians) + CAMERA_OFFSET.z * sin(yawRadians),
		CAMERA_OFFSET.y,
		-CAMERA_OFFSET.x * sin(yawRadians) + CAMERA_OFFSET.z * cos(yawRadians)
	)
	_camera.size = maxf(REPRESENTATIVE_CAMERA_SIZE, float(_sourceDistanceSetting.value) + 5.0)
	_camera.position = focus + offset
	_camera.look_at(focus, Vector3.UP)


## A flat translucent polygon covering exactly the tiles the spell affects.
##
## Filled rather than an outline band because the guide must now follow any
## `AREA_SHAPE`, and offsetting a non-convex outline (the cross) into a clean
## band is far more work than triangulating the region itself. Built
## double-sided — each triangle added in both windings — so it reads regardless
## of the camera's orbit, without depending on the material's cull mode.
func _updateFootprintRing() -> void:
	if _footprintRing == null:
		return
	var polygon := _footprintPolygon(_footprintRadius, _areaShape)
	var indices := Geometry2D.triangulate_polygon(polygon)
	var surfaceTool := SurfaceTool.new()
	surfaceTool.begin(Mesh.PRIMITIVE_TRIANGLES)
	for triangle: int in range(0, indices.size(), 3):
		var a := _groundPoint(polygon[indices[triangle]])
		var b := _groundPoint(polygon[indices[triangle + 1]])
		var c := _groundPoint(polygon[indices[triangle + 2]])
		surfaceTool.add_vertex(a)
		surfaceTool.add_vertex(b)
		surfaceTool.add_vertex(c)
		surfaceTool.add_vertex(a)
		surfaceTool.add_vertex(c)
		surfaceTool.add_vertex(b)
	_footprintRing.mesh = surfaceTool.commit()


func _groundPoint(point: Vector2) -> Vector3:
	return Vector3(point.x, 0.0, point.y)


## The tiles each `AREA_SHAPE` actually covers, in world units with tile = 1.0.
## A radius-R footprint reaches R + 0.5 from centre because the outermost tile
## contributes its own half-width — the same `radius + 0.5` the effects use for
## their own boundaries, so guide and effect agree by construction.
func _footprintPolygon(radius: int, shape: String) -> PackedVector2Array:
	var extent := float(radius) + 0.5
	match shape:
		"cross":
			# Twelve corners tracing a plus: arms one tile wide (half-width 0.5)
			# reaching `extent` along each axis. Matches ShapeCaster.getCross.
			var arm := 0.5
			return PackedVector2Array([
				Vector2(extent, arm), Vector2(arm, arm), Vector2(arm, extent),
				Vector2(-arm, extent), Vector2(-arm, arm), Vector2(-extent, arm),
				Vector2(-extent, -arm), Vector2(-arm, -arm), Vector2(-arm, -extent),
				Vector2(arm, -extent), Vector2(arm, -arm), Vector2(extent, -arm),
			])
		"line":
			# Direction-dependent in play and unknown here, so the guide shows
			# the reachable band rather than claiming a specific orientation.
			return PackedVector2Array([
				Vector2(extent, 0.5), Vector2(-extent, 0.5),
				Vector2(-extent, -0.5), Vector2(extent, -0.5),
			])
		_:
			# Manhattan diamond — ShapeCaster.getCircle, the default for every
			# area spell that does not set AREA_SHAPE.
			return PackedVector2Array([
				Vector2(extent, 0.0), Vector2(0.0, extent),
				Vector2(-extent, 0.0), Vector2(0.0, -extent),
			])


func _surfaceY(height: int) -> float:
	return (
		float(height) * BattleMeshFactoryScript.TERRAIN_CELL_SIZE.y
		+ BattleMeshFactoryScript.TERRAIN_CELL_SIZE.y * 0.5
	)
