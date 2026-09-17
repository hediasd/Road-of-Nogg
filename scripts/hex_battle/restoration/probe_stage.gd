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
		_checkOrthographicOnly(stage)
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


func _checkOrthographicOnly(stage) -> void:
	var hasProjectionProperty := false
	for property: Dictionary in stage.graphicsPanel.get_property_list():
		if str(property.get("name", "")) == "projectionOption":
			hasProjectionProperty = true
	_check(not hasProjectionProperty,
		"graphics panel still exposes a projection control")
	_check(stage._camera.camera.projection == Camera3D.PROJECTION_ORTHOGONAL,
		"camera is not orthographic")
	_check(stage._camera.camera.position.length() >= stage._camera.ORTHOGRAPHIC_CAMERA_DISTANCE - 0.01,
		"orthographic camera remained close enough for the rotating board to cross its near plane")


func _checkConversions(stage) -> void:
	var sizes := [Vector2i(1280, 720), Vector2i(1920, 1080)]
	var presets := [stage.renderer.PRESET_NONE, "harsh"]
	var points := [Vector3.ZERO, Vector3(-2.0, 0.0, 0.0), Vector3(2.0, 0.0, 0.0)]
	for size in sizes:
		root.size = size
		await _frames(2)
		for preset in presets:
			_applyLook(stage.renderer, preset)
			await _frames(2)
			var rect: Rect2 = stage.displayRect()
			_check(rect.size.x > 0.0 and rect.size.y > 0.0,
				"empty display rect at %s / %s" % [size, preset])
			for worldPoint in points:
				var renderPoint: Vector2 = stage._camera.projectToRenderViewport(worldPoint)
				var screenPoint: Vector2 = stage.projectWorldToScreen(worldPoint)
				_check(renderPoint.x >= 0.0 and rect.has_point(screenPoint),
					"projected point escaped display at %s / %s" % [size, preset])
				var roundTrip: Vector2 = stage.screenToRenderViewport(screenPoint)
				_check(roundTrip.distance_to(renderPoint) < 0.05,
					"projection round trip drifted at %s / %s" % [size, preset])
			var margin := rect.position - Vector2.ONE
			if margin.x >= 0.0 and margin.y >= 0.0:
				_check(stage.screenToRenderViewport(margin).x < 0.0,
					"letterbox margin became pickable")


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


## The harshest look the drawer can reach: CRT at the smallest low-res target. The named retro
## presets it replaces are gone; this is what a projection has to survive now.
func _applyLook(renderer, look: String) -> void:
	if look == "harsh":
		renderer.set_preset(renderer.PRESET_SATURATED_CRT, false)
		renderer.set_low_res(true, Vector2i(320, 240), false)
		renderer.set_features(true, true, false)
	else:
		renderer.set_preset(look, false)
