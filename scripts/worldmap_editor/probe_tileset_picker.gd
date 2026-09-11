extends SceneTree

const PickerScript = preload("res://src/presentation/worldmap/editor/WorldMapTilesetPicker.gd")

var failures: Array[String] = []
var selectionSignals := 0
var primarySignals := 0


func _init() -> void:
	_run.call_deferred()


func _run() -> void:
	var picker = PickerScript.new()
	root.add_child(picker)
	await process_frame
	var preview := picker.get_node("PickerColumn/PrimaryTilePreview/PrimaryTileImage") as Control
	_require(preview != null and not preview.visible, "empty picker reserved a blank preview and squeezed its guidance")
	var image := Image.create(96, 64, false, Image.FORMAT_RGBA8)
	image.fill(Color.WHITE)
	var texture := ImageTexture.create_from_image(image)
	var shuffled: Array[Dictionary] = [
		{"ID": "tC", "CELL": Vector2i(2, 1), "LABEL": "Lower right", "TERRAIN": "grass", "VARIANT": "base"},
		{"ID": "tA", "CELL": Vector2i(0, 0), "LABEL": "Upper left", "TERRAIN": "land", "VARIANT": "base"},
		{"ID": "tB", "CELL": Vector2i(2, 0), "LABEL": "Upper right", "TERRAIN": "sea", "VARIANT": "edge"},
		{"ID": "tD", "CELL": Vector2i(0, 1), "LABEL": "Lower left", "TERRAIN": "land", "VARIANT": "edge"},
	]
	picker.configure("synthetic", texture, 32, shuffled)
	picker.selectionChanged.connect(func(_tilesetID: String, _tileIDs: Array[String]) -> void: selectionSignals += 1)
	picker.primaryTileChanged.connect(func(_tilesetID: String, _tileID: String) -> void: primarySignals += 1)
	_checkHitMapping(picker)
	_checkSelectionGestures(picker)
	_checkDefensiveCopiesAndReconfigure(picker, texture, shuffled)
	_checkSpatialKeyboardAndEmptySelection(picker, texture, shuffled)
	if not failures.is_empty():
		for failure: String in failures:
			printerr("HXW_TILESET_PICKER_FAILURE: %s" % failure)
		quit(1)
		return
	print("WORLD MAP TILESET PICKER OK")
	quit(0)


func _checkHitMapping(picker: PickerScript) -> void:
	_require(picker.tileAtSheetPoint(Vector2(1, 1)) == "tA", "did not use CELL for shuffled upper-left metadata")
	_require(picker.tileAtSheetPoint(Vector2(95, 63)) == "tC", "did not map lower-right frame")
	_require(picker.tileAtSheetPoint(Vector2(33, 1)).is_empty(), "blank sheet slot was treated as a tile")
	_require(picker.tileAtSheetPoint(Vector2(-1, 0)).is_empty() and picker.tileAtSheetPoint(Vector2(96, 0)).is_empty(), "out-of-bounds hit was accepted")
	picker._fitMode = false
	for zoom: int in [1, 2, 4]:
		picker._paletteZoom = zoom
		picker._handleSheetInput(_leftClick(Vector2(65.0 * zoom, 1.0 * zoom)))
		_require(picker.primaryTileID() == "tB", "zoomed sheet hit mapping changed at %dx" % zoom)
	selectionSignals = 0
	primarySignals = 0


func _checkSelectionGestures(picker: PickerScript) -> void:
	picker._selectPlain("tB")
	_require(picker.selectedTileIDs() == ["tB"] and picker.primaryTileID() == "tB", "plain click did not replace selection/primary")
	picker._toggleSelection("tA")
	_require(picker.selectedTileIDs() == ["tA", "tB"] and picker.primaryTileID() == "tA", "Ctrl-click did not toggle and promote clicked frame")
	picker._toggleSelection("tA")
	_require(picker.selectedTileIDs() == ["tB"] and picker.primaryTileID() == "tB", "Ctrl-click removal did not keep a consistent primary")
	picker._selectPlain("tA")
	picker._selectRange("tC")
	_require(picker.selectedTileIDs() == ["tA", "tB", "tD", "tC"] and picker.primaryTileID() == "tC", "Shift rectangle did not skip sparse slots or preserve clicked primary")
	_require(selectionSignals == 4 and primarySignals == 4, "gestures emitted duplicate or missing change signals")


func _checkDefensiveCopiesAndReconfigure(picker: PickerScript, texture: Texture2D, tiles: Array[Dictionary]) -> void:
	var selection: Array[String] = picker.selectedTileIDs()
	selection.clear()
	_require(not picker.selectedTileIDs().is_empty(), "selectedTileIDs returned internal array")
	picker.selectTileIDs(["tD", "missing", "tA", "tD"])
	_require(picker.selectedTileIDs() == ["tA", "tD"] and picker.primaryTileID() == "tA", "silent controller selection was not normalized")
	var signalsBefore := Vector2i(selectionSignals, primarySignals)
	picker.configure("synthetic", texture, 32, tiles)
	_require(picker.selectedTileIDs() == ["tA", "tD"] and picker.primaryTileID() == "tA", "same-tileset configure discarded valid selection")
	_require(Vector2i(selectionSignals, primarySignals) == signalsBefore, "configure emitted user-change signals")
	picker.configure("replacement", texture, 32, [{"ID": "new", "CELL": Vector2i(1, 0)}])
	_require(picker.selectedTileIDs().is_empty() and picker.primaryTileID().is_empty(), "different tileset retained stale selection")
	var preview := picker.get_node("PickerColumn/PrimaryTilePreview/PrimaryTileImage") as Control
	_require(preview != null and not preview.visible, "picker showed a blank primary preview with no selection")


func _checkSpatialKeyboardAndEmptySelection(picker: PickerScript, texture: Texture2D, tiles: Array[Dictionary]) -> void:
	picker.configure("synthetic", texture, 32, tiles)
	picker._selectPlain("tA")
	picker._handleKeyboardSelection(KEY_RIGHT)
	_require(picker.primaryTileID() == "tB", "Right did not select the nearest populated cell on the row")
	picker._handleKeyboardSelection(KEY_DOWN)
	_require(picker.primaryTileID() == "tC", "Down did not select the nearest populated cell in the column")
	picker._handleKeyboardSelection(KEY_LEFT)
	_require(picker.primaryTileID() == "tD", "Left did not select the nearest populated cell on the same row")
	picker._handleKeyboardSelection(KEY_LEFT)
	_require(picker.primaryTileID() == "tD", "Left wrapped into a different row through a transparent slot")
	picker._handleKeyboardSelection(KEY_ESCAPE)
	_require(picker.selectedTileIDs().is_empty() and picker.primaryTileID().is_empty(), "Escape did not clear art selection")
	picker._selectPlain("")
	_require(picker.selectedTileIDs().is_empty(), "blank-sheet plain selection reused stale art")


func _require(condition: bool, message: String) -> void:
	if not condition:
		failures.append(message)


func _leftClick(position: Vector2) -> InputEventMouseButton:
	var event := InputEventMouseButton.new()
	event.position = position
	event.button_index = MOUSE_BUTTON_LEFT
	event.pressed = true
	return event
