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
## Terrain heights on the hex VERTEX lattice -- two floats per cell over a block padded one cell
## in each direction, because a hex on the edge has vertices owned by cells just outside it. See
## `WorldMapHeightField` for the addressing. A third kind rather than a grid layer because the
## array is not one entry per cell and `layerSize()` would have to lie about it.
const KIND_HEIGHTS := "heights"

## How a map's cells are arranged. `square` is the original 16 px tile lattice, kept working
## unchanged -- `temp2_authored` is square and its byte-exact bake parity is the sharpest test in
## the project. `hex_flat` is the flat-top hex lattice, where `size_tiles` means COLUMNS x ROWS.
##
## Defaulted to square so every existing map file loads with no migration and no version bump,
## which is what the format being layer-agnostic was for.
const LAYOUT_SQUARE := "square"
const LAYOUT_HEX_FLAT := "hex_flat"

## An empty cell in a grid layer. A run of these is how a layer says "nothing here", and it is
## deliberately not the empty string: a run reads `12:-`, which is legible in a diff, where
## `12:` would look like a truncation.
const EMPTY := "-"

var region_name := ""
var description := ""
var size_tiles := Vector2i.ZERO
## `square` or `hex_flat`. On a hex map `size_tiles` is the lattice's columns and rows.
var layout := LAYOUT_SQUARE
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
static func create(name: String, sizeTiles: Vector2i, mapLayout := LAYOUT_SQUARE) -> WorldMapTileData:
	var data := WorldMapTileData.new()
	data.region_name = name
	data.size_tiles = sizeTiles
	data.layout = mapLayout
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


## A sparse layer of placed things. `NEXT_ID` is the id allocator for whatever the layer holds --
## see `WorldMapObjectLayer` for what it means and why it only ever rises. It lives on the BLOCK
## rather than on the document because two list layers must not share an allocator: an object and
## a future spawn point both starting at 0 is fine, and forcing them to interleave would make
## every id depend on what else happened to be placed first.
func addListLayer(layerID: String) -> void:
	layers[layerID] = {"KIND": KIND_LIST, "NEXT_ID": 0, "ITEMS": []}
	if not _layerOrder.has(layerID):
		_layerOrder.append(layerID)


## A height layer, sized for this map's lattice and created FLAT -- adding one changes nothing
## about how a map renders until something sculpts it, which is what lets a height layer be added
## to an existing document without touching how it already looks.
func addHeightLayer(layerID: String) -> void:
	var values := PackedFloat32Array()
	values.resize(heightValueCount())
	values.fill(0.0)
	layers[layerID] = {"KIND": KIND_HEIGHTS, "VALUES": values}
	if not _layerOrder.has(layerID):
		_layerOrder.append(layerID)


## How many height values this map's vertex lattice needs: two per cell over a block padded one
## cell in each direction. See `WorldMapHeightField`'s own note on the padding.
func heightValueCount() -> int:
	return (size_tiles.x + 2) * (size_tiles.y + 2) * 2


func layerIDs() -> Array[String]:
	return _layerOrder.duplicate()


## A grid layer's dimensions in ITS OWN cells.
##
## On a SQUARE map a tile-grade layer is the region's tile size and a cel-grade one is that times
## the fixed ratio -- the payoff of the tile law making that ratio a constant.
##
## On a HEX map every grid layer is the lattice, whatever its grid kind. Hexagons do not tile into
## smaller hexagons, so there is no finer hex lattice for a cel-grade layer to mean; sub-tile
## detail on hex is the six triangles a hex fans into, which is WMH-10 and is not a second grid.
func layerSize(layerID: String) -> Vector2i:
	if not layers.has(layerID):
		return Vector2i.ZERO
	var block: Dictionary = layers[layerID]
	if str(block["KIND"]) != KIND_GRID:
		return Vector2i.ZERO
	return _gridSize(str(block["GRID_KIND"]))


func _gridSize(gridKind: String) -> Vector2i:
	if layout == LAYOUT_HEX_FLAT:
		return size_tiles
	if gridKind == WorldMapTilesetCatalog.GRID_CEL:
		return size_tiles * Uniforms.CELS_PER_TILE
	return size_tiles


## The map's extent in world units. On a hex map this is the lattice's bounding box, which is what
## a square region is sized to contain; on a square map it is simply the tile count.
func worldExtent() -> Vector2:
	if layout == LAYOUT_HEX_FLAT:
		return WorldMapHexGrid.latticeExtent(size_tiles.x, size_tiles.y)
	return Vector2(size_tiles)


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


## Heights as the shortest text that round-trips them. A whole number writes as `0` rather than
## `0.0000` so a flat field's runs stay short, and anything else keeps four decimals -- well below
## what a 16 px world unit can express on screen, and stable across a save/load cycle.
static func _heightsAsStrings(values: PackedFloat32Array) -> PackedStringArray:
	var out := PackedStringArray()
	out.resize(values.size())
	for index in values.size():
		var value := values[index]
		out[index] = str(int(value)) if is_equal_approx(value, roundf(value)) else "%.4f" % value
	return out


## One past the highest numeric suffix any item's `ID` carries, or 0 for an empty layer. Parses
## the id rather than trusting a stored counter, which is what makes a missing or stale `NEXT_ID`
## self-healing instead of dangerous -- see `fromDictionary`.
static func _highestIDPlusOne(items: Array) -> int:
	var highest := -1
	for entry in items:
		if not entry is Dictionary:
			continue
		var id := str((entry as Dictionary).get("ID", ""))
		var digits := ""
		for index in range(id.length() - 1, -1, -1):
			if not id[index].is_valid_int():
				break
			digits = id[index] + digits
		if not digits.is_empty():
			highest = maxi(highest, int(digits))
	return highest + 1


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
		elif str(block["KIND"]) == KIND_HEIGHTS:
			# Run-length encoded as text, exactly like a grid layer's cells: a flat field is one
			# run, which keeps an unsculpted map's file small and a sculpted map's diff readable.
			blocks.append({
				"ID": layerID,
				"KIND": KIND_HEIGHTS,
				"RLE": encodeRLE(_heightsAsStrings(block["VALUES"])),
			})
		else:
			blocks.append({
				"ID": layerID,
				"KIND": KIND_LIST,
				"NEXT_ID": block.get("NEXT_ID", 0),
				"ITEMS": block["ITEMS"],
			})
	return {
		"FORMAT_VERSION": FORMAT_VERSION,
		"NAME": region_name,
		"DESCRIPTION": description,
		"SIZE_TILES": [size_tiles.x, size_tiles.y],
		"LAYOUT": layout,
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
	var declaredLayout := str(migrated.get("LAYOUT", LAYOUT_SQUARE))
	if declaredLayout != LAYOUT_SQUARE and declaredLayout != LAYOUT_HEX_FLAT:
		push_warning("WorldMapTileData: unknown LAYOUT '%s'" % declaredLayout)
		return null
	data.layout = declaredLayout
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
			var items := (block.get("ITEMS", []) as Array).duplicate(true)
			data.layers[layerID]["ITEMS"] = items
			# An absent `NEXT_ID` is DERIVED from the items rather than defaulted to zero, so a
			# file written before the allocator existed -- or hand-edited without it -- can never
			# reissue an id that is already in use. Only ever rises, the same contract
			# `WorldMapTilesetCatalog.NEXT_ID` carries and for the same reason.
			data.layers[layerID]["NEXT_ID"] = maxi(
				int(block.get("NEXT_ID", 0)), _highestIDPlusOne(items)
			)
			continue
		if kind == KIND_HEIGHTS:
			data.addHeightLayer(layerID)
			var runs = block.get("RLE", [])
			if runs is Array and not (runs as Array).is_empty():
				var text := decodeRLE(runs, data.heightValueCount())
				if text.is_empty():
					push_warning("WorldMapTileData: height layer '%s' failed to decode" % layerID)
					return null
				var values: PackedFloat32Array = data.layers[layerID]["VALUES"]
				for index in text.size():
					values[index] = float(text[index])
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
