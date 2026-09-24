## Shared footprint projection for the impact and area family.
##
## THE PROBLEM. The sketch lays its area studies out on a flat rectangle around
## `T`. A hex footprint is neither flat-sided nor always centred on the target:
## a cross has arms and gaps, a line runs from the caster. Placing the sketch's
## points radially at a scale would drop cubes on cells the spell did not hit,
## which advertises damage that did not happen.
##
## THE PROJECTION. Each authored ground point keeps its direction from the
## pattern's origin; only its distance is remapped. `areaPoint(dx, dz)` takes
## the point's share of the study's authored radius (`areaReferenceRadius`) and
## places it at that share of the footprint's reach in that direction, measured
## in `prepare()` from the affected cells. So a pattern fills a disc as a disc,
## stretches along a cross's arms and pulls in between them, and runs along a
## line. Nothing is added or removed: the study keeps its counts, its order and
## its internal layout, and only the ground it lands on changes shape.
##
## `AREA_SCALING` decides how far. Under `spread` the pattern reaches the
## footprint's edge. Under `none` it keeps its authored size and is only pulled
## in where the footprint is smaller than it. Either way nothing lands outside
## the affected cells: a final guard walks any point that still would back
## toward the origin.
##
## Heights, cube sizes and the chips of each burst stay at the plain cube
## scale. Rubble is local to the cube that made it, and is only held inside the
## footprint, never spread with it.

extends "res://src/presentation/effects/cube_placeholders/shared/CubePlaceholderComposition.gd"

const Profile = preload("res://src/presentation/effects/cube_placeholders/shared/CubePlaceholderProfile.gd")

const REFERENCE_DURATION_S := 4.8
const BATTLE_DURATION_S := 2.0
## Directions the footprint reach is measured in.
const DIRECTIONS := 48
## Share of the measured reach a pattern may use, so a cube's centre stays
## inside its cell rather than on the border.
const FILL := 0.85
## Share a rubble chip may use: chips may reach nearer the edge than the
## pattern, never past it.
const CHIP_FILL := 0.95
## The union-of-discs estimate of a hex: its inscribed radius as a share of
## the smaller cell half-extent.
const CELL_DISC := 0.9

var _origins: Array[Vector3] = []
var _reaches: Array[PackedFloat32Array] = []


func binding() -> String:
	return BINDING_AREA


func referenceDurationSeconds() -> float:
	return REFERENCE_DURATION_S


func battleDurationSeconds() -> float:
	return BATTLE_DURATION_S


## Measures, per anchor, how far the footprint reaches in each direction from
## the pattern's origin: the anchor if it stands on an affected cell, else the
## affected cell nearest it (a line spell's centre need not be on its line).
## Estimated as the union of one disc per cell, which never overstates the
## reach, and exact enough for a pattern that only uses 85% of it.
func prepare(frames: Array) -> void:
	_origins.clear()
	_reaches.clear()
	for frame: CubePlaceholderFrame in frames:
		var footprint := frame.footprint
		if footprint == null or footprint.isEmpty():
			_origins.append(frame.target)
			_reaches.append(PackedFloat32Array())
			continue
		var origin := frame.target
		if not footprint.containsWorldPoint(origin):
			var best := INF
			for centre: Vector3 in footprint.world_positions:
				var distance := _flat(centre - frame.target).length()
				if distance < best:
					best = distance
					origin = Vector3(centre.x, frame.target.y, centre.z)
		var disc := minf(footprint.cell_width, footprint.cell_height) * 0.5 * CELL_DISC
		var reaches := PackedFloat32Array()
		reaches.resize(DIRECTIONS)
		for index: int in range(DIRECTIONS):
			var angle := float(index) / float(DIRECTIONS) * TAU
			var direction := Vector3(cos(angle), 0.0, sin(angle))
			var reach := 0.0
			for centre: Vector3 in footprint.world_positions:
				var relative := _flat(centre - origin)
				var along := relative.dot(direction)
				var across := relative.cross(direction).length()
				if across < disc and along > -disc:
					reach = maxf(reach, along + sqrt(disc * disc - across * across))
			reaches[index] = reach
		_origins.append(origin)
		_reaches.append(reaches)


## The pattern's origin on the ground for this anchor.
func areaOrigin(frame: CubePlaceholderFrame) -> Vector3:
	return _origins[frame.anchorIndex] if frame.anchorIndex < _origins.size() else frame.target


## The ground point for a study point `dx` forward and `dz` beside `T`, in
## sketch units, projected onto the footprint as the header describes.
func areaPoint(frame: CubePlaceholderFrame, dx: float, dz: float) -> Vector3:
	var scale := frame.cubeScale()
	var offset := frame.forward * (dx * scale) + frame.side * (dz * scale)
	if frame.anchorIndex >= _reaches.size() or _reaches[frame.anchorIndex].is_empty():
		return frame.target + offset
	var origin := _origins[frame.anchorIndex]
	var radius := offset.length()
	if radius < 0.0001:
		return origin
	var authored := maxf(areaReferenceRadius(), 0.0001) * scale
	var share := minf(radius / authored, 1.0)
	var limit := _reachToward(frame.anchorIndex, offset) * FILL
	var placed := share * limit if frame.areaScale > 1.0 else minf(radius, share * limit)
	return _guard(frame, origin + offset / radius * placed)


## Holds a rubble chip inside the footprint: pulls it in only if it would
## pass the edge.
func clampInside(frame: CubePlaceholderFrame, point: Vector3) -> Vector3:
	if frame.anchorIndex >= _reaches.size() or _reaches[frame.anchorIndex].is_empty():
		return point
	var origin := _origins[frame.anchorIndex]
	var offset := _flat(point - origin)
	var radius := offset.length()
	if radius < 0.0001:
		return point
	var limit := _reachToward(frame.anchorIndex, offset) * CHIP_FILL
	if radius <= limit:
		return point
	var held := origin + offset / radius * limit
	held.y = point.y
	return _guard(frame, held)


## The sketch's `debris`, with each chip's ground position held inside the
## footprint and positions at the cube scale.
func areaDebris(
		frame: CubePlaceholderFrame, t: float, start: float, center: Vector3,
		n: int, reach: float, s: float, duration: float, idBase: int, role: int) -> void:
	if t < start or t > start + duration:
		return
	var q := phase(t, start, start + duration)
	var sc := frame.cubeScale()
	for i: int in range(n):
		var a := frame.rnd(i + 42) * TAU
		var r := q * reach * (0.4 + frame.rnd(i + 120))
		var ground := center + frame.forward * (cos(a) * r * sc) + frame.side * (sin(a) * r * sc)
		ground = clampInside(frame, ground)
		var lift := 0.08 + sin(q * PI) * (0.2 + frame.rnd(i + 80) * 0.5)
		frame.cube(idBase + i, ground + frame.up * (lift * sc), s * (1.0 - q * 0.9), q * 6.0 + i, role)


## A point `y` sketch units above a ground point, at the cube scale.
static func above(frame: CubePlaceholderFrame, ground: Vector3, y: float) -> Vector3:
	return ground + frame.up * (y * frame.cubeScale())


func _reachToward(anchor: int, offset: Vector3) -> float:
	var reaches := _reaches[anchor]
	var angle := fposmod(atan2(offset.z, offset.x), TAU)
	var position := angle / TAU * float(DIRECTIONS)
	var low := int(floor(position)) % DIRECTIONS
	var high := (low + 1) % DIRECTIONS
	var blend: float = position - floor(position)
	# The smaller neighbour decides where the two differ a lot, so an arm's
	# edge never lets a point slip into the gap beside it.
	var lower := minf(reaches[low], reaches[high])
	return lerpf(reaches[low], reaches[high], blend) if absf(reaches[low] - reaches[high]) < 0.5 else lower


## Walks a point back toward the origin until it stands on an affected cell.
## The projection makes this rare; it is what makes "never outside" a
## guarantee rather than an estimate.
func _guard(frame: CubePlaceholderFrame, point: Vector3) -> Vector3:
	var footprint := frame.footprint
	if footprint == null or footprint.isEmpty() or footprint.containsWorldPoint(point):
		return point
	var origin := _origins[frame.anchorIndex]
	var held := point
	for _step: int in range(8):
		held = origin.lerp(held, 0.8)
		held.y = point.y
		if footprint.containsWorldPoint(held):
			return held
	return Vector3(origin.x, point.y, origin.z)


static func _flat(vector: Vector3) -> Vector3:
	return Vector3(vector.x, 0.0, vector.z)
