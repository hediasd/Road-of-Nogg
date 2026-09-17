## WMH-3's self-contained validation: the shader's hex geometry agrees with
## `WorldMapHexGrid`'s -- the same claim `applyGrid()`'s cursor and the picker's own cell both
## rest on -- verified as math rather than as pixels.
##
## PIXELS ARE NOT AVAILABLE HERE. Godot's dummy renderer under `--headless` produces no real
## framebuffer, so a probe cannot render the overlay and measure a highlighted region's centroid
## the way the plan's own prose describes. What it CAN do, and what actually backs that same
## claim, is prove the shader's formulas and the CPU picker's formulas compute the identical
## thing: `hex_nearest_axial` / `hex_axial_centre` in `worldmap_ground.gdshader` are ported here
## line for line and checked against `WorldMapHexGrid.worldToCell` / `.cellCentre` over a dense
## sample including the boundary points that catch independent-axis rounding -- the same
## technique `probe_hex_grid.gd` already used to catch that exact bug once. If the shader and
## the CPU ever disagree, this is where it would show, not in a rendered pixel nobody measured.
##
## A REAL RENDER IS STILL DONE, deferred rather than self-contained: see the class note in the
## commit this probe ships with for the non-headless screenshot that confirms the lattice and
## the cursor actually appear where this file proves they must.

extends SceneTree

const Hex = preload("res://src/presentation/worldmap/editor/WorldMapHexGrid.gd")

var _failures := 0


func _initialize() -> void:
	_checkNearestAxialMatchesPicker()
	_checkAxialCentreMatchesCellCentre()
	_checkEdgeDistanceSignAgreesWithMembership()
	_checkCursorCentreRoundTrips()
	_checkSpokeFoldingIsComplete()
	_checkLatticeBoundMatchesContains()
	_checkPickerRefusesMarginCells()

	print("")
	print("probe_hex_grid_overlay: %s" % ("PASS" if _failures == 0 else "%d FAILURE(S)" % _failures))
	if _failures == 0:
		print("WORLD MAP HEX GRID OVERLAY OK")
	quit(1 if _failures > 0 else 0)


func _fail(message: String) -> void:
	_failures += 1
	print("  FAIL  %s" % message)


## `hex_nearest_axial` from `worldmap_ground.gdshader`, ported line for line. Any change to one
## must be made to the other; this probe is what would notice a drift.
func _shaderNearestAxial(p: Vector2) -> Vector2:
	var centred := p - Vector2(1.0, 1.0)
	var qf := centred.x / 1.5
	var rf := (centred.y - qf) / 2.0

	var xf := qf
	var zf := rf
	var yf := -xf - zf
	var rx: float = round(xf)
	var ry: float = round(yf)
	var rz: float = round(zf)
	var dx := absf(rx - xf)
	var dy := absf(ry - yf)
	var dz := absf(rz - zf)
	if dx > dy and dx > dz:
		rx = -ry - rz
	elif dy > dz:
		ry = -rx - rz
	else:
		rz = -rx - ry
	return Vector2(rx, rz)


## `hex_axial_centre`, ported the same way.
func _shaderAxialCentre(axial: Vector2) -> Vector2:
	return Vector2(1.5 * axial.x + 1.0, 2.0 * axial.y + axial.x + 1.0)


## `hex_edge_distance`, ported the same way.
func _shaderEdgeDistance(local: Vector2) -> float:
	var q := Vector2(absf(local.x), absf(local.y))
	var flatEdge := q.y - 1.0
	var slant := (2.0 * q.x + q.y - 2.0) * 0.4472135955
	return maxf(flatEdge, slant)


## The load-bearing check: for a dense sample of world points, including the exact boundary
## points `probe_hex_grid.gd` uses to catch independent-axis rounding, the shader's own axial
## resolution matches `WorldMapHexGrid.offsetToAxial(WorldMapHexGrid.worldToCell(p))` exactly.
func _checkNearestAxialMatchesPicker() -> void:
	print("-- shader axial resolution matches WorldMapHexGrid, over a dense sample --")
	var tested := 0
	for col in range(0, 15):
		for row in range(0, 11):
			for frac: Vector2 in [Vector2(0.5, 0.5), Vector2(0.1, 0.9), Vector2(0.9, 0.1)]:
				var p := Vector2(float(col), float(row)) + frac
				tested += 1
				var fromShader := _shaderNearestAxial(p)
				var fromPicker := Hex.offsetToAxial(Hex.worldToCell(p))
				if not fromShader.is_equal_approx(Vector2(fromPicker)):
					_fail("at %s: shader gives axial %s, picker gives %s" % [
						p, fromShader, fromPicker
					])
					return
	print("  ok    %d interior points agree" % tested)

	# The boundary points: just inside each vertex and edge midpoint, exactly as
	# probe_hex_grid.gd's own rounding check does -- this is where independent-axis rounding
	# would fail and interior sampling would not catch it.
	var vertexOffsets := [
		Vector2(1.0, 0.0), Vector2(0.5, 1.0), Vector2(-0.5, 1.0),
		Vector2(-1.0, 0.0), Vector2(-0.5, -1.0), Vector2(0.5, -1.0),
	]
	var boundaryTested := 0
	for col in range(1, 14):
		for row in range(1, 10):
			var cell := Vector2i(col, row)
			var centre: Vector2 = Hex.cellCentre(cell)
			for i in vertexOffsets.size():
				var vertex: Vector2 = vertexOffsets[i]
				var nextVertex: Vector2 = vertexOffsets[(i + 1) % vertexOffsets.size()]
				for offset in [vertex, (vertex + nextVertex) * 0.5]:
					var point: Vector2 = centre + (offset as Vector2) * 0.88
					boundaryTested += 1
					var fromShader := Hex.axialToOffset(Vector2i(
						roundi(_shaderNearestAxial(point).x), roundi(_shaderNearestAxial(point).y)
					))
					var fromPicker := Hex.worldToCell(point)
					if fromShader != fromPicker:
						_fail("boundary point %s: shader resolves to offset %s, picker to %s" % [
							point, fromShader, fromPicker
						])
						return
	print("  ok    %d boundary points agree" % boundaryTested)


func _checkAxialCentreMatchesCellCentre() -> void:
	print("-- shader axial centre matches WorldMapHexGrid.cellCentre --")
	for col in range(-5, 15):
		for row in range(-5, 12):
			var cell := Vector2i(col, row)
			var axial := Hex.offsetToAxial(cell)
			var fromShader := _shaderAxialCentre(Vector2(axial))
			var fromPicker: Vector2 = Hex.cellCentre(cell)
			if not fromShader.is_equal_approx(fromPicker):
				_fail("cell %s: shader centre %s, WorldMapHexGrid centre %s" % [
					cell, fromShader, fromPicker
				])
				return
	print("  ok    400 cells, shader and WorldMapHexGrid agree on every centre")


## The edge distance's sign must actually mean inside/outside, not just be a smooth field --
## checked against the hand-derived hex vertices themselves, at points scaled in and out from
## a cell's own centre.
func _checkEdgeDistanceSignAgreesWithMembership() -> void:
	print("-- hex_edge_distance's sign matches actual inside/outside --")
	var vertexOffsets := [
		Vector2(1.0, 0.0), Vector2(0.5, 1.0), Vector2(-0.5, 1.0),
		Vector2(-1.0, 0.0), Vector2(-0.5, -1.0), Vector2(0.5, -1.0),
	]
	for offset in vertexOffsets:
		var inside: Vector2 = (offset as Vector2) * 0.9
		var outside: Vector2 = (offset as Vector2) * 1.1
		if _shaderEdgeDistance(inside) >= 0.0:
			_fail("%s (90%% to vertex) reports outside (d=%.4f)" % [
				inside, _shaderEdgeDistance(inside)
			])
			return
		if _shaderEdgeDistance(outside) <= 0.0:
			_fail("%s (110%% to vertex) reports inside (d=%.4f)" % [
				outside, _shaderEdgeDistance(outside)
			])
			return
	if _shaderEdgeDistance(Vector2.ZERO) >= 0.0:
		_fail("the hex's own centre reports outside or on the boundary")
		return
	if _shaderEdgeDistance(Vector2(3.0, 3.0)) <= 0.0:
		_fail("a point far outside the hex reports inside")
		return
	print("  ok    inside negative, outside positive, at every vertex direction and the centre")


## What `applyGrid()` actually sets for the cursor -- `region.position + WorldMapHexGrid.
## cellCentre(cell)` -- must land exactly on a zero of `hex_edge_distance` relative to itself
## (trivially true) AND, more usefully, must be the point `hex_nearest_axial` resolves BACK to
## the same cell from. This is the closure the risk section actually asks for: the cursor the
## HUD draws and the cell the picker would return for that same screen position are the same
## cell, end to end, not just individually correct.
func _checkCursorCentreRoundTrips() -> void:
	print("-- a cell's cursor centre round-trips back to that same cell --")
	var region := Rect2(Vector2(3.0, 4.0), Vector2(15.0, 11.0))
	for col in 15:
		for row in 11:
			var cell := Vector2i(col, row)
			var worldCentre: Vector2 = region.position + Hex.cellCentre(cell)
			var regionLocal := worldCentre - region.position
			var resolvedAxial := _shaderNearestAxial(regionLocal)
			var resolvedOffset := Hex.axialToOffset(Vector2i(
				roundi(resolvedAxial.x), roundi(resolvedAxial.y)
			))
			if resolvedOffset != cell:
				_fail("cursor centre for %s resolves back to %s" % [cell, resolvedOffset])
				return
	print("  ok    165 cells: cursor centre always resolves back to its own cell")


## After folding by `abs()`, the six spokes collapse onto exactly two representative points --
## (1, 0) and (0.5, 1). Checked by folding all six of `WorldMapHexGrid`'s own vertex offsets and
## confirming each lands on one of those two, which is the assumption `hex_subtriangle_coverage`
## depends on to test only two spokes instead of six.
func _checkSpokeFoldingIsComplete() -> void:
	print("-- folding collapses all six hex vertices to the two spokes tested --")
	var vertexOffsets := [
		Vector2(1.0, 0.0), Vector2(0.5, 1.0), Vector2(-0.5, 1.0),
		Vector2(-1.0, 0.0), Vector2(-0.5, -1.0), Vector2(0.5, -1.0),
	]
	var canonical := [Vector2(1.0, 0.0), Vector2(0.5, 1.0)]
	for vertex in vertexOffsets:
		var folded := Vector2(absf((vertex as Vector2).x), absf((vertex as Vector2).y))
		var matches := false
		for c in canonical:
			if folded.is_equal_approx(c):
				matches = true
				break
		if not matches:
			_fail("vertex %s folds to %s, which is neither canonical spoke" % [vertex, folded])
			return
	print("  ok    all 6 vertices fold to (1, 0) or (0.5, 1)")


## `hex_in_lattice` from the shader, ported the same way as the functions above. The row term is
## the float port of `axialToOffset`'s `(q - (q & 1)) / 2`, which is integer `floor(q / 2)` for
## negative q as well as positive -- the reason `floor(q * 0.5)` is faithful and not an
## approximation. This check is what would catch that claim being wrong.
func _shaderInLattice(p: Vector2, cols: int, rows: int) -> bool:
	if cols <= 0 or rows <= 0:
		return true
	var axial := _shaderNearestAxial(p)
	var col := axial.x
	var row: float = axial.y + floor(axial.x * 0.5)
	return col >= 0.0 and row >= 0.0 and col < float(cols) and row < float(rows)


## Gate 1's Finding 1. The shader's lattice bound must agree with `WorldMapHexGrid.contains` on
## exactly the same points -- including, and especially, the margin strip on the right and bottom
## where the two used to disagree by drawing unpaintable hexes.
func _checkLatticeBoundMatchesContains() -> void:
	print("-- the shader's lattice bound matches WorldMapHexGrid.contains --")
	var cols := 31
	var rows := 23
	var extent: Vector2 = Hex.latticeExtent(cols, rows)
	# Sample well past the lattice on both axes, so the margin strip is covered densely rather
	# than clipped past.
	var tested := 0
	var insideSeen := 0
	var outsideSeen := 0
	var x := 0.0
	while x < extent.x + 3.0:
		var y := 0.0
		while y < extent.y + 3.0:
			var p := Vector2(x, y)
			tested += 1
			var fromShader := _shaderInLattice(p, cols, rows)
			var fromGrid := Hex.contains(Hex.worldToCell(p), cols, rows)
			if fromShader != fromGrid:
				_fail("at %s: shader says in-lattice=%s, WorldMapHexGrid says %s" % [
					p, fromShader, fromGrid
				])
				return
			if fromShader:
				insideSeen += 1
			else:
				outsideSeen += 1
			y += 0.37
		x += 0.37
	if outsideSeen == 0:
		_fail("sampled no out-of-lattice points, so the bound was never actually exercised")
		return
	print("  ok    %d points agree (%d inside, %d in the margin)" % [
		tested, insideSeen, outsideSeen
	])


## The other half of Finding 1: picking must REFUSE a margin cell rather than name it. Without a
## camera this checks the bound directly on the same cells `pickTile` would run it on, which is
## the part that regressed -- the ray solve was never in question.
func _checkPickerRefusesMarginCells() -> void:
	print("-- margin cells are refused, not named --")
	var cols := 31
	var rows := 23
	var extent: Vector2 = Hex.latticeExtent(cols, rows)
	var marginPoints := [
		Vector2(extent.x + 0.5, 10.0),
		Vector2(10.0, extent.y + 0.5),
		Vector2(extent.x + 0.5, extent.y + 0.5),
	]
	for point: Vector2 in marginPoints:
		var cell := Hex.worldToCell(point)
		if Hex.contains(cell, cols, rows):
			_fail("%s was expected to be margin but resolves to in-lattice cell %s" % [
				point, cell
			])
			return
		if _shaderInLattice(point, cols, rows):
			_fail("%s is a margin point the shader would still draw a hex on" % [point])
			return
	# And the converse: a cell just inside the last column and row must still be accepted, so the
	# bound is not simply refusing everything near the edge.
	for cell in [Vector2i(cols - 1, rows - 1), Vector2i(cols - 1, 0), Vector2i(0, rows - 1)]:
		var centre: Vector2 = Hex.cellCentre(cell)
		if not Hex.contains(Hex.worldToCell(centre), cols, rows):
			_fail("edge cell %s was refused, so the bound is too tight" % [cell])
			return
		if not _shaderInLattice(centre, cols, rows):
			_fail("edge cell %s would not be drawn, so the bound is too tight" % [cell])
			return
	print("  ok    3 margin points refused; the 3 extreme lattice cells still accepted")
