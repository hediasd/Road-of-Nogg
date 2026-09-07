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


## The region's pixel size: its tile count times the tile law's constant. Not stored anywhere --
## deriving it is what keeps a baked texture from ever disagreeing with the data's own extent.
static func pixelSizeOf(data: WorldMapTileData) -> Vector2i:
	return data.size_tiles * Uniforms.TILE_PIXELS


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
	var cellPx := _cellPixels(str(block["GRID_KIND"]))
	var rect := Rect2i(cells.position * cellPx, cells.size * cellPx)
	markPixelsDirty(rect)


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
## the authored order rather than a second thing to keep in step.
func _composeRect(data: WorldMapTileData, rect: Rect2i) -> void:
	for layerID in data.layerIDs():
		var block: Dictionary = data.layers[layerID]
		if str(block["KIND"]) != WorldMapTileData.KIND_GRID:
			continue
		var sheet: Dictionary = _sheets.get(str(block["TILESET"]), {})
		if sheet.is_empty():
			continue
		var cellPx := _cellPixels(str(block["GRID_KIND"]))
		var size := data.layerSize(layerID)
		# Only the cells the rect actually touches.
		var first := Vector2i(rect.position.x / cellPx, rect.position.y / cellPx)
		var last := Vector2i(
			int(ceil(float(rect.position.x + rect.size.x) / cellPx)),
			int(ceil(float(rect.position.y + rect.size.y) / cellPx))
		)
		var sheetImage: Image = sheet["image"]
		var cells: Dictionary = sheet["cells"]
		for y in range(maxi(0, first.y), mini(size.y, last.y)):
			for x in range(maxi(0, first.x), mini(size.x, last.x)):
				var id := data.getCell(layerID, Vector2i(x, y))
				if id == WorldMapTileData.EMPTY or not cells.has(id):
					continue
				var source: Vector2i = cells[id]
				var from := Rect2i(source * cellPx, Vector2i(cellPx, cellPx))
				var to := Vector2i(x * cellPx, y * cellPx)
				# `blend_rect`, not `blit_rect`: an overlay tile with transparent pixels must let
				# the ground beneath show through. Ground tiles are opaque, so the two agree
				# there and only the overlay depends on the difference.
				_image.blend_rect(sheetImage, from, to)


func _cellPixels(gridKind: String) -> int:
	return WorldMapTilesetCatalog.gridPixels(gridKind)


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
