## Control construction, collapsible sections, and readout formatting for the world map
## debug scene's panel.
##
## Holds every control the scene drives and knows how to render the status block; it does
## not decide what any of them mean. Handlers stay with the controller, because a control's
## behaviour is framing policy rather than a property of the panel.
##
## This diverges from `VfxDebugHud` on purpose. That HUD resolves references out of a
## hand-authored `.tscn`, which is right when the controls are heterogeneous and
## hand-placed. Here the panel is sixteen framing keys of the same few shapes, and the plan
## asks for a seam that later world-map tools extend. So `SECTIONS` declares the controls
## as DATA and the panel is built from it, which makes adding a road-spline or node-graph
## tool one entry in `SECTIONS` -- or one `addSection()` call from outside -- plus its
## handlers, rather than surgery on a scene file and a forty-line reference block.
##
## Adding a row to the readout is likewise one entry in `STATUS_ROWS` and one key handed
## to `setStatus()`, never a new positional argument in a nine-slot format string.

class_name WorldMapDebugHud
extends RefCounted

const Uniforms = preload("res://src/presentation/worldmap/WorldMapGroundUniforms.gd")

const ROW_SLIDER := "slider"
const ROW_COLOR := "color"
const ROW_OPTION := "option"

## Rows of the status block, in order: id, label. Ids match the keys `setStatus()` is
## handed.
const STATUS_ROWS := [
	["preset", "Preset"],
	["region", "Region"],
	["tiles", "Tiles across"],
	["density", "Px per tile"],
	["ratio", "Near:far"],
	["needed", "Region needed"],
	["depth", "Depth range"],
	["buffer", "Buffer"],
	["horizon", "Horizon"],
]

## The control declaration. Each row is one framing key; `type` picks the widget and the
## remaining fields configure it. Ranges are deliberately wider than the presets use --
## this is the surface a framing is chosen on, so it has to be able to leave them behind.
const SECTIONS := [
	{
		"id": "camera",
		"title": "Camera",
		"rows": [
			{"key": Uniforms.K_PITCH, "label": "Pitch", "type": ROW_SLIDER,
				"min": 2.0, "max": 85.0, "step": 0.5},
			{"key": Uniforms.K_FOV, "label": "Vertical FOV", "type": ROW_SLIDER,
				"min": 10.0, "max": 110.0, "step": 0.5},
			{"key": Uniforms.K_HEIGHT, "label": "Height (tiles)", "type": ROW_SLIDER,
				"min": 2.0, "max": 220.0, "step": 0.5},
		],
	},
	{
		"id": "ground",
		"title": "Ground",
		"rows": [
			{"key": Uniforms.K_UNITS_PER_MAP_PIXEL, "label": "Units / map px",
				"type": ROW_SLIDER, "min": 0.01, "max": 0.5, "step": 0.0025},
			{"key": Uniforms.K_CURVATURE, "label": "Curvature k", "type": ROW_SLIDER,
				"min": 0.0, "max": 0.02, "step": 0.0001},
			{"key": Uniforms.K_VOID_COLOR, "label": "Off-map void", "type": ROW_COLOR},
		],
	},
	{
		"id": "fog",
		"title": "Fog",
		"rows": [
			{"key": Uniforms.K_FOG_START, "label": "Fog start", "type": ROW_SLIDER,
				"min": 0.0, "max": 300.0, "step": 1.0},
			{"key": Uniforms.K_FOG_END, "label": "Fog end", "type": ROW_SLIDER,
				"min": 1.0, "max": 500.0, "step": 1.0},
			{"key": Uniforms.K_FOG_CURVE, "label": "Fog curve", "type": ROW_SLIDER,
				"min": 0.2, "max": 4.0, "step": 0.05},
			{"key": Uniforms.K_FOG_COLOR, "label": "Fog colour", "type": ROW_COLOR},
		],
	},
	{
		"id": "life",
		"title": "Life",
		"rows": [
			{"key": Uniforms.K_CLOUD_STRENGTH, "label": "Cloud shadow", "type": ROW_SLIDER,
				"min": 0.0, "max": 0.6, "step": 0.01},
			# Capped at 40 rather than 160: cloud_scale is world units per noise cell, so
			# past roughly a third of the region's width the whole visible ground samples
			# one cell and the control silently stops doing anything.
			{"key": Uniforms.K_CLOUD_SCALE, "label": "Cloud scale", "type": ROW_SLIDER,
				"min": 2.0, "max": 40.0, "step": 0.5},
			{"key": Uniforms.K_CLOUD_SPEED, "label": "Cloud speed", "type": ROW_SLIDER,
				"min": 0.0, "max": 6.0, "step": 0.1},
		],
	},
	{
		"id": "presentation",
		"title": "Presentation",
		"rows": [
			{"key": Uniforms.K_RENDER_SCALE, "label": "Render scale", "type": ROW_SLIDER,
				"min": 0.1, "max": 1.0, "step": 0.01},
			{"key": Uniforms.K_FILTER_MODE, "label": "Filter", "type": ROW_OPTION,
				"options": ["Nearest", "Nearest + mip", "Linear + mip"],
				"values": [
					Uniforms.FILTER_NEAREST,
					Uniforms.FILTER_NEAREST_MIPMAP,
					Uniforms.FILTER_LINEAR_MIPMAP,
				]},
			{"key": Uniforms.K_SPRITE_MODE, "label": "Sprite", "type": ROW_OPTION,
				"options": ["Fixed screen size", "World billboard"],
				"values": [Uniforms.SPRITE_FIXED, Uniforms.SPRITE_WORLD]},
		],
	},
]

var root: CanvasLayer
var column: VBoxContainer
var statusPanel: GridContainer

var presetOption: OptionButton
var regionOption: OptionButton
var tileGridToggle: CheckButton
var copyButton: Button

var _statusValues: Dictionary = {}
var _controls: Dictionary = {}
var _rows: Dictionary = {}
## Set while pushing values INTO controls, so echoing a framing back does not read as the
## user editing it and knock the preset selection to Custom.
var _suppressSignals := false


func _init(hudRoot: CanvasLayer) -> void:
	root = hudRoot
	column = root.get_node("PanelContainer/Scroll/Column") as VBoxContainer


## Builds the whole panel. `onFramingChanged` fires whenever the user moves any framing
## control; the controller reads the current framing back with `readFraming()`.
func build(onFramingChanged: Callable) -> void:
	_buildHeader()
	_buildStatus()
	for section in SECTIONS:
		addSection(section, onFramingChanged)


## The extension seam: a later world-map tool declares its controls in the same shape and
## calls this. Nothing about the panel needs to know what the section is for.
func addSection(section: Dictionary, onFramingChanged: Callable) -> void:
	var toggle := CheckButton.new()
	toggle.text = str(section["title"])
	toggle.button_pressed = true
	column.add_child(toggle)

	var grid := GridContainer.new()
	grid.columns = 3
	column.add_child(grid)
	toggle.toggled.connect(func(pressed: bool) -> void: grid.visible = pressed)

	for row in section["rows"]:
		_buildRow(grid, row, onFramingChanged)


func _buildHeader() -> void:
	var grid := GridContainer.new()
	grid.columns = 2
	column.add_child(grid)

	grid.add_child(_label("Preset"))
	presetOption = OptionButton.new()
	presetOption.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	grid.add_child(presetOption)

	grid.add_child(_label("Region"))
	regionOption = OptionButton.new()
	regionOption.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	grid.add_child(regionOption)

	var buttons := HBoxContainer.new()
	column.add_child(buttons)
	tileGridToggle = CheckButton.new()
	tileGridToggle.text = "16 px tile grid"
	buttons.add_child(tileGridToggle)
	copyButton = Button.new()
	copyButton.text = "Copy settings"
	buttons.add_child(copyButton)


func _buildStatus() -> void:
	statusPanel = GridContainer.new()
	statusPanel.columns = 2
	column.add_child(statusPanel)
	for entry in STATUS_ROWS:
		statusPanel.add_child(_label(str(entry[1])))
		var value := Label.new()
		value.text = "-"
		statusPanel.add_child(value)
		_statusValues[str(entry[0])] = value


func _buildRow(grid: GridContainer, row: Dictionary, onFramingChanged: Callable) -> void:
	var key := str(row["key"])
	_rows[key] = row
	grid.add_child(_label(str(row["label"])))

	var rowType := str(row["type"])
	if rowType == ROW_SLIDER:
		var step := float(row["step"])
		var slider := HSlider.new()
		slider.min_value = float(row["min"])
		slider.max_value = float(row["max"])
		slider.step = step
		slider.custom_minimum_size = Vector2(170.0, 0.0)
		slider.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		grid.add_child(slider)
		var readback := Label.new()
		readback.custom_minimum_size = Vector2(56.0, 0.0)
		grid.add_child(readback)
		slider.value_changed.connect(
			func(value: float) -> void:
				readback.text = _formatNumber(value, step)
				if not _suppressSignals:
					onFramingChanged.call()
		)
		_controls[key] = slider
	elif rowType == ROW_COLOR:
		var picker := ColorPickerButton.new()
		picker.custom_minimum_size = Vector2(170.0, 24.0)
		picker.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		grid.add_child(picker)
		grid.add_child(Control.new())
		picker.color_changed.connect(
			func(_colour: Color) -> void:
				if not _suppressSignals:
					onFramingChanged.call()
		)
		_controls[key] = picker
	elif rowType == ROW_OPTION:
		var option := OptionButton.new()
		for text in row["options"]:
			option.add_item(str(text))
		option.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		grid.add_child(option)
		grid.add_child(Control.new())
		option.item_selected.connect(
			func(_index: int) -> void:
				if not _suppressSignals:
					onFramingChanged.call()
		)
		_controls[key] = option


## Pushes a framing into the controls without firing change handlers.
func setFraming(framing: Dictionary) -> void:
	_suppressSignals = true
	for key in _controls:
		if not framing.has(key):
			continue
		var row: Dictionary = _rows[key]
		var rowType := str(row["type"])
		if rowType == ROW_SLIDER:
			(_controls[key] as HSlider).value = float(framing[key])
		elif rowType == ROW_COLOR:
			(_controls[key] as ColorPickerButton).color = framing[key]
		elif rowType == ROW_OPTION:
			var values: Array = row["values"]
			var index := values.find(framing[key])
			(_controls[key] as OptionButton).selected = maxi(index, 0)
	# Readbacks are refreshed while still suppressed: re-emitting value_changed to relabel
	# the sliders is not the user editing anything, and letting it escape would knock the
	# preset selection to Custom on every programmatic setFraming().
	_refreshReadbacks()
	_suppressSignals = false


## Reads every control back into a complete framing.
func readFraming() -> Dictionary:
	var framing := Uniforms.DEFAULTS.duplicate(true)
	for key in _controls:
		var row: Dictionary = _rows[key]
		var rowType := str(row["type"])
		if rowType == ROW_SLIDER:
			framing[key] = (_controls[key] as HSlider).value
		elif rowType == ROW_COLOR:
			framing[key] = (_controls[key] as ColorPickerButton).color
		elif rowType == ROW_OPTION:
			var values: Array = row["values"]
			var index: int = (_controls[key] as OptionButton).selected
			framing[key] = values[maxi(index, 0)]
	return framing


func setStatus(values: Dictionary) -> void:
	for key in values:
		if _statusValues.has(key):
			(_statusValues[key] as Label).text = str(values[key])


func toggleVisible() -> void:
	root.visible = not root.visible


func _refreshReadbacks() -> void:
	for key in _controls:
		var row: Dictionary = _rows[key]
		if str(row["type"]) != ROW_SLIDER:
			continue
		var slider := _controls[key] as HSlider
		slider.value_changed.emit(slider.value)


func _formatNumber(value: float, step: float) -> String:
	if step >= 1.0:
		return "%d" % int(round(value))
	if step >= 0.01:
		return "%.2f" % value
	return "%.4f" % value


func _label(text: String) -> Label:
	var node := Label.new()
	node.text = text
	return node
