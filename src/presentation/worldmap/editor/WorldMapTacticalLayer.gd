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
