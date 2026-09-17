## WMH-8's self-contained validation: a vertex edit moves exactly the three hexes sharing it,
## picking on a slope returns the hex the renderer draws there, and a flat field renders
## identically to no height field at all.
##
## THE THREE-HEX CLAIM IS THE ONE EVERYTHING ELSE RESTS ON. Heights are on vertices precisely so
## that neighbouring hexes cannot disagree about the ground where they meet; if an edit reached
## two hexes or four, the surface would have a seam and every system sampling it would inherit
## that seam differently.

extends SceneTree

const MapData = preload("res://src/presentation/worldmap/editor/WorldMapTileData.gd")
const HeightField = preload("res://src/presentation/worldmap/editor/WorldMapHeightField.gd")
const ObjectLayer = preload("res://src/presentation/worldmap/editor/WorldMapObjectLayer.gd")
const SurfacePick = preload("res://src/presentation/worldmap/editor/WorldMapSurfacePick.gd")

const SCRATCH := "user://probe_scratch/worldmap/_probe_heights.json"

var _failures := 0


func _initialize() -> void:
	DirAccess.make_dir_recursive_absolute("user://probe_scratch/worldmap")
	_cleanup()
	_checkVertexGeometry()
	_checkVertexIsSharedByExactlyThreeHexes()
	_checkFlatFieldIsZeroEverywhere()
	_checkEditMovesExactlyThreeHexes()
	_checkInterpolationIsContinuousAcrossAnEdge()
	_checkTools()
	_checkRoundTrip()
	_checkObjectAnchoringUsesTheSameSurface()
	_checkSurfaceMeshIsTheSampledSurface()
	_checkFlatMeshMatchesNoField()
	await _checkPickingOnASlope()
	_cleanup()

	print("")
	print("probe_height_field: %s" % ("PASS" if _failures == 0 else "%d FAILURE(S)" % _failures))
	if _failures == 0:
		print("WORLD MAP HEIGHT FIELD OK")
	quit(1 if _failures > 0 else 0)


func _fail(message: String) -> void:
	_failures += 1
	print("  FAIL  %s" % message)


func _cleanup() -> void:
	if FileAccess.file_exists(SCRATCH):
		DirAccess.remove_absolute(ProjectSettings.globalize_path(SCRATCH))


func _fresh() -> WorldMapTileData:
	var data := MapData.create("_probe_heights", Vector2i(9, 7), MapData.LAYOUT_HEX_FLAT)
	HeightField.ensureLayer(data)
	return data


## A vertex sits at the centroid of its three cells, and a hex's six land on its six corners.
## Both are load-bearing: the first is how the mesh will place them, the second is what makes the
## fan triangulation the same one the sub-triangle layer uses.
func _checkVertexGeometry() -> void:
	print("-- a vertex is the centroid of its three cells, at the hex's own corners --")
	var checked := 0
	for col in range(-1, 10):
		for row in range(-1, 8):
			var cell := Vector2i(col, row)
			var centre: Vector2 = WorldMapHexGrid.cellCentre(cell)
			var vertices := HeightField.cellVertices(cell)
			if vertices.size() != 6:
				_fail("cell %s has %d vertices, expected 6" % [cell, vertices.size()])
				return
			for i in vertices.size():
				checked += 1
				var expected: Vector2 = centre + HeightField.CORNER_OFFSETS[i]
				if not HeightField.vertexPosition(vertices[i]).is_equal_approx(expected):
					_fail("cell %s vertex %d is at %s, its corner is %s" % [
						cell, i, HeightField.vertexPosition(vertices[i]), expected
					])
					return
	print("  ok    %d vertices, each the centroid of its three cells and on its corner" % checked)


func _checkVertexIsSharedByExactlyThreeHexes() -> void:
	print("-- three hexes meet at a vertex, and each hex owns exactly two --")
	for col in range(0, 9):
		for row in range(0, 7):
			for index in HeightField.PER_CELL:
				var vertex := Vector3i(col, row, index)
				var cells := HeightField.vertexCells(vertex)
				if cells.size() != 3:
					_fail("%s is shared by %d cells, expected 3" % [vertex, cells.size()])
					return
				# Mutually adjacent, or they do not meet at a point.
				for a in 3:
					for b in range(a + 1, 3):
						if WorldMapHexGrid.distance(cells[a], cells[b]) != 1:
							_fail("%s: cells %s and %s are not adjacent" % [
								vertex, cells[a], cells[b]
							])
							return
				# And each of the three genuinely lists this vertex among its own six.
				for cell in cells:
					if not HeightField.cellVertices(cell).has(vertex):
						_fail("%s claims cell %s, which does not list it back" % [vertex, cell])
						return
	print("  ok    126 vertices, each shared by three mutually adjacent hexes that agree")


func _checkFlatFieldIsZeroEverywhere() -> void:
	print("-- a flat field samples zero everywhere, like no field at all --")
	var flat := _fresh()
	var none := MapData.create("_probe_none", Vector2i(9, 7), MapData.LAYOUT_HEX_FLAT)
	var extent: Vector2 = flat.worldExtent()
	var x := 0.0
	var tested := 0
	while x < extent.x:
		var y := 0.0
		while y < extent.y:
			var point := Vector2(x, y)
			tested += 1
			if not is_equal_approx(HeightField.sample(flat, point), 0.0):
				_fail("a flat field samples %f at %s" % [HeightField.sample(flat, point), point])
				return
			if not is_equal_approx(HeightField.sample(none, point), 0.0):
				_fail("a map with NO height layer samples non-zero at %s" % point)
				return
			y += 0.31
		x += 0.29
	print("  ok    %d points, flat field and no field both sample exactly zero" % tested)


## The item's own headline: a vertex edit moves exactly the three hexes sharing it. Checked by
## sampling every cell's centre before and after -- the three must move, and nothing else may.
func _checkEditMovesExactlyThreeHexes() -> void:
	print("-- one vertex edit moves exactly the three hexes sharing it --")
	var data := _fresh()
	var vertex := Vector3i(4, 3, 0)
	var expected := HeightField.vertexCells(vertex)

	var before := {}
	for col in 9:
		for row in 7:
			var cell := Vector2i(col, row)
			before[cell] = HeightField.sample(data, WorldMapHexGrid.cellCentre(cell))

	if not HeightField.raiseVertex(data, vertex, 4.0):
		_fail("raising the vertex reported no change")
		return

	var moved: Array[Vector2i] = []
	for col in 9:
		for row in 7:
			var cell := Vector2i(col, row)
			var after := HeightField.sample(data, WorldMapHexGrid.cellCentre(cell))
			if not is_equal_approx(after, float(before[cell])):
				moved.append(cell)
	if moved.size() != 3:
		_fail("the edit moved %d hexes: %s" % [moved.size(), moved])
		return
	for cell in expected:
		if not moved.has(cell):
			_fail("hex %s shares the vertex but did not move" % cell)
			return
	# And it moved them by the amount sharing implies: one of six vertices, so a sixth of the
	# raise at each centre.
	for cell in moved:
		var delta: float = HeightField.sample(data, WorldMapHexGrid.cellCentre(cell)) - float(before[cell])
		if not is_equal_approx(delta, 4.0 / 6.0):
			_fail("hex %s moved by %f, expected %f" % [cell, delta, 4.0 / 6.0])
			return
	print("  ok    exactly the three sharing hexes moved, each by a sixth of the raise")


## Neighbouring hexes share the vertices between them, so the surface cannot have a step at a hex
## boundary. Sampled either side of an edge at a shrinking distance: the gap must shrink with it.
func _checkInterpolationIsContinuousAcrossAnEdge() -> void:
	print("-- the surface is continuous across a hex boundary --")
	var data := _fresh()
	# An irregular field, so continuity is not accidentally true because everything is flat.
	var rng := RandomNumberGenerator.new()
	rng.seed = 20260907
	for col in range(-1, 10):
		for row in range(-1, 8):
			for index in HeightField.PER_CELL:
				HeightField.setHeightAt(data, Vector3i(col, row, index), rng.randf_range(-3.0, 3.0))

	var a := Vector2i(4, 3)
	for neighbour in WorldMapHexGrid.neighbours(a):
		var midpoint: Vector2 = (
			WorldMapHexGrid.cellCentre(a) + WorldMapHexGrid.cellCentre(neighbour)
		) * 0.5
		var direction := (
			WorldMapHexGrid.cellCentre(neighbour) - WorldMapHexGrid.cellCentre(a)
		).normalized()
		var previous := INF
		for step in [0.01, 0.001, 0.0001]:
			var here := HeightField.sample(data, midpoint - direction * step)
			var there := HeightField.sample(data, midpoint + direction * step)
			var gap := absf(here - there)
			if gap > previous + 1e-6:
				_fail("the gap across the %s edge grew as the step shrank" % neighbour)
				return
			previous = gap
		if previous > 1e-3:
			_fail("a step of %f remains across the %s edge at 0.0001 apart" % [previous, neighbour])
			return
	print("  ok    all six edges of a hex: the gap vanishes as the samples close in")


func _checkTools() -> void:
	print("-- flatten and smooth --")
	var data := _fresh()
	var patch: Array[Vector2i] = [Vector2i(4, 3), Vector2i(5, 3), Vector2i(4, 4)]
	HeightField.flatten(data, patch, 5.0)
	for cell in patch:
		if not is_equal_approx(HeightField.sample(data, WorldMapHexGrid.cellCentre(cell)), 5.0):
			_fail("flatten left %s at %f" % [
				cell, HeightField.sample(data, WorldMapHexGrid.cellCentre(cell))
			])
			return

	# Smoothing a spike must reduce it, and must not move the field's overall level much --
	# a smooth that drifts is the Jacobi/Gauss-Seidel trap the implementation guards against.
	var spiky := _fresh()
	HeightField.raiseVertex(spiky, Vector3i(4, 3, 0), 9.0)
	var peakBefore := HeightField.heightAt(spiky, Vector3i(4, 3, 0))
	var ring: Array[Vector2i] = HeightField.vertexCells(Vector3i(4, 3, 0))
	HeightField.smooth(spiky, ring, 1.0)
	var peakAfter := HeightField.heightAt(spiky, Vector3i(4, 3, 0))
	if peakAfter >= peakBefore:
		_fail("smoothing a spike left it at %f, was %f" % [peakAfter, peakBefore])
		return
	if peakAfter < 0.0:
		_fail("smoothing overshot the spike to %f" % peakAfter)
		return
	print("  ok    flatten sets a plateau; smoothing lowers a spike without overshooting it")


func _checkRoundTrip() -> void:
	print("-- a sculpted field survives a save and reload --")
	var data := _fresh()
	var rng := RandomNumberGenerator.new()
	rng.seed = 424242
	var written := {}
	for _i in 60:
		var vertex := Vector3i(rng.randi_range(0, 8), rng.randi_range(0, 6), rng.randi_range(0, 1))
		var height := rng.randf_range(-6.0, 6.0)
		HeightField.setHeightAt(data, vertex, height)
		written[vertex] = HeightField.heightAt(data, vertex)
	if not data.saveTo(SCRATCH):
		_fail("could not write the scratch document")
		return
	var reloaded := MapData.loadFrom(SCRATCH)
	if reloaded == null:
		_fail("could not read the scratch document back")
		return
	if not HeightField.has(reloaded):
		_fail("the reloaded document has no height layer")
		return
	for vertex in written:
		var back := HeightField.heightAt(reloaded, vertex as Vector3i)
		if absf(back - float(written[vertex])) > 1e-3:
			_fail("%s came back as %f, was %f" % [vertex, back, written[vertex]])
			return
	# And a flat field costs almost nothing to store: one run, not thousands of entries.
	var flat := _fresh()
	var runs: Array = flat.toDictionary()["LAYERS"][2]["RLE"]
	if runs.size() != 1:
		_fail("a flat field encodes to %d runs, expected 1" % runs.size())
		return
	print("  ok    60 sculpted vertices survive a round trip; a flat field is one run")


## WMH-7 built object anchoring against a sampler it could not yet be given. This is that sampler
## -- and the point is that an object rests on the surface the RENDERER draws, because both go
## through `HeightField.sample`.
func _checkObjectAnchoringUsesTheSameSurface() -> void:
	print("-- an object anchors to the sampled surface, not to a second one --")
	var data := _fresh()
	var cell := Vector2i(4, 3)
	HeightField.flatten(data, [cell], 3.5)
	var record := ObjectLayer.place(data, "house", cell)
	var sampler := HeightField.samplerFor(data)
	var anchored := ObjectLayer.anchorHeight(record, sampler)
	var surface := HeightField.sample(data, WorldMapHexGrid.cellCentre(cell))
	if not is_equal_approx(anchored, surface):
		_fail("the object anchored at %f, the surface there is %f" % [anchored, surface])
		return
	if not is_equal_approx(ObjectLayer.worldPosition(data, record, sampler).y, surface):
		_fail("the object's world position does not sit on the surface")
		return
	print("  ok    anchor %.3f equals the sampled surface, through the one interpolation" % anchored)


## The mesh is not an approximation of the surface -- it IS the surface. Every mesh vertex must
## equal what `sample()` returns at its own XZ, or rendering and picking are two different
## grounds and this item's stated risk is live.
func _checkSurfaceMeshIsTheSampledSurface() -> void:
	print("-- every surface-mesh vertex sits exactly where sample() says --")
	var data := _fresh()
	var rng := RandomNumberGenerator.new()
	rng.seed = 8080
	for col in range(-1, 10):
		for row in range(-1, 8):
			for index in HeightField.PER_CELL:
				HeightField.setHeightAt(data, Vector3i(col, row, index), rng.randf_range(-2.0, 5.0))

	var mesh := HeightField.buildSurfaceMesh(data)
	if mesh == null:
		_fail("no surface mesh was built")
		return
	var positions: PackedVector3Array = mesh.surface_get_arrays(0)[Mesh.ARRAY_VERTEX]
	var checked := 0
	for point in positions:
		var sampled := HeightField.sample(data, Vector2(point.x, point.z))
		checked += 1
		if absf(sampled - point.y) > 1e-3:
			_fail("mesh vertex %s: sample() says %f there" % [point, sampled])
			return
	print("  ok    %d vertices, each exactly on the sampled surface" % checked)


## "A flat field renders identically to no height field at all" -- checked as geometry: every
## vertex of a flat field's mesh is at y = 0, so it is the same ground a map with no field gets.
func _checkFlatMeshMatchesNoField() -> void:
	print("-- a flat field's surface is the same ground as no field at all --")
	var flat := _fresh()
	var mesh := HeightField.buildSurfaceMesh(flat)
	var positions: PackedVector3Array = mesh.surface_get_arrays(0)[Mesh.ARRAY_VERTEX]
	for point in positions:
		if not is_zero_approx(point.y):
			_fail("a flat field put a vertex at y = %f" % point.y)
			return
	# And the fan covers the lattice: six triangles per cell, so the index count is exact.
	var indices: PackedInt32Array = mesh.surface_get_arrays(0)[Mesh.ARRAY_INDEX]
	var expected := flat.size_tiles.x * flat.size_tiles.y * 6 * 3
	if indices.size() != expected:
		_fail("the mesh has %d indices, six triangles per cell is %d" % [indices.size(), expected])
		return
	print("  ok    every vertex at y=0, and six triangles for each of %d cells" % [
		flat.size_tiles.x * flat.size_tiles.y
	])


## The item's own risk: "picking and rendering sampling the surface differently, so the cursor
## sits off the visible ground on a slope". Rays are cast at a real camera through a genuinely
## sloped field, and the point picking returns must lie ON the surface the mesh draws.
func _checkPickingOnASlope() -> void:
	print("-- picking on a slope lands on the surface the renderer draws --")
	var data := _fresh()
	# A ramp rising to the east, so most of the map is genuinely sloped rather than flat.
	for col in range(-1, 10):
		for row in range(-1, 8):
			for index in HeightField.PER_CELL:
				HeightField.setHeightAt(data, Vector3i(col, row, index), float(col) * 0.8)

	var viewport := SubViewport.new()
	viewport.size = Vector2i(480, 360)
	root.add_child(viewport)
	var camera := Camera3D.new()
	camera.fov = 45.0
	camera.near = 0.5
	camera.far = 400.0
	var extent: Vector2 = data.worldExtent()
	var focus := Vector3(extent.x * 0.5, 0.0, extent.y * 0.5)
	camera.position = focus + Vector3(0.0, sin(deg_to_rad(60.0)) * 26.0, cos(deg_to_rad(60.0)) * 26.0)
	camera.rotation_degrees = Vector3(-60.0, 0.0, 0.0)
	viewport.add_child(camera)
	camera.current = true
	await process_frame
	await process_frame

	var sampler := HeightField.pointSamplerFor(data)
	var region := Rect2(Vector2.ZERO, extent)
	var tested := 0
	var worst := 0.0
	for sx in range(20, 470, 15):
		for sy in range(20, 350, 15):
			var screen := Vector2(sx, sy)
			var point = SurfacePick.surfacePointOnTerrain(camera, screen, 0.0, sampler, Vector2.ZERO)
			if point == null:
				continue
			var world := point as Vector3
			var local := Vector2(world.x, world.z)
			if not region.has_point(local):
				continue
			tested += 1
			# The returned point must be ON the surface: its own height must equal what the
			# surface has at its own XZ.
			worst = maxf(worst, absf(world.y - HeightField.sample(data, local)))
	if tested < 20:
		_fail("only %d rays landed inside the region; the test proves little" % tested)
		viewport.queue_free()
		return
	if worst > 1e-2:
		_fail("a picked point sat %f above or below the drawn surface" % worst)
		viewport.queue_free()
		return

	# And the flat solve, used on the same sloped field, would have been visibly wrong -- so this
	# check is not passing merely because the ramp is gentle.
	var flatMiss := 0.0
	for sx in range(20, 470, 15):
		var flatPoint = SurfacePick.surfacePoint(camera, Vector2(sx, 180), 0.0)
		if flatPoint == null:
			continue
		var flatLocal := Vector2((flatPoint as Vector3).x, (flatPoint as Vector3).z)
		if region.has_point(flatLocal):
			flatMiss = maxf(flatMiss, absf(HeightField.sample(data, flatLocal)))
	if flatMiss < 0.5:
		_fail("the flat solve was already within %f, so the slope was too gentle to test" % flatMiss)
		viewport.queue_free()
		return
	viewport.queue_free()
	print("  ok    %d rays, worst miss %.5f units; the flat solve would miss by up to %.2f" % [
		tested, worst, flatMiss
	])
