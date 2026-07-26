## LineOfSight — Dofus-style discrete Bresenham line-of-sight check.
## Fully stateless. Pass an isBlocker callable for game-specific LoS rules.
##
## Algorithm details (Bresenham discrete raycast):
##   1. Steps from source center to target center using Bresenham integer arithmetic.
##   2. Each intermediate cell (not source, not target) is tested via isBlocker.
##   3. Exact diagonal corner crossings use the Dofus rule: LoS is blocked
##      only if BOTH flanking (non-diagonal) cells are blockers.
##      If only one is blocked, the ray sneaks through the corner.

class_name LineOfSight


static func hasLoS(
		fromPos: Vector2i,
		toPos: Vector2i,
		isBlocker: Callable) -> bool:
	## Returns true if there is clear line of sight from fromPos to toPos.
	## isBlocker: func(pos: Vector2i) -> bool
	## Source and target cells are never passed to isBlocker.

	if fromPos == toPos:
		return true  # Same cell is always visible

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

	while true:
		if cx == x1 and cy == y1:
			break  # Reached the target cell

		var e2: int = 2 * err
		var stepX: bool = e2 > -dy
		var stepY: bool = e2 < dx

		if stepX and stepY:
			# Exact diagonal corner crossing — apply Dofus corner rule.
			# Check both flanking non-diagonal cells.
			# LoS blocked only if BOTH flanking cells are blockers.
			var cellA: Vector2i = Vector2i(cx + sx, cy)
			var cellB: Vector2i = Vector2i(cx, cy + sy)
			if isBlocker.call(cellA) and isBlocker.call(cellB):
				return false
			# Advance diagonally (both axes step simultaneously)
			err += dx - dy
			cx += sx
			cy += sy
		elif stepX:
			err -= dy
			cx += sx
		else:
			err += dx
			cy += sy

		# Check this intermediate cell (skip source and target)
		if not (cx == x0 and cy == y0) and not (cx == x1 and cy == y1):
			if isBlocker.call(Vector2i(cx, cy)):
				return false

	return true
static func hasHeightAwareLoS(
		fromPos: Vector2i,
		toPos: Vector2i,
		sourceEyeHeight: float,
		targetEyeHeight: float,
		getBlockerTop: Callable,
		epsilon: float = 0.001) -> bool:
	## Uses the same discrete supercover/corner cells as hasLoS, but compares each
	## intermediate blocker top against the interpolated ray height.
	return hasLoS(fromPos, toPos, func(cell: Vector2i) -> bool:
		var delta = Vector2(toPos - fromPos)
		var relative = Vector2(cell - fromPos)
		var denominator = maxf(delta.length_squared(), 1.0)
		var t = clampf(relative.dot(delta) / denominator, 0.0, 1.0)
		var rayHeight = lerpf(sourceEyeHeight, targetEyeHeight, t)
		return float(getBlockerTop.call(cell)) > rayHeight + epsilon
	)
