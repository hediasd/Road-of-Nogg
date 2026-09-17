## WME-6's self-contained validation: the bake is deterministic, a partial rebake equals a full
## one, and the composed texture is byte-identical to the art it was cut from.
##
## The last of those is an unusually exact acceptance test, and it exists because of a choice
## made two items earlier: the bootstrap tileset was cut out of region `temp2` rather than drawn
## fresh, so reassembling `temp2_authored` from those tiles must reproduce `temp2` itself. Not
## "looks the same" -- the same bytes. That single assertion covers the whole chain at once: the
## sheet cut, the ledger hashes, the cell ids the authoring pass resolved, and the compositing
## order and blend mode used here.
##
## `temp2` is 15.5 walk tiles wide, so the target is its first 240 px. The rightmost 8 px is a
## cel-grade remainder a tile-grade ground layer cannot hold, and that is a property of the art
## rather than a defect in the bake.

extends SceneTree

const MapData = preload("res://src/presentation/worldmap/editor/WorldMapTileData.gd")
const Baker = preload("res://src/presentation/worldmap/editor/WorldMapBaker.gd")
const TilesetCatalog = preload("res://src/presentation/worldmap/editor/WorldMapTilesetCatalog.gd")
const RegionCatalog = preload("res://src/presentation/worldmap/WorldMapRegionCatalog.gd")
const Uniforms = preload("res://src/presentation/worldmap/WorldMapGroundUniforms.gd")

const AUTHORED := "temp2_authored"
const HEX_TILESET := "temp2_hex32_ground"

var _failures := 0


func _initialize() -> void:
	_checkParityWithSourceArt()
	_checkDeterminism()
	_checkPartialEqualsFull()
	_checkErasureClears()
	_checkDirtyCoalescing()
	_checkCommittedArtifact()
	_checkImportFlags()
	_checkHexCanvasSize()
	_checkHexFramePlacement()
	_checkHexFrameCornersAreTransparent()
	_checkHexPartialEqualsFull()

	print("")
	print("probe_bake_parity: %s" % ("PASS" if _failures == 0 else "%d FAILURE(S)" % _failures))
	if _failures == 0:
		print("WORLD MAP BAKE PARITY OK")
	quit(1 if _failures > 0 else 0)


func _fail(message: String) -> void:
	_failures += 1
	print("  FAIL  %s" % message)


func _load() -> WorldMapTileData:
	return MapData.loadFrom(MapData.pathFor(AUTHORED))


## Reports where two images first differ, which is far more useful than "not equal" when a
## compositing bug puts one tile in the wrong place.
func _describeDifference(a: Image, b: Image) -> String:
	var left := a.get_data()
	var right := b.get_data()
	if left.size() != right.size():
		return "byte counts differ: %d vs %d" % [left.size(), right.size()]
	var diffs := 0
	var firstAt := -1
	for i in left.size():
		if left[i] != right[i]:
			diffs += 1
			if firstAt < 0:
				firstAt = i
	if diffs == 0:
		return ""
	var pixel := firstAt / 4
	return "%d bytes differ, first at pixel (%d, %d)" % [
		diffs, pixel % a.get_width(), pixel / a.get_width()
	]


## The headline assertion -- see the class note.
func _checkParityWithSourceArt() -> void:
	print("-- the bake reproduces the art it was cut from --")
	var data := _load()
	if data == null:
		_fail("could not load %s" % AUTHORED)
		return
	var baker := Baker.new()
	if baker.bake(data) == null:
		_fail("bake produced no texture")
		return
	var baked := baker.image()
	var source := TilesetCatalog.loadSheetImage("res://assets/worldmap/regions/temp2.png")
	if source == null:
		_fail("could not read temp2's art")
		return
	if Vector2i(baked.get_size()) != Vector2i(240, 176):
		_fail("baked size is %s, expected (240, 176)" % baked.get_size())
		return
	var target := source.get_region(Rect2i(0, 0, baked.get_width(), baked.get_height()))
	var difference := _describeDifference(baked, target)
	if not difference.is_empty():
		_fail("baked output is not temp2's first 240 px: %s" % difference)
		return
	print("  ok    240 x 176 baked, byte-identical to temp2's first 240 px")


func _checkDeterminism() -> void:
	print("-- the same data bakes to the same bytes --")
	var data := _load()
	var first := Baker.new()
	first.bake(data)
	var second := Baker.new()
	second.bake(data)
	var difference := _describeDifference(first.image(), second.image())
	if not difference.is_empty():
		_fail("two bakes of one map differ: %s" % difference)
		return
	# And again through a save/load cycle of the source, so determinism survives serialisation.
	var reloaded := _load()
	var third := Baker.new()
	third.bake(reloaded)
	difference = _describeDifference(first.image(), third.image())
	if not difference.is_empty():
		_fail("a bake after reloading the source differs: %s" % difference)
		return
	print("  ok    identical across two bakes and across a reload of the source")


## The dirty-rect model's whole claim: recomposing only what changed lands in the same place as
## recomposing everything. A partial path that is merely close is worse than none, because the
## error accumulates silently across a session of editing.
func _checkPartialEqualsFull() -> void:
	print("-- a partial rebake equals a full one --")
	var data := _load()
	var baker := Baker.new()
	baker.bake(data)

	# Edit a scatter of cells, including two far apart, then flush only those.
	var edits := [
		[Vector2i(0, 0), "t005"],
		[Vector2i(7, 4), "t012"],
		[Vector2i(14, 10), "t000"],
		[Vector2i(3, 9), "t021"],
	]
	for edit in edits:
		var cell: Vector2i = edit[0]
		data.setCell("ground", cell, str(edit[1]))
		baker.markCellsDirty(data, "ground", Rect2i(cell, Vector2i.ONE))
	if not baker.flush(data):
		_fail("flush reported nothing to do after 4 edits")
		return

	var reference := Baker.new()
	reference.bake(data)
	var difference := _describeDifference(baker.image(), reference.image())
	if not difference.is_empty():
		_fail("partial rebake diverged from a full bake: %s" % difference)
		return
	print("  ok    4 scattered edits, flushed partially, identical to a full bake")


## A cell whose tile is erased must stop showing its old pixels. Compositing over stale content
## would leave them, which is why `flush` clears each dirty rect before recomposing it.
func _checkErasureClears() -> void:
	print("-- erasing a cell clears what was there --")
	var data := _load()
	var baker := Baker.new()
	baker.bake(data)
	data.setCell("ground", Vector2i(5, 5), MapData.EMPTY)
	baker.markCellsDirty(data, "ground", Rect2i(Vector2i(5, 5), Vector2i.ONE))
	baker.flush(data)

	var tile := Uniforms.TILE_PIXELS
	var patch := baker.image().get_region(Rect2i(5 * tile, 5 * tile, tile, tile))
	for y in patch.get_height():
		for x in patch.get_width():
			if patch.get_pixel(x, y).a > 0.0:
				_fail("an erased cell still has opaque pixels at (%d, %d)" % [x, y])
				return
	# And a full bake of the same data agrees.
	var reference := Baker.new()
	reference.bake(data)
	var difference := _describeDifference(baker.image(), reference.image())
	if not difference.is_empty():
		_fail("erasure via flush differs from a full bake: %s" % difference)
		return
	print("  ok    the cell is fully transparent, and matches a full bake")


## Dirty rects snap out to whole tiles and absorb into an enclosing entry, so a drag across one
## tile does not accumulate a hundred identical rects.
func _checkDirtyCoalescing() -> void:
	print("-- dirty rects coalesce --")
	var data := _load()
	var baker := Baker.new()
	baker.bake(data)
	if baker.dirtyCount() != 0:
		_fail("a fresh bake left %d dirty rects" % baker.dirtyCount())
		return
	for _i in 20:
		baker.markCellsDirty(data, "ground", Rect2i(Vector2i(4, 4), Vector2i.ONE))
	if baker.dirtyCount() != 1:
		_fail("20 marks on one cell produced %d rects" % baker.dirtyCount())
		return
	# A cel-grade mark snaps OUT to the tile beneath it, which has two consequences worth
	# asserting separately. Cel (9, 9) lies inside tile (4, 4) -- 9 / 2 rounds down to 4 -- so it
	# is absorbed by the rect already covering that tile rather than adding a second one. That
	# is the snapping working: a cel brush cannot leave the ground under it stale, because it
	# always dirties the whole tile it sits in.
	baker.markCellsDirty(data, "overlay", Rect2i(Vector2i(9, 9), Vector2i.ONE))
	if baker.dirtyCount() != 1:
		_fail("a cel mark inside an already-dirty tile added a rect (%d)" % baker.dirtyCount())
		return
	# A cel in a tile nothing has touched does add its own.
	baker.markCellsDirty(data, "overlay", Rect2i(Vector2i(18, 18), Vector2i.ONE))
	if baker.dirtyCount() != 2:
		_fail("a cel mark in a clean tile produced %d rects" % baker.dirtyCount())
		return
	print("  ok    20 marks collapse to 1; a cel inside that tile absorbs; one elsewhere adds")


## The committed build artifact must actually agree with its source. A stale PNG renders a map
## nobody authored, and it is exactly the disagreement the linter will later be asked to flag.
func _checkCommittedArtifact() -> void:
	print("-- the committed PNG agrees with its source --")
	var data := _load()
	var baker := Baker.new()
	baker.bake(data)
	var path: String = Baker.generatedPathFor(AUTHORED)
	var committed := TilesetCatalog.loadSheetImage(path)
	if committed == null:
		_fail("no committed artifact at %s" % path)
		return
	var difference := _describeDifference(baker.image(), committed)
	if not difference.is_empty():
		_fail("the committed PNG is stale: %s" % difference)
		return
	# And the region catalog loads it as an authored region.
	var region := RegionCatalog.loadRegion(AUTHORED)
	if region.is_empty():
		_fail("the catalog could not load the authored region")
		return
	if str(region["kind"]) != RegionCatalog.KIND_AUTHORED:
		_fail("the region loaded as '%s'" % region["kind"])
		return
	if region["map_px"] != Vector2i(240, 176):
		_fail("the catalog reports %s map pixels" % region["map_px"])
		return
	print("  ok    PNG matches the source, and loads as an authored region at 240 x 176")


## Godot's importer defaults are backwards for this rig: `WORLDMAP_DESIGN.md` section 4 wants
## mipmaps for the far field, and a lossy compression mode would put the artifact out of step
## with its own source.
func _checkImportFlags() -> void:
	print("-- the baked artifact imports like region art --")
	var path: String = Baker.generatedPathFor(AUTHORED) + ".import"
	if not FileAccess.file_exists(path):
		_fail("no .import beside the baked artifact")
		return
	var text := FileAccess.get_file_as_string(path)
	if text.find("mipmaps/generate=true") < 0:
		_fail("mipmaps are off; Godot's default is backwards for this rig")
		return
	if text.find("compress/mode=0") < 0:
		_fail("the artifact is not importing losslessly")
		return
	# Compared against the art it must behave like, rather than against a remembered constant.
	var reference := FileAccess.get_file_as_string("res://assets/worldmap/regions/temp2.png.import")
	for flag in ["mipmaps/generate=true", "compress/mode=0"]:
		if reference.find(flag) < 0:
			_fail("region art no longer carries %s; this check is out of date" % flag)
			return
	print("  ok    mipmaps on and lossless, matching temp2's own import")


## WMH-5B: canvas size for a hex document is `worldExtent() * TILE_PIXELS`, not `size_tiles *
## TILE_PIXELS` -- on a hex document those are different things (columns/rows vs. world units).
func _checkHexCanvasSize() -> void:
	print("-- hex canvas size is worldExtent(), not size_tiles --")
	var checked := 0
	for lattice in WorldMapHexGrid.exactSquareLattices():
		if lattice.x > 16:
			break  # a couple of small lattices is enough; large ones only cost time here
		var data := MapData.create("_probe_hex_canvas", lattice, MapData.LAYOUT_HEX_FLAT)
		data.layers["ground"]["TILESET"] = HEX_TILESET
		var expected: Vector2 = data.worldExtent() * float(Uniforms.TILE_PIXELS)
		var expectedSize := Vector2i(int(round(expected.x)), int(round(expected.y)))
		var actual := Baker.pixelSizeOf(data)
		if actual != expectedSize:
			_fail("lattice %s: pixelSizeOf is %s, expected %s" % [lattice, actual, expectedSize])
			return
		var baker := Baker.new()
		if baker.bake(data) == null:
			_fail("lattice %s: bake produced no texture" % lattice)
			return
		if Vector2i(baker.image().get_size()) != expectedSize:
			_fail("lattice %s: baked image is %s, expected %s" % [
				lattice, baker.image().get_size(), expectedSize
			])
			return
		checked += 1
	if checked == 0:
		_fail("no lattices were actually checked")
		return
	print("  ok    canvas size matches worldExtent() x TILE_PIXELS across %d lattices" % checked)


## Every cell's frame lies inside the canvas, and the bounding box of every frame's own extent --
## NOT a per-pixel union; a hex lattice's rectangular bounding box legitimately leaves its four
## corners uncovered by any hexagon, the same geometric fact the void colour renders around --
## reaches exactly to the canvas edges, neither clipped nor with wasted margin.
func _checkHexFramePlacement() -> void:
	print("-- every hex frame lies inside the canvas; their bounds reach every edge exactly --")
	var lattice := Vector2i(7, 5)
	var data := MapData.create("_probe_hex_placement", lattice, MapData.LAYOUT_HEX_FLAT)
	data.layers["ground"]["TILESET"] = HEX_TILESET
	var canvas := Baker.pixelSizeOf(data)
	var framePx := int(TilesetCatalog.tilesetFor(HEX_TILESET)["FRAME_PX"])

	var minX := 2147483647
	var minY := 2147483647
	var maxX := -2147483648
	var maxY := -2147483648
	for col in lattice.x:
		for row in lattice.y:
			var centre: Vector2 = WorldMapHexGrid.cellCentre(Vector2i(col, row)) * Uniforms.TILE_PIXELS
			var half := framePx * 0.5
			var frameRect := Rect2i(
				Vector2i(int(round(centre.x - half)), int(round(centre.y - half))),
				Vector2i(framePx, framePx)
			)
			var exceeds := (
				frameRect.position.x < 0 or frameRect.position.y < 0
				or frameRect.position.x + frameRect.size.x > canvas.x
				or frameRect.position.y + frameRect.size.y > canvas.y
			)
			if exceeds:
				_fail("cell (%d, %d)'s frame %s exceeds the canvas %s" % [
					col, row, frameRect, canvas
				])
				return
			minX = mini(minX, frameRect.position.x)
			minY = mini(minY, frameRect.position.y)
			maxX = maxi(maxX, frameRect.position.x + frameRect.size.x)
			maxY = maxi(maxY, frameRect.position.y + frameRect.size.y)
	if minX != 0 or minY != 0 or maxX != canvas.x or maxY != canvas.y:
		_fail("frame bounds are (%d,%d)-(%d,%d), expected (0,0)-%s" % [
			minX, minY, maxX, maxY, canvas
		])
		return
	print("  ok    %d cells, no frame exceeds the canvas, bounds reach every edge exactly" % [
		lattice.x * lattice.y
	])


## The overlap contract WMH-5B's compositing depends on: a hex sheet's frame corners must be
## transparent, or overlapping frames would overwrite each other's content instead of compositing
## as hexagons. Checked rather than trusted, so a future hex sheet cut without its mask fails
## loudly here instead of rendering as corner-shaped overwrite artifacts.
func _checkHexFrameCornersAreTransparent() -> void:
	print("-- hex sheet frame corners are transparent (the overlap contract) --")
	var reference := TilesetCatalog.tilesetFor(HEX_TILESET)
	var sheet := TilesetCatalog.loadSheetImage(str(reference["SHEET"]))
	if sheet == null:
		_fail("could not load the sheet for %s" % HEX_TILESET)
		return
	var framePx := int(reference["FRAME_PX"])
	var checked := 0
	for tile in reference["TILES"]:
		var cell: Vector2i = (tile as Dictionary)["CELL"]
		var ox := cell.x * framePx
		var oy := cell.y * framePx
		for corner in [
			Vector2i(0, 0), Vector2i(framePx - 1, 0),
			Vector2i(0, framePx - 1), Vector2i(framePx - 1, framePx - 1),
		]:
			checked += 1
			if sheet.get_pixel(ox + corner.x, oy + corner.y).a > 0.01:
				_fail("%s frame at sheet cell %s has an opaque corner at %s" % [
					HEX_TILESET, cell, corner
				])
				return
	print("  ok    %d frame corners across %d tiles, all transparent" % [
		checked, (reference["TILES"] as Array).size()
	])


## WMH-5B's headline risk: a full bake can be perfectly correct while every EDIT quietly eats a
## strip of its neighbours, because `_composeRect` clears to transparent before recomposing --
## that appears only in the partial-flush path, never in a from-scratch bake, which is exactly
## what a naive test would check instead. Run on both column parities, since which neighbour a
## frame overlaps into differs between them.
func _checkHexPartialEqualsFull() -> void:
	print("-- hex partial rebake equals a full one, on both column parities --")
	var lattice := Vector2i(9, 7)
	var tileIDs: Array = []
	for tile in TilesetCatalog.tilesetFor(HEX_TILESET)["TILES"]:
		tileIDs.append(str((tile as Dictionary)["ID"]))
	if tileIDs.size() < 2:
		_fail("hex tileset has too few tiles to test with")
		return

	for editCell in [Vector2i(2, 3), Vector2i(3, 3)]:
		var data := MapData.create("_probe_hex_partial", lattice, MapData.LAYOUT_HEX_FLAT)
		data.layers["ground"]["TILESET"] = HEX_TILESET
		# Uniform fill first, so the "before" state has no seams of its own to confuse a diff --
		# then edit the SMALLEST possible change, the one most likely to expose an under-covered
		# dirty rect.
		for col in lattice.x:
			for row in lattice.y:
				data.setCell("ground", Vector2i(col, row), tileIDs[0])

		var baker := Baker.new()
		baker.bake(data)
		data.setCell("ground", editCell, tileIDs[1])
		baker.markCellsDirty(data, "ground", Rect2i(editCell, Vector2i.ONE))
		if not baker.flush(data):
			_fail("flush reported nothing to do after editing %s" % editCell)
			return

		var reference := Baker.new()
		reference.bake(data)
		var difference := _describeDifference(baker.image(), reference.image())
		if not difference.is_empty():
			_fail("hex partial rebake at %s diverged from a full bake: %s" % [editCell, difference])
			return
	print("  ok    single-cell edit on an even and an odd column, partial matches full exactly")
