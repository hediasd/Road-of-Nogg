extends SceneTree

const BattleCursorControllerScript = preload("res://src/presentation/BattleCursorController.gd")


func _init() -> void:
	call_deferred("_run")


func _run() -> void:
	var cursor = MeshInstance3D.new()
	root.add_child(cursor)
	var controller = BattleCursorControllerScript.new(cursor)

	controller.focusTurn(Vector2i(1, 1))
	controller.animateTurnPath(
		[Vector2i(1, 1), Vector2i(2, 1), Vector2i(3, 1)],
		Vector2i(3, 1)
	)
	await create_timer(0.05).timeout

	controller.focusTurn(Vector2i(7, 4))
	await create_timer(0.7).timeout
	if controller.grid_position != Vector2i(7, 4):
		_fail("superseded turn tween changed the grid position")
		return
	if cursor.position != Vector3(7, BattleCursorControllerScript.CURSOR_HEIGHT, 4):
		_fail("superseded turn tween changed the visual position")
		return

	controller.focusPlayerSelection(Vector2i(5, 2))
	await create_timer(0.1).timeout
	if controller.mode != BattleCursorControllerScript.Mode.PLAYER_SELECTION:
		_fail("player selection did not retain cursor ownership")
		return
	if controller.grid_position != Vector2i(5, 2):
		_fail("player selection moved unexpectedly")
		return

	print("CURSOR_CONTROLLER_OK")
	quit(0)


func _fail(reason: String) -> void:
	push_error("CURSOR_CONTROLLER_FAILED: %s" % reason)
	quit(1)
