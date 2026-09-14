## Named tilesets: a sheet PNG, the grid it is cut on, and a ledger of stable tile identities.
##
## Follows the same JSON-catalog shape as `WorldMapRegionCatalog`, through the shared
## `JsonCatalogLoader`. What is specific to this catalog is the IMPORTER: cutting a sheet into
## tiles is trivial, and keeping a tile's identity stable across a re-export of that sheet is
## the entire problem this file exists to solve.
##
## WHY IDENTITY IS NOT THE CELL INDEX. The obvious identity for a tile is where it sits in the
## sheet -- row 3, column 7, so id 31. Then an artist inserts one tile near the front, every
## index after it shifts by one, and every authored region silently repaints itself: the map
## that referenced 31 now names a different tile, with no error at any layer, no failed load,
## and nothing to notice until someone looks at a region they did not touch and finds it
## changed. That is the failure this item exists to make impossible, and it is why a tile id is
## allocated once and never derived from position again.
##
## WHY BOTH A HASH AND A LEDGER. Neither alone is enough, which is worth stating because either
## alone looks sufficient:
##
##  - A CONTENT HASH alone cannot tell two identical tiles apart. A sheet may legitimately hold
##    the same pixels twice meaning two different things -- the same blank green as "grass" and
##    as "unreachable filler" -- and a hash says they are one tile.
##  - A LEDGER of `id -> cell` alone cannot survive the sheet being re-cut. Move every tile one
##    column right and the ledger maps every id to the wrong pixels, confidently.
##
## So both: the ledger carries `ID`, `HASH` and `CELL` per tile, and `reconcile()` matches a
## freshly cut sheet against it in falling order of confidence -- see that function. The ledger
## is append-only in the sense that matters: `NEXT_ID` only ever rises, so an id belonging to a
## removed tile is never reissued to a different one.
##
## THE IMPORTER REPORTS; IT DOES NOT RESOLVE. Every outcome that is not an exact match is
## surfaced as `added` / `moved` / `changed` / `removed` for a human to look at. An importer
## that silently decided a `changed` tile was really the same tile would be back to renumbering
## by inference, and an artist who re-exports a sheet with a one-pixel difference and sees the
## whole sheet reported as changed needs to be told that, not have it hidden.
##
## PALETTE VALIDATION LIVES HERE AND ONLY HERE. The ground shader snaps shadows to a 16-entry
## `palette[]` uniform and the backdrop recolour was built so a sky cannot drift off the
## region's colours (`WORLDMAP_DESIGN.md` section 4). Validating a sheet against its region's
## palette once, at import, is what makes it impossible for any later brush stroke to place an
## illegal colour -- so no stroke ever pays for the check.

class_name WorldMapTilesetCatalog
extends RefCounted

## One config file per tileset, named `<ID>.json`, replaces the old single-file catalog. A sheet
## that has no config file yet is still usable -- it gets an in-memory default entry -- so an
## artist can drop a PNG in `SHEET_DIR` and immediately pick it for a new map. The config becomes
## durable only when `ensureConfig()` or `saveTileset()` actually writes it, which the editor does
## the first time that sheet is selected -- never merely by scanning the folder.
const CONFIG_DIR := "res://data/worldmap/tilesets"
const SHEET_DIR := "res://assets/worldmap/tilesets"
const DEFAULT_FRAME_PX := 32
const DEFAULT_PALETTE_REGION := "temp2"
const MIN_FRAME_PX := 8
const MAX_FRAME_PX := 256
const JsonCatalogLoaderScript = preload("res://src/factories/JsonCatalogLoader.gd")
const Uniforms = preload("res://src/presentation/worldmap/WorldMapGroundUniforms.gd")

## Which of the two grids of the tile law (`WORLDMAP_DESIGN.md` section 1) a sheet is drawn on.
## A tile-grade sheet paints things an entity can observe; a cel-grade sheet is art detail only.
##
## The JSON key is `GRID_KIND`, not `GRID`, and deliberately so: a REGION already has a `GRID`,
## and it is a different thing -- an integer pixel size for its art, the very quantity the tile
## law demoted from being a world measurement. Two fields named `GRID` meaning a string kind in
## one file and a pixel count in another is how "tile" came to mean three things before the tile
## law; `probe_tile_law.gd` enforces that only the region catalog reads a bare `GRID`, and it
## caught this exact collision.
const GRID_TILE := "tile"
const GRID_CEL := "cel"

## How frames are packed in the SHEET, which is not how they are placed on a map. `grid` is
## rectangular packing: frame (c, r) is the square at (c, r) * FRAME_PX. `honeycomb` packs
## flat-top hexes the way the map places them -- columns step 3/4 of a frame and odd columns
## drop half a frame -- so neighbours share edges and an artist can paint across a seam.
## A honeycomb sheet is unpacked into a grid atlas on load (`loadTilesetImage`), so `CELL`
## keeps meaning (column, row) and nothing downstream of the load knows the difference.
## Omitted from a config means `grid`, which keeps every existing file byte-identical.
const LAYOUT_GRID := "grid"
const LAYOUT_HONEYCOMB := "honeycomb"

## Reconciliation verdicts, in falling order of confidence. `UNCHANGED` is the silent one; the
## other four are what a re-import reports for a human to read.
const UNCHANGED := "unchanged"
const MOVED := "moved"
const CHANGED := "changed"
const REMOVED := "removed"
const ADDED := "added"

## Hex characters kept from the SHA-256 of a tile's pixels. 16 hex digits is 64 bits, which is
## far past the birthday bound for the few hundred tiles a sheet holds -- and `cutSheet` does
## not trust that anyway: it compares the actual bytes whenever two tiles hash alike, so a
## genuine collision is reported rather than assumed away.
const HASH_CHARS := 16

## Pixels this transparent are treated as absent: not palette-checked, because a fully
## transparent pixel has no colour to be off-palette.
const ALPHA_FLOOR := 0.5

static var list: Array = []
static var _index: Dictionary = {}
static var _configDir := CONFIG_DIR
static var _sheetDir := SHEET_DIR
## Tileset IDs discovered as a readable PNG in `_sheetDir` during the last reload, sorted. A
## config-only entry (its PNG missing or unreadable) is not in this set: `sheetIDs()` is "what may
## be offered for a new document", not "what the catalog remembers".
static var _sheetStems: Array[String] = []
## Tileset IDs whose entry came from folder discovery rather than a stored config, and so have
## never been cut into tiles. Cutting is deferred to the first `tilesetFor()` call that actually
## needs the tiles, so reloading the catalog never decodes a PNG -- see the class note on why
## reading pixels is expensive enough to matter.
static var _uncut: Dictionary = {}
## Tileset IDs with a config file on disk, whether loaded this session or written by
## `saveTileset()`/`ensureConfig()` since. Kept separately from `_index` because a discovered
## sheet with no config still gets an `_index` entry.
static var _hasConfig: Dictionary = {}


static func _static_init() -> void:
	reloadCatalog()


## Loads every tileset config in `configDir`, then discovers every PNG in `sheetDir` that has no
## config yet. A stored config's `SHEET`, `GRID_KIND` and `FRAME_PX` always win -- folder discovery
## never overrides an authored value, only fills the gap when there is none. Neither pass reads a
## PNG's pixels: cutting happens lazily in `tilesetFor()`, and a stored config's `TILES` are used
## exactly as written, never reconciled against the sheet's current art (see `importSheet` for the
## explicit, human-reviewed path that does that).
static func reloadCatalog(configDir: String = CONFIG_DIR, sheetDir: String = SHEET_DIR) -> bool:
	_configDir = configDir
	_sheetDir = sheetDir

	var newList: Array = []
	var newIndex: Dictionary = {}
	var newHasConfig: Dictionary = {}
	var newUncut: Dictionary = {}
	var newSheetStems: Array[String] = []

	var configDirHandle := DirAccess.open(configDir)
	if configDirHandle != null:
		var configNames := configDirHandle.get_files_at(configDir)
		var stemsToLoad: Array[String] = []
		for fileName in configNames:
			if fileName.get_extension().to_lower() == "json":
				stemsToLoad.append(fileName.get_basename())
		stemsToLoad.sort()
		for stem in stemsToLoad:
			var reference := _loadConfig(configDir.path_join(stem + ".json"), stem)
			if reference.is_empty():
				continue
			newList.append(reference)
			newIndex[stem] = reference
			newHasConfig[stem] = true

	var sheetDirHandle := DirAccess.open(sheetDir)
	if sheetDirHandle != null:
		var sheetNames := sheetDirHandle.get_files_at(sheetDir)
		var stems: Array[String] = []
		for fileName in sheetNames:
			if fileName.get_extension().to_lower() == "png":
				stems.append(fileName.get_basename())
		stems.sort()
		for stem in stems:
			newSheetStems.append(stem)
			if newIndex.has(stem):
				continue
			var reference := {
				"NAME": stem,
				"DESCRIPTION": "",
				"SHEET": sheetDir.path_join(stem + ".png"),
				"GRID_KIND": GRID_TILE,
				"FRAME_PX": DEFAULT_FRAME_PX,
				"LAYOUT": LAYOUT_GRID,
				"PALETTE_REGION": DEFAULT_PALETTE_REGION,
				"NEXT_ID": 0,
				"TILES": [],
			}
			newList.append(reference)
			newIndex[stem] = reference
			newUncut[stem] = true

	newList.sort_custom(func(a, b) -> bool: return str(a["NAME"]) < str(b["NAME"]))

	list = newList
	_index = newIndex
	_hasConfig = newHasConfig
	_uncut = newUncut
	_sheetStems = newSheetStems
	return true


## Reads and validates one config file. Returns `{}` (with a warning) for anything that does not
## belong in the catalog; a bad file is skipped, not fatal to the whole reload -- see
## `reloadCatalog`'s own note on why folder discovery must survive one hand-edited-broken file.
static func _loadConfig(path: String, expectedName: String) -> Dictionary:
	var parsed := JsonCatalogLoaderScript._loadJson(path)
	if not parsed["success"]:
		push_warning("WorldMapTilesetCatalog: %s (%s)" % [parsed["error"], path])
		return {}
	var value = parsed["value"]
	if not value is Dictionary:
		push_warning("WorldMapTilesetCatalog: %s is not a JSON object" % path)
		return {}
	var reference: Dictionary = (value as Dictionary).duplicate(true)
	var nameKey := str(reference.get("NAME", ""))
	if nameKey != expectedName:
		push_warning(
			"WorldMapTilesetCatalog: %s has NAME '%s', expected '%s'" % [path, nameKey, expectedName]
		)
		return {}
	var sheetPath := str(reference.get("SHEET", ""))
	var grid := str(reference.get("GRID_KIND", GRID_TILE))
	if sheetPath.is_empty() or not (grid == GRID_TILE or grid == GRID_CEL):
		push_warning("WorldMapTilesetCatalog: invalid entry '%s'" % nameKey)
		return {}
	reference["GRID_KIND"] = grid
	# FRAME SIZE IS NOT THE GRID KIND, and conflating them was a real bug. `GRID_KIND` says
	# which of the tile law's two grids a sheet's contents belong to; `FRAME_PX` says how big
	# each cell in the SHEET is. For square art those coincide -- a tile-grade sheet has 16 px
	# frames -- so the distinction stayed invisible until a 32 px hex sheet arrived, was cut
	# on the 16 px grid its kind implied, and imported 300 quarter-hexes instead of 75 hexes.
	# Defaulted from the grid kind, so every existing square tileset is unaffected.
	var frame := int(reference.get("FRAME_PX", gridPixels(grid)))
	if frame <= 0:
		push_warning("WorldMapTilesetCatalog: entry '%s' has FRAME_PX %d" % [nameKey, frame])
		return {}
	reference["FRAME_PX"] = frame
	var layout := str(reference.get("LAYOUT", LAYOUT_GRID))
	if not (layout == LAYOUT_GRID or layout == LAYOUT_HONEYCOMB):
		push_warning("WorldMapTilesetCatalog: entry '%s' has LAYOUT '%s'" % [nameKey, layout])
		return {}
	reference["LAYOUT"] = layout
	reference["TILES"] = _normaliseTiles(reference.get("TILES", []))
	# Held rather than recomputed so a removed tile's id can never be reissued: the counter
	# only rises, and it rises past whatever the ledger already holds even if the file was
	# hand-edited down.
	reference["NEXT_ID"] = maxi(
		int(reference.get("NEXT_ID", 0)), _highestID(reference["TILES"]) + 1
	)
	return reference


## Every tileset ID with a readable PNG directly under `sheetDir`, sorted -- what the New Map
## dialog offers. A config-only entry whose PNG is gone is not included, so a stale config never
## re-appears as a choice; it stays readable for maps that already reference it (see `has()`).
static func sheetIDs() -> Array[String]:
	return _sheetStems.duplicate()


## Whether `<ID>.json` exists under the configured `configDir`, either because it was loaded this
## session or because `saveTileset()`/`ensureConfig()` has since written it.
static func hasConfigFile(tilesetID: String) -> bool:
	return _hasConfig.get(tilesetID, false)


static func configPathFor(tilesetID: String) -> String:
	return _configDir.path_join(tilesetID + ".json")


## Cuts a discovered-but-never-saved sheet the first time something actually asks for its tiles.
## Deferred out of `reloadCatalog()` so scanning the folder never decodes a PNG -- see `_uncut`'s
## own note.
static func _cutInPlace(tilesetID: String, reference: Dictionary) -> void:
	var image := loadTilesetImage(reference)
	if image == null:
		push_warning(
			"WorldMapTilesetCatalog: could not read sheet at %s" % str(reference["SHEET"])
		)
		_uncut.erase(tilesetID)
		return
	var cut := cutSheet(image, int(reference["FRAME_PX"]))
	var reconciled := reconcile([], cut["cells"], 0)
	reference["TILES"] = reconciled["tiles"]
	reference["NEXT_ID"] = reconciled["next_id"]
	_uncut.erase(tilesetID)


## Fills in every per-tile field so callers never probe for absence. Two of these are authored
## now and read by nothing yet, which is deliberate: `LIFTABLE` gates Phase D's elevation (only
## flat top-down art may be raised -- `WORLDMAP_DESIGN.md` section 8) and `WALKABLE` seeds the
## walkability layer. Both describe the ART, so retrofitting them later means revisiting every
## sheet ever drawn; authoring them from the first import costs a default and saves that.
static func _normaliseTiles(raw: Variant) -> Array:
	var out: Array = []
	if not raw is Array:
		return out
	for entry in raw:
		if not entry is Dictionary:
			continue
		var tile: Dictionary = (entry as Dictionary).duplicate(true)
		tile["ID"] = str(tile.get("ID", ""))
		tile["HASH"] = str(tile.get("HASH", ""))
		var cell = tile.get("CELL", [0, 0])
		tile["CELL"] = Vector2i(int(cell[0]), int(cell[1])) if cell is Array else Vector2i.ZERO
		tile["LABEL"] = str(tile.get("LABEL", ""))
		# Live from WME-10 (autotiling) and WME-11 (the overlay layer) onward.
		tile["TERRAIN"] = str(tile.get("TERRAIN", ""))
		tile["AUTOTILE"] = str(tile.get("AUTOTILE", ""))
		tile["VARIANT"] = str(tile.get("VARIANT", ""))
		# Reserved; see this function's own note.
		tile["WALKABLE"] = str(tile.get("WALKABLE", ""))
		tile["LIFTABLE"] = bool(tile.get("LIFTABLE", false))
		out.append(tile)
	return out


## Ids are `t<number>`; this reads the number back so `NEXT_ID` can be held above every one that
## exists. An id that does not parse contributes nothing rather than breaking the load.
static func _highestID(tiles: Array) -> int:
	var highest := -1
	for tile in tiles:
		var id := str((tile as Dictionary)["ID"])
		if id.begins_with("t") and id.substr(1).is_valid_int():
			highest = maxi(highest, int(id.substr(1)))
	return highest


static func ids() -> Array[String]:
	var result: Array[String] = []
	for reference in list:
		result.append(str(reference["NAME"]))
	return result


static func has(tilesetID: String) -> bool:
	return _index.has(tilesetID)


static func tilesetFor(tilesetID: String) -> Dictionary:
	var reference: Dictionary = _index.get(tilesetID, {})
	if not reference.is_empty() and _uncut.get(tilesetID, false):
		_cutInPlace(tilesetID, reference)
	return reference


## The authored `WALKABLE` fact for one tile, as the tri-state string `_normaliseTiles` stores:
## `"true"`, `"false"`, or `""` for a sheet that has never had the field authored. Callers that
## want a plain yes/no want `isWalkable()` below; this exists so a caller can tell "explicitly not
## walkable" apart from "nobody has said yet" when that distinction matters.
static func walkableFor(tilesetID: String, tileID: String) -> String:
	for tile in tilesetFor(tilesetID).get("TILES", []):
		if str((tile as Dictionary).get("ID", "")) == tileID:
			return str((tile as Dictionary).get("WALKABLE", ""))
	return ""


## Whether a tile can be walked on, defaulting to true. Only an explicit `"false"` refuses; an
## unset field, an unknown tile and an unknown tileset all read as walkable, which is the safer
## direction to be wrong in -- a sheet nobody has annotated yet should not silently wall off every
## cell painted from it.
static func isWalkable(tilesetID: String, tileID: String) -> bool:
	return walkableFor(tilesetID, tileID) != "false"


## Sets one tile's `WALKABLE` fact in memory only -- nothing is written until `saveTileset()` is
## called. Returns `false` for an unknown tileset or tile, and never touches `TERRAIN`, map
## document history, or tactical cells.
static func setWalkable(tilesetID: String, tileID: String, walkable: bool) -> bool:
	var reference := tilesetFor(tilesetID)
	if reference.is_empty():
		return false
	for tile in reference.get("TILES", []):
		if str((tile as Dictionary).get("ID", "")) == tileID:
			(tile as Dictionary)["WALKABLE"] = "true" if walkable else "false"
			return true
	return false


## Re-cuts a tileset at a new frame size, in memory only. Reconciled against an EMPTY ledger --
## never the tileset's own current tiles -- because every existing `CELL` means something
## different once the sheet is sliced differently; keeping the old ledger would leave `t000`
## pinned to whatever art now happens to occupy cell (0,0). Every old id is retired and never
## reissued: `NEXT_ID` carries forward from the tileset's current value.
##
## Returns `{success, changed, retired, added, error}`. `changed` is false (with `success` true)
## when `framePx` already matches -- a no-op the caller can skip saving for.
static func setFrameSize(tilesetID: String, framePx: int) -> Dictionary:
	if not _index.has(tilesetID):
		return {
			"success": false, "changed": false, "retired": 0, "added": 0,
			"error": "unknown tileset '%s'" % tilesetID,
		}
	if framePx < MIN_FRAME_PX or framePx > MAX_FRAME_PX:
		return {
			"success": false, "changed": false, "retired": 0, "added": 0,
			"error": "frame size %d is outside %d..%d" % [framePx, MIN_FRAME_PX, MAX_FRAME_PX],
		}
	var reference := tilesetFor(tilesetID)
	if int(reference["FRAME_PX"]) == framePx:
		return {"success": true, "changed": false, "retired": 0, "added": 0, "error": ""}
	var image := loadTilesetImage(reference, framePx)
	if image == null:
		return {
			"success": false, "changed": false, "retired": 0, "added": 0,
			"error": "could not read sheet at %s" % str(reference["SHEET"]),
		}
	var cut := cutSheet(image, framePx)
	var reconciled := reconcile([], cut["cells"], int(reference["NEXT_ID"]))
	var retiredCount: int = (reference.get("TILES", []) as Array).size()
	reference["TILES"] = reconciled["tiles"]
	reference["FRAME_PX"] = framePx
	reference["NEXT_ID"] = reconciled["next_id"]
	return {
		"success": true, "changed": true, "retired": retiredCount,
		"added": (reconciled["tiles"] as Array).size(), "error": "",
	}


## Map pixels per cell for a grid kind. Both come from the tile law's constants rather than
## being declared per sheet, which is the whole point of the ratio being fixed.
static func gridPixels(gridKind: String) -> int:
	return Uniforms.CEL_PIXELS if gridKind == GRID_CEL else Uniforms.TILE_PIXELS


## SHA-256 of a tile's raw RGBA8 bytes, truncated. Alpha is included: two tiles differing only
## in transparency are genuinely different tiles.
##
## Prefer `hashCell()` over calling this with bytes gathered by hand -- see the trap it exists
## to close.
static func hashBytes(bytes: PackedByteArray) -> String:
	var context := HashingContext.new()
	context.start(HashingContext.HASH_SHA256)
	context.update(bytes)
	return context.finish().hex_encode().substr(0, HASH_CHARS)


## THE one definition of "a tile's bytes". Every hash of a cell goes through here, and that is
## not tidiness -- it closes a trap that produced identical-looking pixels hashing differently.
##
## `Image.get_region()` PRESERVES MIPMAPS. A 16x16 cell taken from an image that carries a mip
## chain returns 1364 bytes, not 1024: the region brings 256 + 64 + 16 + 4 + 1 pixels with it.
## Region art imports with `mipmaps/generate=true` (`WORLDMAP_DESIGN.md` section 4 wants them for
## the far field), while a sheet read from its PNG has none -- so cutting the same tile from a
## region and from a sheet produced two different hashes for byte-identical pixels, and the
## first authored region matched 0 of its 165 cells against a ledger built from its own art.
##
## The bytes compared differ in LENGTH, not in content, which is what made it look like an
## impossible failure: a byte-by-byte walk over the overlap reports zero differences.
## An image in the one form this file hashes and reads: RGBA8, uncompressed, no mip chain.
## Anything cutting cells for comparison against a ledger must go through here first -- see
## `hashCell` for what happens when two callers normalise differently.
static func normalise(image: Image) -> Image:
	var working := image
	if working.is_compressed():
		working = working.duplicate()
		working.decompress()
	if working.has_mipmaps():
		if working == image:
			working = working.duplicate()
		working.clear_mipmaps()
	if working.get_format() != Image.FORMAT_RGBA8:
		if working == image:
			working = working.duplicate()
		working.convert(Image.FORMAT_RGBA8)
	return working


static func hashCell(image: Image, rect: Rect2i) -> String:
	var piece := image.get_region(rect)
	if piece.has_mipmaps():
		piece.clear_mipmaps()
	if piece.get_format() != Image.FORMAT_RGBA8:
		piece.convert(Image.FORMAT_RGBA8)
	return hashBytes(piece.get_data())


## Cuts a sheet into grid cells, in a fixed row-major order so a re-import of an unchanged sheet
## produces an identical list. Returns one entry per NON-BLANK cell: `{cell, hash, bytes}`.
##
## FULLY TRANSPARENT CELLS ARE NOT TILES. A sheet holding a number of tiles that is not a
## multiple of its column count has padding in its last row, and that padding is unavoidable --
## so allocating an id per blank cell would fill the ledger with entries that carry no art and
## that churn on every re-export, as adding one tile shifts where the padding falls. Worse, a
## deleted tile leaves a hole rather than shortening the sheet, and a blank-as-tile reading
## would report that hole as `changed` (the slot was repainted to nothing) instead of `removed`,
## which is the opposite of what happened.
##
## The count is returned rather than dropped silently, so an unexpectedly blank sheet is
## visible. A sheet that wants a deliberate do-nothing tile must give it a pixel: transparency
## is how this file spells "no tile here", and it cannot mean both.
##
## Reports a true hash collision rather than trusting the truncation. Two cells that hash alike
## are compared byte for byte, and only a genuine mismatch -- different pixels, same hash -- is
## a collision worth a human's attention; identical pixels hashing alike is just a duplicate
## tile, which is ordinary and which `reconcile` handles by cell.
static func cutSheet(image: Image, gridPx: int) -> Dictionary:
	var working := normalise(image)

	var cells: Array = []
	var collisions: Array = []
	var seen: Dictionary = {}
	var blank := 0
	var wide := working.get_width() / gridPx
	var tall := working.get_height() / gridPx
	for row in tall:
		for column in wide:
			var rect := Rect2i(column * gridPx, row * gridPx, gridPx, gridPx)
			var piece := working.get_region(rect)
			if _isBlank(piece):
				blank += 1
				continue
			var bytes := piece.get_data()
			var digest := hashCell(working, rect)
			if seen.has(digest) and seen[digest] != bytes:
				collisions.append(digest)
			seen[digest] = bytes
			cells.append({"cell": Vector2i(column, row), "hash": digest, "bytes": bytes})
	return {
		"cells": cells,
		"collisions": collisions,
		"blank": blank,
		# The remainder is reported rather than silently dropped: `temp2` is 248 px wide, which
		# is 15.5 tiles, so a sheet cut from art like it legitimately has a partial last column.
		"remainder": Vector2i(working.get_width() % gridPx, working.get_height() % gridPx),
	}


## Matches a freshly cut sheet against an existing ledger, in falling order of confidence. Each
## pass consumes what it matches, so a later, weaker pass can never claim a tile a stronger one
## already explained:
##
##  1. SAME HASH AND SAME CELL -- the tile did not move and did not change. `unchanged`.
##  2. SAME HASH, DIFFERENT CELL -- the artist moved it. `moved`, id preserved. This is the pass
##     that makes inserting a tile safe.
##  3. SAME CELL, DIFFERENT HASH -- the artist repainted that slot. `changed`, id preserved,
##     because the slot's meaning is what the region referenced and the pixels are what changed.
##  4. LEDGER ENTRY LEFT OVER -- the tile is gone from the sheet. `removed`. Its id is retired
##     and never reissued.
##  5. CELL LEFT OVER -- something new. `added`, and only here is a fresh id allocated.
##
## Duplicate pixels are why passes 1 and 2 are separate rather than one hash lookup: with two
## identical tiles in a sheet, pass 1 pins each to the cell it already occupied, and only what
## genuinely relocated is left for pass 2.
static func reconcile(ledger: Array, cut: Array, nextID: int) -> Dictionary:
	var byCell: Dictionary = {}
	for entry in cut:
		byCell[(entry as Dictionary)["cell"]] = entry

	var claimedCells: Dictionary = {}
	var resolved: Array = []
	var report: Dictionary = {UNCHANGED: [], MOVED: [], CHANGED: [], REMOVED: [], ADDED: []}
	var pending: Array = ledger.duplicate(true)

	# Pass 1 -- same hash, same cell.
	var stillPending: Array = []
	for tile in pending:
		var cell: Vector2i = tile["CELL"]
		var found: Variant = byCell.get(cell)
		if found != null and str((found as Dictionary)["hash"]) == str(tile["HASH"]):
			claimedCells[cell] = true
			resolved.append(tile)
			report[UNCHANGED].append(str(tile["ID"]))
		else:
			stillPending.append(tile)
	pending = stillPending

	# Pass 2 -- same hash somewhere else. Cells are visited in the sheet's own row-major order
	# so a tile duplicated several times resolves the same way on every run.
	stillPending = []
	for tile in pending:
		var moved := false
		for entry in cut:
			var cell: Vector2i = (entry as Dictionary)["cell"]
			if claimedCells.has(cell):
				continue
			if str((entry as Dictionary)["hash"]) != str(tile["HASH"]):
				continue
			claimedCells[cell] = true
			var from: Vector2i = tile["CELL"]
			tile["CELL"] = cell
			resolved.append(tile)
			report[MOVED].append("%s %s -> %s" % [str(tile["ID"]), from, cell])
			moved = true
			break
		if not moved:
			stillPending.append(tile)
	pending = stillPending

	# Pass 3 -- same cell, repainted.
	stillPending = []
	for tile in pending:
		var cell: Vector2i = tile["CELL"]
		var found: Variant = byCell.get(cell)
		if found != null and not claimedCells.has(cell):
			claimedCells[cell] = true
			tile["HASH"] = str((found as Dictionary)["hash"])
			resolved.append(tile)
			report[CHANGED].append("%s at %s" % [str(tile["ID"]), cell])
		else:
			stillPending.append(tile)

	# Pass 4 -- whatever the sheet no longer holds.
	for tile in stillPending:
		report[REMOVED].append("%s was %s" % [str(tile["ID"]), tile["CELL"]])

	# Pass 5 -- whatever the ledger has never seen. The only pass that allocates.
	var allocated := nextID
	for entry in cut:
		var cell: Vector2i = (entry as Dictionary)["cell"]
		if claimedCells.has(cell):
			continue
		var tile: Dictionary = _normaliseTiles([{
			"ID": "t%03d" % allocated,
			"HASH": str((entry as Dictionary)["hash"]),
			"CELL": [cell.x, cell.y],
		}])[0]
		allocated += 1
		resolved.append(tile)
		report[ADDED].append("%s at %s" % [str(tile["ID"]), cell])

	# Sorted by cell so the written file reads in sheet order regardless of when an id was
	# allocated -- a diff of the ledger should show what moved, not the allocation history.
	resolved.sort_custom(func(a, b) -> bool:
		var ca: Vector2i = a["CELL"]
		var cb: Vector2i = b["CELL"]
		return (ca.y * 100000 + ca.x) < (cb.y * 100000 + cb.x)
	)
	return {"tiles": resolved, "report": report, "next_id": allocated}


## Every colour in the sheet that the region's palette does not contain. Exact RGB match, not a
## tolerance: unlike the structure extractor's colour key -- which compares against colours that
## round-tripped through PNG import and so must allow drift (`WORLDMAP_DESIGN.md` section 9) --
## both sides here are read from imported PNGs in the same way, so an exact mismatch is a real
## one. Fully transparent pixels have no colour and are skipped.
static func offPaletteColours(image: Image, palette: PackedColorArray) -> Array:
	var allowed: Dictionary = {}
	for colour in palette:
		allowed[_key(colour)] = true
	var offending: Dictionary = {}
	var working := normalise(image)
	for y in working.get_height():
		for x in working.get_width():
			var pixel := working.get_pixel(x, y)
			if pixel.a < ALPHA_FLOOR:
				continue
			var key := _key(pixel)
			if not allowed.has(key):
				offending[key] = true
	var out: Array = []
	for key in offending:
		out.append("#%06x" % key)
	out.sort()
	return out


## Whether every pixel of a cut cell is transparent enough to count as absent -- see `cutSheet`
## on why a blank cell is padding rather than a tile.
static func _isBlank(piece: Image) -> bool:
	for y in piece.get_height():
		for x in piece.get_width():
			if piece.get_pixel(x, y).a >= ALPHA_FLOOR:
				return false
	return true


static func _key(colour: Color) -> int:
	return (
		(int(round(colour.r * 255.0)) << 16)
		| (int(round(colour.g * 255.0)) << 8)
		| int(round(colour.b * 255.0))
	)


## Reads a sheet from the AUTHORED PNG rather than through Godot's import pipeline, and that is
## deliberate. A tile's identity is the hash of its pixels, so the pixels have to come from a
## source no setting can quietly change: `ResourceLoader` hands back whatever the importer
## produced, so flipping a compression preset -- or Godot's own `detect_3d` deciding a sheet is
## used in 3D and switching it to a lossy VRAM format -- would alter every hash at once and
## report an entire sheet as `changed` for a reason that has nothing to do with the art.
##
## Nothing samples a tileset in a shader, so there is no cost to this: sheets are read on the
## CPU by this importer and by the baker that will compose them into a region texture, and it is
## that region texture -- not the sheet -- which carries the import settings section 4 cares
## about. Godot's own generated `.import` for the bootstrap sheet confirms the hazard is real
## rather than theoretical: it carries `detect_3d/compress_to=1`, which would switch the sheet
## to a lossy VRAM format the moment anything used it in 3D. Reading the file makes that
## setting unable to reach us.
##
## THE CONSTRAINT THIS IMPOSES IS CHECKED, NOT ASSUMED. Reading `res://` as a file works while
## running from the source tree and NOT in an exported build, where the PNG has been replaced by
## its imported form. That is fine -- the editor is a source-tree tool and never ships -- but a
## silent `null` in an export would be a mystery, so an export refuses loudly instead. Godot
## also emits its own "this will not work on export" warning here, which is correct and is left
## in place rather than worked around.
static func loadSheetImage(sheetPath: String) -> Image:
	if OS.has_feature("template"):
		push_error(
			"WorldMapTilesetCatalog: tileset sheets are read from source PNGs and cannot be "
			+ "read in an exported build. The world map editor is a source-tree tool."
		)
		return null
	if not FileAccess.file_exists(sheetPath):
		return null
	var image := Image.new()
	if image.load(sheetPath) != OK:
		return null
	return normalise(image)


## A tileset's sheet as a grid atlas: the PNG itself for a `grid` layout, or the honeycomb
## unpacked into one square frame per hex. Every reader that turns `CELL` into pixels -- the
## cutter, the baker, the picker -- goes through here so they all see the same atlas.
## `framePx` overrides the stored frame size, for re-cutting at a size not yet applied.
static func loadTilesetImage(reference: Dictionary, framePx := 0) -> Image:
	var image := loadSheetImage(str(reference.get("SHEET", "")))
	if image == null or str(reference.get("LAYOUT", LAYOUT_GRID)) != LAYOUT_HONEYCOMB:
		return image
	return unpackHoneycomb(image, framePx if framePx > 0 else int(reference["FRAME_PX"]))


## Whether local pixel (x, y) lies inside the flat-top hex of a `framePx` frame. Its vertices are
## (F, F/2), (3F/4, F), (F/4, F), (0, F/2), (F/4, 0), (3F/4, 0); each row two pixels further from
## the middle row insets one more pixel. At 32 px this is exactly the starter sheet's mask, and
## it tiles with no gap or overlap at the honeycomb's 3F/4 column step.
static func hexContains(framePx: int, x: int, y: int) -> bool:
	var half := framePx / 2
	var inset := (half - y) / 2 if y < half else (y - half + 1) / 2
	return x >= inset and x < framePx - inset and y >= 0 and y < framePx


## Lifts every hex out of a honeycomb sheet into a grid atlas. Hex (c, r) sits at
## (c * 3F/4, r * F + (c odd ? F/2 : 0)); only pixels inside its hex mask are copied, so a
## neighbour's edge never leaks into a frame's transparent corners. A slot the sheet is too
## small to hold completely is left blank, which `cutSheet` already reads as "no tile".
static func unpackHoneycomb(image: Image, framePx: int) -> Image:
	var step := framePx * 3 / 4
	var drop := framePx / 2
	var columns := 0 if image.get_width() < framePx else (image.get_width() - framePx) / step + 1
	var rows := image.get_height() / framePx
	var atlas := Image.create(maxi(columns, 1) * framePx, maxi(rows, 1) * framePx, false, Image.FORMAT_RGBA8)
	for column in columns:
		for row in rows:
			var origin := Vector2i(column * step, row * framePx + (drop if column % 2 == 1 else 0))
			if origin.y + framePx > image.get_height():
				continue
			for y in framePx:
				for x in framePx:
					if hexContains(framePx, x, y):
						atlas.set_pixel(column * framePx + x, row * framePx + y, image.get_pixel(origin.x + x, origin.y + y))
	return atlas


## Imports a tileset's sheet and reconciles it against the ledger the catalog already holds.
## Returns `{success, report, collisions, off_palette, tiles, next_id, error}`; the caller
## decides whether to accept the result -- see `applyImport`. Nothing is written here, because
## an import that reports `removed` on a whole sheet is exactly the moment a human should be
## looking rather than a file should be changing.
static func importSheet(tilesetID: String, palette := PackedColorArray()) -> Dictionary:
	if not _index.has(tilesetID):
		return _importFailure("unknown tileset '%s'" % tilesetID)
	var reference: Dictionary = _index[tilesetID]
	var sheetPath := str(reference["SHEET"])
	var image := loadTilesetImage(reference)
	if image == null:
		return _importFailure("could not read sheet at %s" % sheetPath)

	var gridPx := int(reference["FRAME_PX"])
	var cut := cutSheet(image, gridPx)
	var reconciled := reconcile(
		reference["TILES"], cut["cells"], int(reference["NEXT_ID"])
	)
	return {
		"success": true,
		"tiles": reconciled["tiles"],
		"report": reconciled["report"],
		"next_id": reconciled["next_id"],
		"collisions": cut["collisions"],
		"remainder": cut["remainder"],
		"blank": cut["blank"],
		"off_palette": offPaletteColours(image, palette) if palette.size() > 0 else [],
		"error": "",
	}


static func _importFailure(message: String) -> Dictionary:
	push_warning("WorldMapTilesetCatalog: %s" % message)
	return {
		"success": false, "tiles": [], "report": {}, "next_id": 0,
		"collisions": [], "remainder": Vector2i.ZERO, "blank": 0, "off_palette": [],
		"error": message,
	}


## Accepts an `importSheet` result into the in-memory catalog. Separate from `importSheet` so a
## caller can look at the report first -- see that function's own note.
static func applyImport(tilesetID: String, result: Dictionary) -> bool:
	if not _index.has(tilesetID) or not bool(result.get("success", false)):
		return false
	var reference: Dictionary = _index[tilesetID]
	reference["TILES"] = result["tiles"]
	reference["NEXT_ID"] = int(result["next_id"])
	return true


## Renders one tileset entry as the JSON text its config file holds. A re-save with nothing
## changed produces a BYTE-IDENTICAL file, which is the property that matters: several agent
## sessions share one working tree here, and a config that reshuffled itself on every write would
## turn every save into a conflict that is not a real disagreement.
##
## Two things supply that determinism, and only one of them is this function's doing. Tiles are
## written in sheet order -- so a diff shows what moved rather than the order ids happened to be
## allocated in -- while the KEY order inside each object is Godot's: `JSON.stringify` sorts keys
## alphabetically regardless of the order they were built in. That is why the emitted files read
## `AUTOTILE, CELL, HASH, ID, ...` rather than the order below. Deterministic either way, so the
## construction order here is for reading, not for the output.
static func serialise(reference: Dictionary) -> String:
	var tiles: Array = []
	for tile in reference.get("TILES", []):
		var cellValue = (tile as Dictionary).get("CELL", Vector2i.ZERO)
		var cell: Vector2i = cellValue if cellValue is Vector2i else Vector2i(cellValue[0], cellValue[1])
		tiles.append({
			"ID": tile["ID"],
			"HASH": tile["HASH"],
			"CELL": [cell.x, cell.y],
			"LABEL": tile["LABEL"],
			"TERRAIN": tile["TERRAIN"],
			"AUTOTILE": tile["AUTOTILE"],
			"VARIANT": tile["VARIANT"],
			"WALKABLE": tile["WALKABLE"],
			"LIFTABLE": tile["LIFTABLE"],
		})
	var out := {
		"NAME": reference["NAME"],
		"DESCRIPTION": reference.get("DESCRIPTION", ""),
		"SHEET": reference["SHEET"],
		"GRID_KIND": reference["GRID_KIND"],
		"FRAME_PX": reference["FRAME_PX"],
		"PALETTE_REGION": reference.get("PALETTE_REGION", ""),
		"NEXT_ID": reference["NEXT_ID"],
		"TILES": tiles,
	}
	if str(reference.get("LAYOUT", LAYOUT_GRID)) != LAYOUT_GRID:
		out["LAYOUT"] = reference["LAYOUT"]
	return JSON.stringify(out, "\t") + "\n"


## Writes one tileset's config file to `configPathFor(tilesetID)`, creating `_configDir` if it
## does not exist yet. This writes only that one file -- a sibling tileset's config, loaded or
## discovered, is never touched by a save that was not asked for.
static func saveTileset(tilesetID: String) -> bool:
	if not _index.has(tilesetID):
		push_warning("WorldMapTilesetCatalog: unknown tileset '%s'" % tilesetID)
		return false
	var path := configPathFor(tilesetID)
	DirAccess.make_dir_recursive_absolute(path.get_base_dir())
	var file := FileAccess.open(path, FileAccess.WRITE)
	if file == null:
		push_warning("WorldMapTilesetCatalog: could not write %s" % path)
		return false
	file.store_string(serialise(_index[tilesetID]))
	file.close()
	_hasConfig[tilesetID] = true
	return true


## Makes a tileset's config file durable the first time it is used, and does nothing (successfully)
## if it already exists -- see the class note on why folder discovery alone must never write a
## file. Returns `false` only for an unknown tileset ID or a failed write.
static func ensureConfig(tilesetID: String) -> bool:
	if not _index.has(tilesetID):
		return false
	if hasConfigFile(tilesetID):
		return true
	return saveTileset(tilesetID)


## One line per verdict that has entries, for a console or a HUD panel. An import with nothing
## to say returns a single "unchanged" line rather than an empty string, because silence and
## success should not look the same.
static func describeReport(report: Dictionary) -> String:
	var lines: Array[String] = []
	for verdict in [ADDED, MOVED, CHANGED, REMOVED]:
		var entries: Array = report.get(verdict, [])
		if not entries.is_empty():
			lines.append("%s (%d): %s" % [verdict, entries.size(), ", ".join(entries)])
	if lines.is_empty():
		var count: int = (report.get(UNCHANGED, []) as Array).size()
		return "unchanged (%d tiles)" % count
	return "\n".join(lines)
