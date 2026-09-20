## Symmetric conservative supercover line of sight for flat-top hex cells.

class_name LineOfSight

const HexGridScript = preload("res://src/board/HexGrid.gd")
const SQRT_THREE := 1.7320508075688772
const HEX_APOTHEM := SQRT_THREE * 0.5
const EPSILON := 0.000001
const HEX_NORMALS: Array[Vector2] = [
	Vector2(0.0, 1.0),
	Vector2(SQRT_THREE * 0.5, 0.5),
	Vector2(SQRT_THREE * 0.5, -0.5),
	Vector2(0.0, -1.0),
	Vector2(-SQRT_THREE * 0.5, -0.5),
	Vector2(-SQRT_THREE * 0.5, 0.5),
]


## Pure geometry, keyed by axial displacement and source column parity. Nothing
## about occupancy, height or board contents may enter this dictionary: those
## are asked per query by the caller's blocker callable. Retention is bounded;
## the whole table is dropped rather than evicted one entry at a time, because
## every entry is equally cheap to rebuild.
const MAX_RAY_TEMPLATES := 4096
static var _rayTemplates: Dictionary = {}


## Diagnostics for the cost probe. Not an input to any gameplay decision.
static func rayTemplateStats() -> Dictionary:
	return {"templates": _rayTemplates.size(), "capacity": MAX_RAY_TEMPLATES}


static func clearRayTemplates() -> void:
	_rayTemplates.clear()


static func supercoverCells(fromPos: Vector2i, toPos: Vector2i) -> Array[Vector2i]:
	## Every cell whose closed hex touches the centre-to-centre segment. Source
	## and target are included in this geometry query; visibility checks skip them.
	var result: Array[Vector2i] = []
	for entry: Dictionary in _supercoverEntries(fromPos, toPos):
		result.append(entry["cell"])
	return result


static func hasLoS(fromPos: Vector2i, toPos: Vector2i, isBlocker: Callable) -> bool:
	for entry: Dictionary in _supercoverEntries(fromPos, toPos):
		var cell: Vector2i = entry["cell"]
		if cell == fromPos or cell == toPos:
			continue
		if bool(isBlocker.call(cell)):
			return false
	return true


static func hasHeightAwareLoS(
		fromPos: Vector2i,
		toPos: Vector2i,
		sourceEyeHeight: float,
		targetEyeHeight: float,
		getBlockerTop: Callable,
		epsilon: float = 0.001) -> bool:
	## A touched cell blocks when its top rises above the ray anywhere in the
	## segment interval inside that cell. Interpolation uses actual hex-centre
	## geometry and the clipped entry/exit points, not offset-vector lengths.
	for entry: Dictionary in _supercoverEntries(fromPos, toPos):
		var cell: Vector2i = entry["cell"]
		if cell == fromPos or cell == toPos:
			continue
		var enterHeight := lerpf(sourceEyeHeight, targetEyeHeight, float(entry["enter_t"]))
		var exitHeight := lerpf(sourceEyeHeight, targetEyeHeight, float(entry["exit_t"]))
		var lowestRayHeight := minf(enterHeight, exitHeight)
		if float(getBlockerTop.call(cell)) > lowestRayHeight + epsilon:
			return false
	return true


static func _supercoverEntries(fromPos: Vector2i, toPos: Vector2i) -> Array[Dictionary]:
	## Cell centres are an affine image of axial coordinates, so the touched set,
	## its entry/exit parameters and its order depend only on the axial
	## displacement and on the source column's parity -- parity alone decides how
	## an axial offset lands in storage rows, and the order tie-break reads those
	## rows. Building the answer once per displacement and translating it also
	## makes the query exactly translation-invariant, which computing centres at
	## absolute coordinates only approximated.
	if fromPos == toPos:
		return [{"cell": fromPos, "enter_t": 0.0, "exit_t": 1.0}]
	var fromAxial := HexGridScript.offsetToAxial(fromPos)
	var toAxial := HexGridScript.offsetToAxial(toPos)
	var key := Vector3i(
		toAxial.x - fromAxial.x, toAxial.y - fromAxial.y, fromPos.x & 1)
	var template: Array = _rayTemplates.get(key, [])
	if template.is_empty():
		template = _buildRayTemplate(key)
		if _rayTemplates.size() >= MAX_RAY_TEMPLATES:
			_rayTemplates.clear()
		_rayTemplates[key] = template
	var entries: Array[Dictionary] = []
	for entry: Dictionary in template:
		entries.append({
			"cell": fromPos + Vector2i(entry["delta"]),
			"enter_t": entry["enter_t"],
			"exit_t": entry["exit_t"],
		})
	return entries


static func _buildRayTemplate(key: Vector3i) -> Array:
	var origin := Vector2i(key.z, 0)
	var originAxial := HexGridScript.offsetToAxial(origin)
	var target := HexGridScript.axialToOffset(
		originAxial + Vector2i(key.x, key.y))
	var start := _cellCenter(origin)
	var finish := _cellCenter(target)
	var entries: Array[Dictionary] = []
	var candidateRadius := HexGridScript.distance(origin, target) + 1
	for cell: Vector2i in HexGridScript.disc(origin, candidateRadius):
		var interval := _segmentHexInterval(start, finish, _cellCenter(cell))
		if interval.x < 0.0:
			continue
		entries.append({
			"cell": cell,
			"enter_t": interval.x,
			"exit_t": interval.y,
		})
	entries.sort_custom(func(a: Dictionary, b: Dictionary) -> bool:
		var delta := float(a["enter_t"]) - float(b["enter_t"])
		if absf(delta) > EPSILON:
			return delta < 0.0
		var aCell: Vector2i = a["cell"]
		var bCell: Vector2i = b["cell"]
		return aCell.y < bCell.y or (aCell.y == bCell.y and aCell.x < bCell.x)
	)
	var template: Array = []
	for entry: Dictionary in entries:
		template.append({
			"delta": Vector2i(entry["cell"]) - origin,
			"enter_t": entry["enter_t"],
			"exit_t": entry["exit_t"],
		})
	return template


static func _cellCenter(cell: Vector2i) -> Vector2:
	var axial := HexGridScript.offsetToAxial(cell)
	return Vector2(1.5 * float(axial.x), SQRT_THREE * (float(axial.y) + float(axial.x) * 0.5))


static func _segmentHexInterval(start: Vector2, finish: Vector2, center: Vector2) -> Vector2:
	var delta := finish - start
	var relativeStart := start - center
	var enter := 0.0
	var exit := 1.0
	for normal: Vector2 in HEX_NORMALS:
		var numerator := HEX_APOTHEM + EPSILON - normal.dot(relativeStart)
		var denominator := normal.dot(delta)
		if absf(denominator) <= EPSILON:
			if numerator < 0.0:
				return Vector2(-1.0, -1.0)
			continue
		var boundary := numerator / denominator
		if denominator > 0.0:
			exit = minf(exit, boundary)
		else:
			enter = maxf(enter, boundary)
		if enter > exit + EPSILON:
			return Vector2(-1.0, -1.0)
	if exit < -EPSILON or enter > 1.0 + EPSILON:
		return Vector2(-1.0, -1.0)
	return Vector2(clampf(enter, 0.0, 1.0), clampf(exit, 0.0, 1.0))
