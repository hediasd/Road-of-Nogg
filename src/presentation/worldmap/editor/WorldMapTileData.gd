## An authored region: its size in walk tiles, and one block per layer of what is on it.
##
## This is the SOURCE. From WME-5 onward a region is either `painted` -- a hand-drawn PNG, which
## is what `temp` and `temp2` are and which keeps working exactly as before -- or `authored`, in
## which case this file is the truth and the region's PNG is a build artifact baked from it.
##
## A LIVE MODEL, NOT A CATALOG RECORD. Unlike `WorldMapRegionCatalog` or
## `WorldMapTilesetCatalog`, which hand back dictionaries describing authored data, this is a
## mutable object: brushes edit it, the history stack records deltas of it, and the baker reads
## it. That is why it is a `RefCounted` with real state rather than a dictionary in the house
## catalog style.
##
## THE FORMAT IS LAYER-AGNOSTIC, AND THAT IS THE LOAD-BEARING DECISION. Nothing here enumerates
## which layers exist. A layer block names itself and declares how it stores its contents --
## `grid` for a dense lattice run-length encoded, `list` for sparse placed things -- and this
## file can read any layer it has never heard of. Adding elevation, props, walkability or a
## travel graph later is therefore a DATA change with no format migration and no version bump.
##
## That reconciles two instructions that pointed different ways. The cycle file's WME-5 risk
## says to "reserve the height layer's shape now even though it stays empty"; Gate 1 trimmed the
## editor to ground and overlay only, on the user's "can we add more as we go later". Writing an
## empty height block would satisfy the letter of the first and contradict the second, and would
## be speculative structure besides. Being indifferent to the layer set satisfies what the risk
## actually wanted -- that Phase D cannot force a migration -- while adding nothing Gate 1 said
## not to build.
##
## WHY RLE, AND WHY ONE RUN PER LINE. Several agent sessions share one working tree, so a
## serialisation that reshuffles itself turns every save into a conflict that is not a real
## disagreement. Runs are emitted one per array element, which `JSON.stringify` puts on its own
## line, so a diff shows the runs that changed rather than one enormous altered string. A dense
## 15x11 ground layer of 40 distinct tiles is a few dozen lines this way and one line otherwise.

class_name WorldMapTileData
extends RefCounted

const Uniforms = preload("res://src/presentation/worldmap/WorldMapGroundUniforms.gd")

## Bumped only when a change cannot be read by the previous reader. Adding a layer does not
## qualify -- see the class note on why the format does not enumerate layers.
const FORMAT_VERSION := 1

const AUTHORED_DIR := "res://data/worldmap/authored"

## Storage kinds a layer block may declare.
const KIND_GRID := "grid"
const KIND_LIST := "list"

## An empty cell in a grid layer. A run of these is how a layer says "nothing here", and it is
## deliberately not the empty string: a run reads `12:-`, which is legible in a diff, where
## `12:` would look like a truncation.
const EMPTY := "-"

var region_name := ""
var description := ""
var size_tiles := Vector2i.ZERO
## The region whose palette this map's tilesets must stay inside, and whose fog and void colours
## it inherits. Those belong to the PLACE, per `WORLDMAP_DESIGN.md` section 4.
var palette_region := ""
var fog_color := Color("cfe9f5")
var void_color := Color.BLACK

## Layer id -> block. A grid block carries `KIND`, `GRID_KIND`, `TILESET` and `CELLS`
## (a PackedStringArray of tile ids, row-major). A list block carries `KIND` and `ITEMS`.
var layers: Dictionary = {}
## Load order, so a save writes layers back in the order the file declared them rather than in
## whatever order a Dictionary happens to iterate.
var _layerOrder: Array[String] = []


## A new authored region with the layers Gate 1 left in scope, both empty. Any other layer is
## added by `addGridLayer` / `addListLayer` without this file needing to learn what it is.
static func create(name: String, sizeTiles: Vector2i) -> WorldMapTileData:
	var data := WorldMapTileData.new()
	data.region_name = name
	data.size_tiles = sizeTiles
	data.addGridLayer("ground", WorldMapTilesetCatalog.GRID_TILE, "")
	data.addGridLayer("overlay", WorldMapTilesetCatalog.GRID_CEL, "")
	return data


func addGridLayer(layerID: String, gridKind: String, tilesetID: String) -> void:
	var count := _cellCount(gridKind)
	var cells := PackedStringArray()
	cells.resize(count)
	cells.fill(EMPTY)
	layers[layerID] = {
		"KIND": KIND_GRID,
		"GRID_KIND": gridKind,
		"TILESET": tilesetID,
		"CELLS": cells,
	}
	if not _layerOrder.has(layerID):
		_layerOrder.append(layerID)


func addListLayer(layerID: String) -> void:
	layers[layerID] = {"KIND": KIND_LIST, "ITEMS": []}
	if not _layerOrder.has(layerID):
		_layerOrder.append(layerID)


func layerIDs() -> Array[String]:
	return _layerOrder.duplicate()


## A grid layer's dimensions in ITS OWN cells. A tile-grade layer is the region's tile size; a
## cel-grade one is that times the fixed ratio -- which is the whole payoff of the tile law
## making that ratio a constant rather than a per-region property.
func layerSize(layerID: String) -> Vector2i:
	if not layers.has(layerID):
		return Vector2i.ZERO
	var block: Dictionary = layers[layerID]
	if str(block["KIND"]) != KIND_GRID:
		return Vector2i.ZERO
	return _gridSize(str(block["GRID_KIND"]))


func _gridSize(gridKind: String) -> Vector2i:
	if gridKind == WorldMapTilesetCatalog.GRID_CEL:
		return size_tiles * Uniforms.CELS_PER_TILE
	return size_tiles


func _cellCount(gridKind: String) -> int:
	var size := _gridSize(gridKind)
	return size.x * size.y


## The tile id at a cell, or `EMPTY`. Out-of-bounds reads return `EMPTY` rather than erroring:
## a brush dragged past the edge asks about cells that are not there, and that is ordinary.
func getCell(layerID: String, cell: Vector2i) -> String:
	if not layers.has(layerID):
		return EMPTY
	var block: Dictionary = layers[layerID]
	if str(block["KIND"]) != KIND_GRID:
		return EMPTY
	var size := _gridSize(str(block["GRID_KIND"]))
	if cell.x < 0 or cell.y < 0 or cell.x >= size.x or cell.y >= size.y:
		return EMPTY
	return (block["CELLS"] as PackedStringArray)[cell.y * size.x + cell.x]


## Writes a cell. Returns whether anything actually changed, which is what lets WME-7's history
## coalesce a drag into one undo entry without recording no-op strokes.
func setCell(layerID: String, cell: Vector2i, tileID: String) -> bool:
	if not layers.has(layerID):
		return false
	var block: Dictionary = layers[layerID]
	if str(block["KIND"]) != KIND_GRID:
		return false
	var size := _gridSize(str(block["GRID_KIND"]))
	if cell.x < 0 or cell.y < 0 or cell.x >= size.x or cell.y >= size.y:
		return false
	var cells: PackedStringArray = block["CELLS"]
	var index := cell.y * size.x + cell.x
	if cells[index] == tileID:
		return false
	cells[index] = tileID
	return true


## Run-length encodes a row-major cell array as `"<count>:<id>"` entries, one run per element.
## See the class note on why the runs are separate elements rather than one joined string.
static func encodeRLE(cells: PackedStringArray) -> Array:
	var runs: Array = []
	if cells.is_empty():
		return runs
	var current := cells[0]
	var length := 1
	for i in range(1, cells.size()):
		if cells[i] == current:
			length += 1
			continue
		runs.append("%d:%s" % [length, current])
		current = cells[i]
		length = 1
	runs.append("%d:%s" % [length, current])
	return runs


## Decodes runs back into exactly `expected` cells. A run list that does not add up is a
## corrupt or hand-mangled file, so it fails loudly rather than padding to fit and leaving a map
## quietly missing its last row.
static func decodeRLE(runs: Array, expected: int) -> PackedStringArray:
	var cells := PackedStringArray()
	for entry in runs:
		var text := str(entry)
		var split := text.split(":", true, 1)
		if split.size() != 2 or not split[0].is_valid_int():
			push_warning("WorldMapTileData: malformed RLE run '%s'" % text)
			return PackedStringArray()
		var length := int(split[0])
		for _i in length:
			cells.append(split[1])
	if cells.size() != expected:
		push_warning(
			"WorldMapTileData: RLE decodes to %d cells, expected %d" % [cells.size(), expected]
		)
		return PackedStringArray()
	return cells


func toDictionary() -> Dictionary:
	var blocks: Array = []
	for layerID in _layerOrder:
		var block: Dictionary = layers[layerID]
		if str(block["KIND"]) == KIND_GRID:
			blocks.append({
				"ID": layerID,
				"KIND": KIND_GRID,
				"GRID_KIND": block["GRID_KIND"],
				"TILESET": block["TILESET"],
				"RLE": encodeRLE(block["CELLS"]),
			})
		else:
			blocks.append({"ID": layerID, "KIND": KIND_LIST, "ITEMS": block["ITEMS"]})
	return {
		"FORMAT_VERSION": FORMAT_VERSION,
		"NAME": region_name,
		"DESCRIPTION": description,
		"SIZE_TILES": [size_tiles.x, size_tiles.y],
		"PALETTE_REGION": palette_region,
		"FOG_COLOR": fog_color.to_html(false),
		"VOID_COLOR": void_color.to_html(false),
		"LAYERS": blocks,
	}


## Reads a parsed dictionary, migrating it forward first. Returns null on anything it cannot
## trust -- a wrong version, a broken RLE run, a missing size -- rather than a half-built map.
static func fromDictionary(raw: Dictionary) -> WorldMapTileData:
	var migrated := migrate(raw)
	if migrated.is_empty():
		return null

	var size = migrated.get("SIZE_TILES", [])
	if not size is Array or (size as Array).size() != 2:
		push_warning("WorldMapTileData: missing or malformed SIZE_TILES")
		return null

	var data := WorldMapTileData.new()
	data.region_name = str(migrated.get("NAME", ""))
	data.description = str(migrated.get("DESCRIPTION", ""))
	data.size_tiles = Vector2i(int(size[0]), int(size[1]))
	data.palette_region = str(migrated.get("PALETTE_REGION", ""))
	data.fog_color = Color(str(migrated.get("FOG_COLOR", "cfe9f5")))
	data.void_color = Color(str(migrated.get("VOID_COLOR", "000000")))

	for entry in migrated.get("LAYERS", []):
		if not entry is Dictionary:
			continue
		var block: Dictionary = entry
		var layerID := str(block.get("ID", ""))
		if layerID.is_empty():
			continue
		var kind := str(block.get("KIND", KIND_GRID))
		if kind == KIND_LIST:
			data.addListLayer(layerID)
			data.layers[layerID]["ITEMS"] = (block.get("ITEMS", []) as Array).duplicate(true)
			continue
		var gridKind := str(block.get("GRID_KIND", WorldMapTilesetCatalog.GRID_TILE))
		data.addGridLayer(layerID, gridKind, str(block.get("TILESET", "")))
		var runs = block.get("RLE", [])
		if runs is Array and not (runs as Array).is_empty():
			var cells := decodeRLE(runs, data._cellCount(gridKind))
			if cells.is_empty():
				push_warning("WorldMapTileData: layer '%s' failed to decode" % layerID)
				return null
			data.layers[layerID]["CELLS"] = cells
	return data


## The migration hook. It does nothing at version 1 and exists anyway, because adding one after
## a format has instances in the wild means writing the migration you did not keep the
## information to write. A FUTURE version is refused outright -- reading a file written by a
## newer editor by ignoring the parts it does not recognise is how data gets silently dropped.
static func migrate(raw: Dictionary) -> Dictionary:
	var version := int(raw.get("FORMAT_VERSION", 0))
	if version == FORMAT_VERSION:
		return raw
	if version > FORMAT_VERSION:
		push_warning(
			"WorldMapTileData: file is FORMAT_VERSION %d, this build reads %d"
			% [version, FORMAT_VERSION]
		)
		return {}
	# No older version exists yet. When one does, each step goes here, smallest first, each
	# raising FORMAT_VERSION by one so the chain is readable.
	push_warning("WorldMapTileData: unreadable FORMAT_VERSION %d" % version)
	return {}


static func pathFor(regionName: String) -> String:
	return "%s/%s.json" % [AUTHORED_DIR, regionName]


static func loadFrom(path: String) -> WorldMapTileData:
	if not FileAccess.file_exists(path):
		push_warning("WorldMapTileData: no file at %s" % path)
		return null
	var parser := JSON.new()
	if parser.parse(FileAccess.get_file_as_string(path)) != OK:
		push_warning(
			"WorldMapTileData: %s parse failed at line %d: %s"
			% [path, parser.get_error_line(), parser.get_error_message()]
		)
		return null
	if not parser.data is Dictionary:
		push_warning("WorldMapTileData: %s root is not a dictionary" % path)
		return null
	return fromDictionary(parser.data)


## Writes the map. A re-save with nothing changed produces a byte-identical file: runs are
## emitted in cell order, layers in load order, and `JSON.stringify` sorts keys itself -- see
## the class note on why that property is a correctness concern here and not a preference.
func saveTo(path: String) -> bool:
	DirAccess.make_dir_recursive_absolute(path.get_base_dir())
	var file := FileAccess.open(path, FileAccess.WRITE)
	if file == null:
		push_warning("WorldMapTileData: could not write %s" % path)
		return false
	file.store_string(JSON.stringify(toDictionary(), "\t") + "\n")
	file.close()
	return true
