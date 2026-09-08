## The cells a cast actually affects, and where they are in the world.
##
## THIS IS THE ARGUMENT THE SQUARE PATH NEVER HAD. `GodotVisualAdapter` drives a storm with
## `setFootprint(radiusInTiles, ...)`, and every area effect turns that into a square extent --
## `diameter := radius * 2 + 1`, the bounding box of a Manhattan diamond. On a hex board that is
## wrong twice over: the affected set is a hex disc rather than a diamond, and its bounding box is
## not square, because columns advance three quarters of a cell width while rows advance a whole
## cell height.
##
## So a hex cast carries the RESOLVED CELLS themselves. Not a radius the presentation re-derives a
## shape from -- the actual ordered list HXB-7 produced, which is the only thing that can be
## trusted to agree with what the simulation resolved.
##
## EMPTY CELLS ARE PART OF THE FOOTPRINT. The bounds below span every affected cell, not only the
## ones that happened to contain a target. A seven-cell blast with one unit standing in it is
## seven cells wide; collapsing it to that unit's body is the specific failure the item names, and
## it is what makes a spell look like it missed the ground it actually hit.

class_name HexVfxFootprint
extends RefCounted

const HexBattleLayoutScript = preload("res://src/presentation/battle/HexBattleLayout.gd")

## The affected cells, in the order the resolver produced them. Order is preserved rather than
## sorted: a line spell's cells run from the caster outward, and an effect that animates along its
## footprint needs that direction.
var cells: Array[Vector2i] = []

## One world-space centre per cell, index-aligned with `cells`.
var world_positions: Array[Vector3] = []

## The world-space box every affected cell fits inside, corners included -- not centre-to-centre.
var bounds: AABB = AABB()

## Cell metrics the footprint was resolved at, so a consumer sizing geometry against one cell
## (a wash, a ring) does not have to re-derive them from the map.
var cell_width: float = 2.0
var cell_height: float = 2.0


## Builds a footprint from resolved cells and the map they were resolved on.
##
## `bounds` is grown by each cell's POLYGON rather than its centre, so a wash sized to it covers
## the affected hexes completely instead of stopping half a cell short at every edge.
static func fromCells(resolvedCells: Array, map: BattleMapDefinition) -> HexVfxFootprint:
	var footprint := HexVfxFootprint.new()
	footprint.cell_width = map.cellWidth
	footprint.cell_height = map.cellHeight
	if resolvedCells.is_empty():
		return footprint

	var layout: HexBattleLayout = HexBattleLayoutScript.new(map)
	var grown := false
	for value in resolvedCells:
		var cell: Vector2i = value
		footprint.cells.append(cell)
		var centre: Vector3 = layout.cellCenter(cell)
		footprint.world_positions.append(centre)
		for corner: Vector3 in layout.cellPolygon(cell):
			if not grown:
				footprint.bounds = AABB(corner, Vector3.ZERO)
				grown = true
			else:
				footprint.bounds = footprint.bounds.expand(corner)
	return footprint


func isEmpty() -> bool:
	return cells.is_empty()


func cellCount() -> int:
	return cells.size()


## The footprint's centre in world space -- the middle of the affected ground, which is not the
## impact cell when a shape is one-sided (a line runs away from its caster).
func center() -> Vector3:
	if cells.is_empty():
		return Vector3.ZERO
	return bounds.position + bounds.size * 0.5


## The horizontal span, largest axis. What an effect sizing a single radial mesh should use, since
## a hex footprint's X and Z spans differ and a mesh drawn to the smaller one clips the ground it
## is supposed to cover.
func worldDiameter() -> float:
	return maxf(bounds.size.x, bounds.size.z)


## The tile radius the donor profiles calibrate DENSITY against -- particle counts, emission
## rates, layer counts. Those numbers were tuned against a tile count, so they keep reading a
## tile-ish radius even on hex, where the EXTENT comes from `bounds` instead.
##
## Derived from the cell count rather than from the world span, because that is the quantity the
## donors' own `sqrt(area)` density curves were fitted to. A hex disc of radius R holds
## `3R(R+1)+1` cells, so this inverts that.
func densityRadiusHint() -> int:
	var count := float(cells.size())
	if count <= 1.0:
		return 1
	# 3R^2 + 3R + 1 = count  ->  R = (-3 + sqrt(12 * count - 3)) / 6
	var radius := (-3.0 + sqrt(maxf(12.0 * count - 3.0, 0.0))) / 6.0
	return maxi(int(round(radius)), 1)


## Whether a world-space point lies on one of the affected cells.
##
## Exact for flat-top hexes: in per-cell normalised coordinates the hexagon's boundary in the
## first quadrant is the segment from (1, 0) to (0.5, 1), which is `2X + Z = 2`, and the flat top
## is `Z = 1`. A point satisfying both, mirrored into the first quadrant by absolute value, is
## inside. No angle comparison and so no wrap-around case.
func containsWorldPoint(point: Vector3) -> bool:
	var halfWidth := cell_width * 0.5
	var halfHeight := cell_height * 0.5
	for centre: Vector3 in world_positions:
		var x := absf(point.x - centre.x) / halfWidth
		var z := absf(point.z - centre.z) / halfHeight
		if z <= 1.0 and 2.0 * x + z <= 2.0:
			return true
	return false
