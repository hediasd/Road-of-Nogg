## What fills the workspace's palette and inspector columns: the tilesheet picker, the value row
## the active layer's tool applies, the layer list, the under-cursor readout and the off-contract
## badge.
##
## FRAME VERSUS CONTENTS. `WorldMapWorkspaceChrome` builds the header, toolbar, columns and footer
## and owns every action button; this fills two of those columns. The split is why neither file
## has to know much about the other: the chrome hands over two `VBoxContainer`s and takes back a
## status string, and everything about WHICH LAYER and WHICH VALUE lives here.
##
## THE PICKER DRIVES THE VALUE ROW, NOT THE OTHER WAY ROUND. `WorldMapTilesetPicker` reports a
## primary tile id; this relays that into the same value row the brushes already read through
## `selectedTileID()`. One source of truth for "what will be painted" is what keeps a visual
## selection and a painted cell from disagreeing, and it is why the picker needed no controller
## API of its own.
##
## VALUE ROW, NOT A TILE ROW. A height layer takes a sculpt step, an object layer takes a kind and
## the tactical layer takes a battle terrain -- none of those are tiles, and none of them may be
## offered as texture thumbnails. The picker is shown only for the layers whose values really are
## sheet frames; every other kind gets the labelled row and no sheet at all.

class_name WorldMapEditorHud
extends RefCounted

const ChromeScript = preload("res://src/presentation/worldmap/editor/workspace/WorldMapWorkspaceChrome.gd")
const PickerScript = preload("res://src/presentation/worldmap/editor/WorldMapTilesetPicker.gd")

var chrome: ChromeScript
var badge: Label
var picker: PickerScript
var tileOption: OptionButton
var tileLabel: Label
var seedSpin: SpinBox

var _paletteTitle: Label
var _pickerHint: Label
var _cursorCellValue: Label
var _cursorTileValue: Label
var _layerButtons: Array[Button] = []
var _layerVisibilityToggles: Array[CheckBox] = []
var _layerLockToggles: Array[CheckBox] = []
var _layerIDs: Array[String] = []
var _layerLabels: Array[String] = []
var _tileIDs: Array[String] = []
var _suppressPickerRelay := false


func _init(workspaceChrome: ChromeScript) -> void:
	chrome = workspaceChrome


func build(
	layers: Array,
	onLayerSelected: Callable,
	onVisibilityToggled: Callable,
	onLockToggled: Callable
) -> void:
	_buildPalette()
	_buildInspector(layers, onLayerSelected, onVisibilityToggled, onLockToggled)


func _buildPalette() -> void:
	var column := chrome.paletteColumn

	_paletteTitle = Label.new()
	_paletteTitle.name = "PaletteTilesetName"
	_paletteTitle.text = "No tileset"
	_paletteTitle.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	column.add_child(_paletteTitle)

	picker = PickerScript.new()
	picker.name = "TilesetPicker"
	picker.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	picker.primaryTileChanged.connect(_onPickerPrimaryChanged)
	column.add_child(picker)

	_pickerHint = Label.new()
	_pickerHint.name = "PaletteHint"
	_pickerHint.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_pickerHint.text = ""
	_pickerHint.visible = false
	column.add_child(_pickerHint)

	column.add_child(HSeparator.new())

	var valueRow := VBoxContainer.new()
	column.add_child(valueRow)
	tileLabel = _label("Tile")
	valueRow.add_child(tileLabel)
	tileOption = OptionButton.new()
	tileOption.name = "ValueRow"
	tileOption.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	tileOption.tooltip_text = "What the active layer's tool applies."
	tileOption.item_selected.connect(_onValueRowSelected)
	valueRow.add_child(tileOption)

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
	seedRow.add_child(seedSpin)


func _buildInspector(
	layers: Array,
	onLayerSelected: Callable,
	onVisibilityToggled: Callable,
	onLockToggled: Callable
) -> void:
	var column := chrome.inspectorColumn

	badge = Label.new()
	badge.name = "OffContractBadge"
	badge.add_theme_color_override("font_color", Color(1.0, 0.55, 0.2))
	badge.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	badge.visible = false
	column.add_child(badge)

	var grid := GridContainer.new()
	grid.name = "LayerRows"
	grid.columns = 3
	column.add_child(grid)

	for i in layers.size():
		var layer: Dictionary = layers[i]
		var id := str(layer["id"])
		_layerIDs.append(id)
		_layerLabels.append(str(layer["label"]))

		var select := Button.new()
		select.text = str(layer["label"]) + "  (empty)"
		select.toggle_mode = true
		select.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		select.modulate = Color(1.0, 1.0, 1.0, 0.5)
		# Clipped so a long layer name cannot set the inspector's minimum width; the full name is
		# in the tooltip. The whole workspace has to fit 1280 x 720 with both panels open.
		select.clip_text = true
		select.tooltip_text = str(layer["label"])
		select.pressed.connect(func() -> void: onLayerSelected.call(i))
		grid.add_child(select)
		_layerButtons.append(select)

		# DISABLED ON PURPOSE, not decoration. Hiding a layer's art in the editor view is the
		# painting item's work; a toggle that moved but changed nothing would be exactly the
		# working-looking dead control this rebuild set out to remove, so it says so instead.
		var visibility := CheckBox.new()
		visibility.button_pressed = true
		visibility.disabled = true
		visibility.tooltip_text = (
			"Per-layer view filtering is not implemented yet. Every authored layer is shown, "
			+ "saved and exported regardless of this control."
		)
		visibility.toggled.connect(func(on: bool) -> void: onVisibilityToggled.call(id, on))
		grid.add_child(visibility)
		_layerVisibilityToggles.append(visibility)

		var lock := CheckBox.new()
		lock.button_pressed = false
		lock.tooltip_text = "Locked -- refuses tool input even while active"
		lock.toggled.connect(func(on: bool) -> void: onLockToggled.call(id, on))
		grid.add_child(lock)
		_layerLockToggles.append(lock)

	column.add_child(HSeparator.new())
	column.add_child(_label("Under cursor"))
	var readout := GridContainer.new()
	readout.columns = 2
	column.add_child(readout)
	readout.add_child(_label("Cell"))
	_cursorCellValue = Label.new()
	_cursorCellValue.text = "--"
	readout.add_child(_cursorCellValue)
	readout.add_child(_label("Value"))
	_cursorTileValue = Label.new()
	_cursorTileValue.text = "--"
	readout.add_child(_cursorTileValue)


## "" clears the badge. The editor camera's own `offContractReason()` is the only legitimate
## source -- see its class note on why nothing about how the map LOOKS may be judged while it is
## showing.
func setOffContract(reason: String) -> void:
	badge.text = reason
	badge.visible = not reason.is_empty()


func setStatus(message: String) -> void:
	chrome.setStatus(message)


func setCursorReadout(cellText: String, valueText: String) -> void:
	if _cursorCellValue != null:
		_cursorCellValue.text = cellText
	if _cursorTileValue != null:
		_cursorTileValue.text = valueText


func setActiveLayer(index: int) -> void:
	for i in _layerButtons.size():
		_layerButtons[i].set_pressed_no_signal(i == index)


func setLayerEnabled(id: String, enabled: bool) -> void:
	var index := _layerIDs.find(id)
	if index < 0:
		return
	_layerButtons[index].text = _layerLabels[index] + ("" if enabled else "  (empty)")
	_layerButtons[index].modulate = Color(1.0, 1.0, 1.0, 1.0 if enabled else 0.5)


func setLayerLocked(id: String, locked: bool) -> void:
	var index := _layerIDs.find(id)
	if index >= 0:
		_layerLockToggles[index].set_pressed_no_signal(locked)


## Points the picker at a real catalog entry. `tiles` is the catalog's own normalised tile list,
## whose `CELL` values are what locate art -- never the array order. A tileset whose sheet Godot
## has not imported yet still configures: the picker draws nothing and the value row still works,
## which is a readable state rather than a crash.
func configurePalette(
	tilesetID: String, sheet: Texture2D, framePx: int, tiles: Array[Dictionary]
) -> void:
	if picker == null:
		return
	_paletteTitle.text = tilesetID if not tilesetID.is_empty() else "No tileset"
	picker.visible = true
	_suppressPickerRelay = true
	picker.configure(tilesetID, sheet, framePx, tiles)
	_suppressPickerRelay = false
	var missingSheet := sheet == null and not tilesetID.is_empty()
	_pickerHint.text = (
		"This tileset's sheet is not imported yet, so no frames are shown. The value row below "
		+ "still selects its tiles by id."
	)
	_pickerHint.visible = missingSheet


## Hides the sheet for a layer whose values are not sheet frames, and says which kind it is
## instead -- see the class note on why a height step may not be offered as a thumbnail.
func showValueOnlyPalette(kindLabel: String) -> void:
	if picker == null:
		return
	picker.visible = false
	_paletteTitle.text = "%s layer" % kindLabel.capitalize()
	_pickerHint.text = "This layer's values are not tiles, so it has no tilesheet."
	_pickerHint.visible = true


func hasValueRow() -> bool:
	return tileOption != null


func selectedTileID() -> String:
	return selectedValue()


func selectedValue() -> String:
	if tileOption == null or tileOption.selected < 0:
		return WorldMapTileData.EMPTY
	var index := tileOption.selected
	return _tileIDs[index] if index >= 0 and index < _tileIDs.size() else WorldMapTileData.EMPTY


func selectTileID(id: String) -> void:
	var index := _tileIDs.find(id)
	if index >= 0:
		tileOption.selected = index
		_syncPickerToValue()


## `labels` is what a person reads and `values` is what the controller acts on -- a pair rather
## than one list, because a sculpt step reads "+0.50" and acts as `0.5`. `values` is the authority
## on length; a labels list that disagrees is truncated rather than silently mismatched.
func setValueChoices(labels: Array[String], values: Array[String], selectedValueID := "") -> void:
	_tileIDs = values.duplicate()
	tileOption.clear()
	for i in _tileIDs.size():
		tileOption.add_item(labels[i] if i < labels.size() else _tileIDs[i])
	var index := _tileIDs.find(selectedValueID)
	tileOption.selected = index if index >= 0 else (0 if not _tileIDs.is_empty() else -1)
	tileOption.disabled = _tileIDs.is_empty()
	_syncPickerToValue()


## Tile choices: the value row with an erase entry in front of it. Erasing is a value rather than
## a separate brush, so every shape can erase -- the toolbar's Erase button selects this entry
## rather than being a tool of its own.
func setTileChoices(ids: Array[String], selectedID := "") -> void:
	var labels: Array[String] = ["Erase (-)"]
	var values: Array[String] = [WorldMapTileData.EMPTY]
	for id in ids:
		labels.append(id)
		values.append(id)
	setValueChoices(labels, values, selectedID if not ids.is_empty() else "")
	if selectedID.is_empty() or not ids.has(selectedID):
		# Default to the first real tile rather than to Erase: an author who picks a layer wants
		# to paint on it far more often than to clear it.
		tileOption.selected = 1 if not ids.is_empty() else 0
		_syncPickerToValue()
	tileOption.disabled = ids.is_empty()


## Selects the erase entry without changing tool. What the toolbar's Erase button applies.
func selectEraseValue() -> bool:
	var index := _tileIDs.find(WorldMapTileData.EMPTY)
	if index < 0:
		return false
	tileOption.selected = index
	return true


func firstPaintableValue() -> String:
	for id in _tileIDs:
		if id != WorldMapTileData.EMPTY:
			return id
	return ""


func setValueLabel(text: String) -> void:
	if tileLabel != null:
		tileLabel.text = text


func scatterSeed() -> int:
	return int(seedSpin.value)


func _onValueRowSelected(_index: int) -> void:
	_syncPickerToValue()


## Keeps the sheet's outline on whatever the value row now applies, without letting that echo back
## as a user selection -- see `_suppressPickerRelay`.
func _syncPickerToValue() -> void:
	if picker == null or not picker.visible:
		return
	var value := selectedValue()
	var selection: Array[String] = []
	if value != WorldMapTileData.EMPTY:
		selection.append(value)
	_suppressPickerRelay = true
	picker.selectTileIDs(selection)
	_suppressPickerRelay = false


func _onPickerPrimaryChanged(_tilesetID: String, tileID: String) -> void:
	if _suppressPickerRelay or tileID.is_empty():
		return
	var index := _tileIDs.find(tileID)
	if index >= 0:
		tileOption.selected = index


func _label(text: String) -> Label:
	var made := Label.new()
	made.text = text
	return made
