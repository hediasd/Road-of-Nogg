## Editor-only visual picker for an already-normalized tileset ledger.
##
## The picker deliberately knows only the supplied sheet and tile metadata.  It
## does not load a catalog or mutate a document: its caller owns both of those
## boundaries and receives stable tile ids through the two signals below.
class_name WorldMapTilesetPicker
extends Control

signal primaryTileChanged(tilesetID: String, tileID: String)
signal selectionChanged(tilesetID: String, tileIDs: Array[String])

const PALETTE_ZOOMS: Array[int] = [1, 2, 4]
const SHEET_VIEWPORT_MIN_HEIGHT := 112.0


class SheetCanvas extends Control:
	var picker: WorldMapTilesetPicker

	func _draw() -> void:
		picker._drawSheet(self)

	func _gui_input(event: InputEvent) -> void:
		picker._handleSheetInput(event)


var _tilesetID := ""
var _sheet: Texture2D
var _framePx := 0
var _tilesByID: Dictionary = {}
var _tileIDsByCell: Dictionary = {}
## Whether each tile id is walkable, from the same `WALKABLE` field `configure()` reads off the
## raw tile dict. Kept out of `_tilesByID`'s normalised shape because it changes independently of
## everything else there -- `setTileWalkable()` updates one entry without touching the rest.
var _walkableByID: Dictionary = {}
var _selectedTileIDs: Array[String] = []
var _primaryTileID := ""
var _plainClickAnchor := Vector2i(-1, -1)
var _paletteZoom := 2
var _fitMode := true

var _uiBuilt := false
var _zoomLabel: Label
var _sheetScroll: ScrollContainer
var _sheetCanvas: SheetCanvas


func _ready() -> void:
	_ensureUi()
	_refreshUi()


## `tiles` is catalog-normalized data: each record needs ID and CELL, while
## LABEL/TERRAIN/VARIANT are display metadata.  Positions always come from CELL;
## shuffled ledger arrays and transparent sheet slots cannot alter hit mapping.
func configure(tilesetID: String, sheet: Texture2D, framePx: int, tiles: Array[Dictionary]) -> void:
	var previousTilesetID := _tilesetID
	var previousSelection := _selectedTileIDs.duplicate()
	var previousPrimary := _primaryTileID
	_tilesetID = tilesetID
	_sheet = sheet
	_framePx = max(framePx, 0)
	_tilesByID.clear()
	_tileIDsByCell.clear()
	_walkableByID.clear()
	for tile: Dictionary in tiles:
		var id := str(tile.get("ID", ""))
		var cellValue = tile.get("CELL", Vector2i(-1, -1))
		if id.is_empty() or not (cellValue is Vector2i):
			continue
		var cell: Vector2i = cellValue
		if cell.x < 0 or cell.y < 0 or _tileIDsByCell.has(cell):
			continue
		if _sheet != null and _framePx > 0:
			var sheetSize := _sheet.get_size()
			if (cell.x + 1) * _framePx > sheetSize.x or (cell.y + 1) * _framePx > sheetSize.y:
				continue
		var normalized := {
			"ID": id,
			"CELL": cell,
			"LABEL": str(tile.get("LABEL", "")),
			"TERRAIN": str(tile.get("TERRAIN", "")),
			"VARIANT": str(tile.get("VARIANT", "")),
		}
		_tilesByID[id] = normalized
		_tileIDsByCell[cell] = id
		_walkableByID[id] = str(tile.get("WALKABLE", "")) != "false"

	_selectedTileIDs.clear()
	if previousTilesetID == _tilesetID:
		for id: String in previousSelection:
			if _tilesByID.has(id):
				_selectedTileIDs.append(id)
	_sortSelection()
	_primaryTileID = previousPrimary if _selectedTileIDs.has(previousPrimary) else _firstSelectedID()
	if _plainClickAnchor.x < 0 or _plainClickAnchor.y < 0 or not _tileIDsByCell.has(_plainClickAnchor):
		_plainClickAnchor = Vector2i(-1, -1)
	_ensureUi()
	_refreshUi()


## Controller synchronization is intentionally silent.  Only a human gesture
## can emit a change signal, avoiding selection feedback loops during refresh.
func selectTileIDs(tileIDs: Array[String]) -> void:
	_selectedTileIDs.clear()
	var seen: Dictionary = {}
	for id: String in tileIDs:
		if _tilesByID.has(id) and not seen.has(id):
			seen[id] = true
			_selectedTileIDs.append(id)
	_sortSelection()
	_primaryTileID = _firstSelectedID()
	_ensureUi()
	_refreshUi()


func selectedTileIDs() -> Array[String]:
	return _selectedTileIDs.duplicate()


## Updates one tile's marker without a full `configure()`. Unknown ids are ignored rather than
## added -- this reflects a fact the caller already has from the catalog, not a new tile.
func setTileWalkable(tileID: String, walkable: bool) -> void:
	if not _tilesByID.has(tileID):
		return
	_walkableByID[tileID] = walkable
	if _uiBuilt:
		_sheetCanvas.queue_redraw()


func primaryTileID() -> String:
	return _primaryTileID


## `point` is in unzoomed source-image pixels, not picker-local coordinates.
func tileAtSheetPoint(point: Vector2) -> String:
	if _sheet == null or _framePx <= 0 or point.x < 0.0 or point.y < 0.0:
		return ""
	var size := _sheet.get_size()
	if point.x >= size.x or point.y >= size.y:
		return ""
	var cell := Vector2i(floori(point.x / _framePx), floori(point.y / _framePx))
	if (cell.x + 1) * _framePx > size.x or (cell.y + 1) * _framePx > size.y:
		return ""
	return str(_tileIDsByCell.get(cell, ""))


## THE PICKER IS AS TALL AS ITS CONTENTS, and this is the only thing that says so. `PickerColumn`
## is ANCHORED to this control rather than parented to a container, so nothing propagates its
## minimum size up here on its own -- and because it grows in both directions, a picker laid out
## shorter than its column does not clip: the column spills UPWARDS and draws over whatever sits
## above it in the palette. That is what happened when the height floor came down; the starter
## sheet's quick-choice row lost its bottom edge to the tilesheet toolbar.
##
## Reporting the real minimum makes the floor a floor again. Too little room now scrolls the
## palette, which is what a scroll is for, instead of stacking two rows on the same pixels.
func _get_minimum_size() -> Vector2:
	var column := get_node_or_null("PickerColumn") as Control
	if column == null:
		return custom_minimum_size
	var wanted := column.get_combined_minimum_size()
	return Vector2(maxf(custom_minimum_size.x, wanted.x), maxf(custom_minimum_size.y, wanted.y))


func _ensureUi() -> void:
	if _uiBuilt:
		return
	_uiBuilt = true
	name = "WorldMapTilesetPicker"
	tooltip_text = "Choose one or more tiles from this tileset."
	focus_mode = Control.FOCUS_ALL
	texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	# The HEIGHT floor is 220, not the 300 this shipped with. The guarantee that actually matters
	# is `SHEET_VIEWPORT_MIN_HEIGHT` on the sheet's own scroll, applied separately below; 300 was a
	# second, larger floor on top of it, and the difference was dead space under the sheet. The
	# left column now carries the map menu underneath, so that slack came straight out of the
	# buttons. Given more room the sheet still expands into it.
	#
	# A FLOOR ONLY. The real minimum comes from `_get_minimum_size()` below, which is what stops a
	# short floor from becoming an overlap.
	custom_minimum_size = Vector2(220.0, 220.0)
	resized.connect(_refreshUi)

	var column := VBoxContainer.new()
	column.name = "PickerColumn"
	column.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	column.grow_horizontal = Control.GROW_DIRECTION_BOTH
	column.grow_vertical = Control.GROW_DIRECTION_BOTH
	column.size_flags_vertical = Control.SIZE_EXPAND_FILL
	add_child(column)

	var toolbar := HBoxContainer.new()
	toolbar.name = "PaletteZoomControls"
	column.add_child(toolbar)
	var title := Label.new()
	title.name = "PaletteLabel"
	title.text = "Tilesheet"
	title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	toolbar.add_child(title)
	var fit := Button.new()
	fit.name = "PaletteFit"
	fit.text = "Fit"
	fit.tooltip_text = "Fit the complete tilesheet into the palette"
	fit.focus_mode = Control.FOCUS_ALL
	fit.pressed.connect(_fitSheet)
	toolbar.add_child(fit)
	var zoomOut := Button.new()
	zoomOut.name = "PaletteZoomOut"
	zoomOut.text = "−"
	zoomOut.tooltip_text = "Decrease tilesheet zoom"
	zoomOut.focus_mode = Control.FOCUS_ALL
	zoomOut.pressed.connect(func() -> void: _changeZoom(-1))
	toolbar.add_child(zoomOut)
	_zoomLabel = Label.new()
	_zoomLabel.name = "PaletteZoomLabel"
	_zoomLabel.tooltip_text = "Tilesheet zoom"
	toolbar.add_child(_zoomLabel)
	var zoomIn := Button.new()
	zoomIn.name = "PaletteZoomIn"
	zoomIn.text = "+"
	zoomIn.tooltip_text = "Increase tilesheet zoom"
	zoomIn.focus_mode = Control.FOCUS_ALL
	zoomIn.pressed.connect(func() -> void: _changeZoom(1))
	toolbar.add_child(zoomIn)

	_sheetScroll = ScrollContainer.new()
	_sheetScroll.name = "TilesheetScroll"
	_sheetScroll.tooltip_text = "Scroll the tilesheet without moving the map camera"
	_sheetScroll.custom_minimum_size = Vector2(0.0, SHEET_VIEWPORT_MIN_HEIGHT)
	_sheetScroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_sheetScroll.mouse_filter = Control.MOUSE_FILTER_STOP
	column.add_child(_sheetScroll)
	_sheetCanvas = SheetCanvas.new()
	_sheetCanvas.name = "TilesheetCanvas"
	_sheetCanvas.picker = self
	_sheetCanvas.tooltip_text = "Left click selects. Ctrl-click toggles. Shift-click selects a rectangle. Arrow keys move selection."
	_sheetCanvas.focus_mode = Control.FOCUS_ALL
	_sheetCanvas.mouse_filter = Control.MOUSE_FILTER_STOP
	_sheetCanvas.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	_sheetScroll.add_child(_sheetCanvas)


func _changeZoom(direction: int) -> void:
	_fitMode = false
	var currentIndex := PALETTE_ZOOMS.find(_paletteZoom)
	currentIndex = clampi(currentIndex + direction, 0, PALETTE_ZOOMS.size() - 1)
	if _paletteZoom == PALETTE_ZOOMS[currentIndex]:
		return
	_paletteZoom = PALETTE_ZOOMS[currentIndex]
	_refreshUi()


func _fitSheet() -> void:
	_fitMode = true
	_refreshUi()


func _refreshUi() -> void:
	if not _uiBuilt:
		return
	_zoomLabel.text = "Fit" if _fitMode else "%dx" % _paletteZoom
	if _sheet == null or _framePx <= 0:
		_sheetCanvas.custom_minimum_size = Vector2.ZERO
	else:
		_sheetCanvas.custom_minimum_size = _sheet.get_size() * _displayZoom()
	_sheetCanvas.queue_redraw()


func _drawSheet(canvas: Control) -> void:
	if _sheet == null:
		return
	canvas.draw_rect(Rect2(Vector2.ZERO, canvas.size), Color("15222b"), true)
	canvas.draw_texture_rect(_sheet, Rect2(Vector2.ZERO, _sheet.get_size() * _displayZoom()), false)
	for id: String in _selectedTileIDs:
		var rect := _zoomedFrameRect(id)
		canvas.draw_rect(rect, Color("60d8ff"), false, 2.0)
	if not _primaryTileID.is_empty():
		canvas.draw_rect(_zoomedFrameRect(_primaryTileID).grow(-3.0), Color("fff2a3"), false, 2.0)
	# Drawn last so the mark is never hidden under a selection or primary outline.
	for id: String in _tilesByID:
		if _walkableByID.get(id, true):
			continue
		var mark := _zoomedFrameRect(id).grow(-6.0)
		canvas.draw_line(mark.position, mark.end, Color("ff5a5a"), 2.0)
		canvas.draw_line(Vector2(mark.position.x, mark.end.y), Vector2(mark.end.x, mark.position.y), Color("ff5a5a"), 2.0)


func _handleSheetInput(event: InputEvent) -> void:
	if event is InputEventMouseButton:
		var mouse := event as InputEventMouseButton
		if mouse.button_index == MOUSE_BUTTON_WHEEL_UP or mouse.button_index == MOUSE_BUTTON_WHEEL_DOWN:
			_sheetScroll.scroll_vertical = max(0, _sheetScroll.scroll_vertical + (-48 if mouse.button_index == MOUSE_BUTTON_WHEEL_UP else 48))
			_sheetCanvas.accept_event()
			return
		if mouse.button_index == MOUSE_BUTTON_LEFT and mouse.pressed:
			var id := tileAtSheetPoint(mouse.position / _displayZoom())
			if mouse.shift_pressed:
				_selectRange(id)
			elif mouse.ctrl_pressed:
				_toggleSelection(id)
			else:
				_selectPlain(id)
			_sheetCanvas.grab_focus()
			_sheetCanvas.accept_event()
			return
	if event is InputEventKey:
		var key := event as InputEventKey
		if key.pressed and not key.echo:
			_handleKeyboardSelection(key.keycode)
			_sheetCanvas.accept_event()


func _handleKeyboardSelection(keycode: Key) -> void:
	if _tilesByID.is_empty():
		return
	if keycode == KEY_ESCAPE:
		_plainClickAnchor = Vector2i(-1, -1)
		_applyUserSelection([], "")
		return
	if keycode == KEY_ENTER or keycode == KEY_SPACE:
		if _primaryTileID.is_empty():
			_selectPlain(_orderedTileIDs()[0])
		return
	if keycode != KEY_LEFT and keycode != KEY_RIGHT and keycode != KEY_UP and keycode != KEY_DOWN:
		return
	if _primaryTileID.is_empty():
		_selectPlain(_orderedTileIDs()[0])
		return
	var next := _tileInDirection(_cellForID(_primaryTileID), keycode)
	if not next.is_empty():
		_selectPlain(next)


func _selectPlain(id: String) -> void:
	if id.is_empty():
		_plainClickAnchor = Vector2i(-1, -1)
		_applyUserSelection([], "")
		return
	_plainClickAnchor = _cellForID(id)
	_applyUserSelection([id], id)


func _toggleSelection(id: String) -> void:
	if id.is_empty():
		return
	var next := _selectedTileIDs.duplicate()
	if next.has(id):
		next.erase(id)
		_applyUserSelection(next, _firstID(next))
	else:
		next.append(id)
		_applyUserSelection(next, id)


func _selectRange(id: String) -> void:
	if id.is_empty():
		return
	var end := _cellForID(id)
	if _plainClickAnchor.x < 0 or _plainClickAnchor.y < 0:
		_plainClickAnchor = end
	var start := _plainClickAnchor
	var selected: Array[String] = []
	for candidate: String in _orderedTileIDs():
		var cell := _cellForID(candidate)
		if cell.x >= min(start.x, end.x) and cell.x <= max(start.x, end.x) and cell.y >= min(start.y, end.y) and cell.y <= max(start.y, end.y):
			selected.append(candidate)
	_applyUserSelection(selected, id)


func _applyUserSelection(tileIDs: Array[String], primaryID: String) -> void:
	var next: Array[String] = []
	var seen: Dictionary = {}
	for id: String in tileIDs:
		if _tilesByID.has(id) and not seen.has(id):
			seen[id] = true
			next.append(id)
	next.sort_custom(_sortIDsByCell)
	var nextPrimary := primaryID if next.has(primaryID) else _firstID(next)
	var selectionChangedNow := next != _selectedTileIDs
	var primaryChangedNow := nextPrimary != _primaryTileID
	if not selectionChangedNow and not primaryChangedNow:
		return
	_selectedTileIDs = next
	_primaryTileID = nextPrimary
	_refreshUi()
	if selectionChangedNow:
		selectionChanged.emit(_tilesetID, selectedTileIDs())
	if primaryChangedNow:
		primaryTileChanged.emit(_tilesetID, _primaryTileID)


func _sortSelection() -> void:
	_selectedTileIDs.sort_custom(_sortIDsByCell)


func _orderedTileIDs() -> Array[String]:
	var ids: Array[String] = []
	for id: String in _tilesByID:
		ids.append(id)
	ids.sort_custom(_sortIDsByCell)
	return ids


func _sortIDsByCell(left: String, right: String) -> bool:
	var leftCell := _cellForID(left)
	var rightCell := _cellForID(right)
	if leftCell.y != rightCell.y:
		return leftCell.y < rightCell.y
	if leftCell.x != rightCell.x:
		return leftCell.x < rightCell.x
	return left < right


func _zoomedFrameRect(id: String) -> Rect2:
	return Rect2(Vector2(_cellForID(id) * _framePx * _displayZoom()), Vector2(_framePx, _framePx) * _displayZoom())


func _displayZoom() -> float:
	if not _fitMode or _sheet == null:
		return float(_paletteZoom)
	var viewport := _sheetScroll.size
	if viewport.x <= 1.0 or viewport.y <= 1.0:
		return 1.0
	var sourceSize := _sheet.get_size()
	return maxf(0.25, minf(viewport.x / sourceSize.x, viewport.y / sourceSize.y))


## Arrow navigation stays spatial even when a sheet intentionally has transparent slots. A
## missing neighbour does nothing rather than wrapping to a different row or column.
func _tileInDirection(origin: Vector2i, keycode: Key) -> String:
	var bestID := ""
	var bestDistance := 2147483647
	for candidate: String in _orderedTileIDs():
		var cell := _cellForID(candidate)
		var valid := false
		var distance := 0
		if keycode == KEY_LEFT and cell.y == origin.y and cell.x < origin.x:
			valid = true
			distance = origin.x - cell.x
		elif keycode == KEY_RIGHT and cell.y == origin.y and cell.x > origin.x:
			valid = true
			distance = cell.x - origin.x
		elif keycode == KEY_UP and cell.x == origin.x and cell.y < origin.y:
			valid = true
			distance = origin.y - cell.y
		elif keycode == KEY_DOWN and cell.x == origin.x and cell.y > origin.y:
			valid = true
			distance = cell.y - origin.y
		if valid and distance < bestDistance:
			bestID = candidate
			bestDistance = distance
	return bestID


func _cellForID(id: String) -> Vector2i:
	var tile: Dictionary = _tilesByID.get(id, {})
	return tile.get("CELL", Vector2i(-1, -1)) as Vector2i


func _firstSelectedID() -> String:
	return _firstID(_selectedTileIDs)


func _firstID(ids: Array[String]) -> String:
	return "" if ids.is_empty() else ids[0]
