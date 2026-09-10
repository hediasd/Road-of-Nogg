## Which cells a gesture will change. ONE answer, consumed by both the preview and the edit.
##
## WHY THIS EXISTS AT ALL. A preview that computes its own shape and a brush that computes its own
## shape agree right up until one of them is changed, and the failure is silent: the author aims
## at a highlighted footprint and gets a different set of cells. Every tool below returns the
## exact list the controller then paints, so the highlight cannot be a second opinion about what
## is about to happen -- it is the same list, drawn.
##
## GEOMETRY IS BORROWED, NOT RE-DERIVED. Discs come from `WorldMapBrushes.discCells`, lines from
## its hex-aware `lineCells`, adjacency and parity from `WorldMapHexGrid`. Nothing here does
## offset arithmetic on a hex lattice; that is the one failure mode this geometry has, and it is
## already solved one level down.
##
## CLIPPING IS PART OF THE ANSWER. A radius that runs off the lattice edge, or a drag that leaves
## the map, must not be previewed as if those cells existed -- `WorldMapTileData.setCell` would
## refuse them and the author would be shown a footprint larger than the edit. Every function
## returns cells the document actually holds, in a stable order, with no duplicates.

class_name WorldMapWorkspaceFootprint
extends RefCounted

const Brushes = preload("res://src/presentation/worldmap/editor/WorldMapBrushes.gd")


## A brush stamp centred on one cell. `radius` counts hex RINGS: zero is the single cell under the
## pointer, one adds its six neighbours. The workspace displays that as "1 hex", "7 hexes" and so
## on rather than as the ring count, because the count is what an author is choosing.
static func discCells(centre: Vector2i, radius: int, lattice: Vector2i) -> Array[Vector2i]:
	return clip(Brushes.discCells(centre, maxi(radius, 0)), lattice)


## A drag from one pointer sample to the next, as the cells a continuous stroke covers. Pointer
## samples arrive as far apart as the frame rate and the author's hand put them, so painting only
## the sampled cells leaves a dotted line across a fast drag; the hex line path between them is
## what makes the stroke continuous, and each step carries the same disc the brush has.
static func dragCells(
	from: Vector2i, to: Vector2i, radius: int, hex: bool, lattice: Vector2i
) -> Array[Vector2i]:
	var path := Brushes.lineCells(from, to, hex)
	if radius <= 0:
		return clip(path, lattice)
	var swept: Array[Vector2i] = []
	for step in path:
		swept.append_array(Brushes.discCells(step, radius))
	return clip(swept, lattice)


static func lineCells(from: Vector2i, to: Vector2i, hex: bool, lattice: Vector2i) -> Array[Vector2i]:
	return clip(Brushes.lineCells(from, to, hex), lattice)


## An OFFSET-CELL rectangle, which on a hex lattice is a ragged-looking band rather than a tidy
## shape on screen. That is what the tool has always done and what its label now says; the preview
## draws the real cells so the shape is never a surprise. `WorldMapBrushes.disc` is the tool for
## an area that looks round on hexes.
static func rectangleCells(from: Vector2i, to: Vector2i, lattice: Vector2i) -> Array[Vector2i]:
	return clip(Brushes.rectangleCells(from, to), lattice)


## Where a sheet multi-selection lands when stamped at `anchor`.
##
## The selected sheet frames are read as cells of a LOCAL VIRTUAL ODD-Q LATTICE -- the same
## odd-column-drops convention the map uses -- so a 2x2 block of sheet frames describes a 2x2 block
## of hexes rather than a rectangle of pixels. Each frame's position is converted to an AXIAL delta
## from the selection's own top-left frame, because axial deltas are translation-invariant and
## offset deltas are not: the identical `(dx, dy)` lands on a different relative hex depending on
## whether the anchor column is odd or even, which would silently reshape a stamp as the author
## moved it one column sideways.
##
## Returns `{axialDelta: tileID}`, which is exactly `WorldMapBrushes.stampHex`'s own pattern shape.
## Frames the author did not select are simply absent, and an absent key is a hole in the stamp.
static func stampPattern(sheetCells: Array, tileIDs: Array) -> Dictionary:
	var pattern := {}
	if sheetCells.is_empty() or sheetCells.size() != tileIDs.size():
		return pattern
	var originCell: Vector2i = sheetCells[0]
	for entry in sheetCells:
		var cell: Vector2i = entry
		if cell.y < originCell.y or (cell.y == originCell.y and cell.x < originCell.x):
			originCell = cell
	var originAxial := WorldMapHexGrid.offsetToAxial(originCell)
	for index in sheetCells.size():
		var delta := WorldMapHexGrid.offsetToAxial(sheetCells[index] as Vector2i) - originAxial
		pattern[delta] = str(tileIDs[index])
	return pattern


## The map cells a stamp pattern covers when anchored at `anchor`, in the same axial arithmetic
## `WorldMapBrushes.stampHex` will use to apply it -- so the preview and the stamp cannot disagree
## about where the pattern lands across a parity boundary.
static func stampCells(anchor: Vector2i, pattern: Dictionary, lattice: Vector2i) -> Array[Vector2i]:
	var anchorAxial := WorldMapHexGrid.offsetToAxial(anchor)
	var cells: Array[Vector2i] = []
	for delta in pattern:
		cells.append(WorldMapHexGrid.axialToOffset(anchorAxial + (delta as Vector2i)))
	return clip(cells, lattice)


## Deduplicated, in first-seen order, and restricted to cells the lattice holds. A zero lattice
## means "unbounded", matching the convention the picker and the grid overlay already use.
static func clip(cells: Array, lattice: Vector2i) -> Array[Vector2i]:
	var result: Array[Vector2i] = []
	var seen := {}
	for entry in cells:
		var cell: Vector2i = entry
		if seen.has(cell):
			continue
		seen[cell] = true
		if lattice.x > 0 and lattice.y > 0:
			if not WorldMapHexGrid.contains(cell, lattice.x, lattice.y):
				continue
		result.append(cell)
	return result


## How the brush size reads to a person: the number of cells a full disc covers, not the ring
## count. Radius 0 is "1 hex", radius 1 is "7 hexes", radius 2 is "19 hexes".
static func radiusLabel(radius: int) -> String:
	var count := 1
	for ring in range(1, maxi(radius, 0) + 1):
		count += 6 * ring
	return "1 hex" if count == 1 else "%d hexes" % count
