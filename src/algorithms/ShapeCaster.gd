## Stable flat-top hex footprints in odd-column offset coordinates.

class_name ShapeCaster

const HexGridScript = preload("res://src/board/HexGrid.gd")


static func getCircle(center: Vector2i, radius: int) -> Array[Vector2i]:
	return HexGridScript.disc(center, radius)


static func getCross(center: Vector2i, radius: int) -> Array[Vector2i]:
	if radius < 0:
		return []
	var axialCenter := HexGridScript.offsetToAxial(center)
	var result: Array[Vector2i] = [center]
	for direction: Vector2i in HexGridScript.AXIAL_NEIGHBOURS:
		for distance in range(1, radius + 1):
			result.append(HexGridScript.axialToOffset(axialCenter + direction * distance))
	result.sort_custom(_rowMajorLess)
	return result


static func getLine(origin: Vector2i, target: Vector2i, length: int) -> Array[Vector2i]:
	## Projects along the closest selected axial direction and excludes the caster.
	if origin == target or length <= 0:
		return []
	var axialOrigin := HexGridScript.offsetToAxial(origin)
	var direction := _directionToward(origin, target)
	var result: Array[Vector2i] = []
	for distance in range(1, length + 1):
		result.append(HexGridScript.axialToOffset(axialOrigin + direction * distance))
	return result


static func _directionToward(origin: Vector2i, target: Vector2i) -> Vector2i:
	var bestDirection: Vector2i = HexGridScript.AXIAL_NEIGHBOURS[0]
	var bestDistance := 2147483647
	var axialOrigin := HexGridScript.offsetToAxial(origin)
	for direction: Vector2i in HexGridScript.AXIAL_NEIGHBOURS:
		var neighbor := HexGridScript.axialToOffset(axialOrigin + direction)
		var distance := HexGridScript.distance(neighbor, target)
		if distance < bestDistance:
			bestDistance = distance
			bestDirection = direction
	return bestDirection


static func _rowMajorLess(a: Vector2i, b: Vector2i) -> bool:
	return a.y < b.y or (a.y == b.y and a.x < b.x)
