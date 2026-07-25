extends ImmediateMesh

func rebuild() -> void:
	clear_surfaces()
	surface_begin(Mesh.PRIMITIVE_TRIANGLES)

	surface_set_normal(Vector3(0, 0, 1))
	surface_set_uv(Vector2(0, 0))
	surface_add_vertex(Vector3(-1, -1, 0))

	surface_set_normal(Vector3(0, 0, 1))
	surface_set_uv(Vector2(0, 1))
	surface_add_vertex(Vector3(-5, 5, 0))

	surface_set_normal(Vector3(0, 0, 1))
	surface_set_uv(Vector2(1, 1))
	surface_add_vertex(Vector3(5, 5, 0))

	surface_end()
