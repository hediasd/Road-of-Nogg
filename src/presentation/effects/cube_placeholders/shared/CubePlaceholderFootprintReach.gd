## How far an affected footprint reaches from an origin, in each horizontal
## direction. Lets a shape spread over an area stay on the cells the spell hit:
## a point is kept within the reach in its own direction, so a footprint
## clipped by the board edge, or a cross with gaps between its arms, never
## receives a cube outside it.
##
## Estimated as the union of one disc per affected cell (0.9 of the smaller
## cell half-extent), which never overstates the reach. Measured once per cast,
## in `prepare`, never while sampling.

class_name CubePlaceholderFootprintReach
extends RefCounted

const DIRECTIONS := 48
const CELL_DISC := 0.9

var origin: Vector3 = Vector3.ZERO
var reaches: PackedFloat32Array = PackedFloat32Array()


## Null when there is no footprint to respect.
static func measure(footprint: HexVfxFootprint, from: Vector3) -> CubePlaceholderFootprintReach:
	if footprint == null or footprint.isEmpty():
		return null
	var result := CubePlaceholderFootprintReach.new()
	result.origin = from
	var disc := minf(footprint.cell_width, footprint.cell_height) * 0.5 * CELL_DISC
	result.reaches.resize(DIRECTIONS)
	for index: int in range(DIRECTIONS):
		var angle := float(index) / float(DIRECTIONS) * TAU
		var direction := Vector3(cos(angle), 0.0, sin(angle))
		var reach := 0.0
		for centre: Vector3 in footprint.world_positions:
			var relative := Vector3(centre.x - from.x, 0.0, centre.z - from.z)
			var along := relative.dot(direction)
			var across := relative.cross(direction).length()
			if across < disc and along > -disc:
				reach = maxf(reach, along + sqrt(disc * disc - across * across))
		result.reaches[index] = reach
	return result


## The reach toward a horizontal offset. Where neighbouring directions differ
## a lot (an arm's edge), the smaller one decides.
func toward(offset: Vector3) -> float:
	var angle := fposmod(atan2(offset.z, offset.x), TAU)
	var position := angle / TAU * float(DIRECTIONS)
	var low := int(floor(position)) % DIRECTIONS
	var high := (low + 1) % DIRECTIONS
	var blend: float = position - floor(position)
	if absf(reaches[low] - reaches[high]) < 0.5:
		return lerpf(reaches[low], reaches[high], blend)
	return minf(reaches[low], reaches[high])
