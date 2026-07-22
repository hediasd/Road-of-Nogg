## ParabolicArc — 3D parabolic trajectory clearance checker.
## Fully stateless. Pass a getObstacleHeight callable to check if an arching projectile clears terrain.
##
## Algorithm details:
##   1. Uses Bresenham to find all cells between source and target.
##   2. Calculates distance 't' (0.0 to 1.0) along the ray for each intermediate cell.
##   3. Calculates the projectile height z(t) using a parabolic arc:
##      z(t) = lerp(z_start, z_end, t) + max_arc_height * 4 * t * (1 - t)
##   4. Tests if z(t) > getObstacleHeight(cell). If not, the shot is blocked.

class_name ParabolicArc


static func hasClearArc(
		fromPos: Vector2i, 
		toPos: Vector2i, 
		zStart: float, 
		zEnd: float, 
		maxArcHeight: float, 
		getObstacleHeight: Callable) -> bool:
	## Returns true if a parabolic arc clears all obstacles between fromPos and toPos.
	## zStart: The starting elevation (e.g. tile height + unit height)
	## zEnd: The ending elevation (e.g. tile height + target unit height)
	## maxArcHeight: The peak height added to the arc at the midpoint
	## getObstacleHeight: func(pos: Vector2i) -> float
	
	if fromPos == toPos:
		return true

	var x0: int = fromPos.x
	var y0: int = fromPos.y
	var x1: int = toPos.x
	var y1: int = toPos.y

	var dx: int = abs(x1 - x0)
	var dy: int = abs(y1 - y0)
	var sx: int = 1 if x0 < x1 else -1
	var sy: int = 1 if y0 < y1 else -1
	var err: int = dx - dy

	var cx: int = x0
	var cy: int = y0
	
	var totalDist: float = sqrt(dx * dx + dy * dy)
	
	while true:
		if cx == x1 and cy == y1:
			break
			
		var e2: int = 2 * err
		var stepX: bool = e2 > -dy
		var stepY: bool = e2 < dx
		
		if stepX and stepY:
			err += dx - dy
			cx += sx
			cy += sy
		elif stepX:
			err -= dy
			cx += sx
		else:
			err += dx
			cy += sy

		# Check this intermediate cell
		if not (cx == x0 and cy == y0) and not (cx == x1 and cy == y1):
			var currentDist: float = sqrt(pow(cx - x0, 2) + pow(cy - y0, 2))
			var t: float = currentDist / totalDist if totalDist > 0 else 0.0
			
			# Parabola formula
			var baseHeight: float = lerp(zStart, zEnd, t)
			var arcHeight: float = maxArcHeight * 4.0 * t * (1.0 - t)
			var z_t: float = baseHeight + arcHeight
			
			var obstacleHeight: float = getObstacleHeight.call(Vector2i(cx, cy))
			if z_t <= obstacleHeight:
				return false

	return true
