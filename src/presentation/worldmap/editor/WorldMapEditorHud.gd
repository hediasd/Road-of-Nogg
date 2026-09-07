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
var tileOption: OptionButton
var seedSpin: SpinBox
var status: Label
var saveButton: Button

## Document lifecycle chrome (WMH-5). `nameEdit` is shared between New and Save As: typing a
## name and hitting New starts a fresh document under that name, typing a (possibly different)
## name and hitting Save As writes the currently open one under it -- one field for "what name
## am I working under" rather than two that could disagree.
var newLatticeOption: OptionButton
var nameEdit: LineEdit
var newButton: Button
var openOption: OptionButton
var openButton: Button
var saveAsButton: Button
var dirtyMarker: Label

var _layerButtons: Array[Button] = []
var _layerVisibilityToggles: Array[CheckButton] = []
var _layerLockToggles: Array[CheckButton] = []
var _layerIDs: Array[String] = []
var _layerLabels: Array[String] = []
var _tileIDs: Array[String] = []
var _newLattices: Array[Vector2i] = []
var _confirmDialog: ConfirmationDialog
var _onDiscardConfirmed: Callable
var _onDiscardCancelled: Callable


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
	_buildBrushControls()


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
		_layerIDs.append(id)
		_layerLabels.append(str(layer["label"]))

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


func setLayerEnabled(id: String, enabled: bool) -> void:
	var index := _layerIDs.find(id)
	if index < 0:
		return
	_layerButtons[index].text = _layerLabels[index] + ("" if enabled else "  (empty)")
	_layerButtons[index].modulate = Color(1.0, 1.0, 1.0, 1.0 if enabled else 0.5)


func _buildBrushControls() -> void:
	column.add_child(HSeparator.new())
	var tileRow := HBoxContainer.new()
	column.add_child(tileRow)
	tileRow.add_child(_label("Tile"))
	tileOption = OptionButton.new()
	tileOption.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	tileOption.focus_mode = Control.FOCUS_NONE
	tileRow.add_child(tileOption)

	var seedRow := HBoxContainer.new()
	column.add_child(seedRow)
	seedRow.add_child(_label("Scatter seed"))
	seedSpin = SpinBox.new()
	seedSpin.min_value = 0
	seedSpin.max_value = 2147483647
	seedSpin.step = 1
	seedSpin.value = 1
	seedSpin.allow_greater = false
	seedSpin.allow_lesser = false
	seedSpin.focus_mode = Control.FOCUS_NONE
	seedRow.add_child(seedSpin)

	saveButton = Button.new()
	saveButton.text = "Save authored map"
	saveButton.focus_mode = Control.FOCUS_NONE
	column.add_child(saveButton)

	status = Label.new()
	status.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	status.text = "Choose an authored region to edit."
	column.add_child(status)


## Builds the document lifecycle row: New (a lattice-size choice plus the shared name field),
## Open (a list of documents already on disk) and Save As. `onDiscardConfirmed`/`onDiscardCancelled`
## back the confirmation dialog New and Open are routed through whenever the open document has
## unsaved changes -- see the controller's own `_guardDirty` for why the dialog is a thin trigger
## over pure logic rather than the thing that decides anything itself.
func buildDocumentControls(
	lattices: Array[Vector2i], onNew: Callable, onOpen: Callable, onSaveAs: Callable,
	onDiscardConfirmed: Callable, onDiscardCancelled: Callable
) -> void:
	_newLattices = lattices
	column.add_child(HSeparator.new())
	column.add_child(_label("Document"))

	dirtyMarker = Label.new()
	dirtyMarker.add_theme_color_override("font_color", Color(1.0, 0.75, 0.3))
	dirtyMarker.text = "● Unsaved changes"
	dirtyMarker.visible = false
	column.add_child(dirtyMarker)

	var nameRow := HBoxContainer.new()
	column.add_child(nameRow)
	nameRow.add_child(_label("Name"))
	nameEdit = LineEdit.new()
	nameEdit.text = "untitled"
	nameEdit.placeholder_text = "map name"
	nameEdit.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	nameEdit.focus_mode = Control.FOCUS_CLICK
	nameRow.add_child(nameEdit)

	var newRow := HBoxContainer.new()
	column.add_child(newRow)
	newRow.add_child(_label("New (hex)"))
	newLatticeOption = OptionButton.new()
	newLatticeOption.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	newLatticeOption.focus_mode = Control.FOCUS_NONE
	# EXACT-FIT ONLY (WMH-2's `exactSquareLattices`), not an arbitrary size field: every choice
	# here fills its declared square with no margin, so a brand new document never has to answer
	# the margin question WMH-R1 already settled (void colour, not a terrain) before it has even
	# painted a single cell.
	for lattice in lattices:
		var extent: Vector2 = WorldMapHexGrid.latticeExtent(lattice.x, lattice.y)
		newLatticeOption.add_item("%d x %d  (%.0f units)" % [lattice.x, lattice.y, extent.x])
	newRow.add_child(newLatticeOption)
	newButton = Button.new()
	newButton.text = "New"
	newButton.focus_mode = Control.FOCUS_NONE
	newButton.pressed.connect(onNew)
	newRow.add_child(newButton)

	var openRow := HBoxContainer.new()
	column.add_child(openRow)
	openRow.add_child(_label("Open"))
	openOption = OptionButton.new()
	openOption.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	openOption.focus_mode = Control.FOCUS_NONE
	openRow.add_child(openOption)
	openButton = Button.new()
	openButton.text = "Open"
	openButton.focus_mode = Control.FOCUS_NONE
	openButton.pressed.connect(onOpen)
	openRow.add_child(openButton)

	saveAsButton = Button.new()
	saveAsButton.text = "Save as (name above)"
	saveAsButton.focus_mode = Control.FOCUS_NONE
	saveAsButton.pressed.connect(onSaveAs)
	column.add_child(saveAsButton)

	_onDiscardConfirmed = onDiscardConfirmed
	_onDiscardCancelled = onDiscardCancelled
	_confirmDialog = ConfirmationDialog.new()
	_confirmDialog.title = "Discard unsaved changes?"
	_confirmDialog.dialog_text = (
		"This document has unsaved changes. Discarding them cannot be undone."
	)
	_confirmDialog.get_ok_button().text = "Discard changes"
	_confirmDialog.confirmed.connect(func() -> void: _onDiscardConfirmed.call())
	_confirmDialog.canceled.connect(func() -> void: _onDiscardCancelled.call())
	root.add_child(_confirmDialog)


func selectedNewLattice() -> Vector2i:
	if newLatticeOption == null or newLatticeOption.selected < 0:
		return Vector2i.ZERO
	var index := newLatticeOption.selected
	return _newLattices[index] if index >= 0 and index < _newLattices.size() else Vector2i.ZERO


func documentNameField() -> String:
	return nameEdit.text.strip_edges() if nameEdit != null else ""


## `names` is every document already on disk, from the controller's own directory scan --
## this file has no opinion on where they live, only how to list them.
func setOpenChoices(names: Array[String]) -> void:
	openOption.clear()
	for name in names:
		openOption.add_item(name)
	openOption.disabled = names.is_empty()


func selectedOpenName() -> String:
	if openOption == null or openOption.selected < 0 or openOption.item_count == 0:
		return ""
	return openOption.get_item_text(openOption.selected)


func setDirty(dirty: bool) -> void:
	if dirtyMarker != null:
		dirtyMarker.visible = dirty


## Shows the discard-confirmation dialog. Skipped under the headless dummy display server --
## `popup_centered()` errors there because a `Window` never actually enters a display-backed
## tree under it (verified: `is_inside_tree()` reports false even after `add_child`), and a
## probe exercising the GUARD's pending/blocked state has no window to click anyway. The state
## this dialog fronts (`_pendingDiscardAction` on the controller) is unaffected either way --
## the probe drives it directly through `confirmPendingDiscard()` / `cancelPendingDiscard()`.
func promptDiscard() -> void:
	if DisplayServer.get_name() == "headless":
		return
	_confirmDialog.popup_centered()


func setTileChoices(ids: Array[String], selectedID := "") -> void:
	_tileIDs = ids.duplicate()
	tileOption.clear()
	# Erasing is a tile choice rather than a separate tool, so every shape can erase.
	tileOption.add_item("Erase (-)")
	for id in _tileIDs:
		tileOption.add_item(id)
	var index := _tileIDs.find(selectedID)
	tileOption.selected = index + 1 if index >= 0 else (1 if not _tileIDs.is_empty() else 0)
	tileOption.disabled = _tileIDs.is_empty()


func selectedTileID() -> String:
	if tileOption == null or tileOption.selected <= 0:
		return WorldMapTileData.EMPTY
	var index := tileOption.selected - 1
	return _tileIDs[index] if index >= 0 and index < _tileIDs.size() else WorldMapTileData.EMPTY


func selectTileID(id: String) -> void:
	if id == WorldMapTileData.EMPTY:
		tileOption.selected = 0
		return
	var index := _tileIDs.find(id)
	if index >= 0:
		tileOption.selected = index + 1


func scatterSeed() -> int:
	return int(seedSpin.value)


func setStatus(message: String) -> void:
	status.text = message


func _label(text: String) -> Label:
	var made := Label.new()
	made.text = text
	return made
