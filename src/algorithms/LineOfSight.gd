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
	if fromPos == toPos:
		return [{"cell": fromPos, "enter_t": 0.0, "exit_t": 1.0}]
	var start := _cellCenter(fromPos)
	var finish := _cellCenter(toPos)
	var entries: Array[Dictionary] = []
	var candidateRadius := HexGridScript.distance(fromPos, toPos) + 1
	for cell: Vector2i in HexGridScript.disc(fromPos, candidateRadius):
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
	return entries


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
