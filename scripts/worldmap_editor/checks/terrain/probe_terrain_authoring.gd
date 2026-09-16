extends SceneTree

## FHB-8: a battlefield filled from the art, overridden per cell, and filled again after the art
## changes without losing the overrides.
##
## Two halves. The data half drives `WorldMapTacticalLayer` on in-memory documents and round-trips
## one through the real file envelope. The editor half drives the real editor scene headless --
## no pointer, no window -- through the same accessors the other editor probes use, to prove what
## the data half cannot: one Undo reverses a whole fill, a reset asks first, and an override is
## drawn differently from a derived cell. Nothing here writes a file.

const MapDataScript = preload("res://src/presentation/worldmap/editor/WorldMapTileData.gd")
const Tactical = preload("res://src/presentation/worldmap/editor/WorldMapTacticalLayer.gd")
const FileDocument = preload("res://src/presentation/worldmap/editor/document/WorldMapFileDocument.gd")
const BattleExport = preload("res://src/presentation/worldmap/editor/WorldMapBattleExport.gd")
const Actions = preload("res://src/presentation/worldmap/editor/workspace/WorldMapWorkspaceActions.gd")
const EditorScene = preload("res://scenes/debug/WorldMapEditorScene.tscn")

const STARTER := "temp2_hex32_starter"
const LAND := "t000"
const SEA := "t001"
const GRASS := "t002"
const HEXMAP := "res://data/worldmap/authored/hexmap.noggmap.json"

var failures: Array[String] = []


func _init() -> void:
	_run.call_deferred()


func _run() -> void:
	_checkFillFromArt()
	_checkOverridesSurviveRefill()
	_checkResetDiscardsOverrides()
	_checkUntrackedBattlefieldAsksFirst()
	_checkEnvelopeRoundTrip()
	_checkExportIgnoresTheBasis()
	_checkHexmapFillsWithoutChange()
	await _checkEditor()

	if not failures.is_empty():
		for failure: String in failures:
			printerr("HEX_TERRAIN_AUTHORING_FAILURE: %s" % failure)
		quit(1)
		return
	print("HEX_TERRAIN_AUTHORING_OK")
	quit(0)


# ---------------------------------------------------------------- data


## A map with no battlefield fills in one action, and every cell then reads as coming from the art.
func _checkFillFromArt() -> void:
	var data := _fixture()
	var plan := Tactical.fillPlan(data, true)
	_require(bool(plan["ok"]), "fill plan refused a hex map with ground: %s" % plan["error"])
	_require(int(plan["replacesUntracked"]) == 0, "a map with no battlefield asked to replace work")
	Tactical.applyFillPlan(data, plan)
	var derived := Tactical.derivedFrom(data)
	for cell: Vector2i in derived:
		_require(Tactical.terrainAt(data, cell) == str(derived[cell]),
			"fill left %s at %s, the art says %s" % [Tactical.terrainAt(data, cell), cell, derived[cell]])
		_require(Tactical.sourceAt(data, cell, derived) == Tactical.SOURCE_ART,
			"a freshly filled cell %s does not read as from the art" % cell)
	_require(Tactical.overrideCells(data).is_empty(), "a fresh fill produced overrides")
	var again := Tactical.fillPlan(data, true)
	_require((again["terrain"] as Dictionary).is_empty() and (again["basis"] as Dictionary).is_empty(),
		"a second fill over unchanged art still wanted to write")


## The heart of the item. Three cells set by hand, then the art repainted under two of them and
## beside them, then a second fill.
func _checkOverridesSurviveRefill() -> void:
	var data := _filledFixture()
	_override(data)
	var overrides := Tactical.overrideCells(data)
	_require(overrides.size() == 3, "expected 3 overrides, found %s" % str(overrides))
	_require(Tactical.sourceAt(data, Vector2i(0, 1), {}) == Tactical.SOURCE_HAND,
		"painting a cell off the board did not read as an override")

	# New art: the sea override's tile becomes land, and a plain land cell becomes sea.
	data.setCell("ground", Vector2i(1, 0), LAND)
	data.setCell("ground", Vector2i(1, 1), SEA)
	var derived := Tactical.derivedFrom(data)
	_require(Tactical.sourceAt(data, Vector2i(1, 1), derived) == Tactical.SOURCE_STALE,
		"a from-art cell whose art changed does not read as stale")

	var plan := Tactical.fillPlan(data, true)
	_require(int(plan["kept"]) == 2, "refill should keep 2 overrides, kept %d" % int(plan["kept"]))
	_require(int(plan["replacesUntracked"]) == 0 and int(plan["discardsOverrides"]) == 0,
		"an ordinary refill over a recorded map wanted confirmation")
	Tactical.applyFillPlan(data, plan)
	derived = Tactical.derivedFrom(data)

	_require(Tactical.terrainAt(data, Vector2i(0, 0)) == "blocked"
		and Tactical.sourceAt(data, Vector2i(0, 0), derived) == Tactical.SOURCE_HAND,
		"the blocked override on land did not survive the refill")
	_require(Tactical.terrainAt(data, Vector2i(0, 1)) == MapDataScript.EMPTY
		and Tactical.sourceAt(data, Vector2i(0, 1), derived) == Tactical.SOURCE_HAND,
		"the off-board override did not survive the refill")
	_require(Tactical.terrainAt(data, Vector2i(1, 1)) == "blocked"
		and Tactical.sourceAt(data, Vector2i(1, 1), derived) == Tactical.SOURCE_ART,
		"the repainted sea cell did not take the art's new answer")
	# The art came round to agree with the person, so the cell follows the art again.
	_require(Tactical.terrainAt(data, Vector2i(1, 0)) == "clear"
		and Tactical.sourceAt(data, Vector2i(1, 0), derived) == Tactical.SOURCE_ART,
		"an override the art now agrees with was not absorbed")
	_require(Tactical.terrainAt(data, Vector2i(2, 0)) == "clear", "an untouched grass cell moved")


func _checkResetDiscardsOverrides() -> void:
	var data := _filledFixture()
	_override(data)
	var plan := Tactical.fillPlan(data, false)
	_require(int(plan["discardsOverrides"]) == 3,
		"reset should report 3 overrides to discard, reported %d" % int(plan["discardsOverrides"]))
	Tactical.applyFillPlan(data, plan)
	_require(Tactical.overrideCells(data).is_empty(), "reset left overrides behind")
	_require(Tactical.terrainAt(data, Vector2i(0, 1)) == "clear", "reset did not put the off-board cell back")


## A battlefield painted before any fill has no basis, so its hand work is indistinguishable from
## art. That is the one case a keep-overrides fill must ask about.
func _checkUntrackedBattlefieldAsksFirst() -> void:
	var data := _fixture()
	Tactical.applyDerived(data)
	data.setCell(Tactical.DEFAULT_LAYER, Vector2i(0, 0), "rough")
	_require(Tactical.sourceAt(data, Vector2i(0, 0), {}) == Tactical.SOURCE_UNTRACKED,
		"a cell with no basis did not read as untracked")
	var plan := Tactical.fillPlan(data, true)
	_require(int(plan["replacesUntracked"]) == 1,
		"filling over one untracked hand cell reported %d" % int(plan["replacesUntracked"]))
	Tactical.applyFillPlan(data, plan)
	_require(Tactical.terrainAt(data, Vector2i(0, 0)) == "clear", "the confirmed fill did not replace it")
	_require(Tactical.fillPlan(data, true)["replacesUntracked"] == 0, "the fill did not record a basis")

	var refused := MapDataScript.create("square", Vector2i(3, 2))
	_require(not bool(Tactical.fillPlan(refused, true)["ok"]), "a square map was offered a battlefield fill")


## Provenance is only real if it survives a save. Through the actual envelope validator and codec.
func _checkEnvelopeRoundTrip() -> void:
	var data := _filledFixture()
	_override(data)
	data.setCell("ground", Vector2i(1, 1), SEA)
	var record := FileDocument.nextSaveRecord(FileDocument.createRecord(data), false)
	_require(not record.is_empty(), "the envelope refused a document carrying a basis layer")
	if record.is_empty():
		return
	_require(int(record["VERSION"]) == 1 and int((record["CONTENT"] as Dictionary)["FORMAT_VERSION"]) == 1,
		"the basis layer changed a format version")
	var parser := JSON.new()
	_require(parser.parse(FileDocument.canonicalText(record)) == OK, "canonical text did not parse")
	var decoded := FileDocument.decodeRecord(parser.data as Dictionary)
	_require(bool(decoded["ok"]), "the saved envelope did not decode: %s" % decoded.get("error", ""))
	if not bool(decoded["ok"]):
		return
	var reopened := decoded["data"] as WorldMapTileData
	_require(reopened.layerIDs() == data.layerIDs(),
		"layer order changed across the round trip: %s" % str(reopened.layerIDs()))
	var before := Tactical.derivedFrom(data)
	var after := Tactical.derivedFrom(reopened)
	for cell: Vector2i in before:
		_require(Tactical.terrainAt(reopened, cell) == Tactical.terrainAt(data, cell)
			and Tactical.basisAt(reopened, cell) == Tactical.basisAt(data, cell)
			and Tactical.sourceAt(reopened, cell, after) == Tactical.sourceAt(data, cell, before),
			"cell %s changed across the round trip" % cell)
	_require(Tactical.fillPlan(reopened, true)["kept"] == Tactical.fillPlan(data, true)["kept"],
		"a refill after reopening keeps different cells than before saving")


## The battle export reads only the battlefield layer. A basis must not change one byte of it.
func _checkExportIgnoresTheBasis() -> void:
	var data := _filledFixture()
	_override(data)
	var raw := data.toDictionary()
	var kept: Array = []
	for layer in raw["LAYERS"]:
		if str((layer as Dictionary)["ID"]) != Tactical.basisLayerFor():
			kept.append(layer)
	_require(kept.size() == (raw["LAYERS"] as Array).size() - 1, "the fixture carried no basis layer")
	raw["LAYERS"] = kept
	var stripped := MapDataScript.fromDictionary(raw)
	var withBasis := BattleExport.buildDefinition(data, "", Tactical.DEFAULT_LAYER, "probe")
	var withoutBasis := BattleExport.buildDefinition(stripped, "", Tactical.DEFAULT_LAYER, "probe")
	_require(bool(withBasis.get("ok", false)), "the fixture did not export: %s" % withBasis.get("error", ""))
	if not bool(withBasis.get("ok", false)) or not bool(withoutBasis.get("ok", false)):
		return
	# SOURCE is the document's identity and fingerprint, which any change to the document moves,
	# a basis included. Everything a battle reads must be identical.
	var a := (withBasis["definition"] as Dictionary).duplicate(true)
	var b := (withoutBasis["definition"] as Dictionary).duplicate(true)
	a.erase("SOURCE")
	b.erase("SOURCE")
	_require(JSON.stringify(a) == JSON.stringify(b),
		"the basis layer changed what the exported battle definition says about the board")


## The committed map's battlefield was filled from its art by FHB-4, so a fill must change no
## terrain and must not ask. Read only; the file is not written.
func _checkHexmapFillsWithoutChange() -> void:
	var parser := JSON.new()
	_require(parser.parse(FileAccess.get_file_as_string(HEXMAP)) == OK, "hexmap did not parse")
	var decoded := FileDocument.decodeRecord(parser.data as Dictionary)
	_require(bool(decoded["ok"]), "hexmap did not decode")
	if not bool(decoded["ok"]):
		return
	var plan := Tactical.fillPlan(decoded["data"] as WorldMapTileData, true)
	_require(bool(plan["ok"]) and (plan["terrain"] as Dictionary).is_empty(),
		"filling hexmap from its art would change %d battle cells" % (plan["terrain"] as Dictionary).size())
	_require(int(plan["replacesUntracked"]) == 0, "filling hexmap would ask for confirmation")


# ---------------------------------------------------------------- editor


func _checkEditor() -> void:
	var editor = EditorScene.instantiate()
	root.add_child(editor)
	await process_frame

	var chrome = editor.get("_chrome")
	var fillButton: Button = chrome.buttonFor(Actions.TERRAIN_FILL)
	_require(fillButton != null and chrome.mapMenuColumn.is_ancestor_of(fillButton),
		"Fill from art is not in the left column's menu")
	_require(chrome.buttonFor(Actions.TERRAIN_RESET) != null, "Reset to art has no button")

	editor.requestNewDocument(Vector2i(16, 12), "terrain_probe", STARTER)
	var document: WorldMapTileData = editor.openDocument()
	var history: WorldMapEditHistory = editor.get("_history")
	var landCells: Array[Vector2i] = []
	for col in 8:
		landCells.append(Vector2i(col, 5))
	_paint(editor, history, document, "ground", landCells, LAND)

	editor.performAction(Actions.TERRAIN_FILL)
	_require(not editor.hasPendingTerrainFill(), "filling a map with no battlefield asked first")
	_require(editor.activeLayerID() == Tactical.DEFAULT_LAYER, "the fill did not show the battlefield")
	_require(Tactical.terrainAt(document, Vector2i(3, 5)) == "clear"
		and Tactical.terrainAt(document, Vector2i(3, 6)) == "blocked",
		"the editor's fill did not follow the art")
	var state: Dictionary = editor.terrainOverlayState()
	_require(bool(state.get("visible", false)), "the battlefield overlay is not shown on the tactical layer")
	_require(int(state.get("tinted", 0)) == 16 * 12 and int(state.get("hand", -1)) == 0,
		"the overlay after a fill drew %s" % str(state))

	# One Undo takes the whole fill back, both layers; one Redo restores it.
	editor.performAction(Actions.UNDO)
	_require(Tactical.playableCount(document) == 0
		and Tactical.basisAt(document, Vector2i(3, 5)) == MapDataScript.EMPTY,
		"one Undo did not reverse both halves of the fill")
	_require(Tactical.terrainAt(document, Vector2i(3, 5)) == MapDataScript.EMPTY
		and document.getCell("ground", Vector2i(3, 5)) == LAND,
		"the Undo reached past the fill into the ground paint")
	editor.performAction(Actions.REDO)
	_require(Tactical.terrainAt(document, Vector2i(3, 5)) == "clear"
		and Tactical.basisAt(document, Vector2i(3, 5)) == "clear",
		"one Redo did not restore both halves of the fill")

	# An override is an ordinary paint on the battlefield layer, and is drawn differently.
	var hand: Array[Vector2i] = [Vector2i(3, 5)]
	_paint(editor, history, document, Tactical.DEFAULT_LAYER, hand, "blocked")
	state = editor.terrainOverlayState()
	_require(int(state.get("hand", 0)) == 1, "a hand-painted battle cell is not drawn as an override: %s" % state)
	_require(editor.terrainReadout(Vector2i(3, 5)).contains("by hand"),
		"Inspect does not say the cell was set by hand: %s" % editor.terrainReadout(Vector2i(3, 5)))

	# Repaint the art beside it: stale until the next fill, and the override survives that fill.
	var sea: Array[Vector2i] = [Vector2i(4, 5)]
	_paint(editor, history, document, "ground", sea, SEA)
	_require(int(editor.terrainOverlayState().get("stale", 0)) == 1, "changed art is not drawn as stale")
	editor.performAction(Actions.TERRAIN_FILL)
	_require(not editor.hasPendingTerrainFill(), "an ordinary refill asked first")
	_require(Tactical.terrainAt(document, Vector2i(4, 5)) == "blocked", "the refill did not follow the new art")
	_require(Tactical.terrainAt(document, Vector2i(3, 5)) == "blocked", "the refill erased the override")
	state = editor.terrainOverlayState()
	_require(int(state.get("hand", 0)) == 1 and int(state.get("stale", -1)) == 0,
		"after the refill the overlay drew %s" % state)

	# Reset discards overrides, so it asks. Cancel changes nothing; confirming resets; Undo restores.
	editor.performAction(Actions.TERRAIN_RESET)
	_require(editor.hasPendingTerrainFill(), "Reset to art did not ask before discarding an override")
	editor.cancelPendingTerrainFill()
	_require(Tactical.terrainAt(document, Vector2i(3, 5)) == "blocked", "a cancelled reset changed the map")
	editor.performAction(Actions.TERRAIN_RESET)
	editor.confirmPendingTerrainFill()
	_require(Tactical.terrainAt(document, Vector2i(3, 5)) == "clear"
		and Tactical.overrideCells(document).is_empty(), "the confirmed reset kept the override")
	editor.performAction(Actions.UNDO)
	_require(Tactical.terrainAt(document, Vector2i(3, 5)) == "blocked"
		and Tactical.overrideCells(document).size() == 1, "one Undo did not bring the override back")

	editor.set_process(false)
	editor.queue_free()
	await process_frame


# ---------------------------------------------------------------- fixtures


## Three by two on the starter sheet: land, sea, grass / land, land, nothing painted.
func _fixture() -> WorldMapTileData:
	var data := MapDataScript.create("probe_terrain_authoring", Vector2i(3, 2), MapDataScript.LAYOUT_HEX_FLAT)
	data.layers["ground"]["TILESET"] = STARTER
	data.setCell("ground", Vector2i(0, 0), LAND)
	data.setCell("ground", Vector2i(1, 0), SEA)
	data.setCell("ground", Vector2i(2, 0), GRASS)
	data.setCell("ground", Vector2i(0, 1), LAND)
	data.setCell("ground", Vector2i(1, 1), LAND)
	return data


func _filledFixture() -> WorldMapTileData:
	var data := _fixture()
	Tactical.applyFillPlan(data, Tactical.fillPlan(data, true))
	return data


## Blocked on land, clear on sea, and off the board on land.
func _override(data: WorldMapTileData) -> void:
	data.setCell(Tactical.DEFAULT_LAYER, Vector2i(0, 0), "blocked")
	data.setCell(Tactical.DEFAULT_LAYER, Vector2i(1, 0), "clear")
	data.setCell(Tactical.DEFAULT_LAYER, Vector2i(0, 1), MapDataScript.EMPTY)


## A stroke through the editor's own history and its own after-edit hook -- what the paint tool
## does once a pointer has picked the cells.
func _paint(
	editor, history: WorldMapEditHistory, document: WorldMapTileData, layerID: String,
	cells: Array[Vector2i], value: String
) -> void:
	history.beginStroke(layerID)
	for cell in cells:
		history.paintCell(document, cell, value)
	history.endStroke()
	editor.call("_afterCellsEdited", layerID, cells)


func _require(condition: bool, message: String) -> void:
	if not condition:
		failures.append(message)
