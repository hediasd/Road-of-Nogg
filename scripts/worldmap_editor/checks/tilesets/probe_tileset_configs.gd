extends SceneTree

## Bounded check on `WorldMapTilesetCatalog`'s per-tileset config files and folder discovery:
## which sheets are offered, that a stored config's tiles are never reconciled on load, that
## cutting a discovered sheet is deferred until something asks for its tiles, that saving a
## config touches only that one file, and the walkable/frame-size mutators.
##
## Works entirely under one disposable `user://` directory with its own `configs/` and `sheets/`
## subfolders, pointed at through `reloadCatalog`'s directory arguments -- the production catalog
## is never touched until the final restore.

const Catalog = preload("res://src/presentation/worldmap/editor/WorldMapTilesetCatalog.gd")

var failures: Array[String] = []
var _root: String


func _init() -> void:
	_root = "user://htd1_%d" % Time.get_ticks_usec()
	_run()


func _run() -> void:
	var configDir := "%s/configs" % _root
	var sheetDir := "%s/sheets" % _root
	DirAccess.make_dir_recursive_absolute(configDir)
	DirAccess.make_dir_recursive_absolute(sheetDir)

	_writeOpaquePng("%s/alpha.png" % sheetDir, 64, 32)
	_writeTransparentPng("%s/blank.png" % sheetDir, 32, 32)
	_writeOpaquePng("%s/odd.png" % sheetDir, 64, 48)
	_writeOpaquePng("%s/legacy.png" % sheetDir, 32, 32)
	_writeText("%s/legacy.json" % configDir, JSON.stringify({
		"NAME": "legacy",
		"SHEET": "%s/legacy.png" % sheetDir,
		"GRID_KIND": "tile",
		"FRAME_PX": 16,
		"PALETTE_REGION": "temp2",
		"NEXT_ID": 2,
		"TILES": [
			{
				"ID": "t000", "HASH": "deadbeefdeadbeef", "CELL": [0, 0], "LABEL": "Kept",
				"TERRAIN": "", "AUTOTILE": "", "VARIANT": "", "WALKABLE": "", "LIFTABLE": false,
			},
			{
				"ID": "t001", "HASH": "feedfacefeedface", "CELL": [1, 0], "LABEL": "",
				"TERRAIN": "", "AUTOTILE": "", "VARIANT": "", "WALKABLE": "false", "LIFTABLE": false,
			},
		],
	}, "\t"))
	_writeText("%s/bad.json" % configDir, JSON.stringify({
		"NAME": "nope",
		"SHEET": "%s/bad.png" % sheetDir,
		"GRID_KIND": "tile",
		"FRAME_PX": 32,
		"NEXT_ID": 0,
		"TILES": [],
	}, "\t"))

	Catalog.reloadCatalog(configDir, sheetDir)

	_require(
		Catalog.sheetIDs() == ["alpha", "blank", "legacy", "odd"],
		"sheetIDs() was %s" % [Catalog.sheetIDs()]
	)
	_require(not Catalog.has("nope"), "bad.json's mismatched NAME was loaded anyway")
	_require(Catalog.has("alpha") and Catalog.has("blank") and Catalog.has("odd"), "a discovered sheet is missing")

	_checkUncutUntilAsked()
	_checkCuttingResults()
	_checkLegacyUntouched()
	_checkEnsureConfig(configDir)
	_checkWalkablePersistence(configDir, sheetDir)
	_checkFrameSize()

	Catalog.reloadCatalog()
	_require(
		Catalog.has("temp2_ground") and Catalog.has("temp2_hex32_ground")
		and Catalog.has("temp2_hex32_starter"),
		"the production catalog lost a migrated tileset"
	)

	_removeRecursive(_root)

	if not failures.is_empty():
		for failure: String in failures:
			printerr("HTD1_FAILURE: %s" % failure)
		quit(1)
		return
	print("WORLD MAP TILESET CONFIGS OK")
	quit(0)


## Reloading must never decode a PNG: a discovered sheet's `TILES` stays empty until `tilesetFor`
## is actually called for it.
func _checkUncutUntilAsked() -> void:
	var beforeAsk := {}
	for reference in Catalog.list:
		if str((reference as Dictionary)["NAME"]) == "alpha":
			beforeAsk = reference
	_require(
		(beforeAsk.get("TILES", []) as Array).is_empty(),
		"alpha was cut before anything asked for its tiles"
	)


func _checkCuttingResults() -> void:
	var alpha := Catalog.tilesetFor("alpha")
	_require((alpha.get("TILES", []) as Array).size() == 2, "alpha should cut to 2 tiles")
	var blank := Catalog.tilesetFor("blank")
	_require((blank.get("TILES", []) as Array).is_empty(), "blank should cut to 0 tiles")
	var odd := Catalog.tilesetFor("odd")
	_require(
		(odd.get("TILES", []) as Array).size() == 2,
		"odd should cut to 2 tiles, ignoring its 16 px remainder row"
	)


## A stored config's tiles are the authority, exactly as written -- reload must never reconcile
## them against the sheet's current pixels.
func _checkLegacyUntouched() -> void:
	var legacy := Catalog.tilesetFor("legacy")
	_require(int(legacy.get("FRAME_PX", -1)) == 16, "legacy's stored FRAME_PX was overridden")
	var tiles: Array = legacy.get("TILES", [])
	_require(tiles.size() == 2, "legacy's stored tile count changed")
	if tiles.size() == 2:
		_require(str((tiles[0] as Dictionary)["HASH"]) == "deadbeefdeadbeef", "legacy tile 0 was reconciled")
		_require(str((tiles[1] as Dictionary)["HASH"]) == "feedfacefeedface", "legacy tile 1 was reconciled")


func _checkEnsureConfig(configDir: String) -> void:
	var path := "%s/alpha.json" % configDir
	_require(not FileAccess.file_exists(path), "alpha.json existed before ensureConfig")
	_require(Catalog.ensureConfig("alpha"), "ensureConfig failed to create alpha.json")
	_require(FileAccess.file_exists(path), "ensureConfig did not write alpha.json")
	var firstBytes := FileAccess.get_file_as_bytes(path)
	_require(Catalog.ensureConfig("alpha"), "a second ensureConfig call failed")
	var secondBytes := FileAccess.get_file_as_bytes(path)
	_require(firstBytes == secondBytes, "a second ensureConfig call changed the file")

	Catalog.reloadCatalog(configDir, "%s/sheets" % _root)
	_require(Catalog.hasConfigFile("alpha"), "alpha's config was not recognised after reload")
	var reloaded := Catalog.tilesetFor("alpha")
	_require(
		(reloaded.get("TILES", []) as Array).size() == 2,
		"alpha did not load its 2 tiles straight from the config file"
	)


func _checkWalkablePersistence(configDir: String, sheetDir: String) -> void:
	_require(not Catalog.setWalkable("nope-tileset", "t000", false), "setWalkable accepted an unknown tileset")
	_require(not Catalog.setWalkable("alpha", "tXXX", false), "setWalkable accepted an unknown tile")
	_require(Catalog.isWalkable("alpha", "t000"), "an unset WALKABLE did not default to walkable")

	_require(Catalog.setWalkable("alpha", "t001", false), "setWalkable failed for a real tile")
	_require(Catalog.saveTileset("alpha"), "saveTileset failed")
	Catalog.reloadCatalog(configDir, sheetDir)
	_require(not Catalog.isWalkable("alpha", "t001"), "false walkability did not persist across reload")
	_require(Catalog.isWalkable("alpha", "t000"), "an untouched tile's default walkability changed")


func _checkFrameSize() -> void:
	var tooSmall := Catalog.setFrameSize("alpha", 7)
	_require(not bool(tooSmall["success"]), "frame size 7 should be rejected")
	var tooBig := Catalog.setFrameSize("alpha", 257)
	_require(not bool(tooBig["success"]), "frame size 257 should be rejected")

	var before := Catalog.tilesetFor("alpha")
	var retiredCount: int = (before.get("TILES", []) as Array).size()
	var result := Catalog.setFrameSize("alpha", 16)
	_require(bool(result["success"]) and bool(result["changed"]), "setFrameSize(16) should succeed and change alpha")
	_require(int(result["retired"]) == retiredCount, "setFrameSize did not report the retired count")
	_require(int(result["added"]) == 8, "a 64x32 sheet cut at 16 px should yield 8 tiles")

	var after := Catalog.tilesetFor("alpha")
	var ids: Array[String] = []
	for tile in after.get("TILES", []):
		ids.append(str((tile as Dictionary)["ID"]))
	ids.sort()
	_require(
		ids == ["t002", "t003", "t004", "t005", "t006", "t007", "t008", "t009"],
		"setFrameSize reused an old id instead of allocating fresh ones: %s" % [ids]
	)

	var noop := Catalog.setFrameSize("alpha", 16)
	_require(bool(noop["success"]) and not bool(noop["changed"]), "re-applying the same frame size should be a no-op")


func _writeOpaquePng(path: String, width: int, height: int) -> void:
	var image := Image.create(width, height, false, Image.FORMAT_RGBA8)
	image.fill(Color(0.6, 0.2, 0.8, 1.0))
	image.save_png(path)


func _writeTransparentPng(path: String, width: int, height: int) -> void:
	var image := Image.create(width, height, false, Image.FORMAT_RGBA8)
	image.fill(Color(0.0, 0.0, 0.0, 0.0))
	image.save_png(path)


func _writeText(path: String, text: String) -> void:
	var file := FileAccess.open(path, FileAccess.WRITE)
	file.store_string(text)
	file.close()


func _removeRecursive(path: String) -> void:
	var dir := DirAccess.open(path)
	if dir == null:
		return
	for fileName in dir.get_files_at(path):
		DirAccess.remove_absolute(path.path_join(fileName))
	for dirName in dir.get_directories_at(path):
		_removeRecursive(path.path_join(dirName))
	DirAccess.remove_absolute(path)


func _require(condition: bool, message: String) -> void:
	if not condition:
		failures.append(message)
