## Terrain height, stored on the hex VERTEX lattice rather than per cell, and the single
## interpolation that rendering, picking, object anchoring and export all sample.
##
## WHY VERTICES AND NOT CELLS. A height per cell gives a field of flat plateaus with a cliff at
## every edge -- there is nowhere for a slope to live. Heights on the vertices make the surface
## continuous by construction: neighbouring hexes share the vertices between them, so they cannot
## disagree about the ground where they meet.
##
## THREE HEXES MEET AT A HEX VERTEX, not four, and that is what makes the triangulation
## unambiguous. A square grid's vertex is shared by four cells, so a quad must pick one of two
## diagonals and every system that samples it must pick the SAME one. A hex has no such choice:
## each hex fans into six triangles from its own centre, and the fan is the same one the
## sub-triangle detail layer uses, so the two agree by construction rather than by convention.
##
## OWNERSHIP, AND WHY STORAGE IS DENSE. Six corners shared three ways is exactly two vertices per
## hex, so a vertex is addressed as `(ownerCol, ownerRow, index)` with index 0 or 1 -- an owner
## cell and which of its two. Measured rather than assumed: 400 cells resolve to 880 distinct
## vertices, two per cell plus the boundary ring. The three cells meeting at a vertex are, in
## axial terms:
##
##     index 0:  (q, r), (q+1, r), (q+1, r-1)
##     index 1:  (q, r), (q+1, r), (q, r+1)
##
## and a vertex sits at the CENTROID of those three cell centres -- exact, including for the
## pre-stretched hexes this project uses, because a centroid survives any linear map. Verified
## across 600 vertices before this file was written.
##
## Storage pads the owner range by one cell in each direction, because a hex on the lattice edge
## has vertices owned by cells just outside it. Two floats per owner cell over a `(cols+2) x
## (rows+2)` block, run-length encoded as text the same way ground cells are -- a flat field is
## one run, which is what keeps an unsculpted map's file small and its diffs readable.
##
## HEIGHT IS REGION SPACE. Curvature is applied after it, by the shader, and is never stored:
## `WORLDMAP_DESIGN.md` and this cycle's own file both say curvature is a rendering transform.
## Reversing the two would curve the heights themselves.
##
## CONTINUOUS, NOT QUANTISED. An earlier note claimed continuous heights make slope
## classification undecidable; that is false -- an explicit threshold classifies them -- and the
## cycle file corrects it. Nothing here rounds.

class_name WorldMapHeightField
extends RefCounted

const MapData = preload("res://src/presentation/worldmap/editor/WorldMapTileData.gd")

## The layer heights live in unless told otherwise.
const DEFAULT_LAYER := "heights"

## Two vertices per hex -- see the class note.
const PER_CELL := 2

## The six vertices of a hex, in the order its six corner offsets run:
## (1,0), (0.5,1), (-0.5,1), (-1,0), (-0.5,-1), (0.5,-1). Each entry is a `(dq, dr, index)`
## AXIAL delta from the cell's own axial coordinates. Hand-derived and then checked against those
## corner positions across 600 vertices, which is the only reason to trust a table like this.
const CELL_VERTICES := [
	[0, 0, 0], [0, 0, 1], [-1, 1, 0], [-1, 0, 1], [-1, 0, 0], [0, -1, 1],
]

## The six corner offsets from a hex's centre, in the same order as `CELL_VERTICES`.
const CORNER_OFFSETS := [
	Vector2(1.0, 0.0), Vector2(0.5, 1.0), Vector2(-0.5, 1.0),
	Vector2(-1.0, 0.0), Vector2(-0.5, -1.0), Vector2(0.5, -1.0),
]

## Barycentric tolerance when deciding which fan triangle a point falls in. A point exactly on a
## fan edge belongs to both triangles and they agree there, so the only thing this guards is
## floating-point noise leaving a point in none of the six.
const INSIDE_EPSILON := 1e-5


## The six vertices of `cell`, in corner order, as `(ownerCol, ownerRow, index)` with the owner in
## OFFSET coordinates.
static func cellVertices(cell: Vector2i) -> Array[Vector3i]:
	var axial := WorldMapHexGrid.offsetToAxial(cell)
	var out: Array[Vector3i] = []
	for entry in CELL_VERTICES:
		var owner := WorldMapHexGrid.axialToOffset(
			axial + Vector2i(int(entry[0]), int(entry[1]))
		)
		out.append(Vector3i(owner.x, owner.y, int(entry[2])))
	return out


## The three cells meeting at `vertex`, in offset coordinates. Exactly three -- see the class
## note on why that is the whole reason this triangulation needs no diagonal chosen.
static func vertexCells(vertex: Vector3i) -> Array[Vector2i]:
	var owner := WorldMapHexGrid.offsetToAxial(Vector2i(vertex.x, vertex.y))
	var third := Vector2i(1, -1) if vertex.z == 0 else Vector2i(0, 1)
	var out: Array[Vector2i] = []
	for axial in [owner, owner + Vector2i(1, 0), owner + third]:
		out.append(WorldMapHexGrid.axialToOffset(axial))
	return out


## Where a vertex sits, in region-local world units: the centroid of the three cell centres that
## meet there.
static func vertexPosition(vertex: Vector3i) -> Vector2:
	var sum := Vector2.ZERO
	for cell in vertexCells(vertex):
		sum += WorldMapHexGrid.cellCentre(cell)
	return sum / 3.0


## Ensures a height layer exists, sized for `data`'s lattice, and returns its block. A field is
## created flat, so adding one to a map changes nothing about how it renders until something
## sculpts it.
static func ensureLayer(data: WorldMapTileData, layerID := DEFAULT_LAYER) -> Dictionary:
	if data.layers.has(layerID):
		return data.layers[layerID]
	data.addHeightLayer(layerID)
	return data.layers[layerID]


static func has(data: WorldMapTileData, layerID := DEFAULT_LAYER) -> bool:
	if not data.layers.has(layerID):
		return false
	return str((data.layers[layerID] as Dictionary).get("KIND", "")) == MapData.KIND_HEIGHTS


## Index of a vertex within the stored array, or -1 when the owner falls outside the padded
## block. The padding is one cell in each direction -- see the class note.
static func indexOf(data: WorldMapTileData, vertex: Vector3i) -> int:
	var cols := data.size_tiles.x + 2
	var rows := data.size_tiles.y + 2
	var col := vertex.x + 1
	var row := vertex.y + 1
	if col < 0 or row < 0 or col >= cols or row >= rows or vertex.z < 0 or vertex.z >= PER_CELL:
		return -1
	return (row * cols + col) * PER_CELL + vertex.z


static func heightAt(data: WorldMapTileData, vertex: Vector3i, layerID := DEFAULT_LAYER) -> float:
	if not has(data, layerID):
		return 0.0
	var index := indexOf(data, vertex)
	if index < 0:
		return 0.0
	var values: PackedFloat32Array = data.layers[layerID]["VALUES"]
	return values[index] if index < values.size() else 0.0


## Writes a vertex height. Returns whether anything changed, matching
## `WorldMapTileData.setCell`'s contract so a history layer can coalesce no-ops the same way.
static func setHeightAt(
	data: WorldMapTileData, vertex: Vector3i, height: float, layerID := DEFAULT_LAYER
) -> bool:
	ensureLayer(data, layerID)
	var index := indexOf(data, vertex)
	if index < 0:
		return false
	var values: PackedFloat32Array = data.layers[layerID]["VALUES"]
	if index >= values.size() or is_equal_approx(values[index], height):
		return false
	values[index] = height
	return true


## The height at a hex's centre: the mean of its six vertices. Derived rather than stored,
## because a stored centre could disagree with the ring around it and there would be no way to
## say which was right.
static func centreHeight(data: WorldMapTileData, cell: Vector2i, layerID := DEFAULT_LAYER) -> float:
	var sum := 0.0
	for vertex in cellVertices(cell):
		sum += heightAt(data, vertex, layerID)
	return sum / float(CORNER_OFFSETS.size())


## THE interpolation. Every system that needs to know where the ground is calls this one function
## -- rendering builds its mesh from it, picking refines against it, object anchoring samples it,
## and the export carries what it produced. A second interpolation anywhere is two surfaces that
## disagree, which is the failure this item exists to prevent.
##
## Within a hex the surface is the six triangles fanning from its centre to consecutive corners,
## so the value is a plain barycentric blend of the centre and two corners. All six are tested
## rather than the sector being chosen by angle: a point on a fan edge belongs to both triangles
## and they agree there, so testing is exact where an angle comparison would need its own
## wrap-around care.
static func sample(data: WorldMapTileData, local: Vector2, layerID := DEFAULT_LAYER) -> float:
	if not has(data, layerID):
		return 0.0
	var cell := WorldMapHexGrid.worldToCell(local)
	var centre := WorldMapHexGrid.cellCentre(cell)
	var vertices := cellVertices(cell)
	var centreValue := 0.0
	for vertex in vertices:
		centreValue += heightAt(data, vertex, layerID)
	centreValue /= float(vertices.size())

	var point := local - centre
	var slot := fanTriangleOf(point)
	if slot < 0:
		# Numerically outside every fan triangle, which can only happen a hair outside the hex.
		# The centre value is the honest answer rather than a guess at which edge it fell past.
		return centreValue
	var weights := _barycentric(
		point, CORNER_OFFSETS[slot], CORNER_OFFSETS[(slot + 1) % CORNER_OFFSETS.size()]
	)
	return (
		weights.x * centreValue
		+ weights.y * heightAt(data, vertices[slot], layerID)
		+ weights.z * heightAt(data, vertices[(slot + 1) % vertices.size()], layerID)
	)


## Which of a hex's six fan triangles a point falls in, as an index into `CORNER_OFFSETS`, or -1
## when it falls in none. `offset` is measured FROM THE HEX CENTRE, which is the frame the fan is
## defined in.
##
## THE ONE DEFINITION OF FAN MEMBERSHIP in world space. `sample()` above is one caller and the
## editor's detail tool is the other; `WorldMapBaker` carries a deliberate second implementation
## in PIXEL space, for the reason its own note gives. Two is already one more than ideal -- a
## third, added because this loop happened to live inside `sample`, is how the terrain a click
## lands on and the terrain a triangle is painted into start disagreeing.
static func fanTriangleOf(offset: Vector2) -> int:
	for i in CORNER_OFFSETS.size():
		var a: Vector2 = CORNER_OFFSETS[i]
		var b: Vector2 = CORNER_OFFSETS[(i + 1) % CORNER_OFFSETS.size()]
		var weights := _barycentric(offset, a, b)
		if weights.x < -INSIDE_EPSILON or weights.y < -INSIDE_EPSILON or weights.z < -INSIDE_EPSILON:
			continue
		return i
	return -1


## The cell and fan triangle a REGION-LOCAL point falls in, as `(col, row, slot)` -- the same
## shape `WorldMapTileData.detailIndexOf` addresses a detail slot by. `slot` is -1 when the point
## resolves to a cell but to none of its triangles, which the caller must treat as "no target"
## rather than as slot 0.
static func triangleAt(local: Vector2) -> Vector3i:
	var cell := WorldMapHexGrid.worldToCell(local)
	return Vector3i(cell.x, cell.y, fanTriangleOf(local - WorldMapHexGrid.cellCentre(cell)))


## Barycentric weights of `point` in the triangle (origin, a, b), as (origin, a, b).
static func _barycentric(point: Vector2, a: Vector2, b: Vector2) -> Vector3:
	var determinant := a.x * b.y - b.x * a.y
	if absf(determinant) < 1e-12:
		return Vector3(1.0, 0.0, 0.0)
	var u := (point.x * b.y - b.x * point.y) / determinant
	var v := (a.x * point.y - point.x * a.y) / determinant
	return Vector3(1.0 - u - v, u, v)


## Every vertex touched by a set of cells, without duplicates -- the cells share them, which is
## the point.
static func verticesOfCells(cells: Array) -> Array[Vector3i]:
	var seen := {}
	var out: Array[Vector3i] = []
	for cell in cells:
		for vertex in cellVertices(cell as Vector2i):
			if seen.has(vertex):
				continue
			seen[vertex] = true
			out.append(vertex)
	return out


## Raises (or lowers, with a negative delta) one vertex. The tool that everything else is built
## from: because three hexes share the vertex, one edit moves all three at once, which is exactly
## what makes a hill a hill rather than a column.
static func raiseVertex(
	data: WorldMapTileData, vertex: Vector3i, delta: float, layerID := DEFAULT_LAYER
) -> bool:
	return setHeightAt(data, vertex, heightAt(data, vertex, layerID) + delta, layerID)


## Sets every vertex of every listed cell to one height. Flattening a region is the tool that
## makes a plateau or a lake floor, so it acts on the cells' shared vertices rather than on cell
## centres -- the boundary of a flattened area is shared with its unflattened neighbours, and
## those neighbours slope into it for free.
static func flatten(
	data: WorldMapTileData, cells: Array, height: float, layerID := DEFAULT_LAYER
) -> int:
	var changed := 0
	for vertex in verticesOfCells(cells):
		if setHeightAt(data, vertex, height, layerID):
			changed += 1
	return changed


## Moves every vertex of every listed cell a fraction of the way toward the mean of its own
## neighbourhood. Reads the whole field BEFORE writing any of it, so a smooth pass cannot feed
## its own output back in and drift across the sweep -- the ordinary Jacobi-versus-Gauss-Seidel
## trap, and the reason a smooth tool sometimes pulls terrain in the direction it happened to
## iterate.
static func smooth(
	data: WorldMapTileData, cells: Array, strength := 0.5, layerID := DEFAULT_LAYER
) -> int:
	var targets := verticesOfCells(cells)
	var before := {}
	for vertex in targets:
		before[vertex] = heightAt(data, vertex, layerID)
		for neighbour in neighbourVertices(vertex):
			if not before.has(neighbour):
				before[neighbour] = heightAt(data, neighbour, layerID)

	var changed := 0
	var amount := clampf(strength, 0.0, 1.0)
	for vertex in targets:
		var neighbours := neighbourVertices(vertex)
		if neighbours.is_empty():
			continue
		var sum := 0.0
		for neighbour in neighbours:
			sum += float(before[neighbour])
		var mean := sum / float(neighbours.size())
		var blended: float = lerpf(float(before[vertex]), mean, amount)
		if setHeightAt(data, vertex, blended, layerID):
			changed += 1
	return changed


## The vertices one step away: every other vertex of the three cells that meet at this one. On a
## hex lattice that is the natural neighbourhood, and it needs no separate adjacency table --
## sharing is what defines it.
static func neighbourVertices(vertex: Vector3i) -> Array[Vector3i]:
	var seen := {vertex: true}
	var out: Array[Vector3i] = []
	for cell in vertexCells(vertex):
		for other in cellVertices(cell):
			if seen.has(other):
				continue
			seen[other] = true
			out.append(other)
	return out


## A `Callable` shaped for `WorldMapObjectLayer.anchorHeight` -- cell in, height out. This is how
## an object comes to stand on the terrain rather than at zero, and it goes through `sample()`
## like everything else so an object cannot rest on a surface the renderer does not draw.
static func samplerFor(data: WorldMapTileData, layerID := DEFAULT_LAYER) -> Callable:
	return func(cell: Vector2i) -> float:
		return sample(data, WorldMapHexGrid.cellCentre(cell), layerID)


## THE SURFACE, AS GEOMETRY. The same interpolation `sample()` performs, emitted as a mesh: each
## hex fans into six triangles from its centre, with every vertex at the height the field holds
## and every hex centre at the mean of its six.
##
## THE RENDERED SURFACE IS THEREFORE THE SAMPLED SURFACE, not an approximation of it -- which is
## how this item's own risk ("picking and rendering sampling the surface differently, so the
## cursor sits off the visible ground on a slope") is closed by construction rather than by
## keeping two formulas in step. A displacement-mapped plane would have been the other option and
## would have needed exactly that agreement, at a mesh density fine enough to resolve a one-unit
## feature across a plane hundreds of units wide.
##
## POSITIONS ONLY. The ground shader derives its texture coordinates from `world_position.xz`
## rather than from mesh UVs, and it is unshaded, so normals and UVs would be dead weight.
##
## Vertices are shared between hexes rather than emitted per triangle -- they are the same point
## and must carry the same height, which is the entire premise of putting heights on vertices.
##
## `skirtTo` extends a flat frame out to that size around the lattice, so the fog still has
## geometry to close over where the region does not reach. It meets the lattice at its bounding
## box, so a vertex sculpted at the very edge of the lattice can separate from the skirt; nothing
## authored so far does that, and it is named rather than guarded against.
static func buildSurfaceMesh(
	data: WorldMapTileData, skirtTo := Vector2.ZERO, layerID := DEFAULT_LAYER
) -> ArrayMesh:
	var cols := data.size_tiles.x
	var rows := data.size_tiles.y
	if cols <= 0 or rows <= 0:
		return null

	var positions := PackedVector3Array()
	var indices := PackedInt32Array()
	var seen := {}

	for col in cols:
		for row in rows:
			var cell := Vector2i(col, row)
			var centre: Vector2 = WorldMapHexGrid.cellCentre(cell)
			var vertices := cellVertices(cell)
			# `z = 2` marks a hex CENTRE, which no real vertex uses -- vertices are index 0 or 1.
			var centreKey := Vector3i(col, row, 2)
			var centreIndex := _vertexIndex(
				seen, positions, centreKey,
				Vector3(centre.x, centreHeight(data, cell, layerID), centre.y)
			)
			for i in vertices.size():
				var a: Vector3i = vertices[i]
				var b: Vector3i = vertices[(i + 1) % vertices.size()]
				var pa: Vector2 = centre + CORNER_OFFSETS[i]
				var pb: Vector2 = centre + CORNER_OFFSETS[(i + 1) % CORNER_OFFSETS.size()]
				var ia := _vertexIndex(
					seen, positions, a, Vector3(pa.x, heightAt(data, a, layerID), pa.y)
				)
				var ib := _vertexIndex(
					seen, positions, b, Vector3(pb.x, heightAt(data, b, layerID), pb.y)
				)
				# Wound so the surface faces up, matching a PlaneMesh's own winding.
				indices.append(centreIndex)
				indices.append(ib)
				indices.append(ia)

	var extent: Vector2 = WorldMapHexGrid.latticeExtent(cols, rows)
	if skirtTo.x > extent.x or skirtTo.y > extent.y:
		_appendSkirt(positions, indices, extent, skirtTo)

	var arrays := []
	arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX] = positions
	arrays[Mesh.ARRAY_INDEX] = indices
	var mesh := ArrayMesh.new()
	mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
	return mesh


static func _vertexIndex(
	seen: Dictionary, positions: PackedVector3Array, key: Vector3i, position: Vector3
) -> int:
	if seen.has(key):
		return int(seen[key])
	var index := positions.size()
	positions.append(position)
	seen[key] = index
	return index


## A flat frame from the lattice's bounding box out to `outer`, centred on the lattice, so the
## fog has somewhere to close before the geometry runs out. Four quads, deliberately not one big
## quad under the lattice: overlapping the hex surface at the same height would z-fight across
## the whole map on a flat field.
static func _appendSkirt(
	positions: PackedVector3Array, indices: PackedInt32Array, extent: Vector2, outer: Vector2
) -> void:
	var margin := Vector2(
		maxf(0.0, (outer.x - extent.x) * 0.5), maxf(0.0, (outer.y - extent.y) * 0.5)
	)
	var x0 := -margin.x
	var y0 := -margin.y
	var x1 := extent.x + margin.x
	var y1 := extent.y + margin.y
	var frames := [
		[Vector2(x0, y0), Vector2(x1, 0.0)],
		[Vector2(x0, extent.y), Vector2(x1, y1)],
		[Vector2(x0, 0.0), Vector2(0.0, extent.y)],
		[Vector2(extent.x, 0.0), Vector2(x1, extent.y)],
	]
	for frame in frames:
		var lo: Vector2 = frame[0]
		var hi: Vector2 = frame[1]
		if hi.x <= lo.x or hi.y <= lo.y:
			continue
		var base := positions.size()
		positions.append(Vector3(lo.x, 0.0, lo.y))
		positions.append(Vector3(hi.x, 0.0, lo.y))
		positions.append(Vector3(hi.x, 0.0, hi.y))
		positions.append(Vector3(lo.x, 0.0, hi.y))
		for offset in [0, 2, 1, 0, 3, 2]:
			indices.append(base + offset)


## A `Callable` shaped for picking: a region-local world POINT in, a height out. Distinct from
## `samplerFor`, which takes a cell -- an object stands on one hex, but a ray can meet the ground
## anywhere inside one, and rounding a pick to its cell centre would put the cursor visibly off
## the ground on a slope.
static func pointSamplerFor(data: WorldMapTileData, layerID := DEFAULT_LAYER) -> Callable:
	return func(local: Vector2) -> float:
		return sample(data, local, layerID)
