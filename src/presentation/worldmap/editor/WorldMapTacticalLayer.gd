## The battlefield an authored region carries: which of its cells are playable, and what each
## playable one costs to cross. Read by `WorldMapBattleExport` and by nothing at runtime.
##
## A PLAIN GRID LAYER, WHICH IS THE WHOLE POINT. `WorldMapTileData`'s format is deliberately
## layer-agnostic -- its own class note names "walkability" as a thing a later cycle could add as
## DATA with no format migration and no version bump. This is that cycle. Storing tactical terrain
## as a grid layer of string ids means run-length encoding, `WorldMapEditHistory.paintCell`'s
## undo/redo, and save/reopen all already work, because none of them ever knew which layers exist.
## Nothing in this file touches the document format, the history stack, or the baker.
##
## TACTICAL DATA IS AUTHORED, NEVER INFERRED FROM ART. An empty cell here means "not part of the
## battlefield" -- not "clear ground". The alternative, deriving the playable area from whichever
## cells happen to carry a ground tile, reads a decorative decision as a gameplay one: the
## existing hex document leaves the cells under its houses groundless precisely because those
## buildings are objects, and inferring from art would delete exactly those cells from the board.
## So the mask is what someone painted here, and only that.
##
## AN UNKNOWN ID IS AN AUTHORING ERROR. `terrainFor()` returns an empty Dictionary rather than
## falling back to clear terrain, and the export refuses the map naming the cell. A typo that
## silently became walkable ground would be a balance change nobody made and nobody could see.

class_name WorldMapTacticalLayer
extends RefCounted

const MapData = preload("res://src/presentation/worldmap/editor/WorldMapTileData.gd")
const Tilesets = preload("res://src/presentation/worldmap/editor/WorldMapTilesetCatalog.gd")

## The layer tactical terrain lives in unless told otherwise.
const DEFAULT_LAYER := "tactical"

## The authored vocabulary, and the single place a tactical id acquires meaning. Each entry is
## already shaped as one `TERRAIN_DEFINITIONS` record of the HXB-5 map schema, so the export
## copies rather than translates -- a translation step is where a ledger and a schema drift.
##
## Deliberately small. The cycle's approved rules put every traversable cell at one movement
## point and defer terrain defence, evasion and flight to later systems, so a richer table here
## would be inventing balance this migration is not allowed to invent. `rough` exists only
## because the movement contract has to carry a weighted cost at all -- HXB-7 built weighted
## traversal specifically so later terrain rules need no new pathfinding -- and one authored
## example is what keeps that path exercised by real data rather than by a synthetic fixture.
const TERRAIN_LEDGER := {
	"clear": {
		"ID": "clear",
		"CAN_ENTER": true, "CAN_PASS": true, "CAN_STOP": true,
		"MOVE_COST": 1, "ENDS_MOVEMENT": false, "BLOCKS_LOS": false, "STATE_CODE": 0,
	},
	"rough": {
		"ID": "rough",
		"CAN_ENTER": true, "CAN_PASS": true, "CAN_STOP": true,
		"MOVE_COST": 2, "ENDS_MOVEMENT": false, "BLOCKS_LOS": false, "STATE_CODE": 0,
	},
	"blocked": {
		"ID": "blocked",
		"CAN_ENTER": false, "CAN_PASS": false, "CAN_STOP": false,
		"MOVE_COST": 0, "ENDS_MOVEMENT": false, "BLOCKS_LOS": true, "STATE_CODE": 1,
	},
}


## Adds the layer if the document has none, and hands back its block. A tactical layer is created
## entirely EMPTY -- a document that gains one has no battlefield in it yet, which is the same
## "adding a layer changes nothing until something paints it" contract the height layer keeps.
static func ensureLayer(data: WorldMapTileData, layerID := DEFAULT_LAYER) -> Dictionary:
	if not data.layers.has(layerID):
		data.addGridLayer(layerID, WorldMapTilesetCatalog.GRID_TILE, "")
	return data.layers[layerID]


static func has(data: WorldMapTileData, layerID := DEFAULT_LAYER) -> bool:
	return data.layers.has(layerID)


## The authored tactical id at a cell, or `EMPTY` for a cell outside the battlefield.
static func terrainAt(data: WorldMapTileData, cell: Vector2i, layerID := DEFAULT_LAYER) -> String:
	if not data.layers.has(layerID):
		return MapData.EMPTY
	return data.getCell(layerID, cell)


## Whether a cell is part of the battlefield at all -- the `VALID_MASK` the export writes.
static func isPlayable(data: WorldMapTileData, cell: Vector2i, layerID := DEFAULT_LAYER) -> bool:
	return terrainAt(data, cell, layerID) != MapData.EMPTY


static func playableCells(data: WorldMapTileData, layerID := DEFAULT_LAYER) -> Array[Vector2i]:
	var result: Array[Vector2i] = []
	if not data.layers.has(layerID):
		return result
	for row in range(data.size_tiles.y):
		for col in range(data.size_tiles.x):
			var cell := Vector2i(col, row)
			if isPlayable(data, cell, layerID):
				result.append(cell)
	return result


static func playableCount(data: WorldMapTileData, layerID := DEFAULT_LAYER) -> int:
	return playableCells(data, layerID).size()


## The ledger record for an id, or an empty Dictionary when the id is not in the vocabulary.
## Callers treat empty as an authoring error; see the class note on why it is not a fallback.
static func terrainFor(terrainID: String) -> Dictionary:
	if not TERRAIN_LEDGER.has(terrainID):
		return {}
	return (TERRAIN_LEDGER[terrainID] as Dictionary).duplicate(true)


static func knownTerrainIDs() -> Array[String]:
	var result: Array[String] = []
	for key in TERRAIN_LEDGER:
		result.append(str(key))
	result.sort()
	return result


## Every distinct tactical id actually used by the document, sorted -- what the export emits as
## `TERRAIN_DEFINITIONS`. Only what a map uses, so a map's definitions describe that map rather
## than the whole vocabulary.
static func usedTerrainIDs(data: WorldMapTileData, layerID := DEFAULT_LAYER) -> Array[String]:
	var seen: Dictionary = {}
	for cell: Vector2i in playableCells(data, layerID):
		seen[terrainAt(data, cell, layerID)] = true
	var result: Array[String] = []
	for key in seen:
		result.append(str(key))
	result.sort()
	return result


## FHB-2: what a cell's tactical terrain should be, read from the GROUND layer's own art rather
## than decided by hand. Today's answer distinguishes only walkable from not -- a walkable tile
## derives to `clear`, everything else to `blocked` -- with no movement-point difference between
## them; `rough` is never produced here, and this cycle does not ask it to be.
##
## THIS DOES NOT CONTRADICT THE CLASS NOTE ABOVE. "Authored, never inferred from art" is a
## contract about what `isPlayable()`, `terrainAt()` and the export read: they see only what is
## actually painted into the tactical layer, never the ground layer, at read time. This function
## does not change that -- it is a WRITE-time convenience, the tactical equivalent of Fill or
## Scatter, that happens to compute its fill from another layer instead of from a single chosen
## id. Once `applyDerived()` below writes its answer, those cells are ordinary authored data,
## indistinguishable from ones a person painted by hand, and a person can repaint any of them --
## individual override is FHB-8's addition, not this function's.
##
## THE SIGNAL IS THE TILE'S OWN `WALKABLE` FIELD, NOT ITS `TERRAIN` KIND. `WorldMapTilesetCatalog.
## _normaliseTiles()` reserved `WALKABLE` on every tile from the sheet's first import specifically
## to seed this layer, and reading it now is the delayed cost that reservation was for.
## `isWalkable()` defaults an unset field to true, which is why a sheet nobody has annotated
## derives to an entirely walkable map rather than an entirely blocked one -- the safer direction
## to be wrong in.
##
## An empty ground cell -- no tile painted at all -- derives to `blocked`. It is still part of the
## battlefield (this writes a real terrain id, not `EMPTY`), just not enterable; nothing here
## removes a cell from the lattice the way inferring PLAYABILITY from ground art would. See the
## class note's own house example: a groundless cell under an object becomes an impassable cell on
## the board, not a hole in it.
static func derivedFrom(data: WorldMapTileData, groundLayerID := "ground") -> Dictionary:
	var result: Dictionary = {}
	if not data.layers.has(groundLayerID):
		return result
	for row in range(data.size_tiles.y):
		for col in range(data.size_tiles.x):
			var cell := Vector2i(col, row)
			result[cell] = derivedAt(data, cell, groundLayerID)
	return result


## `derivedFrom()`'s answer for one cell, or `EMPTY` when there is no ground layer to read. The
## editor's under-cursor readout asks this every frame, which is why it is not a dictionary lookup
## into a whole-map derivation.
static func derivedAt(data: WorldMapTileData, cell: Vector2i, groundLayerID := "ground") -> String:
	if not data.layers.has(groundLayerID):
		return MapData.EMPTY
	var tilesetID := str((data.layers[groundLayerID] as Dictionary).get("TILESET", ""))
	var tileID := data.getCell(groundLayerID, cell)
	var walkable := tileID != MapData.EMPTY and Tilesets.isWalkable(tilesetID, tileID)
	return "clear" if walkable else "blocked"


## Applies `derivedFrom()` to the document's battlefield layer, creating it first if absent.
## WHOLE-LAYER REPLACEMENT: every cell is overwritten with the derived answer, and no basis is
## recorded. The editor fills through `fillPlan()` below instead, which keeps a person's
## overrides; this stays as the plain, provenance-free fill for tooling that wants exactly that.
static func applyDerived(
	data: WorldMapTileData, groundLayerID := "ground", layerID := DEFAULT_LAYER
) -> void:
	ensureLayer(data, layerID)
	var derived := derivedFrom(data, groundLayerID)
	for cell in derived:
		data.setCell(layerID, cell, str(derived[cell]))


## FHB-8: WHERE DERIVATION ENDS AND OVERRIDE BEGINS.
##
## The battlefield layer above stays the one answer the export reads. Beside it sits a BASIS layer:
## a plain grid layer holding, per cell, what the art said the last time a fill wrote that cell.
## Nothing paints the basis but a fill. That one extra fact is all the provenance needed:
##
##   - basis empty (`EMPTY`)           -> UNTRACKED. No fill has recorded this cell.
##   - terrain differs from the basis  -> SET BY HAND. A person painted something the art did not say.
##   - terrain equals the basis        -> FROM ART. If the art has changed since, it is STALE.
##
## WHY A RECORD OF THE ART, NOT A RECORD OF THE OVERRIDES. Every existing tool -- paint, fill,
## line, rectangle, replace, undo -- already writes the battlefield layer and only that layer. If
## overrides were their own layer, every one of those paths would have to write two layers in one
## undo entry, which the history cannot do. Recording the art instead means a hand edit needs no
## bookkeeping at all: painting a cell makes it differ from its basis, and painting it back makes it
## agree again. Only a fill writes two layers, and the controller links those two entries.
##
## Derivation never produces `EMPTY`, so an empty basis cell cannot be mistaken for a value, and a
## cell painted "off board" over a tracked cell is always an override.
const BASIS_SUFFIX := "_basis"

const SOURCE_UNTRACKED := "untracked"
const SOURCE_ART := "art"
const SOURCE_STALE := "stale"
const SOURCE_HAND := "hand"


## The basis layer that records the art for a battlefield layer. `tactical` -> `tactical_basis`.
static func basisLayerFor(layerID := DEFAULT_LAYER) -> String:
	return layerID + BASIS_SUFFIX


static func basisAt(data: WorldMapTileData, cell: Vector2i, layerID := DEFAULT_LAYER) -> String:
	var basisID := basisLayerFor(layerID)
	if not data.layers.has(basisID):
		return MapData.EMPTY
	return data.getCell(basisID, cell)


## Where a cell's battle terrain came from. `derived` is `derivedFrom()`'s answer for the whole map,
## passed in so a caller asking about many cells derives once; an empty dictionary skips the
## stale check and reports FROM ART for every cell that agrees with its basis.
static func sourceAt(
	data: WorldMapTileData, cell: Vector2i, derived: Dictionary, layerID := DEFAULT_LAYER
) -> String:
	var basis := basisAt(data, cell, layerID)
	if basis == MapData.EMPTY:
		return SOURCE_UNTRACKED
	if terrainAt(data, cell, layerID) != basis:
		return SOURCE_HAND
	if derived.has(cell) and str(derived[cell]) != basis:
		return SOURCE_STALE
	return SOURCE_ART


## Every cell a person has set by hand, row-major.
static func overrideCells(data: WorldMapTileData, layerID := DEFAULT_LAYER) -> Array[Vector2i]:
	var result: Array[Vector2i] = []
	if not data.layers.has(basisLayerFor(layerID)):
		return result
	for row in range(data.size_tiles.y):
		for col in range(data.size_tiles.x):
			var cell := Vector2i(col, row)
			if sourceAt(data, cell, {}, layerID) == SOURCE_HAND:
				result.append(cell)
	return result


## What a fill from the art would write, without writing it. Pure, so the editor can decide whether
## to ask first and the probe can read the answer.
##
## THE RULE, in one sentence: a fill keeps a cell a person set to something the art does not say,
## and gives every other cell the art's answer. Concretely, per cell with art answer `d`:
##
##   - `keepOverrides` and the cell is SET BY HAND and its terrain is not `d`: left alone, both
##     layers. Its basis still names the art it departed from.
##   - otherwise: terrain := `d` and basis := `d`.
##
## A hand-set cell the art has since come to agree with therefore stops being an override. The
## battlefield is identical either way; what changes is that a later repaint of the art moves it.
## That is the price of recording the art rather than the intent, and it only arises when the art
## and the person already agree.
##
## Returns `{ok, error, terrain, basis, kept, replacesUntracked, discardsOverrides}`. `terrain` and
## `basis` map each cell whose value would CHANGE to its new id. `replacesUntracked` counts cells
## with no basis whose current terrain the fill would change on a layer that already holds a
## battlefield -- work nobody can tell apart from the art, which is why the editor asks before
## replacing it. `discardsOverrides` counts hand-set cells a reset would overwrite.
static func fillPlan(
	data: WorldMapTileData, keepOverrides: bool, groundLayerID := "ground", layerID := DEFAULT_LAYER
) -> Dictionary:
	var plan := {
		"ok": false, "error": "", "terrain": {}, "basis": {}, "kept": 0,
		"replacesUntracked": 0, "discardsOverrides": 0,
	}
	if data.layout != MapData.LAYOUT_HEX_FLAT:
		plan["error"] = "battle terrain needs a hex map"
		return plan
	if not data.layers.has(groundLayerID):
		plan["error"] = "the map has no '%s' layer to read the art from" % groundLayerID
		return plan
	var derived := derivedFrom(data, groundLayerID)
	var populated := playableCount(data, layerID) > 0
	var terrain: Dictionary = plan["terrain"]
	var basis: Dictionary = plan["basis"]
	for cell: Vector2i in derived:
		var art := str(derived[cell])
		var current := terrainAt(data, cell, layerID)
		var source := sourceAt(data, cell, derived, layerID)
		if source == SOURCE_HAND and current != art:
			if keepOverrides:
				plan["kept"] = int(plan["kept"]) + 1
				continue
			plan["discardsOverrides"] = int(plan["discardsOverrides"]) + 1
		if source == SOURCE_UNTRACKED and populated and current != art:
			plan["replacesUntracked"] = int(plan["replacesUntracked"]) + 1
		if current != art:
			terrain[cell] = art
		if basisAt(data, cell, layerID) != art:
			basis[cell] = art
	plan["ok"] = true
	return plan


## Writes a plan straight into the document, with no history. For tooling and probes; the editor
## writes the same two dictionaries through its undo history instead.
static func applyFillPlan(data: WorldMapTileData, plan: Dictionary, layerID := DEFAULT_LAYER) -> void:
	if not bool(plan.get("ok", false)):
		return
	ensureBasisLayers(data, layerID)
	var terrain: Dictionary = plan["terrain"]
	for cell in terrain:
		data.setCell(layerID, cell, str(terrain[cell]))
	var basis: Dictionary = plan["basis"]
	for cell in basis:
		data.setCell(basisLayerFor(layerID), cell, str(basis[cell]))


## Creates the battlefield layer and its basis if either is missing, battlefield first so the file
## lists them in that order. Both start empty, which reads as "untracked" everywhere.
static func ensureBasisLayers(data: WorldMapTileData, layerID := DEFAULT_LAYER) -> void:
	ensureLayer(data, layerID)
	var basisID := basisLayerFor(layerID)
	if not data.layers.has(basisID):
		data.addGridLayer(basisID, WorldMapTilesetCatalog.GRID_TILE, "")
