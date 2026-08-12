## Effect-owned low-poly meshes for the target encasement shell.

class_name IceChunkMeshFactory
extends RefCounted

enum Kind { BLOCK, WEDGE, CRYSTAL, SPIKE }


static func create(kind: Kind) -> ArrayMesh:
	match kind:
		Kind.BLOCK:
			return _blockMesh()
		Kind.WEDGE:
			return _wedgeMesh()
		Kind.CRYSTAL:
			return _crystalMesh()
		Kind.SPIKE:
			return _spikeMesh()
	assert(false, "Unknown ice chunk mesh kind.")
	return ArrayMesh.new()


static func kindName(kind: Kind) -> String:
	return Kind.keys()[kind].to_lower()


static func _blockMesh() -> ArrayMesh:
	return _fromTriangles(
		PackedVector3Array([
			Vector3(-0.50, -0.50, 0.48), Vector3(0.50, -0.50, 0.48),
			Vector3(0.50, 0.50, 0.48), Vector3(-0.50, 0.50, 0.48),
			Vector3(-0.42, -0.42, -0.10), Vector3(0.38, -0.48, -0.10),
			Vector3(0.44, 0.34, -0.10), Vector3(-0.46, 0.46, -0.10),
			Vector3(-0.12, -0.20, -0.62), Vector3(0.10, 0.16, -0.68),
		]),
		_faces([
			[0, 2, 1], [0, 3, 2],
			[0, 1, 5], [0, 5, 4], [1, 2, 6], [1, 6, 5],
			[2, 3, 7], [2, 7, 6], [3, 0, 4], [3, 4, 7],
			[4, 5, 8], [5, 9, 8], [5, 6, 9], [6, 7, 9],
			[7, 8, 9], [7, 4, 8],
		])
	)


static func _wedgeMesh() -> ArrayMesh:
	return _fromTriangles(
		PackedVector3Array([
			Vector3(-0.50, -0.50, 0.50), Vector3(0.50, -0.50, 0.50),
			Vector3(-0.42, 0.50, 0.50), Vector3(-0.38, -0.42, -0.08),
			Vector3(0.34, -0.38, -0.08), Vector3(-0.30, 0.40, -0.08),
			Vector3(-0.08, -0.18, -0.68), Vector3(-0.12, 0.30, -0.62),
		]),
		_faces([
			[0, 2, 1], [0, 1, 4], [0, 4, 3], [1, 2, 5], [1, 5, 4],
			[2, 0, 3], [2, 3, 5], [3, 4, 6], [4, 7, 6],
			[4, 5, 7], [5, 3, 6], [5, 6, 7],
		])
	)


static func _crystalMesh() -> ArrayMesh:
	return _fromTriangles(
		PackedVector3Array([
			Vector3(-0.44, -0.46, 0.48), Vector3(0.46, -0.40, 0.48),
			Vector3(0.38, 0.40, 0.48), Vector3(-0.36, 0.48, 0.48),
			Vector3(-0.30, -0.34, -0.06), Vector3(0.28, -0.28, -0.12),
			Vector3(0.22, 0.30, -0.08), Vector3(-0.26, 0.34, -0.14),
			Vector3(0.04, 0.02, -0.72),
		]),
		_faces([
			[0, 2, 1], [0, 3, 2], [0, 1, 5], [0, 5, 4],
			[1, 2, 6], [1, 6, 5], [2, 3, 7], [2, 7, 6],
			[3, 0, 4], [3, 4, 7], [4, 5, 8], [5, 6, 8],
			[6, 7, 8], [7, 4, 8],
		])
	)


static func _spikeMesh() -> ArrayMesh:
	return _fromTriangles(
		PackedVector3Array([
			Vector3(-0.48, 0.0, -0.36), Vector3(0.42, 0.0, -0.42),
			Vector3(0.50, 0.0, 0.34), Vector3(-0.38, 0.0, 0.48),
			Vector3(-0.26, 0.18, -0.22), Vector3(0.24, 0.16, -0.26),
			Vector3(0.28, 0.20, 0.20), Vector3(-0.22, 0.14, 0.26),
			Vector3(0.06, 1.0, -0.04),
		]),
		_faces([
			[0, 2, 1], [0, 3, 2], [0, 1, 5], [0, 5, 4],
			[1, 2, 6], [1, 6, 5], [2, 3, 7], [2, 7, 6],
			[3, 0, 4], [3, 4, 7], [4, 5, 8], [5, 6, 8],
			[6, 7, 8], [7, 4, 8],
		])
	)


static func _faces(values: Array) -> Array[PackedInt32Array]:
	var result: Array[PackedInt32Array] = []
	for value in values:
		result.append(PackedInt32Array(value))
	return result


static func _fromTriangles(
		vertices: PackedVector3Array,
		faces: Array[PackedInt32Array]) -> ArrayMesh:
	var surface := SurfaceTool.new()
	surface.begin(Mesh.PRIMITIVE_TRIANGLES)
	for face: PackedInt32Array in faces:
		assert(face.size() == 3, "Ice chunk faces must be triangles.")
		var uvs := _triangleUVs(vertices, face)
		for cornerIndex: int in range(face.size()):
			var vertexIndex := face[cornerIndex]
			surface.set_uv(uvs[cornerIndex])
			surface.add_vertex(vertices[vertexIndex])
	surface.generate_normals()
	return surface.commit()


static func _triangleUVs(
		vertices: PackedVector3Array,
		face: PackedInt32Array) -> Array[Vector2]:
	var first := vertices[face[0]]
	var second := vertices[face[1]]
	var third := vertices[face[2]]
	var normal := (second - first).cross(third - first).abs()
	var result: Array[Vector2] = []
	for vertexIndex: int in face:
		var vertex := vertices[vertexIndex]
		var uv := Vector2.ZERO
		if normal.x >= normal.y and normal.x >= normal.z:
			uv = Vector2((vertex.z + 0.72) / 1.22, 1.0 - (vertex.y + 0.5) / 1.5)
		elif normal.y >= normal.z:
			uv = Vector2((vertex.x + 0.5), (vertex.z + 0.72) / 1.22)
		else:
			uv = Vector2((vertex.x + 0.5), 1.0 - (vertex.y + 0.5) / 1.5)
		result.append(Vector2(clampf(uv.x, 0.0, 1.0), clampf(uv.y, 0.0, 1.0)))
	return result
