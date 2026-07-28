## Keeps an entity's complete status-badge row aligned to the active battle camera.

extends Node3D


func _process(_delta: float) -> void:
	var camera := get_viewport().get_camera_3d()
	if camera == null or not is_instance_valid(camera):
		return
	_face_camera(camera)


func _face_camera(camera: Camera3D) -> void:
	var row_transform := global_transform
	row_transform.basis = camera.global_transform.basis.orthonormalized()
	global_transform = row_transform
