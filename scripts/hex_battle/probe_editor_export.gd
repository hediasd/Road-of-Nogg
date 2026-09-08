extends SceneTree

const MapDataScript = preload("res://src/presentation/worldmap/editor/WorldMapTileData.gd")
const TacticalScript = preload("res://src/presentation/worldmap/editor/WorldMapTacticalLayer.gd")
const HeightFieldScript = preload("res://src/presentation/worldmap/editor/WorldMapHeightField.gd")
const ObjectLayerScript = preload("res://src/presentation/worldmap/editor/WorldMapObjectLayer.gd")
const BattleExportScript = preload("res://src/presentation/worldmap/editor/WorldMapBattleExport.gd")
const EditHistoryScript = preload("res://src/presentation/worldmap/editor/WorldMapEditHistory.gd")
const BattleMapFactoryScript = preload("res://src/factories/BattleMapFactory.gd")
const ManifestScript = preload("res://src/presentation/battle/BattleMapAssetManifest.gd")

const FIXTURE_REGION := "hex_battle_fixture"
const FIXTURE_MAP := "editor_fixture"

var failures: Array[String] = []


func _init() -> void:
	_checkFixtureLoadsThroughRuntimeFactory()
	_checkTacticalLayerRoundTripsAndUndoes()
	_checkSourceFingerprintTracksTheDocument()
	_checkUnknownTerrainIsRefused()
	_checkSmoothTerrainIsRefused()
	_checkBridgeIsRefused()
	_checkDecorativeWaterIsAllowed()
	_checkManifestDeclaresGeneratedProducts()
	_checkNoEditorDependencyInRuntimeMap()
	_checkSquareDocumentsAreUntouched()

	if not failures.is_empty():
		for failure: String in failures:
			printerr("HXB_EXPORT_FAILURE: %s" % failure)
		quit(1)
		return
	print("HXB_EXPORT_OK")
	quit(0)


func _require(condition: bool, message: String) -> void:
	if not condition:
		failures.append(message)


func _fixture() -> WorldMapTileData:
	return MapDataScript.loadFrom(MapDataScript.pathFor(FIXTURE_REGION))


## The committed product is what the runtime actually reads, so the sharpest check available is
## that `BattleMapFactory` -- which knows nothing about the editor -- accepts it and reproduces
## the authored battlefield cell for cell.
func _checkFixtureLoadsThroughRuntimeFactory() -> void:
	var loaded := BattleMapFactoryScript.loadFromPath(
		"res://data/battle/maps/%s.json" % FIXTURE_MAP
	)
	# A FRESH CHECKOUT LEGITIMATELY CANNOT LOAD THIS MAP, and the first version of this check
	# failed for it. Generated scenes are not committed (see .gitignore and WORLDMAP_EDITOR.md
	# section 13), so the map's VISUAL_SCENE_PATH points at a file that only exists after someone
	# re-exports. That is a declared state, not a fault -- BattleMapAssetManifest exists to report
	# it -- so the missing product is asserted THROUGH the manifest, and the map's own content is
	# then checked with the visual requirement removed. Where the product IS present, the full
	# load must still succeed.
	if not loaded["success"] and str(loaded.get("error", "")) == "missing_visual_resource":
		_require(not ManifestScript.isReady(FIXTURE_MAP),
			"the fixture map will not load but the manifest calls it ready")
		_require(ManifestScript.missingProducts(FIXTURE_MAP).size() == 1,
			"the manifest does not name the missing generated scene")
		var raw := _fixtureMapDictionary()
		if raw.is_empty():
			failures.append("could not read the fixture map to check it headlessly")
			return
		var source: Dictionary = raw["SOURCE"]
		source["VISUAL_SCENE_PATH"] = ""
		source["HEADLESS_ONLY"] = true
		raw["NAME"] = "technical_%s" % FIXTURE_MAP
		loaded = BattleMapFactoryScript.fromDictionary(raw)
		_require(loaded["success"],
			"the fixture map is invalid beyond its pending re-export: %s" % str(loaded.get("error", "")))
		if not loaded["success"]:
			return
	else:
		_require(loaded["success"],
			"the exported fixture map did not load: %s %s" % [
				loaded.get("error", ""), loaded.get("detail", "")
			])
		if not loaded["success"]:
			return
	var map = loaded["definition"]
	var document := _fixture()
	_require(document != null, "the fixture document is missing")
	if document == null:
		return

	_require(map.boardSize == document.size_tiles,
		"exported board size %s does not match the document's %s" % [
			map.boardSize, document.size_tiles
		])
	var authored := TacticalScript.playableCells(document)
	_require(map.validCells().size() == authored.size(),
		"exported %d valid cells for %d authored playable cells" % [
			map.validCells().size(), authored.size()
		])
	for cell: Vector2i in authored:
		_require(map.containsCell(cell), "authored playable cell %s is not on the exported map" % cell)
		_require(map.terrainAt(cell) == TacticalScript.terrainAt(document, cell),
			"cell %s exported as '%s' but was authored '%s'" % [
				cell, map.terrainAt(cell), TacticalScript.terrainAt(document, cell)
			])
	# A cell nobody painted must not appear on the board -- the mask is authored, not inferred.
	for row in range(document.size_tiles.y):
		for col in range(document.size_tiles.x):
			var cell := Vector2i(col, row)
			if not TacticalScript.isPlayable(document, cell):
				_require(not map.containsCell(cell),
					"unpainted cell %s reached the exported board" % cell)

	# The ledger is the single definition of what an id costs; a drift here is a balance change
	# nobody authored.
	for terrainID: String in TacticalScript.usedTerrainIDs(document):
		var ledger := TacticalScript.terrainFor(terrainID)
		var sample := Vector2i(-1, -1)
		for cell: Vector2i in authored:
			if TacticalScript.terrainAt(document, cell) == terrainID:
				sample = cell
				break
		if sample == Vector2i(-1, -1):
			continue
		_require(map.movementCostAt(sample) == int(ledger["MOVE_COST"]),
			"'%s' exported cost %d, ledger says %d" % [
				terrainID, map.movementCostAt(sample), int(ledger["MOVE_COST"])
			])
		_require(map.isTraversable(sample) == bool(ledger["CAN_ENTER"]),
			"'%s' exported traversability disagrees with the ledger" % terrainID)
		_require(map.blocksLineOfSight(sample) == bool(ledger["BLOCKS_LOS"]),
			"'%s' exported line-of-sight blocking disagrees with the ledger" % terrainID)


## The tactical layer is a plain grid layer, which is the whole reason it inherits the document's
## own serialisation and the shared undo stack. This asserts it actually does both rather than
## trusting that it should.
func _checkTacticalLayerRoundTripsAndUndoes() -> void:
	var document := _fixture()
	if document == null:
		failures.append("cannot exercise the tactical layer without the fixture")
		return

	var restored := MapDataScript.fromDictionary(document.toDictionary())
	_require(restored != null, "the fixture document did not survive a dictionary round trip")
	if restored != null:
		_require(
			TacticalScript.playableCount(restored) == TacticalScript.playableCount(document),
			"the tactical layer lost cells through a round trip")
		for cell: Vector2i in TacticalScript.playableCells(document):
			_require(TacticalScript.terrainAt(restored, cell) == TacticalScript.terrainAt(document, cell),
				"cell %s changed terrain through a round trip" % cell)

	var target := TacticalScript.playableCells(document)[0]
	var before := TacticalScript.terrainAt(document, target)
	var history := EditHistoryScript.new()
	history.beginStroke(TacticalScript.DEFAULT_LAYER)
	history.paintCell(document, target, "blocked" if before != "blocked" else "clear")
	history.endStroke()
	_require(TacticalScript.terrainAt(document, target) != before,
		"painting the tactical layer changed nothing")
	_require(history.canUndo(), "a tactical stroke pushed no undo entry")
	history.undo(document)
	_require(TacticalScript.terrainAt(document, target) == before,
		"undoing a tactical stroke did not restore the cell")


## The two products are a pair only if their identity moves when the document does.
func _checkSourceFingerprintTracksTheDocument() -> void:
	var document := _fixture()
	if document == null:
		return
	var before := BattleExportScript.sourceIdentity(document)
	_require(str(before["ID"]) == FIXTURE_REGION, "source identity does not name the region")
	_require(str(before["FINGERPRINT"]).begins_with("sha256:")
			and str(before["FINGERPRINT"]).length() == 71,
		"source fingerprint is not the shape the map schema accepts")

	var stable := BattleExportScript.sourceIdentity(_fixture())
	_require(str(stable["FINGERPRINT"]) == str(before["FINGERPRINT"]),
		"the same document fingerprinted differently twice")

	var target := TacticalScript.playableCells(document)[0]
	document.setCell(
		TacticalScript.DEFAULT_LAYER, target,
		"rough" if TacticalScript.terrainAt(document, target) != "rough" else "clear"
	)
	_require(str(BattleExportScript.sourceIdentity(document)["FINGERPRINT"]) != str(before["FINGERPRINT"]),
		"editing the document left its fingerprint unchanged")


func _checkUnknownTerrainIsRefused() -> void:
	var document := _fixture()
	if document == null:
		return
	var target := TacticalScript.playableCells(document)[0]
	document.setCell(TacticalScript.DEFAULT_LAYER, target, "swamp")
	var unsupported := BattleExportScript.unsupportedFeatures(document)
	_require(_namesFeature(unsupported, "unknown tactical terrain"),
		"an id outside the ledger was accepted instead of refused")
	var built := BattleExportScript.buildDefinition(document)
	_require(not bool(built.get("ok", false)), "the export produced a map with an unknown terrain")
	_require(str(built.get("error", "")).contains("swamp"),
		"the refusal did not name the offending id: %s" % str(built.get("error", "")))


## The load-bearing refusal. Authored heights are continuous over shared vertices, so a sculpted
## cell has no honest single elevation -- and rounding it would put the unit somewhere the ground
## is not.
func _checkSmoothTerrainIsRefused() -> void:
	var document := _fixture()
	if document == null:
		return
	var target := TacticalScript.playableCells(document)[10]
	HeightFieldScript.ensureLayer(document)
	# One vertex of one cell, which is the smallest possible slope.
	var vertex: Vector3i = HeightFieldScript.cellVertices(target)[0]
	HeightFieldScript.setHeightAt(document, vertex, 1.0)
	var unsupported := BattleExportScript.unsupportedFeatures(document)
	_require(_namesFeature(unsupported, "smooth terrain"),
		"a sloped cell was not reported as unsupported")
	var built := BattleExportScript.buildDefinition(document)
	_require(not bool(built.get("ok", false)), "the export flattened a sloped cell instead of refusing it")
	_require(str(built.get("error", "")).contains("smooth terrain"),
		"the refusal did not name smooth terrain: %s" % str(built.get("error", "")))


## A fixed-anchor deck is a second surface over a cell that already has one, and the tactical
## model carries exactly one.
func _checkBridgeIsRefused() -> void:
	var document := _fixture()
	if document == null:
		return
	var target := TacticalScript.playableCells(document)[5]
	ObjectLayerScript.ensureLayer(document)
	ObjectLayerScript.placeBridge(document, "bridge", target, 2.0)
	var unsupported := BattleExportScript.unsupportedFeatures(document)
	_require(_namesFeature(unsupported, "bridge"),
		"a bridge decking a playable cell was not reported as unsupported")
	var built := BattleExportScript.buildDefinition(document)
	_require(not bool(built.get("ok", false)), "the export dropped a bridge instead of refusing it")


## Water is decoration here. Refusing a map for having a lake in it is the specific mistake the
## item text calls out, so this asserts the opposite of the two checks above.
func _checkDecorativeWaterIsAllowed() -> void:
	var document := _fixture()
	if document == null:
		return
	var target := TacticalScript.playableCells(document)[3]
	WorldMapWaterLayer.ensureLayer(document)
	WorldMapWaterLayer.setSurface(document, target, 0.25)
	_require(WorldMapWaterLayer.isWet(document, target), "the probe failed to flood a cell")
	var unsupported := BattleExportScript.unsupportedFeatures(document)
	_require(not _namesFeature(unsupported, "water"),
		"authored water was treated as an unsupported feature")
	var built := BattleExportScript.buildDefinition(document, "res://scenes/worldmap/generated/x.tscn")
	_require(bool(built.get("ok", false)),
		"a map with decorative water was refused: %s" % str(built.get("error", "")))


## The generated scene is not committed by repository policy, so the dependency has to be
## declared somewhere a packaging step can read it.
func _checkManifestDeclaresGeneratedProducts() -> void:
	var products := ManifestScript.productsFor(FIXTURE_MAP)
	_require(products.size() == 1,
		"the manifest listed %d products for the fixture, expected its generated scene" % products.size())
	if products.is_empty():
		return
	var product: Dictionary = products[0]
	_require(str(product["KIND"]) == ManifestScript.KIND_GENERATED,
		"the generated scene was not marked as generated")
	_require(str(product["PATH"]).begins_with("res://scenes/worldmap/generated/"),
		"the manifest points somewhere other than the generated scene directory")
	_require(ManifestScript.describe(FIXTURE_MAP).contains(FIXTURE_MAP),
		"the manifest's description does not name the map")

	var identity := ManifestScript.sourceIdentityFor(FIXTURE_MAP)
	_require(str(identity.get("ID", "")) == FIXTURE_REGION,
		"the manifest read a different source region than the fixture's")
	_require(ManifestScript.authoredPathFor(FIXTURE_REGION) == MapDataScript.pathFor(FIXTURE_REGION),
		"the manifest and the editor disagree about where authored documents live")

	# A map with no visual product needs nothing, which is what HEADLESS_ONLY means.
	_require(ManifestScript.productsFor("technical_hxb_contract_map").is_empty(),
		"a headless-only map was reported as needing a generated product")


## Simulation must never become an editor consumer. The runtime factory and the manifest are the
## two runtime-side readers of this item's output, and neither may reach into the editor.
func _checkNoEditorDependencyInRuntimeMap() -> void:
	for path in [
		"res://src/factories/BattleMapFactory.gd",
		"res://src/presentation/battle/BattleMapAssetManifest.gd",
	]:
		var file := FileAccess.open(path, FileAccess.READ)
		_require(file != null, "could not read %s" % path)
		if file == null:
			continue
		var text := file.get_as_text()
		file.close()
		# Matched on a real load statement, not on the substring: both files DISCUSS the editor
		# boundary in their own headers, and a check that read prose as a dependency would fail
		# on a file for documenting the very rule it keeps.
		for form in ["preload(\"res://src/presentation/worldmap/editor",
				"load(\"res://src/presentation/worldmap/editor"]:
			_require(not text.contains(form),
				"%s loads editor code; simulation must not consume the editor" % path)


## The square path is the sharpest regression surface in the project, and this item added a layer
## to the shared document format. A square document must load, keep its layers, and be refused a
## battle export for the right reason rather than crashing on one.
func _checkSquareDocumentsAreUntouched() -> void:
	var square := MapDataScript.loadFrom(MapDataScript.pathFor("temp2_authored"))
	_require(square != null, "the square authored document no longer loads")
	if square == null:
		return
	_require(square.layout == MapDataScript.LAYOUT_SQUARE, "the square document changed layout")
	_require(square.layerIDs().has("ground") and square.layerIDs().has("overlay"),
		"the square document lost a layer")
	_require(not TacticalScript.has(square),
		"a tactical layer was conjured onto a document nobody painted one onto")
	var restored := MapDataScript.fromDictionary(square.toDictionary())
	_require(restored != null and restored.layerIDs() == square.layerIDs(),
		"the square document did not survive a round trip unchanged")

	var built := BattleExportScript.buildDefinition(square)
	_require(not bool(built.get("ok", false)), "a square document was exported as a hex battle map")
	_require(str(built.get("error", "")).contains("hex_flat"),
		"refusing a square document did not explain why: %s" % str(built.get("error", "")))


func _namesFeature(unsupported: Array[Dictionary], feature: String) -> bool:
	for entry: Dictionary in unsupported:
		if str(entry.get("FEATURE", "")).contains(feature):
			return true
	return false


## The fixture map's raw record, for checks that must bypass the visual-resource requirement.
func _fixtureMapDictionary() -> Dictionary:
	var path := "res://data/battle/maps/%s.json" % FIXTURE_MAP
	if not FileAccess.file_exists(path):
		return {}
	var file := FileAccess.open(path, FileAccess.READ)
	var parsed = JSON.parse_string(file.get_as_text())
	file.close()
	if parsed is Array and parsed.size() == 1 and parsed[0] is Dictionary:
		return (parsed[0] as Dictionary).duplicate(true)
	return {}
