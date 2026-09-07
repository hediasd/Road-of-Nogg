## Placed objects: buildings, towers and whatever else stands ON the map rather than being part
## of it. A `list`-kind layer, which `WorldMapTileData` already supported -- adding objects is a
## data change, not a format migration, which is what that layer-agnostic design was for.
##
## AN OBJECT'S ID IS ALLOCATED, NOT DERIVED, and that is the whole reason this file owns
## placement rather than callers appending dictionaries themselves. Quests, save data and
## triggers will reference these ids, so an id must survive everything that is not a deletion:
## moving the object, rotating it, re-anchoring it, saving and reloading the document, and any
## number of other objects being placed or removed around it. A content hash of position and kind
## would be stable across none of those -- moving a house would rename it. So `NEXT_ID` allocates
## (`o000`, `o001`, ...), only ever rises, and an id belonging to a removed object is NEVER
## reissued: the same contract, for the same reason, as `WorldMapTilesetCatalog.NEXT_ID`.
## `get_instance_id()` is not an option at all -- `AGENTS.md` rules it out for anything gameplay
## can reference, and it would differ between two loads of the same file.
##
## WHAT A RECORD HOLDS, and why each field exists rather than being derived:
##
##   ID         allocated, never reissued -- see above
##   KIND       what it is ("house", "tower"). A catalog reference later; a plain string now.
##   CELL       [col, row] OFFSET cell it stands on, stored as an array because JSON has no
##              Vector2i -- the same convention the tileset ledger's own CELL uses
##   FACING     0-5, an index into `WorldMapHexGrid.AXIAL_NEIGHBOURS`, so 0 is east. Exact on a
##              hex lattice in a way degrees are not, and there is no seventh direction to
##              represent
##   FOOTPRINT  hex radius in cells: 0 is the anchor cell alone, 1 adds its six neighbours
##   ANCHOR     `terrain` (follow the ground under the footprint) or `fixed` (stay at HEIGHT)
##   HEIGHT     world units -- the absolute height when `fixed`, an offset above the anchored
##              surface when `terrain`
##
## ANCHORING SAMPLES THE WHOLE FOOTPRINT AND TAKES THE MAXIMUM. Raising ground under one corner
## of a building must lift the building, not push terrain through its floor, so the surface it
## rests on is the highest cell it covers. A building floating over a dip on one side reads as a
## building on uneven ground; one buried to its windows reads as a bug. Terrain heights arrive in
## WMH-8, so `anchorHeight()` takes the height SAMPLER as an argument rather than reaching for a
## layer that does not exist yet -- flat ground is the default sampler and returns zero, and
## WMH-8 passes the real one without this file changing.
##
## ONE RECORD FEEDS EVERY DERIVED THING. `WORLDMAP_DESIGN.md` section 9 records what happens when
## it does not: temp2's structures were re-anchored by moving the rendered quad instead of the
## record, which left every building standing half a tile from its own shadow and its own pool of
## light -- a defect no probe could catch, because the mask and the record still agreed with each
## other perfectly. So nothing here returns a position that anything downstream is expected to
## adjust: `worldPosition()` is the position, and a sprite, a shadow and a lamp all read it.

class_name WorldMapObjectLayer
extends RefCounted

const MapData = preload("res://src/presentation/worldmap/editor/WorldMapTileData.gd")

## The layer every document puts objects in unless told otherwise. A name rather than a hardcoded
## assumption, so a second object layer (interiors, say) needs no change here.
const DEFAULT_LAYER := "objects"

const K_ID := "ID"
const K_KIND := "KIND"
const K_CELL := "CELL"
const K_FACING := "FACING"
const K_FOOTPRINT := "FOOTPRINT"
const K_ANCHOR := "ANCHOR"
const K_HEIGHT := "HEIGHT"

## Follow the terrain under the footprint, or ignore it and sit at `HEIGHT`.
const ANCHOR_TERRAIN := "terrain"
const ANCHOR_FIXED := "fixed"

## Six facings, so 0-5 with 0 pointing east -- `AXIAL_NEIGHBOURS[0]`.
const FACINGS := 6


## Ensures `layerID` exists as a list layer and returns its block. Safe to call repeatedly; a
## document that already has the layer keeps its items and its allocator.
static func ensureLayer(data: WorldMapTileData, layerID := DEFAULT_LAYER) -> Dictionary:
	if not data.layers.has(layerID):
		data.addListLayer(layerID)
	return data.layers[layerID]


static func items(data: WorldMapTileData, layerID := DEFAULT_LAYER) -> Array:
	if not data.layers.has(layerID):
		return []
	var block: Dictionary = data.layers[layerID]
	if str(block.get("KIND", "")) != MapData.KIND_LIST:
		return []
	return block["ITEMS"]


static func count(data: WorldMapTileData, layerID := DEFAULT_LAYER) -> int:
	return items(data, layerID).size()


## Places an object and returns its record. The caller does not choose the id -- see the class
## note on why allocation lives here.
static func place(
	data: WorldMapTileData, kind: String, cell: Vector2i, layerID := DEFAULT_LAYER,
	facing := 0, footprint := 0, anchor := ANCHOR_TERRAIN, height := 0.0
) -> Dictionary:
	var block := ensureLayer(data, layerID)
	var record := {
		K_ID: allocateID(data, layerID),
		K_KIND: kind,
		K_CELL: [cell.x, cell.y],
		K_FACING: posmod(facing, FACINGS),
		K_FOOTPRINT: maxi(0, footprint),
		K_ANCHOR: anchor if anchor == ANCHOR_FIXED else ANCHOR_TERRAIN,
		K_HEIGHT: height,
	}
	(block["ITEMS"] as Array).append(record)
	return record


## Takes the next id and advances the allocator. Never reissues: `NEXT_ID` only rises, so an id
## freed by `remove()` stays retired.
static func allocateID(data: WorldMapTileData, layerID := DEFAULT_LAYER) -> String:
	var block := ensureLayer(data, layerID)
	var next := int(block.get("NEXT_ID", 0))
	block["NEXT_ID"] = next + 1
	return "o%03d" % next


static func find(data: WorldMapTileData, id: String, layerID := DEFAULT_LAYER) -> Dictionary:
	for entry in items(data, layerID):
		if str((entry as Dictionary).get(K_ID, "")) == id:
			return entry
	return {}


## Removes an object. The id is NOT returned to the allocator -- see the class note.
static func remove(data: WorldMapTileData, id: String, layerID := DEFAULT_LAYER) -> bool:
	var list := items(data, layerID)
	for index in list.size():
		if str((list[index] as Dictionary).get(K_ID, "")) == id:
			list.remove_at(index)
			return true
	return false


## Moves an object to a different cell, KEEPING ITS ID. That is the whole point of allocating
## ids rather than deriving them: a quest that references `o003` still means this building after
## somebody drags it two hexes north.
static func move(data: WorldMapTileData, id: String, cell: Vector2i, layerID := DEFAULT_LAYER) -> bool:
	var record := find(data, id, layerID)
	if record.is_empty():
		return false
	record[K_CELL] = [cell.x, cell.y]
	return true


static func setFacing(data: WorldMapTileData, id: String, facing: int, layerID := DEFAULT_LAYER) -> bool:
	var record := find(data, id, layerID)
	if record.is_empty():
		return false
	record[K_FACING] = posmod(facing, FACINGS)
	return true


## Restores a record's field types after a round trip through JSON, which has one number type:
## `CELL`, `FACING` and `FOOTPRINT` all come back as floats, so a document reopened and re-saved
## with no edit writes `[6.0, 4.0]` where the authored file wrote `[6, 4]`. That breaks
## `WorldMapTileData.saveTo`'s own documented invariant -- "a re-save with nothing changed
## produces a byte-identical file" -- for exactly one layer kind: the list, alone among the four,
## stores dictionaries the format has no schema for and therefore cannot restore on its own.
##
## The schema lives HERE, in the file that defines what an item means, and `WorldMapTileData`
## asks for it by name rather than hardcoding these field types into the format. Unknown fields
## are carried through untouched -- normalising is not the same as validating, and a record
## written by a later version must not lose what this one does not recognise.
static func normaliseItem(raw: Dictionary) -> Dictionary:
	var record := raw.duplicate(true)
	var cell := cellOf(record)
	record[K_ID] = str(record.get(K_ID, ""))
	record[K_KIND] = str(record.get(K_KIND, ""))
	record[K_CELL] = [cell.x, cell.y]
	record[K_FACING] = posmod(int(record.get(K_FACING, 0)), FACINGS)
	record[K_FOOTPRINT] = maxi(0, int(record.get(K_FOOTPRINT, 0)))
	record[K_HEIGHT] = float(record.get(K_HEIGHT, 0.0))
	var anchor := str(record.get(K_ANCHOR, ANCHOR_TERRAIN))
	record[K_ANCHOR] = anchor if anchor == ANCHOR_FIXED else ANCHOR_TERRAIN
	return record


static func cellOf(record: Dictionary) -> Vector2i:
	var raw = record.get(K_CELL, [0, 0])
	if raw is Array and (raw as Array).size() == 2:
		return Vector2i(int(raw[0]), int(raw[1]))
	return Vector2i.ZERO


## Every cell the object covers: the anchor cell, plus every cell within `FOOTPRINT` hex steps of
## it. Goes through `WorldMapBrushes.discCells` rather than walking neighbours here, because
## `WorldMapHexGrid`'s own header is explicit that no caller may perform the parity step itself --
## a second hex-disc implementation in this file is exactly the drift that warns against.
static func footprintCells(record: Dictionary) -> Array[Vector2i]:
	return WorldMapBrushes.discCells(cellOf(record), int(record.get(K_FOOTPRINT, 0)))


## The height the object rests at. `sampler` maps a cell to a terrain height; pass one that
## returns 0 (the default) for flat ground. See the class note on why this takes a sampler rather
## than reading a height layer, and on why the footprint's MAXIMUM is the surface it rests on.
static func anchorHeight(record: Dictionary, sampler := Callable()) -> float:
	var offset := float(record.get(K_HEIGHT, 0.0))
	if str(record.get(K_ANCHOR, ANCHOR_TERRAIN)) == ANCHOR_FIXED:
		return offset
	if not sampler.is_valid():
		return offset
	var highest := -INF
	for cell in footprintCells(record):
		highest = maxf(highest, float(sampler.call(cell)))
	return offset if highest == -INF else highest + offset


## Where the object stands, in region-local world units, with `y` the anchored height. THE
## position -- a sprite, a cast shadow and a lamp all read this one function rather than each
## deriving their own, which is section 9's lesson stated as code.
static func worldPosition(
	data: WorldMapTileData, record: Dictionary, sampler := Callable()
) -> Vector3:
	var cell := cellOf(record)
	var flat := (
		WorldMapHexGrid.cellCentre(cell) if data.layout == MapData.LAYOUT_HEX_FLAT
		else Vector2(float(cell.x) + 0.5, float(cell.y) + 0.5)
	)
	return Vector3(flat.x, anchorHeight(record, sampler), flat.y)


## Facing as a world-space yaw in radians, measured so facing 0 points along +X (east), matching
## `WorldMapHexGrid.AXIAL_NEIGHBOURS[0]`. Six exact facings rather than free rotation, because a
## flat-top hex has exactly six edges to face.
static func facingRadians(record: Dictionary) -> float:
	return TAU * float(int(record.get(K_FACING, 0))) / float(FACINGS)
