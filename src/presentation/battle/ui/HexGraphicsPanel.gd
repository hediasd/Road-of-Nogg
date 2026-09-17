## The battle's debug drawer: the session controls -- pause, speed, skip, restart, setup -- and
## every adjustable graphics value of the retro renderer, behind one toggle in the top-right
## corner. The Look list holds only None, CRT and Custom; everything finer is a control here, and
## touching one turns the Look to Custom.
##
## SESSION CONTROLS LIVE HERE, NOT ON THE HUD. They are how a developer drives playback, not part
## of playing a battle, and docked on the board they took a corner of the screen permanently. The
## keys they name (P, F, Enter, R) work whether or not this drawer is open.

class_name HexGraphicsPanel
extends CanvasLayer

## A session row was clicked. Ids are this file's own SESSION_* constants, and are what
## `HexBattleController._onSessionCommand` answers.
signal session_command(commandID: String)

const RenderPresetCatalogScript = preload("res://src/presentation/RenderPresetCatalog.gd")

const PAUSE := "pause"
const SPEED := "speed"
const SKIP := "skip"
const RESTART := "restart"
const SETUP := "setup"

## The toggle's own band in the top-right corner. The drawer opens directly beneath it.
const TOGGLE_SIZE := Vector2(100.0, 32.0)
const TOGGLE_MARGIN := 12.0
## The drawer scrolls: the session rows plus every graphics control are taller than a 720p screen.
const PANEL_SIZE := Vector2(320.0, 560.0)
const PANEL_BOTTOM_MARGIN := 12.0
const LABEL_WIDTH := 96.0
const VALUE_WIDTH := 44.0
## Low-res render targets offered, largest first. Off renders at the window's own size.
const LOW_RES_SIZES := [Vector2i(640, 480), Vector2i(480, 360), Vector2i(320, 240)]
## [parameter, label, minimum, maximum, step]. Ranges mirror RetroRenderController's own clamps.
const LOOK_SLIDERS := [
	["render_scale", "Render scale", 0.5, 1.5, 0.05],
	["snap_strength", "Jitter", 0.0, 1.0, 0.05],
	["brightness", "Brightness", 0.5, 1.5, 0.01],
	["contrast", "Contrast", 0.5, 1.5, 0.01],
	["saturation", "Saturation", 0.0, 2.0, 0.01],
	["color_levels", "Color levels", 0.0, 64.0, 1.0],
	["dither", "Dither", 0.0, 0.15, 0.005],
	["duotone", "Duotone", 0.0, 1.0, 0.01],
]
const CRT_SLIDERS := [
	["scanline", "Scanlines", 0.0, 0.5, 0.01],
	["scanline_size", "Line size", 0.5, 4.0, 0.05],
	["mask", "Mask", 0.0, 1.0, 0.01],
	["mask_size", "Mask size", 1.0, 6.0, 0.1],
	["mask_dots", "Mask dots", 0.0, 1.0, 0.01],
	["vignette", "Vignette", 0.0, 0.6, 0.01],
	["flicker", "Flicker", 0.0, 0.1, 0.002],
	["color_bleed", "Color bleed", 0.0, 4.0, 0.05],
	["noise", "Noise", 0.0, 0.2, 0.005],
	["glow", "Glow", 0.0, 0.5, 0.01],
]


## How much vertical room the toggle claims at the top of the screen.
static func toggleClearance() -> float:
	return TOGGLE_MARGIN + TOGGLE_SIZE.y


var renderer: RetroRenderController
var battleCamera: HexBattleCamera
var toggleButton: Button
var panel: PanelContainer
var presetOption: OptionButton
var geometryOption: OptionButton
var upscaleOption: OptionButton
var lowResOption: OptionButton
var textureOption: OptionButton
var crtOption: OptionButton
## Parameter id -> {"slider": HSlider, "value": Label}.
var lookSliders: Dictionary = {}
var crtSliders: Dictionary = {}
var sessionTitle: Label
## Session id -> its Button.
var sessionButtons: Dictionary = {}
var _session: Dictionary = {}
var _scroll: ScrollContainer


func _init(value: RetroRenderController) -> void:
	renderer = value
	name = "HexGraphicsPanel"
	layer = 20
	_build()
	_sync()


func _ready() -> void:
	get_viewport().size_changed.connect(_onViewportSizeChanged)
	_onViewportSizeChanged()


func _onViewportSizeChanged() -> void:
	var viewportSize := get_viewport().get_visible_rect().size
	# Below this diagnostic-sized floor there is no usable panel layout; hiding the toggle also
	# ensures it cannot consume every world-input point in the headless 64x64 viewport.
	visible = viewportSize.x >= 320.0 and viewportSize.y >= 280.0
	var height := minf(PANEL_SIZE.y, viewportSize.y - panel.position.y - PANEL_BOTTOM_MARGIN)
	_scroll.custom_minimum_size = Vector2(PANEL_SIZE.x, maxf(height, 0.0))
	panel.size = _scroll.custom_minimum_size


func _build() -> void:
	toggleButton = Button.new()
	toggleButton.name = "GraphicsToggle"
	toggleButton.text = "Debug"
	toggleButton.toggle_mode = true
	toggleButton.set_anchors_preset(Control.PRESET_TOP_RIGHT)
	toggleButton.position = Vector2(-TOGGLE_SIZE.x - TOGGLE_MARGIN, TOGGLE_MARGIN)
	toggleButton.size = TOGGLE_SIZE
	add_child(toggleButton)

	panel = PanelContainer.new()
	panel.name = "GraphicsPanel"
	# Flush under the toggle. The command rail it used to open beside is gone with side turns.
	panel.set_anchors_preset(Control.PRESET_TOP_RIGHT)
	panel.position = Vector2(-(PANEL_SIZE.x + TOGGLE_MARGIN), TOGGLE_MARGIN + TOGGLE_SIZE.y + 6.0)
	panel.size = PANEL_SIZE
	panel.visible = false
	add_child(panel)
	toggleButton.toggled.connect(func(open: bool): panel.visible = open)

	_scroll = ScrollContainer.new()
	_scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	_scroll.custom_minimum_size = PANEL_SIZE
	panel.add_child(_scroll)
	var column := VBoxContainer.new()
	column.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	column.add_theme_constant_override("separation", 8)
	_scroll.add_child(column)
	sessionTitle = Label.new()
	sessionTitle.name = "SessionTitle"
	sessionTitle.text = "SESSION"
	column.add_child(sessionTitle)
	for entry in [
		[PAUSE, "Pause", "P"], [SPEED, "Speed 1x", "F"], [SKIP, "Skip", "Enter"],
		[RESTART, "Restart", "R"], [SETUP, "Setup", ""],
	]:
		var button := Button.new()
		button.name = "Session_%s" % str(entry[0])
		button.text = _sessionLabel(str(entry[1]), str(entry[2]))
		button.pressed.connect(_onSessionPressed.bind(str(entry[0])))
		column.add_child(button)
		sessionButtons[str(entry[0])] = button

	var title := Label.new()
	title.text = "GRAPHICS"
	column.add_child(title)
	presetOption = _option(column, "Look", RenderPresetCatalogScript.labels(),
		RenderPresetCatalogScript.values())
	var lowResLabels: Array[String] = ["Off"]
	var lowResValues: Array[String] = ["off"]
	for size: Vector2i in LOW_RES_SIZES:
		lowResLabels.append("%dx%d" % [size.x, size.y])
		lowResValues.append("%dx%d" % [size.x, size.y])
	lowResOption = _option(column, "Low res", lowResLabels, lowResValues)
	geometryOption = _option(column, "Geometry", ["Stable", "Vertex jitter"],
		["stable", "jitter"])
	textureOption = _option(column, "Textures", ["Perspective", "Affine warp"],
		["perspective", "affine"])
	upscaleOption = _option(column, "Upscale", ["Smooth", "Sharp pixels"],
		["linear", "nearest"])
	for entry in LOOK_SLIDERS:
		lookSliders[str(entry[0])] = _slider(column, entry, _onLookSlider)
	var crtTitle := Label.new()
	crtTitle.text = "CRT"
	column.add_child(crtTitle)
	crtOption = _option(column, "CRT pass", ["Off", "On"], ["off", "on"])
	for entry in CRT_SLIDERS:
		crtSliders[str(entry[0])] = _slider(column, entry, _onCrtSlider)
	var reset := Button.new()
	reset.name = "ResetGraphics"
	reset.text = "Reset"
	column.add_child(reset)
	presetOption.item_selected.connect(_onPresetSelected)
	lowResOption.item_selected.connect(_onLowResSelected)
	geometryOption.item_selected.connect(_onFeaturesSelected)
	textureOption.item_selected.connect(_onTextureSelected)
	upscaleOption.item_selected.connect(_onFeaturesSelected)
	crtOption.item_selected.connect(_onCrtSelected)
	reset.pressed.connect(_onReset)


## What the controller knows about the session: phase ("battle", "ending" or "complete"), paused,
## speed, can_skip, result, rounds. Rendered whether or not the drawer is open, so opening it never
## shows a stale state.
func setSession(session: Dictionary) -> void:
	_session = session.duplicate(true)
	if sessionTitle == null:
		return
	if session.is_empty():
		sessionTitle.text = "SESSION"
		for id in sessionButtons:
			(sessionButtons[id] as Button).disabled = true
		return
	var phase := str(session.get("phase", ""))
	var paused := bool(session.get("paused", false))
	var complete := phase == "complete"
	sessionTitle.text = "SESSION -- %s" % (
		"%s after %d rounds" % [str(session.get("result", "Complete")),
			int(session.get("rounds", 0))] if complete
		else ("Paused" if paused else ("Finishing" if phase == "ending" else "Playing"))
	)
	_setSessionRow(PAUSE, "Resume" if paused else "Pause", "P", not complete)
	_setSessionRow(
		SPEED, "Speed %s" % speedText(float(session.get("speed", 1.0))), "F", not complete)
	_setSessionRow(SKIP, "Skip", "Enter", not complete and bool(session.get("can_skip", false)))
	_setSessionRow(RESTART, "Restart", "R", complete)
	_setSessionRow(SETUP, "Setup", "", true)


## The session state this drawer last drew, for probes.
func drawnSession() -> Dictionary:
	return _session.duplicate(true)


static func speedText(speed: float) -> String:
	if is_equal_approx(speed, roundf(speed)):
		return "%dx" % roundi(speed)
	return "%.1fx" % speed


func _setSessionRow(id: String, label: String, key: String, enabled: bool) -> void:
	var button: Button = sessionButtons.get(id)
	if button == null:
		return
	button.text = _sessionLabel(label, key)
	button.disabled = not enabled


static func _sessionLabel(label: String, key: String) -> String:
	return label if key.is_empty() else "%s   (%s)" % [label, key]


func _onSessionPressed(commandID: String) -> void:
	session_command.emit(commandID)


func _option(parent: Control, labelText: String, labels: Array[String], values: Array[String]) -> OptionButton:
	var row := HBoxContainer.new()
	parent.add_child(row)
	var label := Label.new()
	label.text = labelText
	label.custom_minimum_size.x = LABEL_WIDTH
	row.add_child(label)
	var option := OptionButton.new()
	option.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	for index in range(labels.size()):
		option.add_item(labels[index])
		option.set_item_metadata(index, values[index])
	row.add_child(option)
	return option


func _slider(parent: Control, entry: Array, callback: Callable) -> Dictionary:
	var row := HBoxContainer.new()
	parent.add_child(row)
	var label := Label.new()
	label.text = str(entry[1])
	label.custom_minimum_size.x = LABEL_WIDTH
	row.add_child(label)
	var slider := HSlider.new()
	slider.name = "Slider_%s" % str(entry[0])
	slider.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	slider.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	slider.min_value = float(entry[2])
	slider.max_value = float(entry[3])
	slider.step = float(entry[4])
	slider.value_changed.connect(callback.bind(str(entry[0])))
	row.add_child(slider)
	var value := Label.new()
	value.custom_minimum_size.x = VALUE_WIDTH
	value.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	row.add_child(value)
	return {"slider": slider, "value": value}


func _onPresetSelected(index: int) -> void:
	renderer.set_preset(str(presetOption.get_item_metadata(index)))
	_sync()


func attachCamera(value: HexBattleCamera) -> void:
	battleCamera = value
	_sync()


func _onFeaturesSelected(_index: int) -> void:
	renderer.set_features(
		str(geometryOption.get_item_metadata(geometryOption.selected)) == "jitter",
		str(upscaleOption.get_item_metadata(upscaleOption.selected)) == "nearest"
	)
	_sync()


func _onLowResSelected(index: int) -> void:
	var id := str(lowResOption.get_item_metadata(index))
	if id == "off":
		renderer.set_low_res(false)
	else:
		var parts := id.split("x")
		renderer.set_low_res(true, Vector2i(int(parts[0]), int(parts[1])))
	_sync()


func _onTextureSelected(index: int) -> void:
	renderer.set_affine_mapping(str(textureOption.get_item_metadata(index)) == "affine")
	_sync()


func _onCrtSelected(index: int) -> void:
	renderer.set_crt_enabled(str(crtOption.get_item_metadata(index)) == "on")
	_sync()


func _onLookSlider(value: float, parameter: String) -> void:
	renderer.set_look_parameter(parameter, value)
	_sync()


func _onCrtSlider(value: float, parameter: String) -> void:
	renderer.set_crt_parameter(parameter, value)
	_sync()


func _onReset() -> void:
	renderer.reset_defaults()
	_sync()


func _sync() -> void:
	# A drawer built without a renderer still draws its session controls; there is simply nothing
	# to read the graphics options back from.
	if renderer == null:
		return
	_select(presetOption, renderer.render_preset)
	_select(lowResOption, "%dx%d" % [renderer.render_size.x, renderer.render_size.y]
		if renderer.retro_enabled else "off")
	_select(geometryOption, "jitter" if renderer.vertex_snap_enabled else "stable")
	_select(textureOption, "affine" if renderer.affine_mapping_enabled else "perspective")
	_select(upscaleOption, "nearest" if renderer.nearest_filter_enabled else "linear")
	_select(crtOption, "on" if renderer.crt_enabled else "off")
	for parameter in lookSliders:
		_syncSlider(lookSliders[parameter], renderer.get_look_parameter(parameter))
	for parameter in crtSliders:
		_syncSlider(crtSliders[parameter], renderer.get_crt_parameter(parameter))
		# The CRT values only reach the screen through the CRT pass.
		(crtSliders[parameter]["slider"] as HSlider).editable = renderer.crt_enabled


## Without emitting: a sync that wrote each value back would turn every Look into Custom.
static func _syncSlider(control: Dictionary, value: float) -> void:
	var slider := control["slider"] as HSlider
	slider.set_value_no_signal(value)
	(control["value"] as Label).text = str(roundi(value)) if slider.step >= 1.0 else "%.2f" % value


func _select(option: OptionButton, value: String) -> void:
	for index in range(option.item_count):
		if str(option.get_item_metadata(index)) == value:
			option.select(index)
			return
