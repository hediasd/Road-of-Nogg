extends ImmediateMesh

func _process(_delta):
	# Clean up before drawing.


	# Begin draw.
	begin(Mesh.PRIMITIVE_TRIANGLES)

	# Prepare attributes for add_vertex.
	set_normal(Vector3(0, 0, 1))
	set_uv(Vector2(0, 0))
	# Call last for each vertex, adds the above attributes.
	add_vertex(Vector3(-1, -1, 0))

	set_normal(Vector3(0, 0, 1))
	set_uv(Vector2(0, 1))
	add_vertex(Vector3(-5, 5, 0))

	set_normal(Vector3(0, 0, 1))
	set_uv(Vector2(1, 1))
	add_vertex(Vector3(5, 5, 0))

	# End drawing.
	end()
