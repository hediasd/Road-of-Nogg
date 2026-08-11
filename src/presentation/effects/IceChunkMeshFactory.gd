## Effect-owned low-poly meshes for the target encasement shell.

class_name IceChunkMeshFactory
extends RefCounted

enum Kind { BLOCK, WEDGE, CRYSTAL }


static func create(kind: Kind) -> ArrayMesh:
	match kind:
		Kind.BLOCK:
			return _blockMesh()
		Kind.WEDGE:
			return _wedgeMesh()
		Kind.CRYSTAL:
			return _crystalMesh()
	assert(false, "Unknown ice chunk mesh kind.")
	return ArrayMesh.new()


static func kindName(kind: Kind) -> String:
	return Kind.keys()[kind].to_lower()


static func _blockMesh() -> ArrayMesh:
	return _fromTriangles(
		PackedVector3Array([
			Vector3(-0.50, -0.50, -0.50), Vector3(0.50, -0.50, -0.50),
			Vector3(0.50, 0.50, -0.50), Vector3(-0.50, 0.50, -0.50),
			Vector3(-0.46, -0.46, 0.50), Vector3(0.44, -0.50, 0.50),
			Vector3(0.50, 0.43, 0.50), Vector3(-0.50, 0.50, 0.50),
		]),
		_faces([
			[0, 2, 1], [0, 3, 2], [4, 5, 6], [4, 6, 7],
			[0, 1, 5], [0, 5, 4], [3, 7, 6], [3, 6, 2],
			[1, 2, 6], [1, 6, 5], [0, 4, 7], [0, 7, 3],
		])
	)


static func _wedgeMesh() -> ArrayMesh:
	return _fromTriangles(
		PackedVector3Array([
			Vector3(-0.50, -0.50, -0.50), Vector3(0.50, -0.50, -0.50),
			Vector3(-0.50, 0.50, -0.50), Vector3(-0.50, -0.50, 0.50),
			Vector3(0.50, -0.50, 0.50), Vector3(-0.50, 0.50, 0.50),
		]),
		_faces([
			[0, 2, 1], [3, 4, 5], [0, 1, 4], [0, 4, 3],
			[0, 3, 5], [0, 5, 2], [2, 5, 4], [2, 4, 1],
		])
	)


static func _crystalMesh() -> ArrayMesh:
	return _fromTriangles(
		PackedVector3Array([
			Vector3(-0.42, -0.50, -0.42), Vector3(0.44, -0.46, -0.34),
			Vector3(0.50, -0.36, 0.38), Vector3(-0.48, -0.44, 0.46),
			Vector3(-0.28, 0.34, -0.34), Vector3(0.24, 0.50, -0.18),
			Vector3(0.30, 0.27, 0.35), Vector3(-0.22, 0.43, 0.29),
		]),
		_faces([
			[0, 2, 1], [0, 3, 2], [4, 5, 6], [4, 6, 7],
			[0, 1, 5], [0, 5, 4], [1, 2, 6], [1, 6, 5],
			[2, 3, 7], [2, 7, 6], [3, 0, 4], [3, 4, 7],
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
		for vertexIndex: int in face:
			surface.add_vertex(vertices[vertexIndex])
	surface.generate_normals()
	return surface.commit()
