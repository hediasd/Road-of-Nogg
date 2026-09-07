## The hex lattice: where a cell sits in the world, which cells touch it, how far apart two are,
## which cell a world point falls in, and how a lattice is inscribed in a square map.
##
## Shared lattice arithmetic lives in the headless `HexGrid`; this presentation wrapper retains
## editor dimensions, world conversion, cube rounding, and its established public API. The one
## failure mode this geometry has is column-parity bugs -- arithmetic that is right on even
## columns and half a row out on odd ones -- so no caller performs the parity step itself.
##
## THREE COORDINATE SPACES, and knowing which is which is most of the work:
##
##  - **Offset `(col, row)`** is STORAGE and the public API. A lattice is a plain `cols x rows`
##    rectangle, which is what `WorldMapTileData`'s dense RLE rows, the brushes, the history's
##    `Vector2i` keys and the baker all already index by. Odd columns are dropped half a row.
##  - **Axial `(q, r)`** is the MATHS. Neighbours and distance are trivial in it and horrible in
##    offset.
##  - **Cube `(x, y, z)` with `x + y + z = 0`** exists only inside `roundAxial`, because correct
##    rounding is only expressible there.
##
## The cycle file says to store axial. This stores OFFSET and converts, which reaches the same
## goal by the other route: what that instruction was protecting against is parity arithmetic
## scattered through callers, and centralising the conversion prevents it just as completely --
## while leaving the dense array a rectangle and every existing `Vector2i` caller untouched.
## Storing axial would have made the RLE rows ragged and rewritten plumbing that has nothing
## wrong with it.
##
## GEOMETRY, settled in `docs/plans/worldmap-hex-authoring.md`. Flat-top hexes, pre-stretched so
## they read regular at pitch 60 -- which is what makes the world footprint square. One hex is
## two world units wide and two tall; columns advance 1.5 units; rows advance 2; odd columns drop
## 1. The 16 px world unit is unchanged, so a hex is 32 px of art.

class_name WorldMapHexGrid
extends RefCounted

const HexGridScript = preload("res://src/board/HexGrid.gd")

## World units. Width is vertex-to-vertex horizontally, height flat-to-flat vertically.
const HEX_WIDTH := 2.0
const HEX_HEIGHT := 2.0
## Three quarters of the width -- flat-top columns interlock rather than abut.
const COL_ADVANCE := 1.5
const ROW_ADVANCE := 2.0
## Half a row. THE convention of this file: it is ODD columns that drop, not even ones. Both
## conventions exist in the wild and picking one silently is how a half-row shift appears at a
## map edge months later.
const ODD_COL_DROP := 1.0

## Axial steps to the six neighbours, in the order they are returned. Flat-top, so there is no
## neighbour directly above or below in axial terms -- the six are E, NE, NW, W, SW, SE read on
## screen.
const AXIAL_NEIGHBOURS := HexGridScript.AXIAL_NEIGHBOURS


## Offset -> axial. `(col - (col & 1))` is always even, so the halving is exact and needs no
## rounding decision -- including for negative columns, where a naive `col / 2` would not be.
static func offsetToAxial(cell: Vector2i) -> Vector2i:
	return HexGridScript.offsetToAxial(cell)


static func axialToOffset(axial: Vector2i) -> Vector2i:
	return HexGridScript.axialToOffset(axial)


## The centre of a cell, in REGION-LOCAL world units, with the lattice's bounding box starting at
## the origin. So cell (0, 0) is centred at (1, 1) rather than at (0, 0): its box is the square
## from (0, 0) to (2, 2).
static func cellCentre(cell: Vector2i) -> Vector2:
	return Vector2(
		COL_ADVANCE * float(cell.x) + HEX_WIDTH * 0.5,
		ROW_ADVANCE * float(cell.y) + (ODD_COL_DROP if (cell.x & 1) == 1 else 0.0)
			+ HEX_HEIGHT * 0.5
	)


## The cell a region-local world point falls in. Exact on hex boundaries in the sense that
## matters: a point on an edge resolves to one of the two cells sharing it, never to a third.
static func worldToCell(local: Vector2) -> Vector2i:
	# Back to a centre-origin frame, then invert `cellCentre`'s two expressions:
	#   x = 1.5 q                      ->  q = x / 1.5
	#   z = 2 r + q  (offset drop folded into axial)  ->  r = (z - q) / 2
	var centred := local - Vector2(HEX_WIDTH * 0.5, HEX_HEIGHT * 0.5)
	var qf := centred.x / COL_ADVANCE
	var rf := (centred.y - qf) / ROW_ADVANCE
	return axialToOffset(roundAxial(qf, rf))


## Rounds a fractional axial coordinate to the nearest cell.
##
## ROUNDING EACH AXIS INDEPENDENTLY IS WRONG, and wrong in a way that looks like an off-by-one in
## the picker rather than a coordinate bug: it lands one cell out along every hex seam, so it is
## correct in the middle of a hex and fails exactly where a user aims when they are being precise.
##
## The fix is to round in cube space, where the three coordinates must satisfy `x + y + z = 0`.
## Independent rounding can violate that; restoring it by recomputing the component that moved
## FURTHEST -- the least trustworthy of the three -- is what lands on the true nearest hex.
static func roundAxial(qf: float, rf: float) -> Vector2i:
	var xf := qf
	var zf := rf
	var yf := -xf - zf

	var rx: float = round(xf)
	var ry: float = round(yf)
	var rz: float = round(zf)

	var dx := absf(rx - xf)
	var dy := absf(ry - yf)
	var dz := absf(rz - zf)

	if dx > dy and dx > dz:
		rx = -ry - rz
	elif dy > dz:
		ry = -rx - rz
	else:
		rz = -rx - ry
	return Vector2i(int(rx), int(rz))


## The six cells sharing an edge with this one. Hexes have no diagonal neighbours, which is why
## hex adjacency has none of the corner ambiguity a square grid has.
static func neighbours(cell: Vector2i) -> Array[Vector2i]:
	return HexGridScript.neighbours(cell)


## Steps along the lattice between two cells. In cube space this is the largest of the three
## absolute component differences, which is the same as half their sum.
static func distance(a: Vector2i, b: Vector2i) -> int:
	return HexGridScript.distance(a, b)


## Whether a cell is inside a `cols x rows` lattice.
static func contains(cell: Vector2i, cols: int, rows: int) -> bool:
	return cell.x >= 0 and cell.y >= 0 and cell.x < cols and cell.y < rows


## The world-unit bounding box a `cols x rows` lattice spans.
##
## The odd-column drop only adds height when there IS an odd column, so a single-column lattice
## is shorter than the general formula suggests. Small, and exactly the kind of edge case a
## one-column test map would trip over.
static func latticeExtent(cols: int, rows: int) -> Vector2:
	if cols <= 0 or rows <= 0:
		return Vector2.ZERO
	var drop := ODD_COL_DROP if cols >= 2 else 0.0
	return Vector2(
		COL_ADVANCE * float(cols - 1) + HEX_WIDTH,
		ROW_ADVANCE * float(rows - 1) + HEX_HEIGHT + drop
	)


## The largest lattice that fits inside a square of `sideUnits`. The remainder is MARGIN, and the
## margin is a bake concern rather than data -- only hexes exist as cells, so nothing downstream
## ever has to ask whether a cell is a hex or filler.
static func latticeForSquare(sideUnits: float) -> Vector2i:
	if sideUnits < HEX_WIDTH or sideUnits < HEX_HEIGHT:
		return Vector2i.ZERO
	var cols := int(floor((sideUnits - HEX_WIDTH) / COL_ADVANCE)) + 1
	var drop := ODD_COL_DROP if cols >= 2 else 0.0
	var rows := int(floor((sideUnits - HEX_HEIGHT - drop) / ROW_ADVANCE)) + 1
	return Vector2i(maxi(cols, 0), maxi(rows, 0))


## Whether a lattice fills its square exactly, leaving no margin at all. True when
## `1.5C + 0.5 == 2R + 1`, i.e. `3C = 4R + 1`.
static func isExactSquare(cols: int, rows: int) -> bool:
	if cols < 2 or rows < 1:
		return false
	return 3 * cols == 4 * rows + 1


## Lattices that fill a square exactly, smallest first, for a "new map" dialog to offer.
##
## The largest entry within the default bound is 103 x 77, which spans 155 world units -- and
## that is not a coincidence worth losing: 155 tiles is exactly the region width
## `WORLDMAP_DESIGN.md` section 3 says the reference framing needs before the plane's own edges
## start showing. The hex lattice and the framing constraint agree on the same number.
static func exactSquareLattices(maxSideUnits := 160.0) -> Array[Vector2i]:
	var out: Array[Vector2i] = []
	var rows := 1
	while true:
		var cols := (4 * rows + 1)
		if cols % 3 != 0:
			rows += 1
			continue
		cols /= 3
		var extent := latticeExtent(cols, rows)
		if extent.x > maxSideUnits:
			break
		if cols >= 2:
			out.append(Vector2i(cols, rows))
		rows += 1
	return out
