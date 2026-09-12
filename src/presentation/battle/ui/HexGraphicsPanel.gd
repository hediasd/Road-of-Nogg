## Native-resolution, battle-local controls for the retained retro renderer.

class_name HexGraphicsPanel
extends CanvasLayer

const RenderPresetCatalogScript = preload("res://src/presentation/RenderPresetCatalog.gd")

var renderer: RetroRenderController
var toggleButton: Button
var panel: PanelContainer
var presetOption: OptionButton
var geometryOption: OptionButton
var upscaleOption: OptionButton


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
	toggleButton.text = "Graphics"
	toggleButton.toggle_mode = true
	toggleButton.set_anchors_preset(Control.PRESET_TOP_RIGHT)
	toggleButton.position = Vector2(-112.0, 12.0)
	toggleButton.size = Vector2(100.0, 32.0)
	add_child(toggleButton)

	panel = PanelContainer.new()
	panel.name = "GraphicsPanel"
	panel.set_anchors_preset(Control.PRESET_TOP_RIGHT)
	panel.position = Vector2(-304.0, 50.0)
	panel.size = Vector2(292.0, 190.0)
	panel.visible = false
	add_child(panel)
	toggleButton.toggled.connect(func(open: bool): panel.visible = open)

	var column := VBoxContainer.new()
	column.add_theme_constant_override("separation", 8)
	panel.add_child(column)
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
	_select(presetOption, renderer.render_preset)
	_select(geometryOption, "jitter" if renderer.vertex_snap_enabled else "stable")
	_select(upscaleOption, "nearest" if renderer.nearest_filter_enabled else "linear")


func _select(option: OptionButton, value: String) -> void:
	for index in range(option.item_count):
		if str(option.get_item_metadata(index)) == value:
			option.select(index)
			return
