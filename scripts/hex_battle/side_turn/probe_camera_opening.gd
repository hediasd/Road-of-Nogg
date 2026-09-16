extends SceneTree

const BattleSetupConfigScript = preload("res://src/battle_sim/BattleSetupConfig.gd")
const BattleSetupFactoryScript = preload("res://src/battle_sim/BattleSetupFactory.gd")
const CameraScript = preload("res://src/presentation/battle/HexBattleCamera.gd")
const LayoutScript = preload("res://src/presentation/battle/HexBattleLayout.gd")

const SCENARIO_PATH := "res://data/battle/scenarios/hexmap_player_cpu.json"
const VIEWPORT_SIZE := Vector2i(1280, 720)
const MIN_BOARD_WIDTH_SHARE := 0.58
const SCREEN_MARGIN := 20.0
const LEFT_RESERVED := Rect2(0.0, 0.0, 220.0, 170.0)
const RIGHT_RESERVED := Rect2(1080.0, 0.0, 200.0, 100.0)

var failures: Array[String] = []


func _init() -> void:
	process_frame.connect(_run, CONNECT_ONE_SHOT)


func _run() -> void:
	root.size = VIEWPORT_SIZE
	var config = BattleSetupConfigScript.new()
	config.scenarioPath = SCENARIO_PATH
	config.seed = 42
	var built := BattleSetupFactoryScript.createHexState(config)
	_require(built["success"], "scenario setup failed: %s" % built.get("error", ""))
	if not built["success"]:
		_report()
		return
	var state: BattleState = built["state"]
	var layout = LayoutScript.new(state.battleMap)
	var battleCamera = CameraScript.new()
	root.add_child(battleCamera)
	battleCamera.camera.current = true
	battleCamera.frameMap(state.battleMap, layout)
	await process_frame
	await process_frame

	_require(battleCamera.camera.projection == Camera3D.PROJECTION_ORTHOGONAL,
		"opening projection is not orthographic")
	_require(absf(battleCamera.yaw() - CameraScript.DEFAULT_YAW_DEGREES) < 0.01,
		"opening yaw is not the authored diagonal")
	_require(absf(battleCamera.pitchDegrees() - CameraScript.DEFAULT_PITCH_DEGREES) < 0.01,
		"opening pitch is not the authored three-quarter angle")

	var minX := INF
	var maxX := -INF
	for cell: Vector2i in state.battleMap.validCells():
		var point := battleCamera.projectToRenderViewport(layout.cellCenter(cell))
		if point.x >= 0.0:
			minX = minf(minX, point.x)
			maxX = maxf(maxX, point.x)
	var widthShare := (maxX - minX) / float(VIEWPORT_SIZE.x)
	_require(widthShare >= MIN_BOARD_WIDTH_SHARE,
		"board width share %.3f is below %.2f" % [widthShare, MIN_BOARD_WIDTH_SHARE])

	var safeScreen := Rect2(
		Vector2(SCREEN_MARGIN, SCREEN_MARGIN),
		Vector2(VIEWPORT_SIZE) - Vector2.ONE * SCREEN_MARGIN * 2.0)
	for monsterIDValue in state.monsters:
		var monsterID := int(monsterIDValue)
		var point := battleCamera.projectToRenderViewport(
			layout.cellCenter(state.getMonsterPosition(monsterID)))
		_require(safeScreen.has_point(point), "unit %d opened off screen at %s" % [monsterID, point])
		_require(not LEFT_RESERVED.has_point(point) and not RIGHT_RESERVED.has_point(point),
			"unit %d opened under a reserved HUD box at %s" % [monsterID, point])

	print("SIDE_TURN_CAMERA_EVIDENCE yaw=%.1f pitch=%.1f size=%.2f width_share=%.3f" % [
		battleCamera.yaw(), battleCamera.pitchDegrees(), battleCamera.orthographicSize(), widthShare,
	])
	battleCamera.queue_free()
	_report()


func _require(condition: bool, message: String) -> void:
	if not condition:
		failures.append(message)


func _report() -> void:
	if not failures.is_empty():
		for failure: String in failures:
			printerr("SIDE_TURN_CAMERA_FAILURE: %s" % failure)
		quit(1)
		return
	print("SIDE_TURN_CAMERA_OK")
	quit(0)
