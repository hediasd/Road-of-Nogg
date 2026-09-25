## Builds new hex geometry only: the top-fan surface mesh and hex-shaped pick
## shape HexBattleBoardView needs, and the banded hex rings the board draws
## over authored terrain. Owns no shared shader, no palette, and no state of
## its own. The exported map scene is the terrain a player sees; this
## factory's meshes are tactical overlay and picking geometry on top of it.

class_name HexBattleMeshFactory
extends RefCounted

## Unshaded and double-sided so the overlay reads the same regardless of
## camera angle or scene lighting -- appropriate for a probe/debug surface,
## not a claim about how the shipped board should look.
const DEBUG_SURFACE_COLOR := Color(0.42, 0.46, 0.5)

## Half the pick prism's vertical extent. Thin enough to stay visually flush
## with the surface mesh, thick enough that a raycast is never rejected for
## grazing an exactly zero-height plane.
const PICK_SHAPE_HALF_THICKNESS := 0.02


## A six-triangle top fan from `center` to each consecutive pair of
## `polygon`'s six corners (both in absolute world space, as
## HexBattleLayout.cellCenter/cellPolygon return them). Triangles wind
## center -> corner[i] -> corner[i+1], which is front-facing-up under
## Godot's clockwise-from-in-front convention for a polygon that runs
## anticlockwise when viewed from above -- every normal below is exactly
## Vector3.UP rather than an average that merely leans upward.
static func createSurfaceMesh(center: Vector3, polygon: PackedVector3Array) -> ArrayMesh:
	var vertices := PackedVector3Array()
	var normals := PackedVector3Array()
	var cornerCount := polygon.size()
	for index in range(cornerCount):
		var a := polygon[index]
		var b := polygon[(index + 1) % cornerCount]
		vertices.append(center)
		vertices.append(a)
		vertices.append(b)
		normals.append(Vector3.UP)
		normals.append(Vector3.UP)
		normals.append(Vector3.UP)

	var arrays: Array = []
	arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX] = vertices
	arrays[Mesh.ARRAY_NORMAL] = normals

	var mesh := ArrayMesh.new()
	mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
	return mesh


## A flat, unshaded material distinct from every shared shader family so a
## probe or debug view never implies a palette choice for the shipped board.
static func createDebugMaterial() -> StandardMaterial3D:
	var material := StandardMaterial3D.new()
	material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	material.albedo_color = DEBUG_SURFACE_COLOR
	material.cull_mode = BaseMaterial3D.CULL_DISABLED
	return material


## Appends one ring band inside `polygon` to a flat triangle list. `outer` and
## `inner` are fractions of the way from the hex edge toward `center` (0 is the
## edge itself), so a band never reaches past its own cell and two neighbours'
## bands sit side by side instead of overlapping and doubling their alpha.
static func appendRingBand(
	vertices: PackedVector3Array, colors: PackedColorArray, center: Vector3,
	polygon: PackedVector3Array, outer: float, inner: float, color: Color
) -> void:
	var cornerCount := polygon.size()
	for index in range(cornerCount):
		var a := polygon[index]
		var b := polygon[(index + 1) % cornerCount]
		var aOuter := a.lerp(center, outer)
		var bOuter := b.lerp(center, outer)
		var aInner := a.lerp(center, inner)
		var bInner := b.lerp(center, inner)
		for point: Vector3 in [aInner, aOuter, bOuter, aInner, bOuter, bInner]:
			vertices.append(point)
			colors.append(color)


## A mesh from a flat, vertex-coloured triangle list, every normal up. Paired
## with `createOverlayMaterial`, which reads the colours as albedo.
static func createColoredMesh(vertices: PackedVector3Array, colors: PackedColorArray) -> ArrayMesh:
	var normals := PackedVector3Array()
	normals.resize(vertices.size())
	normals.fill(Vector3.UP)
	var arrays: Array = []
	arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX] = vertices
	arrays[Mesh.ARRAY_NORMAL] = normals
	arrays[Mesh.ARRAY_COLOR] = colors
	var mesh := ArrayMesh.new()
	if not vertices.is_empty():
		mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
	return mesh


## Unshaded, alpha-blended, vertex-coloured. Unshaded for the same reason the
## debug surface is: a tactical line must read the same under any light the
## stage is given. `renderPriority` orders overlays that share a height band.
static func createOverlayMaterial(renderPriority: int = 0) -> StandardMaterial3D:
	var material := StandardMaterial3D.new()
	material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	material.vertex_color_use_as_albedo = true
	material.albedo_color = Color.WHITE
	material.cull_mode = BaseMaterial3D.CULL_DISABLED
	material.render_priority = renderPriority
	return material


## One wash for every reachable hex and one contour only on the outside edge of their union.
## Edges are paired from the authored polygons rather than inferred from axial direction, so the
## contour cannot gap when an odd-column offset or a raised cell changes the local geometry.
static func createRegionMesh(
		centers: Dictionary, polygons: Dictionary, washColor: Color,
		contourColor: Color, contourInset: float
) -> ArrayMesh:
	var vertices := PackedVector3Array()
	var colors := PackedColorArray()
	var edges: Dictionary = {}
	for cell in polygons:
		var center: Vector3 = centers[cell]
		var polygon: PackedVector3Array = polygons[cell]
		for index in range(polygon.size()):
			vertices.append(center)
			vertices.append(polygon[index])
			vertices.append(polygon[(index + 1) % polygon.size()])
			colors.append(washColor)
			colors.append(washColor)
			colors.append(washColor)
			var a := polygon[index]
			var b := polygon[(index + 1) % polygon.size()]
			var key := _regionEdgeKey(a, b)
			if edges.has(key):
				edges[key]["count"] = int(edges[key]["count"]) + 1
			else:
				edges[key] = {"count": 1, "a": a, "b": b, "center": center}
	for key in edges:
		var edge: Dictionary = edges[key]
		if int(edge["count"]) != 1:
			continue
		var center: Vector3 = edge["center"]
		var a: Vector3 = edge["a"]
		var b: Vector3 = edge["b"]
		var innerA := a.lerp(center, contourInset)
		var innerB := b.lerp(center, contourInset)
		for point: Vector3 in [innerA, a, b, innerA, b, innerB]:
			vertices.append(point)
			colors.append(contourColor)
	return createColoredMesh(vertices, colors)


static func _regionEdgeKey(a: Vector3, b: Vector3) -> String:
	var aKey := "%0.5f,%0.5f,%0.5f" % [a.x, a.y, a.z]
	var bKey := "%0.5f,%0.5f,%0.5f" % [b.x, b.y, b.z]
	return "%s|%s" % [aKey, bKey] if aKey < bKey else "%s|%s" % [bKey, aKey]


## A raised, vertex-coloured game board around the painted battlefield. The five matching loops
## describe its recessed playfield, inner rise, broad top rim, outer bevel and bottom wall. The mesh
## owns no collision: tactical picking stays on the per-cell bodies above it.
static func createRaisedBoard(
		playfieldTop: PackedVector3Array,
		innerRimTop: PackedVector3Array,
		outerRimTop: PackedVector3Array,
		outerEdge: PackedVector3Array,
		bottomY: float,
		fieldColor: Color,
		innerBevelColor: Color,
		rimColor: Color,
		outerBevelColor: Color,
		sideColor: Color
) -> ArrayMesh:
	assert(playfieldTop.size() == innerRimTop.size() \
			and playfieldTop.size() == outerRimTop.size() \
			and playfieldTop.size() == outerEdge.size() \
			and playfieldTop.size() >= 3,
		"Raised board loops must have the same polygon size.")
	var vertices := PackedVector3Array()
	var normals := PackedVector3Array()
	var colors := PackedColorArray()
	var center := Vector3.ZERO
	for point: Vector3 in playfieldTop:
		center += point
	center /= float(playfieldTop.size())

	# Recessed bed: visible through transparent/unset terrain texels, never over painted art.
	for index in range(playfieldTop.size()):
		_appendColoredTriangle(vertices, normals, colors,
			center, playfieldTop[index], playfieldTop[(index + 1) % playfieldTop.size()],
			Vector3.UP, fieldColor)

	# A short rise makes the terrain read as seated inside the frame.
	for index in range(playfieldTop.size()):
		var next := (index + 1) % playfieldTop.size()
		_appendColoredQuad(vertices, normals, colors,
			playfieldTop[index], innerRimTop[index], innerRimTop[next], playfieldTop[next],
			Vector3.UP, innerBevelColor)

	# Broad horizontal rim, the defining shape from the reference boards.
	for index in range(innerRimTop.size()):
		var next := (index + 1) % innerRimTop.size()
		_appendColoredQuad(vertices, normals, colors,
			innerRimTop[index], outerRimTop[index], outerRimTop[next], innerRimTop[next],
			Vector3.UP, rimColor)

	# Sloped outer shoulder catches a second tone before the deep wall.
	for index in range(outerRimTop.size()):
		var next := (index + 1) % outerRimTop.size()
		_appendColoredQuad(vertices, normals, colors,
			outerRimTop[index], outerEdge[index], outerEdge[next], outerRimTop[next],
			Vector3.UP, outerBevelColor)

	# Vertical wall. The board is never seen from below, so no bottom face is needed.
	for index in range(outerEdge.size()):
		var next := (index + 1) % outerEdge.size()
		var topA: Vector3 = outerEdge[index]
		var topB: Vector3 = outerEdge[next]
		var bottomA := Vector3(topA.x, bottomY, topA.z)
		var bottomB := Vector3(topB.x, bottomY, topB.z)
		var normal := (topB - topA).cross(bottomA - topA).normalized()
		_appendColoredQuad(vertices, normals, colors,
			topA, bottomA, bottomB, topB, normal, sideColor)

	var arrays: Array = []
	arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX] = vertices
	arrays[Mesh.ARRAY_NORMAL] = normals
	arrays[Mesh.ARRAY_COLOR] = colors
	var mesh := ArrayMesh.new()
	mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
	return mesh


## Unshaded because the board is furniture around the art, not another terrain colour. Its authored
## face colours remain stable under every battle light and camera angle.
static func createBoardMaterial() -> StandardMaterial3D:
	var material := StandardMaterial3D.new()
	material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	material.vertex_color_use_as_albedo = true
	material.cull_mode = BaseMaterial3D.CULL_DISABLED
	return material


static func _appendColoredTriangle(
		vertices: PackedVector3Array,
		normals: PackedVector3Array,
		colors: PackedColorArray,
		a: Vector3,
		b: Vector3,
		c: Vector3,
		normal: Vector3,
		color: Color
) -> void:
	for point: Vector3 in [a, b, c]:
		vertices.append(point)
		normals.append(normal)
		colors.append(color)


static func _appendColoredQuad(
		vertices: PackedVector3Array,
		normals: PackedVector3Array,
		colors: PackedColorArray,
		a: Vector3,
		b: Vector3,
		c: Vector3,
		d: Vector3,
		normal: Vector3,
		color: Color
) -> void:
	_appendColoredTriangle(vertices, normals, colors, a, b, c, normal, color)
	_appendColoredTriangle(vertices, normals, colors, a, c, d, normal, color)


## A convex hex prism covering exactly `polygon` at `center`'s height, so a
## raycast near a slanted edge resolves to the true hex rather than a
## neighbour a bounding box would have picked up. `ConvexPolygonShape3D`
## derives its own hull from a point cloud; the six corners duplicated at two
## Y offsets around `center.y` are already convex and coplanar in pairs, so
## the hull is exactly this hex, not an approximation of it.
static func createPickShape(center: Vector3, polygon: PackedVector3Array) -> ConvexPolygonShape3D:
	var points := PackedVector3Array()
	for corner: Vector3 in polygon:
		points.append(Vector3(corner.x, center.y - PICK_SHAPE_HALF_THICKNESS, corner.z))
		points.append(Vector3(corner.x, center.y + PICK_SHAPE_HALF_THICKNESS, corner.z))
	var shape := ConvexPolygonShape3D.new()
	shape.points = points
	return shape
