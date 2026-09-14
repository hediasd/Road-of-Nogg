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
const Tilesets = preload("res://src/presentation/worldmap/editor/WorldMapTilesetCatalog.gd")

var chrome: ChromeScript
var badge: Label
var picker: PickerScript
var tileOption: OptionButton
var tileLabel: Label
var seedSpin: SpinBox

var _paletteTitle: Label
var _quickChoices: HBoxContainer
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

var _tilesetProperties: VBoxContainer
var _tilesetSheetSize: Label
var _tilesetFrameSize: SpinBox
var _tilesetFrameApply: Button
var _tilesetRefresh: Button
var _tilesetFrameWarning: Label
var _tilesetTileCount: Label
var _tileWalkable: CheckBox
var _onWalkableToggled: Callable
var _onFrameSizeRequested: Callable
var _onRefreshRequested: Callable
var _propertiesTilesetID := ""
var _propertiesFramePx := 0
var _propertiesTileCount := 0
## The authored `WALKABLE` fact per tile id, from the same catalog data `configurePalette()` was
## last called with -- kept here rather than re-read from the picker so `setTileWalkable()` can
## answer "is this the primary tile" without adding that question to the picker's own API.
var _walkableByTileID: Dictionary = {}


func _init(workspaceChrome: ChromeScript) -> void:
	chrome = workspaceChrome


func build(
	layers: Array,
	onLayerSelected: Callable,
	onVisibilityToggled: Callable,
	onLockToggled: Callable,
	hideableReasons: Dictionary,
	onWalkableToggled: Callable = Callable(),
	onFrameSizeRequested: Callable = Callable(),
	onRefreshRequested: Callable = Callable()
) -> void:
	_onWalkableToggled = onWalkableToggled
	_onFrameSizeRequested = onFrameSizeRequested
	_onRefreshRequested = onRefreshRequested
	_buildPalette()
	_buildInspector(layers, onLayerSelected, onVisibilityToggled, onLockToggled, hideableReasons)


func _buildPalette() -> void:
	var column := chrome.paletteColumn

	_paletteTitle = Label.new()
	_paletteTitle.name = "PaletteTilesetName"
	_paletteTitle.text = "No tileset"
	_paletteTitle.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	column.add_child(_paletteTitle)

	_quickChoices = HBoxContainer.new()
	_quickChoices.name = "PaletteQuickChoices"
	_quickChoices.visible = false
	column.add_child(_quickChoices)

	picker = PickerScript.new()
	picker.name = "TilesetPicker"
	picker.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	picker.primaryTileChanged.connect(_onPickerPrimaryChanged)
	picker.walkableToggleRequested.connect(_onPickerWalkableToggleRequested)
	column.add_child(picker)

	_pickerHint = Label.new()
	_pickerHint.name = "PaletteHint"
	_pickerHint.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_pickerHint.text = ""
	_pickerHint.visible = false
	column.add_child(_pickerHint)

	_buildTilesetProperties(column)

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


## The tileset's own facts, shown right under the picker: sheet size, the editable frame size, a
## warning when that frame size is not the 32 px hex maps expect, the tile count, and a Walkable
## checkbox for the selected tile. Everything in this block is written straight to the tileset's
## config file as soon as it changes -- there is no undo, because none of it is part of the map.
func _buildTilesetProperties(column: VBoxContainer) -> void:
	_tilesetProperties = VBoxContainer.new()
	_tilesetProperties.name = "TilesetProperties"
	column.add_child(_tilesetProperties)

	# Named explicitly as tileset-wide: every field below writes to the tileset's own config file,
	# not to this map, and every OTHER map built from the same sheet sees the change too. This
	# block sits under the picker only because the picker is what names which tileset is active --
	# it is not a per-map setting shown here for convenience.
	var heading := Label.new()
	heading.name = "TilesetPropertiesHeading"
	heading.text = "Tileset (shared by every map using this sheet)"
	heading.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	heading.add_theme_color_override("font_color", Color(0.62, 0.70, 0.73))
	_tilesetProperties.add_child(heading)

	_tilesetSheetSize = Label.new()
	_tilesetSheetSize.name = "TilesetSheetSize"
	_tilesetProperties.add_child(_tilesetSheetSize)

	_tilesetRefresh = Button.new()
	_tilesetRefresh.name = "TilesetRefresh"
	_tilesetRefresh.text = "Refresh from art"
	_tilesetRefresh.tooltip_text = (
		"Re-reads the sheet and updates the tileset's tile ledger: new frames are added, moved or "
		+ "repainted frames keep their id, and frames no longer in the sheet are retired. This map's "
		+ "painted cells are not touched."
	)
	_tilesetRefresh.pressed.connect(_onRefreshPressed)
	_tilesetProperties.add_child(_tilesetRefresh)

	var frameRow := HBoxContainer.new()
	_tilesetProperties.add_child(frameRow)
	frameRow.add_child(_label("Frame size"))
	_tilesetFrameSize = SpinBox.new()
	_tilesetFrameSize.name = "TilesetFrameSize"
	_tilesetFrameSize.min_value = Tilesets.MIN_FRAME_PX
	_tilesetFrameSize.max_value = Tilesets.MAX_FRAME_PX
	_tilesetFrameSize.step = 1
	_tilesetFrameSize.suffix = "px"
	_tilesetFrameSize.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_tilesetFrameSize.value_changed.connect(_onFrameSpinChanged)
	frameRow.add_child(_tilesetFrameSize)
	_tilesetFrameApply = Button.new()
	_tilesetFrameApply.name = "TilesetFrameApply"
	_tilesetFrameApply.text = "Apply"
	_tilesetFrameApply.pressed.connect(_onFrameApplyPressed)
	frameRow.add_child(_tilesetFrameApply)

	_tilesetFrameWarning = Label.new()
	_tilesetFrameWarning.name = "TilesetFrameWarning"
	_tilesetFrameWarning.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_tilesetFrameWarning.add_theme_color_override("font_color", Color(1.0, 0.55, 0.2))
	_tilesetFrameWarning.visible = false
	_tilesetProperties.add_child(_tilesetFrameWarning)

	_tilesetTileCount = Label.new()
	_tilesetTileCount.name = "TilesetTileCount"
	_tilesetProperties.add_child(_tilesetTileCount)

	_tileWalkable = CheckBox.new()
	_tileWalkable.name = "TileWalkable"
	_tileWalkable.text = "Walkable"
	_tileWalkable.tooltip_text = (
		"Whether the selected tile can be walked on. Saved to this tileset's config. To set many "
		+ "tiles quickly, turn on Edit walkability above the sheet and click them."
	)
	_tileWalkable.disabled = true
	_tileWalkable.toggled.connect(_onTileWalkableToggledByUser)
	_tilesetProperties.add_child(_tileWalkable)

	_tilesetProperties.visible = false


func _onFrameSpinChanged(_value: float) -> void:
	_tilesetFrameApply.disabled = int(_tilesetFrameSize.value) == _propertiesFramePx


## Refusing outright when there is nothing to lose: a sheet with zero tiles has nothing a re-cut
## could retire, so the confirmation this function otherwise opens would only be asking the author
## to confirm a no-op.
## No confirmation dialog: unlike a frame-size change, a re-import only ever retires a tile id that
## the sheet genuinely no longer has -- everything unchanged, moved or repainted keeps its id (see
## `WorldMapTilesetCatalog.reconcile()`'s own note on that ordering). The report the controller
## puts in the status line afterward is the "a human looks at this" step, not a confirmation before
## it happens.
func _onRefreshPressed() -> void:
	_onRefreshRequested.call(_propertiesTilesetID)


func _onFrameApplyPressed() -> void:
	var framePx := int(_tilesetFrameSize.value)
	if _propertiesTileCount <= 0:
		_onFrameSizeRequested.call(_propertiesTilesetID, framePx)
		return
	var dialog := ConfirmationDialog.new()
	dialog.dialog_text = (
		"Changing the frame size re-cuts the sheet and retires all %d tile IDs. Other saved maps "
		+ "that use %s will lose their art. Continue?"
	) % [_propertiesTileCount, _propertiesTilesetID]
	dialog.confirmed.connect(func() -> void: _onFrameSizeRequested.call(_propertiesTilesetID, framePx))
	dialog.canceled.connect(func() -> void:
		_tilesetFrameSize.set_value_no_signal(_propertiesFramePx)
		_onFrameSpinChanged(_propertiesFramePx)
	)
	dialog.visibility_changed.connect(func() -> void:
		if not dialog.visible:
			dialog.queue_free()
	)
	chrome.root.add_child(dialog)
	dialog.popup_centered()


func _onTileWalkableToggledByUser(pressed: bool) -> void:
	var tileID := picker.primaryTileID() if picker != null else ""
	if tileID.is_empty():
		return
	_onWalkableToggled.call(_propertiesTilesetID, tileID, pressed)


## Reflects the picker's current primary tile in the Walkable checkbox, without writing anything --
## the checkbox is disabled rather than hidden when there is no primary tile, so its own state stays
## visibly meaningless instead of silently applying to whatever was selected before.
func _syncWalkableCheckbox() -> void:
	if _tileWalkable == null:
		return
	var tileID := picker.primaryTileID() if picker != null else ""
	_tileWalkable.disabled = tileID.is_empty()
	_tileWalkable.set_pressed_no_signal(
		not tileID.is_empty() and bool(_walkableByTileID.get(tileID, true))
	)


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
	tilesetID: String, sheet: Texture2D, framePx: int, tiles: Array[Dictionary],
	layout := WorldMapTilesetCatalog.LAYOUT_GRID
) -> void:
	if picker == null:
		return
	_paletteTitle.text = tilesetID if not tilesetID.is_empty() else "No tileset"
	_cellByTileID.clear()
	for tile in tiles:
		var cellValue = tile.get("CELL", null)
		if cellValue is Vector2i:
			_cellByTileID[str(tile.get("ID", ""))] = cellValue
	_configureQuickChoices(tilesetID, sheet, framePx, tiles)
	picker.visible = true
	_suppressPickerRelay = true
	picker.configure(tilesetID, sheet, framePx, tiles, layout)
	_suppressPickerRelay = false
	var missingSheet := sheet == null and not tilesetID.is_empty()
	_pickerHint.text = (
		"This tileset's sheet is not imported yet, so no frames are shown. The value row below "
		+ "still selects its tiles by id."
	)
	_pickerHint.visible = missingSheet
	_configureTilesetProperties(tilesetID, sheet, framePx, tiles)


func _configureTilesetProperties(
	tilesetID: String, sheet: Texture2D, framePx: int, tiles: Array[Dictionary]
) -> void:
	if _tilesetProperties == null:
		return
	_propertiesTilesetID = tilesetID
	_propertiesFramePx = framePx
	_propertiesTileCount = tiles.size()
	_walkableByTileID.clear()
	for tile in tiles:
		_walkableByTileID[str(tile.get("ID", ""))] = str(tile.get("WALKABLE", true)) != "false"
	_tilesetProperties.visible = true
	_tilesetSheetSize.text = (
		"Sheet: %d × %d px" % [int(sheet.get_size().x), int(sheet.get_size().y)]
		if sheet != null else "Sheet: not readable"
	)
	_tilesetFrameSize.set_value_no_signal(framePx)
	_tilesetFrameApply.disabled = true
	_tilesetFrameWarning.text = (
		"Hex maps expect 32 × 32 frames. This sheet uses %d × %d." % [framePx, framePx]
	)
	_tilesetFrameWarning.visible = framePx != 32
	_tilesetTileCount.text = "%d tiles" % tiles.size()
	_syncWalkableCheckbox()


func _configureQuickChoices(
	tilesetID: String, sheet: Texture2D, framePx: int, tiles: Array[Dictionary]
) -> void:
	for child in _quickChoices.get_children():
		_quickChoices.remove_child(child)
		child.queue_free()
	_quickChoices.visible = false
	if tilesetID != "temp2_hex32_starter":
		return
	var byID := {}
	for tile in tiles:
		byID[str(tile.get("ID", ""))] = tile
	for choice: Dictionary in [
		{"id": "t000", "label": "Land"},
		{"id": "t001", "label": "Sea"},
		{"id": "t002", "label": "Grass"},
	]:
		var id := str(choice["id"])
		if not byID.has(id):
			continue
		var button := Button.new()
		button.name = "Quick_%s" % id
		button.text = str(choice["label"])
		button.tooltip_text = "%s (%s)" % [button.text, id]
		button.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		button.custom_minimum_size.x = 68.0
		if sheet != null and framePx > 0:
			var cell: Vector2i = (byID[id] as Dictionary).get("CELL", Vector2i.ZERO)
			var icon := AtlasTexture.new()
			icon.atlas = sheet
			icon.region = Rect2(Vector2(cell * framePx), Vector2(framePx, framePx))
			button.icon = icon
			button.expand_icon = true
		button.pressed.connect(selectTileID.bind(id))
		_quickChoices.add_child(button)
	_quickChoices.visible = _quickChoices.get_child_count() == 3


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
	if _tilesetProperties != null:
		_tilesetProperties.visible = false


func hasValueRow() -> bool:
	return tileOption != null


## The sheet's current multi-selection, in the picker's own (row, column, id) order. What the
## stamp and scatter tools read: selecting several frames IS how a multi-tile stamp is described,
## so there is no second selection UI that could disagree with the sheet the author is looking at.
##
## THE EMPTY ANSWER IS A DECLARED LOCAL, NOT `[] as Array[String]`. On a builtin type `as` is a
## runtime no-op, so that expression yields an UNTYPED array and returning it from a function
## declared `Array[String]` throws -- which meant this errored and returned null on the ordinary
## path, with nothing selected or exactly one frame selected, taking Stamp and Scatter with it.
func selectedSheetTileIDs() -> Array[String]:
	var none: Array[String] = []
	if picker == null or not picker.visible:
		return none
	var ids := picker.selectedTileIDs()
	# One frame is a single-tile stamp, which the caller already handles from the value row; only
	# a real multi-selection is worth reporting as a pattern.
	return ids if ids.size() > 1 else none


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
		_syncWalkableCheckbox()
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
	_syncWalkableCheckbox()


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


## Updates the cached value, the checkbox (only when `tileID` is the primary tile, so a background
## write from elsewhere never overwrites what the checkbox is showing for a tile the author has
## since moved on from), and the picker's own red-X marker.
func setTileWalkable(tileID: String, walkable: bool) -> void:
	_walkableByTileID[tileID] = walkable
	if picker != null:
		picker.setTileWalkable(tileID, walkable)
	if picker != null and picker.primaryTileID() == tileID:
		_syncWalkableCheckbox()


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


func _onPickerWalkableToggleRequested(tilesetID: String, tileID: String, walkable: bool) -> void:
	if _onWalkableToggled.is_valid():
		_onWalkableToggled.call(tilesetID, tileID, walkable)


func _onPickerPrimaryChanged(_tilesetID: String, tileID: String) -> void:
	if _suppressPickerRelay:
		return
	_eraseSelected = false
	_syncWalkableCheckbox()


func _label(text: String) -> Label:
	var made := Label.new()
	made.text = text
	return made
