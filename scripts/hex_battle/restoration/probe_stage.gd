extends SceneTree

const StageScript = preload("res://src/presentation/battle/HexBattleStage.gd")
const CameraScript = preload("res://src/presentation/battle/HexBattleCamera.gd")

var _failures: Array[String] = []


func _initialize() -> void:
	call_deferred("_run")


func _run() -> void:
	await process_frame
	var baseline := _stageNodeCount()
	var stage = await _buildStage()
	_check(stage != null, "stage did not build")
	if stage != null:
		_checkLightAndWorld(stage)
		_checkProjectionControl(stage)
		await _checkConversions(stage)
		stage.dispose()
		await _frames(3)
		_check(_stageNodeCount() == baseline, "stage resources survived teardown")

	var restarted = await _buildStage()
	_check(restarted != null, "stage did not restart")
	if restarted != null:
		_checkLightAndWorld(restarted)
		restarted.dispose()
		await _frames(3)
		_check(_stageNodeCount() == baseline, "restarted stage resources survived teardown")

	if _failures.is_empty():
		print("HPR_STAGE_OK")
		quit(0)
		return
	for failure in _failures:
		push_error(failure)
	quit(1)


func _buildStage():
	var stage = StageScript.new()
	root.add_child(stage)
	await process_frame
	var camera = CameraScript.new()
	stage.worldRoot().add_child(camera)
	stage.attachCamera(camera)
	camera.focusOn(Vector3.ZERO)
	camera.camera.current = true
	await _frames(2)
	return stage


func _checkLightAndWorld(stage) -> void:
	_check(stage.renderer != null, "renderer is missing")
	_check(stage.renderer.world_viewport.own_world_3d, "render viewport does not own its world")
	_check(stage.renderer.world_root.get_child_count() == 3,
		"expected environment, light and camera in one world")
	_check(stage.renderer.world_viewport.get_camera_3d() == stage._camera.camera,
		"isolated viewport does not have exactly the stage camera active")
	_check(stage.environment.environment != null, "battle environment is missing")
	_check(stage.light.rotation_degrees.is_equal_approx(stage.LIGHT_ROTATION),
		"key-light rotation changed")
	_check(stage.light.light_color.is_equal_approx(stage.LIGHT_COLOR), "key-light color changed")
	_check(is_equal_approx(stage.light.light_energy, stage.LIGHT_ENERGY), "key-light energy changed")
	_check(not stage.light.shadow_enabled, "key-light shadows must remain disabled")
	_check(stage.graphicsPanel.battleCamera == stage._camera,
		"graphics panel did not receive the stage camera")


func _checkProjectionControl(stage) -> void:
	var option: OptionButton = stage.graphicsPanel.projectionOption
	_check(option != null, "graphics panel projection control is missing")
	if option == null:
		return
	var orthographicIndex := -1
	var perspectiveIndex := -1
	for index in range(option.item_count):
		var value := str(option.get_item_metadata(index))
		if value == stage._camera.PROJECTION_ORTHOGRAPHIC:
			orthographicIndex = index
		elif value == stage._camera.PROJECTION_PERSPECTIVE:
			perspectiveIndex = index
	_check(orthographicIndex >= 0 and perspectiveIndex >= 0,
		"graphics panel projection choices are incomplete")
	if orthographicIndex < 0 or perspectiveIndex < 0:
		return
	_check(stage._camera.projectionMode() == stage._camera.PROJECTION_ORTHOGRAPHIC,
		"orthographic is not the default projection")
	_check(str(option.get_item_metadata(option.selected)) \
		== stage._camera.PROJECTION_ORTHOGRAPHIC,
		"graphics panel did not show the orthographic default")
	var left := Vector3(-2.0, 0.0, 0.0)
	var right := Vector3(2.0, 0.0, 0.0)
	option.select(perspectiveIndex)
	option.item_selected.emit(perspectiveIndex)
	var perspectiveLeft: Vector2 = stage._camera.projectToRenderViewport(left)
	var perspectiveRight: Vector2 = stage._camera.projectToRenderViewport(right)
	var perspectiveSpan: float = perspectiveLeft.distance_to(perspectiveRight)
	option.select(orthographicIndex)
	option.item_selected.emit(orthographicIndex)
	_check(stage._camera.projectionMode() == stage._camera.PROJECTION_ORTHOGRAPHIC,
		"projection control did not select orthographic")
	_check(stage._camera.camera.projection == Camera3D.PROJECTION_ORTHOGONAL,
		"camera did not enter orthographic projection")
	_check(stage._camera.camera.position.length() >= stage._camera.ORTHOGRAPHIC_CAMERA_DISTANCE - 0.01,
		"orthographic camera remained close enough for the rotating board to cross its near plane")
	var orthographicLeft: Vector2 = stage._camera.projectToRenderViewport(left)
	var orthographicRight: Vector2 = stage._camera.projectToRenderViewport(right)
	var orthographicSpan: float = orthographicLeft.distance_to(orthographicRight)
	_check(absf(perspectiveSpan - orthographicSpan) < 0.5,
		"projection switch visibly changed the board scale")


func _checkConversions(stage) -> void:
	var sizes := [Vector2i(1280, 720), Vector2i(1920, 1080)]
	var presets := [stage.renderer.PRESET_NONE, stage.renderer.PRESET_DITHERED_HORIZON]
	var projections := [
		stage._camera.PROJECTION_PERSPECTIVE,
		stage._camera.PROJECTION_ORTHOGRAPHIC,
	]
	var points := [Vector3.ZERO, Vector3(-2.0, 0.0, 0.0), Vector3(2.0, 0.0, 0.0)]
	for size in sizes:
		root.size = size
		await _frames(2)
		for preset in presets:
			stage.renderer.set_preset(preset, false)
			await _frames(2)
			for projection in projections:
				stage._camera.setProjectionMode(projection)
				await _frames(2)
				var rect: Rect2 = stage.displayRect()
				_check(rect.size.x > 0.0 and rect.size.y > 0.0,
					"empty display rect at %s / %s / %s" % [size, preset, projection])
				for worldPoint in points:
					var renderPoint: Vector2 = stage._camera.projectToRenderViewport(worldPoint)
					var screenPoint: Vector2 = stage.projectWorldToScreen(worldPoint)
					_check(renderPoint.x >= 0.0 and rect.has_point(screenPoint),
						"projected point escaped display at %s / %s / %s" % [
							size, preset, projection])
					var roundTrip: Vector2 = stage.screenToRenderViewport(screenPoint)
					_check(roundTrip.distance_to(renderPoint) < 0.05,
						"projection round trip drifted at %s / %s / %s" % [
							size, preset, projection])
				var margin := rect.position - Vector2.ONE
				if margin.x >= 0.0 and margin.y >= 0.0:
					_check(stage.screenToRenderViewport(margin).x < 0.0,
						"letterbox margin became pickable")
	stage._camera.setProjectionMode(stage._camera.PROJECTION_ORTHOGRAPHIC)


func _stageNodeCount() -> int:
	return _countNamed(root, {
		"HexBattleStage": true,
		"BattleWorldViewport": true,
		"BattleWorldDisplay": true,
		"CRTOverlayLayer": true,
		"BattleWorld": true,
		"BattleKeyLight": true,
		"BattleEnvironment": true,
		"HexGraphicsPanel": true,
	})


func _countNamed(node: Node, wanted: Dictionary) -> int:
	var result := 1 if wanted.has(node.name) else 0
	for child: Node in node.get_children():
		result += _countNamed(child, wanted)
	return result


func _frames(count: int) -> void:
	for _index in range(count):
		await process_frame


func _check(condition: bool, message: String) -> void:
	if not condition:
		_failures.append(message)
