## Composes an authored region's tile data into the single region texture the ground shader
## samples, and keeps that texture current as cells are edited.
##
## THE BAKE IS THE RENDER REPRESENTATION, NOT A COMPATIBILITY SHIM. The alternative -- a
## tile-index texture plus a tileset atlas sampled live in the shader -- was rejected in the
## cycle file and the reason is `WORLDMAP_DESIGN.md` section 4: the ground keeps three sampler
## uniforms bound to the same texture because nearest-with-no-mipmaps IS the look and the far
## field still needs mips. An atlas cannot be mipmapped without bleeding across tile borders,
## and nearest-filtered at magnification it is one texel-rounding error away from sampling its
## neighbour. Composing to one contiguous texture keeps fog, curvature, palette-snapped shadows,
## cloud shadows, the void substitution and all three filter modes working unchanged, because
## none of them can tell the image was not hand-painted.
##
## ONE TEXTURE OBJECT, UPDATED IN PLACE. `bake()` creates the `ImageTexture` once and every
## later flush calls `update()` on that same object. The ground's shader samplers already point
## at it, so a re-bake needs no call into `WorldMapGround` at all -- and in particular does not
## need `configure()`, which would rebuild the mesh for a change that is only pixels.
##
## PARTIAL RECOMPOSITION, FULL UPLOAD -- AND THE SECOND HALF IS NOT A CHOICE. Godot 4 has no
## partial 2D texture upload: `ImageTexture.update()` and `RenderingServer.texture_2d_update()`
## both take a whole image. Verified against 4.4 rather than assumed. So the dirty-rect model
## below governs the COMPOSITION -- the part whose cost scales with region size, since a stroke
## on a 155-tile region otherwise re-blits 24,000 tiles to change one -- while the upload is
## whole-texture regardless. Flushing is therefore something to do once after a batch of edits,
## not once per cell, which is what `markCellsDirty` + `flush` are shaped for.
##
## HEX FRAMES OVERLAP THEIR NEIGHBOURS, AND THAT IS DELIBERATE (WMH-5B). A hex frame is 32 px on
## a 24 px column pitch, so adjacent columns' frames share an 8 px strip -- and the sheet already
## carries the alpha that makes that correct (measured: 0 of 320 frame corners in
## `temp2_hex32_ground` are opaque), so `blend_rect` composites overlapping hexagons that tile
## the plane exactly. The consequence for THIS file is that a square layer's cells tile edge to
## edge -- `cell * framePx` is exact, both for placement and for which cells a dirty rect
## touches -- while a hex layer's do not: a cell whose own centre sits outside a dirty rect can
## still have a frame that reaches into it. `_composeRect` clears each dirty rect to transparent
## before recomposing it, so under-covering here does not merely leave a stale pixel, it ERASES a
## strip of a neighbour that was never told to redraw. `_cellsToPixelRect` and `_composeHexLayer`
## are both deliberately generous rather than tight because of that asymmetry -- over-covering
## costs a handful of redundant blends; under-covering corrupts the image.

class_name WorldMapBaker
extends RefCounted

const Uniforms = preload("res://src/presentation/worldmap/WorldMapGroundUniforms.gd")

## Where a baked region PNG lives. Separated from hand-drawn art on purpose: everything under
## this directory is generated, and nothing in it should ever be edited by hand.
const GENERATED_DIR := "res://assets/worldmap/regions/generated"

var _image: Image
var _texture: ImageTexture
## Accumulated dirty regions in MAP PIXELS, snapped out to whole tiles. Kept as a list rather
## than one union rect: two edits at opposite corners of a map would union into the whole map,
## which is the full rebuild this exists to avoid.
var _dirty: Array[Rect2i] = []
## Tileset id -> `{image, cells}`, where `cells` maps a tile id to its cell in the sheet. Built
## once per bake so a 24,000-tile compose does not re-read a sheet per cell.
var _sheets: Dictionary = {}


func texture() -> ImageTexture:
	return _texture


func image() -> Image:
	return _image


## The region's pixel size: its WORLD extent times the tile law's constant, not its cell count.
## On a square map those agree (`worldExtent()` returns `Vector2(size_tiles)` there); on a hex
## map `size_tiles` is columns and rows, and only `worldExtent()` (WMH-2) converts through
## `WorldMapHexGrid.latticeExtent`. Not stored anywhere -- deriving it is what keeps a baked
## texture from ever disagreeing with the data's own extent. Every lattice lands on whole
## pixels: `COL_ADVANCE`/`ROW_ADVANCE`/`HEX_WIDTH`/`HEX_HEIGHT` are all multiples of 0.5 world
## units, and `TILE_PIXELS` is even, so the round below is exact rather than a rounding choice.
static func pixelSizeOf(data: WorldMapTileData) -> Vector2i:
	var extent := data.worldExtent() * Uniforms.TILE_PIXELS
	return Vector2i(int(round(extent.x)), int(round(extent.y)))


## Full compose. Creates the image and the texture the first time, and reuses both afterwards so
## the object the ground is holding stays the object the ground is holding.
func bake(data: WorldMapTileData) -> ImageTexture:
	var size := pixelSizeOf(data)
	if size.x <= 0 or size.y <= 0:
		push_warning("WorldMapBaker: region has no size")
		return null
	_loadSheets(data)
	if _image == null or Vector2i(_image.get_size()) != size:
		_image = Image.create(size.x, size.y, false, Image.FORMAT_RGBA8)
		_texture = null
	_image.fill(Color(0, 0, 0, 0))
	_composeRect(data, Rect2i(Vector2i.ZERO, size))
	_dirty.clear()
	if _texture == null:
		_texture = ImageTexture.create_from_image(_image)
	else:
		_texture.update(_image)
	return _texture


## Marks a rectangle of a layer's own cells as needing recomposition. The rect is converted to
## map pixels here rather than at flush time, because a layer's cell size is a property of the
## layer and the dirty list should not have to remember which layer each entry came from.
func markCellsDirty(data: WorldMapTileData, layerID: String, cells: Rect2i) -> void:
	if not data.layers.has(layerID):
		return
	var block: Dictionary = data.layers[layerID]
	if str(block["KIND"]) != WorldMapTileData.KIND_GRID:
		return
	markPixelsDirty(_cellsToPixelRect(data, block, cells))


## The map-pixel rect a range of a layer's own cells occupies. Square: exact, because cells tile
## edge to edge. Hex: deliberately GENEROUS, not exact -- see the class note on why an
## under-sized rect here is a correctness bug, not merely a missed optimisation.
func _cellsToPixelRect(data: WorldMapTileData, block: Dictionary, cells: Rect2i) -> Rect2i:
	var framePx := _framePixels(str(block["TILESET"]), str(block["GRID_KIND"]))
	if data.layout != WorldMapTileData.LAYOUT_HEX_FLAT:
		return Rect2i(cells.position * framePx, cells.size * framePx)

	# The tight bounding box of the RANGE's own cell centres, found from its four corners --
	# `cellCentre`'s only non-affine term is the odd-column drop (1 world unit, 16 px), far
	# smaller than the margins added below, so checking corners rather than every interior cell
	# cannot miss an extremum by more than that already-covered amount.
	var lastCol := cells.position.x + cells.size.x - 1
	var lastRow := cells.position.y + cells.size.y - 1
	var minCorner := Vector2(INF, INF)
	var maxCorner := Vector2(-INF, -INF)
	for col in [cells.position.x, lastCol]:
		for row in [cells.position.y, lastRow]:
			var centre := WorldMapHexGrid.cellCentre(Vector2i(col, row)) * Uniforms.TILE_PIXELS
			minCorner.x = minf(minCorner.x, centre.x)
			minCorner.y = minf(minCorner.y, centre.y)
			maxCorner.x = maxf(maxCorner.x, centre.x)
			maxCorner.y = maxf(maxCorner.y, centre.y)

	# Step 1: widen from cell CENTRES to the range's own FRAME footprint.
	var half := float(framePx) * 0.5
	minCorner -= Vector2(half, half)
	maxCorner += Vector2(half, half)
	# Step 2: pad by one FULL frame beyond that -- the reach of a neighbouring cell's frame,
	# which is exactly what "expand by one full frame on all sides" (WMH-5B's own item text) is
	# for.
	minCorner -= Vector2(framePx, framePx)
	maxCorner += Vector2(framePx, framePx)

	var start := Vector2i(int(floor(minCorner.x)), int(floor(minCorner.y)))
	var finish := Vector2i(int(ceil(maxCorner.x)), int(ceil(maxCorner.y)))
	return Rect2i(start, finish - start)


## Marks map pixels dirty, snapped OUT to whole tiles. Snapping to the coarsest grid means a
## cel-grade edit still recomposes the tile-grade cell beneath it, which is what stops a cel
## brush from leaving the ground under it stale.
func markPixelsDirty(rect: Rect2i) -> void:
	if _image == null:
		return
	var tile := Uniforms.TILE_PIXELS
	var start := Vector2i(
		int(floor(float(rect.position.x) / tile)) * tile,
		int(floor(float(rect.position.y) / tile)) * tile
	)
	var finish := Vector2i(
		int(ceil(float(rect.position.x + rect.size.x) / tile)) * tile,
		int(ceil(float(rect.position.y + rect.size.y) / tile)) * tile
	)
	var snapped := Rect2i(start, finish - start).intersection(
		Rect2i(Vector2i.ZERO, Vector2i(_image.get_size()))
	)
	if snapped.size.x <= 0 or snapped.size.y <= 0:
		return
	# Absorbed into an existing entry when one already covers it, so a drag across one tile does
	# not accumulate a hundred identical rects.
	for existing in _dirty:
		if existing.encloses(snapped):
			return
	_dirty.append(snapped)


func dirtyCount() -> int:
	return _dirty.size()


## Recomposes only what has been marked, then uploads once. Returns whether anything was done,
## so a caller can skip the upload entirely on a no-op frame.
func flush(data: WorldMapTileData) -> bool:
	if _image == null or _texture == null or _dirty.is_empty():
		return false
	_loadSheets(data)
	for rect in _dirty:
		# Cleared to transparent first: a cell whose tile was erased must stop showing its old
		# pixels, and compositing over stale content would leave them.
		_image.fill_rect(rect, Color(0, 0, 0, 0))
		_composeRect(data, rect)
	_dirty.clear()
	_texture.update(_image)
	return true


## Draws every layer, in declaration order, over the given map-pixel rect. Ground first and
## overlays after, which is the order the layer list already carries -- so compositing order is
## the authored order rather than a second thing to keep in step. Hex and square layers place
## their cells differently enough (overlapping frames vs. an edge-to-edge grid) that each gets
## its own function rather than one branching per pixel.
func _composeRect(data: WorldMapTileData, rect: Rect2i) -> void:
	var hex := data.layout == WorldMapTileData.LAYOUT_HEX_FLAT
	for layerID in data.layerIDs():
		var block: Dictionary = data.layers[layerID]
		if str(block["KIND"]) != WorldMapTileData.KIND_GRID:
			continue
		var sheet: Dictionary = _sheets.get(str(block["TILESET"]), {})
		if sheet.is_empty():
			continue
		var size := data.layerSize(layerID)
		var framePx := _framePixels(str(block["TILESET"]), str(block["GRID_KIND"]))
		var sheetImage: Image = sheet["image"]
		var cells: Dictionary = sheet["cells"]
		if hex:
			_composeHexLayer(data, layerID, rect, size, framePx, sheetImage, cells)
		else:
			_composeSquareLayer(data, layerID, rect, size, framePx, sheetImage, cells)


## The original placement: cells tile edge to edge, so the rect-to-cell-range conversion is a
## plain divide and each cell's frame lands at exactly `cell * cellPx`.
func _composeSquareLayer(
	data: WorldMapTileData, layerID: String, rect: Rect2i, size: Vector2i, cellPx: int,
	sheetImage: Image, cellsOnSheet: Dictionary
) -> void:
	var first := Vector2i(rect.position.x / cellPx, rect.position.y / cellPx)
	var last := Vector2i(
		int(ceil(float(rect.position.x + rect.size.x) / cellPx)),
		int(ceil(float(rect.position.y + rect.size.y) / cellPx))
	)
	for y in range(maxi(0, first.y), mini(size.y, last.y)):
		for x in range(maxi(0, first.x), mini(size.x, last.x)):
			var id := data.getCell(layerID, Vector2i(x, y))
			if id == WorldMapTileData.EMPTY or not cellsOnSheet.has(id):
				continue
			var source: Vector2i = cellsOnSheet[id]
			var from := Rect2i(source * cellPx, Vector2i(cellPx, cellPx))
			var to := Vector2i(x * cellPx, y * cellPx)
			# `blend_rect`, not `blit_rect`: an overlay tile with transparent pixels must let
			# the ground beneath show through. Ground tiles are opaque, so the two agree
			# there and only the overlay depends on the difference.
			_image.blend_rect(sheetImage, from, to)


## Frames overlap their neighbours (see the class note), so "which cells does `rect` touch" is
## not the square path's plain divide -- a cell whose own centre is outside `rect` can still have
## a frame reaching into it. The candidate range comes from padding `rect` by one frame and
## resolving its four corners through `WorldMapHexGrid.worldToCell`, then padding THAT by one
## more cell in every direction: cheap insurance (a handful of no-op blends at the edges) against
## the corner-based bound landing one cell short of where `worldToCell`'s own rounding would put
## it. `probe_bake_parity.gd`'s partial-vs-full comparison is what actually proves this
## sufficient, on both column parities, rather than this reasoning alone.
func _composeHexLayer(
	data: WorldMapTileData, layerID: String, rect: Rect2i, size: Vector2i, framePx: int,
	sheetImage: Image, cellsOnSheet: Dictionary
) -> void:
	var padded := Rect2i(
		rect.position - Vector2i(framePx, framePx), rect.size + Vector2i(framePx, framePx) * 2
	)
	var corners := [
		Vector2(padded.position),
		Vector2(padded.position.x + padded.size.x, padded.position.y),
		Vector2(padded.position.x, padded.position.y + padded.size.y),
		Vector2(padded.position + padded.size),
	]
	var minCell := Vector2i(2147483647, 2147483647)
	var maxCell := Vector2i(-2147483648, -2147483648)
	for corner in corners:
		var cell := WorldMapHexGrid.worldToCell(corner / float(Uniforms.TILE_PIXELS))
		minCell.x = mini(minCell.x, cell.x)
		minCell.y = mini(minCell.y, cell.y)
		maxCell.x = maxi(maxCell.x, cell.x)
		maxCell.y = maxi(maxCell.y, cell.y)
	minCell -= Vector2i.ONE
	maxCell += Vector2i.ONE

	for y in range(maxi(0, minCell.y), mini(size.y, maxCell.y + 1)):
		for x in range(maxi(0, minCell.x), mini(size.x, maxCell.x + 1)):
			var id := data.getCell(layerID, Vector2i(x, y))
			if id == WorldMapTileData.EMPTY or not cellsOnSheet.has(id):
				continue
			var source: Vector2i = cellsOnSheet[id]
			var from := Rect2i(source * framePx, Vector2i(framePx, framePx))
			var centre := WorldMapHexGrid.cellCentre(Vector2i(x, y)) * Uniforms.TILE_PIXELS
			var half := framePx * 0.5
			var to := Vector2i(int(round(centre.x - half)), int(round(centre.y - half)))
			_image.blend_rect(sheetImage, from, to)


## The pixel size of one FRAME in this layer's tileset -- the sheet's own `FRAME_PX`, not a
## constant derived from `GRID_KIND`. The two already agree for every square tileset today
## (`FRAME_PX` defaults to `gridPixels(GRID_KIND)` when a tileset does not declare its own -- see
## `WorldMapTilesetCatalog.reloadCatalog`), so reading `FRAME_PX` uniformly is a strict
## generalisation rather than a new special case for hex. `FRAME_PX` exists specifically because
## `GRID_KIND` and frame size were once conflated: a 32 px hex sheet cut on the 16 px grid its
## `GRID_KIND` implied imported 300 quarter-hexes instead of 75.
func _framePixels(tilesetID: String, gridKindFallback: String) -> int:
	var reference := WorldMapTilesetCatalog.tilesetFor(tilesetID)
	if reference.is_empty():
		return WorldMapTilesetCatalog.gridPixels(gridKindFallback)
	return int(reference["FRAME_PX"])


## Reads each tileset a layer names, once. The sheet goes through the catalog's own
## `loadSheetImage`, so the pixels composed here are the same normalised pixels its ledger was
## hashed from -- see `WorldMapTilesetCatalog.hashCell` for what happens when two readers of the
## same art normalise differently.
func _loadSheets(data: WorldMapTileData) -> void:
	for layerID in data.layerIDs():
		var block: Dictionary = data.layers[layerID]
		if str(block["KIND"]) != WorldMapTileData.KIND_GRID:
			continue
		var tilesetID := str(block["TILESET"])
		if tilesetID.is_empty() or _sheets.has(tilesetID):
			continue
		var reference: Dictionary = WorldMapTilesetCatalog.tilesetFor(tilesetID)
		if reference.is_empty():
			push_warning("WorldMapBaker: layer '%s' names unknown tileset '%s'" % [
				layerID, tilesetID
			])
			continue
		var sheetImage := WorldMapTilesetCatalog.loadSheetImage(str(reference["SHEET"]))
		if sheetImage == null:
			push_warning("WorldMapBaker: could not read sheet for '%s'" % tilesetID)
			continue
		var cells: Dictionary = {}
		for tile in reference["TILES"]:
			cells[str((tile as Dictionary)["ID"])] = (tile as Dictionary)["CELL"]
		_sheets[tilesetID] = {"image": sheetImage, "cells": cells}


## Drops the cached sheets, so a tileset re-imported mid-session is picked up by the next bake.
func forgetSheets() -> void:
	_sheets.clear()


static func generatedPathFor(regionName: String) -> String:
	return "%s/%s.png" % [GENERATED_DIR, regionName]


## Writes the baked image as the region's committed build artifact.
##
## Committed, not gitignored: a fresh checkout renders without anyone running a bake first, and
## the linter is what flags a PNG that disagrees with its source. It is still GENERATED -- never
## hand-edited, and reproducible from the tile data alone.
func saveTo(path: String) -> bool:
	if _image == null:
		return false
	DirAccess.make_dir_recursive_absolute(path.get_base_dir())
	if _image.save_png(path) != OK:
		push_warning("WorldMapBaker: could not write %s" % path)
		return false
	return true
