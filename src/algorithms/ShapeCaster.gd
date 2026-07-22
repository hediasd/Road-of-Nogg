## ShapeCaster — Math algorithms for determining Area-of-Effect grid coordinates.
## Returns arrays of absolute Vector2i coordinates based on shapes.

class_name ShapeCaster

static func getCircle(center: Vector2i, radius: int) -> Array[Vector2i]:
	var result: Array[Vector2i] = []
	for x in range(-radius, radius + 1):
		for y in range(-radius, radius + 1):
			if abs(x) + abs(y) <= radius:
				result.append(center + Vector2i(x, y))
	return result


static func getCross(center: Vector2i, radius: int) -> Array[Vector2i]:
	var result: Array[Vector2i] = []
	for i in range(-radius, radius + 1):
		if i == 0:
			result.append(center)
		else:
			result.append(center + Vector2i(i, 0))
			result.append(center + Vector2i(0, i))
	return result


static func getLine(origin: Vector2i, target: Vector2i, length: int) -> Array[Vector2i]:
	## Draws a line projecting from origin towards target.
	var result: Array[Vector2i] = []
	var diff = target - origin
	
	# Determine primary direction (orthogonal or perfect diagonal)
	var dir = Vector2i.ZERO
	if abs(diff.x) > abs(diff.y):
		dir = Vector2i(sign(diff.x), 0)
	elif abs(diff.y) > abs(diff.x):
		dir = Vector2i(0, sign(diff.y))
	else:
		dir = Vector2i(sign(diff.x), sign(diff.y))
		
	if dir == Vector2i.ZERO:
		return [origin]
	
	# Start at 0 to include the origin tile if desired, or 1 to start adjacent
	var startPos = origin
	for i in range(1, length + 1):
		result.append(startPos + (dir * i))
	return result
