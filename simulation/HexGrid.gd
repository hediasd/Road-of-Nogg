## Headless flat-top hex lattice mathematics.
##
## Public cells use odd-column offset coordinates so dense Matrix storage stays
## rectangular. Axial coordinates exist only inside this boundary. Callers must
## not duplicate the parity conversion.

class_name HexGrid
extends RefCounted

## E, NE, NW, W, SW, SE in axial coordinates. This order is deterministic and
## matches the world-map editor's established screen-space neighbour order.
const AXIAL_NEIGHBOURS: Array[Vector2i] = [
	Vector2i(1, 0), Vector2i(1, -1), Vector2i(0, -1),
	Vector2i(-1, 0), Vector2i(-1, 1), Vector2i(0, 1),
]


static func offsetToAxial(cell: Vector2i) -> Vector2i:
	return Vector2i(cell.x, cell.y - (cell.x - (cell.x & 1)) / 2)


static func axialToOffset(cell: Vector2i) -> Vector2i:
	return Vector2i(cell.x, cell.y + (cell.x - (cell.x & 1)) / 2)


static func neighbours(cell: Vector2i) -> Array[Vector2i]:
	var axial := offsetToAxial(cell)
	var result: Array[Vector2i] = []
	for step: Vector2i in AXIAL_NEIGHBOURS:
		result.append(axialToOffset(axial + step))
	return result


static func distance(a: Vector2i, b: Vector2i) -> int:
	var axialA := offsetToAxial(a)
	var axialB := offsetToAxial(b)
	var dq := axialA.x - axialB.x
	var dr := axialA.y - axialB.y
	return int((absi(dq) + absi(dq + dr) + absi(dr)) / 2)


## Every cell at most `radius` steps from `center`, sorted by storage row then
## column. A negative radius has no valid footprint.
static func disc(center: Vector2i, radius: int) -> Array[Vector2i]:
	if radius < 0:
		return []
	var axialCenter := offsetToAxial(center)
	var result: Array[Vector2i] = []
	for dq in range(-radius, radius + 1):
		var minimumR := maxi(-radius, -dq - radius)
		var maximumR := mini(radius, -dq + radius)
		for dr in range(minimumR, maximumR + 1):
			result.append(axialToOffset(axialCenter + Vector2i(dq, dr)))
	result.sort_custom(_rowMajorLess)
	return result


static func _rowMajorLess(a: Vector2i, b: Vector2i) -> bool:
	if a.y != b.y:
		return a.y < b.y
	return a.x < b.x
