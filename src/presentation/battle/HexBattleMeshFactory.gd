## Builds new hex geometry only: the top-fan surface mesh and hex-shaped pick
## shape HexBattleBoardView needs. Owns no shared shader, no palette, and no
## state of its own -- every material here is the neutral debug look this
## item is scoped to, not an art decision. HXB-13 supplies the visible
## exported terrain; this factory's meshes are tactical overlay/picking
## geometry underneath it.

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
