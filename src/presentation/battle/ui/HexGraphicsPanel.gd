## The battle's debug drawer: the retained retro renderer's controls, and the session controls --
## pause, speed, skip, restart, setup -- behind one toggle in the top-right corner.
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

## The toggle's own band in the top-right corner. The command rail starts below it, so the drawer
## never sits over the first plate.
const TOGGLE_SIZE := Vector2(100.0, 32.0)
const TOGGLE_MARGIN := 12.0
const PANEL_SIZE := Vector2(292.0, 330.0)
## Room kept clear on the right for the command rail, which is drawn by the HUD above this layer.
const RAIL_CLEARANCE := 250.0


## How much vertical room the toggle claims at the top of the screen.
static func toggleClearance() -> float:
	return TOGGLE_MARGIN + TOGGLE_SIZE.y


var renderer: RetroRenderController
var toggleButton: Button
var panel: PanelContainer
var presetOption: OptionButton
var geometryOption: OptionButton
var upscaleOption: OptionButton
var sessionTitle: Label
## Session id -> its Button.
var sessionButtons: Dictionary = {}
var _session: Dictionary = {}


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
	# Below this diagnostic-sized floor there is no usable panel layout; hiding the toggle also
	# ensures it cannot consume every world-input point in the headless 64x64 viewport.
	visible = get_viewport().get_visible_rect().size.x >= 320.0 \
		and get_viewport().get_visible_rect().size.y >= 240.0


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
	# Opens to the LEFT of the command rail, not under it: this drawer lives in the stage's own
	# viewport, so the HUD draws over it whatever layer it claims.
	panel.set_anchors_preset(Control.PRESET_TOP_RIGHT)
	panel.position = Vector2(-(PANEL_SIZE.x + RAIL_CLEARANCE), TOGGLE_MARGIN + TOGGLE_SIZE.y + 6.0)
	panel.size = PANEL_SIZE
	panel.visible = false
	add_child(panel)
	toggleButton.toggled.connect(func(open: bool): panel.visible = open)

	var column := VBoxContainer.new()
	column.add_theme_constant_override("separation", 8)
	panel.add_child(column)
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
	geometryOption = _option(column, "Geometry", ["Stable", "Vertex jitter"],
		["stable", "jitter"])
	upscaleOption = _option(column, "Upscale", ["Smooth", "Sharp pixels"],
		["linear", "nearest"])
	var reset := Button.new()
	reset.name = "ResetGraphics"
	reset.text = "Reset"
	column.add_child(reset)
	presetOption.item_selected.connect(_onPresetSelected)
	geometryOption.item_selected.connect(_onFeaturesSelected)
	upscaleOption.item_selected.connect(_onFeaturesSelected)
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
	label.custom_minimum_size.x = 82.0
	row.add_child(label)
	var option := OptionButton.new()
	option.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	for index in range(labels.size()):
		option.add_item(labels[index])
		option.set_item_metadata(index, values[index])
	row.add_child(option)
	return option


func _onPresetSelected(index: int) -> void:
	renderer.set_preset(str(presetOption.get_item_metadata(index)))
	_sync()


func _onFeaturesSelected(_index: int) -> void:
	renderer.set_features(
		str(geometryOption.get_item_metadata(geometryOption.selected)) == "jitter",
		str(upscaleOption.get_item_metadata(upscaleOption.selected)) == "nearest"
	)
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
	_select(geometryOption, "jitter" if renderer.vertex_snap_enabled else "stable")
	_select(upscaleOption, "nearest" if renderer.nearest_filter_enabled else "linear")


func _select(option: OptionButton, value: String) -> void:
	for index in range(option.item_count):
		if str(option.get_item_metadata(index)) == value:
			option.select(index)
			return
