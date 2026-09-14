extends SceneTree

## Bounded check on the Hex Map Editor's tileset properties block: what it shows, that selecting a
## tile alone never writes anything, that the Walkable checkbox and the frame-size Apply button
## reflect real state, and the frame-size change guard against a painted document.
##
## Deliberately does not open the editor scene, mirroring `probe_workspace_contract.gd`'s own
## `_checkChromeBuilds` -- everything here is a decision the HUD and controller make before any of
## it is drawn.

const ChromeScript = preload("res://src/presentation/worldmap/editor/workspace/WorldMapWorkspaceChrome.gd")
const HudScript = preload("res://src/presentation/worldmap/editor/WorldMapEditorHud.gd")
const ControllerScript = preload("res://src/presentation/worldmap/editor/WorldMapEditorController.gd")
const Catalog = preload("res://src/presentation/worldmap/editor/WorldMapTilesetCatalog.gd")
const MapDataScript = preload("res://src/presentation/worldmap/editor/WorldMapTileData.gd")
const BakerScript = preload("res://src/presentation/worldmap/editor/WorldMapBaker.gd")

var failures: Array[String] = []
var _root: String


func _init() -> void:
	_root = "user://htd2_%d" % Time.get_ticks_usec()
	_run.call_deferred()


func _run() -> void:
	var configDir := "%s/configs" % _root
	var sheetDir := "%s/sheets" % _root
	DirAccess.make_dir_recursive_absolute(configDir)
	DirAccess.make_dir_recursive_absolute(sheetDir)
	var image := Image.create(64, 32, false, Image.FORMAT_RGBA8)
	image.fill(Color(0.6, 0.2, 0.8, 1.0))
	image.save_png("%s/alpha.png" % sheetDir)
	Catalog.reloadCatalog(configDir, sheetDir)

	var layer := CanvasLayer.new()
	root.add_child(layer)
	var walkableCalls: Array = []
	var frameSizeCalls: Array = []
	var refreshCalls: Array = []
	var chrome := ChromeScript.new()
	chrome.build(
		layer, func(_a: String) -> void: pass, func(_a: String) -> void: pass, []
	)
	var hud := HudScript.new(chrome)
	hud.build(
		ControllerScript.LAYERS,
		func(_i: int) -> void: pass,
		func(_id: String, _on: bool) -> void: pass,
		func(_id: String, _on: bool) -> void: pass,
		{},
		func(tilesetID: String, tileID: String, walkable: bool) -> void:
			walkableCalls.append([tilesetID, tileID, walkable]),
		func(tilesetID: String, framePx: int) -> void:
			frameSizeCalls.append([tilesetID, framePx]),
		func(tilesetID: String) -> void:
			refreshCalls.append(tilesetID)
	)
	await process_frame
	await process_frame

	var alpha := Catalog.tilesetFor("alpha")
	var tiles: Array[Dictionary] = []
	for tile in alpha.get("TILES", []):
		tiles.append(tile as Dictionary)
	var sheetImage := Catalog.loadSheetImage(str(alpha["SHEET"]))
	var sheet: Texture2D = ImageTexture.create_from_image(sheetImage) if sheetImage != null else null
	hud.configurePalette("alpha", sheet, int(alpha["FRAME_PX"]), tiles)

	var properties := hud.chrome.paletteColumn.find_child("TilesetProperties", true, false) as Control
	_require(properties != null, "the tileset properties block was not built")
	if properties == null:
		_finish()
		return
	_require(properties.visible, "the properties block is not visible after configurePalette")

	var heading := properties.find_child("TilesetPropertiesHeading", true, false) as Label
	_require(
		heading != null and heading.text.contains("shared"),
		"the properties block does not say it is shared across maps"
	)

	var refreshButton := properties.find_child("TilesetRefresh", true, false) as Button
	_require(refreshButton != null, "the Refresh from art button was not built")
	refreshButton.emit_signal("pressed")
	_require(refreshCalls == ["alpha"], "pressing Refresh from art recorded %s" % [refreshCalls])

	var sheetSize := properties.find_child("TilesetSheetSize", true, false) as Label
	_require(sheetSize.text == "Sheet: 64 × 32 px", "sheet size label reads '%s'" % sheetSize.text)

	var frameSpin := properties.find_child("TilesetFrameSize", true, false) as SpinBox
	_require(int(frameSpin.value) == 32, "frame size spin did not read 32")

	var frameWarning := properties.find_child("TilesetFrameWarning", true, false) as Label
	_require(not frameWarning.visible, "the 32 px warning is visible for a 32 px sheet")

	var tileCount := properties.find_child("TilesetTileCount", true, false) as Label
	_require(tileCount.text == "2 tiles", "tile count label reads '%s'" % tileCount.text)

	var walkableBox := properties.find_child("TileWalkable", true, false) as CheckBox
	_require(walkableBox != null, "the Walkable checkbox was not built")

	# Selecting a tile alone must never call the walkable callback or touch the config file.
	hud.selectTileID("t001")
	await process_frame
	_require(walkableCalls.is_empty(), "selecting a tile alone invoked the walkable callback")
	_require(
		not FileAccess.file_exists("%s/alpha.json" % configDir),
		"selecting a tile alone wrote a config file"
	)
	_require(not walkableBox.disabled, "the checkbox stayed disabled with a primary tile selected")

	# Toggling the box in the UI must call back with exactly this tileset/tile/value. Setting
	# `button_pressed` on a toggle-mode button already emits `toggled` on its own -- a second,
	# explicit `emit_signal` here would double the recorded call, not simulate a second click.
	walkableBox.button_pressed = false
	_require(
		walkableCalls == [["alpha", "t001", false]],
		"toggling Walkable recorded %s" % [walkableCalls]
	)

	# The HUD's own update path reflects a value without needing another user gesture.
	hud.setTileWalkable("t001", false)
	_require(not walkableBox.button_pressed, "setTileWalkable(false) left the box checked")
	hud.setTileWalkable("t001", true)
	_require(walkableBox.button_pressed, "setTileWalkable(true) left the box unchecked")

	# Frame size: Apply is disabled at the current value and enabled once it differs.
	var applyButton := properties.find_child("TilesetFrameApply", true, false) as Button
	_require(applyButton.disabled, "Apply is enabled although the spin still reads the current size")
	frameSpin.value = 16
	_require(not applyButton.disabled, "Apply stayed disabled after the spin value changed")
	frameSpin.value = 32
	_require(applyButton.disabled, "Apply did not re-disable once the spin matched the current size")

	# Re-showing with a non-32 frame size shows the warning.
	hud.configurePalette("alpha", sheet, 16, tiles)
	_require(frameWarning.visible, "the frame-size warning did not show for a 16 px sheet")
	hud.configurePalette("alpha", sheet, 32, tiles)

	hud.showValueOnlyPalette("terrain height")
	_require(not properties.visible, "showValueOnlyPalette left the properties block visible")

	_checkDocumentUsesTileset()
	_checkRefreshedTileBakes("%s/alpha.png" % sheetDir)

	layer.queue_free()
	Catalog.reloadCatalog()
	_removeRecursive(_root)
	_finish()


## A tile added by Refresh from art must actually draw once painted. The baker keeps each sheet's
## image and id-to-cell map from its first bake, so this repaints the sheet with a third frame,
## re-imports it, paints the new id and checks it lands in the baked image after `forgetSheets()`
## -- the step the controller now takes after every refresh.
func _checkRefreshedTileBakes(sheetPath: String) -> void:
	var doc := MapDataScript.create("refresh", Vector2i(3, 1), MapDataScript.LAYOUT_HEX_FLAT)
	doc.layers["ground"]["TILESET"] = "alpha"
	doc.setCell("ground", Vector2i(1, 0), "t000")
	var baker := BakerScript.new()
	baker.bake(doc)

	var wider := Image.create(96, 32, false, Image.FORMAT_RGBA8)
	wider.fill(Color(0.6, 0.2, 0.8, 1.0))
	wider.save_png(sheetPath)
	var imported := Catalog.importSheet("alpha")
	_require(bool(imported.get("success", false)), "re-importing the widened sheet failed")
	Catalog.applyImport("alpha", imported)
	var ids: Array[String] = []
	for tile in Catalog.tilesetFor("alpha").get("TILES", []):
		ids.append(str((tile as Dictionary)["ID"]))
	_require(ids.has("t002"), "the refresh did not add t002 to the ledger (has %s)" % [ids])

	doc.setCell("ground", Vector2i(1, 0), "t002")
	baker.forgetSheets()
	baker.bake(doc)
	# The baker's own image, not `texture().get_image()`: under the headless dummy renderer a
	# texture's readback stays at its first upload and would report the old tile as drawn.
	var image := baker.image()
	var drawn := false
	for y in image.get_height():
		for x in image.get_width():
			if image.get_pixel(x, y).a > 0.5:
				drawn = true
				break
		if drawn:
			break
	_require(drawn, "a tile added by Refresh from art baked as nothing")


## `_documentUsesTileset` is exercised directly on a bare controller instance -- nothing here opens
## a scene or a real editing session, only the one fact the helper is asked about: whether any cell
## a grid or detail layer actually holds is not empty.
func _checkDocumentUsesTileset() -> void:
	var controller := ControllerScript.new()
	var doc := MapDataScript.create("probe", Vector2i(3, 2), MapDataScript.LAYOUT_HEX_FLAT)
	doc.layers["ground"]["TILESET"] = "alpha"
	controller._document = doc
	_require(
		not controller._documentUsesTileset("alpha"),
		"an unpainted document reported using its tileset"
	)
	doc.setCell("ground", Vector2i(1, 0), "t000")
	_require(
		controller._documentUsesTileset("alpha"),
		"a painted ground cell was not detected"
	)
	_require(
		not controller._documentUsesTileset("beta"),
		"a different tileset ID reported as used"
	)
	controller.free()


func _removeRecursive(path: String) -> void:
	var dir := DirAccess.open(path)
	if dir == null:
		return
	for fileName in dir.get_files_at(path):
		DirAccess.remove_absolute(path.path_join(fileName))
	for dirName in dir.get_directories_at(path):
		_removeRecursive(path.path_join(dirName))
	DirAccess.remove_absolute(path)


func _finish() -> void:
	if not failures.is_empty():
		for failure: String in failures:
			printerr("HTD2_FAILURE: %s" % failure)
		quit(1)
		return
	print("WORLD MAP TILESET PROPERTIES OK")
	quit(0)


func _require(condition: bool, message: String) -> void:
	if not condition:
		failures.append(message)
