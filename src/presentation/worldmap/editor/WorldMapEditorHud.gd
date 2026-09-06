## Editor-only chrome for the world map editor scene: which layer is active, which tool is
## selected, per-layer visibility and lock, and whether the camera view is off the shipping
## contract.
##
## DELIBERATELY SEPARATE FROM `WorldMapDebugHud`. That panel's rows are all framing-KEY shaped
## -- a slider, a colour picker or an option bound to one entry of the framing dictionary -- and
## a layer row is not that shape: it carries visibility and lock toggles with no framing key
## behind either of them. Forcing them through `addSection()` would make the row declaration
## lie about what it configures, so this is its own small panel, sharing nothing with the
## debug HUD but the same `Ui` `CanvasLayer` the editor scene parents both into.
##
## LAYERS AND TOOLS ARE DATA, same reasoning as `WorldMapDebugHud.SECTIONS`: the caller hands in
## the list (`WorldMapEditorController.LAYERS` / `TOOLS`) and a later phase flipping one layer
## from empty to real is a data change there, not a change here.

class_name WorldMapEditorHud
extends RefCounted

var root: CanvasLayer
var column: VBoxContainer
var badge: Label
var toolOption: OptionButton

var _layerButtons: Array[Button] = []
var _layerVisibilityToggles: Array[CheckButton] = []
var _layerLockToggles: Array[CheckButton] = []


func _init(hudRoot: CanvasLayer) -> void:
	root = hudRoot
	column = root.get_node("EditorPanel/Scroll/Column") as VBoxContainer


## `onLayerSelected(index)`, `onToolSelected(index)` mirror the option-button convention
## `WorldMapDebugController` already uses for its own preset and region pickers.
## `onVisibilityToggled(id, on)` and `onLockToggled(id, on)` are keyed by layer id rather than
## index, because a caller reacting to a lock is far more likely to want "which layer" than
## "which row".
func build(
	layers: Array,
	tools: Array,
	onLayerSelected: Callable,
	onToolSelected: Callable,
	onVisibilityToggled: Callable,
	onLockToggled: Callable
) -> void:
	_buildBadge()
	_buildToolSelector(tools, onToolSelected)
	_buildLayerList(layers, onLayerSelected, onVisibilityToggled, onLockToggled)


func _buildBadge() -> void:
	badge = Label.new()
	badge.add_theme_color_override("font_color", Color(1.0, 0.55, 0.2))
	badge.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	badge.visible = false
	column.add_child(badge)


## "" clears the badge. Anything else shows it. The editor camera's own `offContractReason()`
## is the only legitimate source for this string -- see its class note on why nothing about how
## the map LOOKS may be judged while it is showing.
func setOffContract(reason: String) -> void:
	badge.text = reason
	badge.visible = not reason.is_empty()


func _buildToolSelector(tools: Array, onToolSelected: Callable) -> void:
	var row := HBoxContainer.new()
	column.add_child(row)
	row.add_child(_label("Tool"))
	toolOption = OptionButton.new()
	toolOption.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	# Tab and Space are camera shortcuts the controller owns (ortho toggle, snap to contract).
	# A focused OptionButton would otherwise eat Tab for focus-next and Space for "open this
	# dropdown", so it never reaches the controller's _unhandled_key_input at all -- this is
	# not decoration, it is the other half of that shortcut actually working.
	toolOption.focus_mode = Control.FOCUS_NONE
	for tool in tools:
		toolOption.add_item(str((tool as Dictionary)["label"]))
	toolOption.item_selected.connect(onToolSelected)
	row.add_child(toolOption)


func setActiveTool(index: int) -> void:
	if index >= 0 and index < toolOption.item_count:
		toolOption.selected = index


func _buildLayerList(
	layers: Array,
	onLayerSelected: Callable,
	onVisibilityToggled: Callable,
	onLockToggled: Callable
) -> void:
	column.add_child(_label("Layers"))
	var grid := GridContainer.new()
	grid.columns = 3
	column.add_child(grid)

	for i in layers.size():
		var layer: Dictionary = layers[i]
		var id := str(layer["id"])
		var enabled := bool(layer.get("enabled", false))

		var select := Button.new()
		select.text = str(layer["label"]) + ("" if enabled else "  (empty)")
		select.toggle_mode = true
		select.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		# See the tool OptionButton's own note: Tab and Space are the controller's camera
		# shortcuts, and a focused Button would otherwise swallow Space as its own activation.
		select.focus_mode = Control.FOCUS_NONE
		# An empty layer stays selectable -- looking at what nothing has been authored on yet
		# is legitimate -- it just cannot be the target of anything that mutates. Dimmed
		# rather than disabled, so "not built yet" reads differently from "cannot be reached".
		select.modulate = Color(1.0, 1.0, 1.0, 1.0 if enabled else 0.5)
		select.pressed.connect(func() -> void: onLayerSelected.call(i))
		grid.add_child(select)
		_layerButtons.append(select)

		var visibility := CheckButton.new()
		visibility.button_pressed = true
		visibility.tooltip_text = "Visible"
		visibility.focus_mode = Control.FOCUS_NONE
		visibility.toggled.connect(func(on: bool) -> void: onVisibilityToggled.call(id, on))
		grid.add_child(visibility)
		_layerVisibilityToggles.append(visibility)

		var lock := CheckButton.new()
		lock.button_pressed = false
		lock.tooltip_text = "Locked -- refuses tool input even while active"
		lock.focus_mode = Control.FOCUS_NONE
		lock.toggled.connect(func(on: bool) -> void: onLockToggled.call(id, on))
		grid.add_child(lock)
		_layerLockToggles.append(lock)


func setActiveLayer(index: int) -> void:
	for i in _layerButtons.size():
		_layerButtons[i].button_pressed = (i == index)


func _label(text: String) -> Label:
	var made := Label.new()
	made.text = text
	return made
