## What fills the workspace's palette and inspector columns: the tilesheet picker, the value row
## the active layer's tool applies, the layer list, the under-cursor readout and the off-contract
## badge.
##
## FRAME VERSUS CONTENTS. `WorldMapWorkspaceChrome` builds the header, toolbar, columns and footer
## and owns every action button; this fills two of those columns. The split is why neither file
## has to know much about the other: the chrome hands over two `VBoxContainer`s and takes back a
## status string, and everything about WHICH LAYER and WHICH VALUE lives here.
##
## THE PICKER IS THE ART AUTHORITY. `WorldMapTilesetPicker`'s primary tile is what brushes read
## through `selectedTileID()`; the generic value row is hidden for art layers and remains only
## for values that have no tile image, such as sculpt steps and object kinds. Clearing the picker
## therefore clears paint selection unless the author explicitly chooses Erase.
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
var _valueRow: VBoxContainer
var _seedRow: HBoxContainer
var _cursorCellValue: Label
var _cursorTileValue: Label
var _layerButtons: Array[Button] = []
var _layerVisibilityToggles: Array[CheckBox] = []
var _layerLockToggles: Array[CheckBox] = []
var _layerIDs: Array[String] = []
var _layerLabels: Array[String] = []
var _tileIDs: Array[String] = []
## Frame position per tile id, taken from the catalog data the palette was configured with. Kept
## here rather than read back out of the picker so the stamp needs no addition to the picker's
## public API -- frame positions are catalog facts, and this class already has them.
var _cellByTileID: Dictionary = {}
var _suppressPickerRelay := false
var _eraseSelected := false


func _init(workspaceChrome: ChromeScript) -> void:
	chrome = workspaceChrome


func build(
	layers: Array,
	onLayerSelected: Callable,
	onVisibilityToggled: Callable,
	onLockToggled: Callable,
	hideableReasons: Dictionary
) -> void:
	_buildPalette()
	_buildInspector(layers, onLayerSelected, onVisibilityToggled, onLockToggled, hideableReasons)


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

	_valueRow = VBoxContainer.new()
	column.add_child(_valueRow)
	tileLabel = _label("Tile")
	_valueRow.add_child(tileLabel)
	tileOption = OptionButton.new()
	tileOption.name = "ValueRow"
	tileOption.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	tileOption.tooltip_text = "What the active layer's tool applies."
	tileOption.item_selected.connect(_onValueRowSelected)
	_valueRow.add_child(tileOption)

	_seedRow = HBoxContainer.new()
	column.add_child(_seedRow)
	_seedRow.add_child(_label("Scatter seed"))
	seedSpin = SpinBox.new()
	seedSpin.min_value = 0
	seedSpin.max_value = 2147483647
	seedSpin.step = 1
	seedSpin.value = 1
	seedSpin.allow_greater = false
	seedSpin.allow_lesser = false
	_seedRow.add_child(seedSpin)
	_seedRow.visible = false


func _buildInspector(
	layers: Array,
	onLayerSelected: Callable,
	onVisibilityToggled: Callable,
	onLockToggled: Callable,
	hideableReasons: Dictionary
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

		# Live only for the layers that really have a separable view. The rest keep the control in
		# place, disabled, carrying the reason -- an explanation is honest where a toggle that
		# moved and changed nothing would not be. See `WorldMapWorkspaceLayerView.canHide`.
		var visibility := CheckBox.new()
		visibility.button_pressed = true
		var reason := str(hideableReasons.get(id, ""))
		visibility.disabled = not reason.is_empty()
		visibility.tooltip_text = (
			reason if not reason.is_empty()
			else "Show this layer in the editor. Hiding it never changes what is saved or exported."
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
	_cellByTileID.clear()
	for tile in tiles:
		var cellValue = tile.get("CELL", null)
		if cellValue is Vector2i:
			_cellByTileID[str(tile.get("ID", ""))] = cellValue
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
	_valueRow.visible = true
	_seedRow.visible = false
	_eraseSelected = false


func hasValueRow() -> bool:
	return tileOption != null


## The sheet's current multi-selection, in the picker's own (row, column, id) order. What the
## stamp and scatter tools read: selecting several frames IS how a multi-tile stamp is described,
## so there is no second selection UI that could disagree with the sheet the author is looking at.
func selectedSheetTileIDs() -> Array[String]:
	if picker == null or not picker.visible:
		return [] as Array[String]
	var ids := picker.selectedTileIDs()
	# One frame is a single-tile stamp, which the caller already handles from the value row; only
	# a real multi-selection is worth reporting as a pattern.
	return ids if ids.size() > 1 else [] as Array[String]


## The sheet FRAME positions matching `selectedSheetTileIDs()`, in the same order. The stamp reads
## these as cells of a virtual lattice -- see `WorldMapWorkspaceFootprint.stampPattern`.
func selectedSheetCells() -> Array[Vector2i]:
	var cells: Array[Vector2i] = []
	if picker == null or not picker.visible:
		return cells
	var ids := picker.selectedTileIDs()
	if ids.size() <= 1:
		return cells
	for id in ids:
		cells.append(_cellByTileID.get(id, Vector2i.ZERO))
	return cells


func selectedTileID() -> String:
	return selectedValue()


func selectedValue() -> String:
	if picker != null and picker.visible:
		return WorldMapTileData.EMPTY if _eraseSelected else picker.primaryTileID()
	if tileOption == null or tileOption.selected < 0:
		return WorldMapTileData.EMPTY
	var index := tileOption.selected
	return _tileIDs[index] if index >= 0 and index < _tileIDs.size() else WorldMapTileData.EMPTY


func selectTileID(id: String) -> void:
	if picker != null and picker.visible:
		_eraseSelected = false
		var selection: Array[String] = [id]
		picker.selectTileIDs(selection)
		return
	var index := _tileIDs.find(id)
	if index >= 0:
		tileOption.selected = index
		_syncPickerToValue()


## `labels` is what a person reads and `values` is what the controller acts on -- a pair rather
## than one list, because a sculpt step reads "+0.50" and acts as `0.5`. `values` is the authority
## on length; a labels list that disagrees is truncated rather than silently mismatched.
func setValueChoices(labels: Array[String], values: Array[String], selectedValueID := "") -> void:
	_eraseSelected = false
	_valueRow.visible = true
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
	_tileIDs = ids.duplicate()
	_eraseSelected = false
	_valueRow.visible = false
	if picker == null or not picker.visible:
		return
	var next := selectedID if ids.has(selectedID) else (ids[0] if not ids.is_empty() else "")
	var selection: Array[String] = []
	if not next.is_empty():
		selection.append(next)
	_suppressPickerRelay = true
	picker.selectTileIDs(selection)
	_suppressPickerRelay = false


## Selects the erase entry without changing tool. What the toolbar's Erase button applies.
func selectEraseValue() -> bool:
	if picker != null and picker.visible:
		_eraseSelected = not _tileIDs.is_empty()
		picker.selectTileIDs([])
		return _eraseSelected
	var index := _tileIDs.find(WorldMapTileData.EMPTY)
	if index < 0:
		return false
	tileOption.selected = index
	return true


func requiresTileSelection() -> bool:
	return picker != null and picker.visible and not _eraseSelected and picker.primaryTileID().is_empty()


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


func setScatterVisible(visible: bool) -> void:
	if _seedRow != null:
		_seedRow.visible = visible and picker != null and picker.visible


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
	if _suppressPickerRelay:
		return
	_eraseSelected = false


func _label(text: String) -> Label:
	var made := Label.new()
	made.text = text
	return made
