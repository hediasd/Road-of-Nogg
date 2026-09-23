## Renders the spent treatment so it can be looked at: the whole piece against
## the old body-only version, and the two readings of "two shades".
##
## Needs a renderer. Run without --headless:
##
##   ./Godot_v4.4-stable_win64.exe --path . \
##       --script scripts/hex_battle/side_turn/capture_spent_shades.gd
##
## Frames land in `battle_output/spent_shades/`, which is gitignored.

extends SceneTree

const ControllerScript = preload("res://src/systems/hex_battle/HexBattleController.gd")
const OUT_DIR := "res://battle_output/spent_shades"
const SCENARIO := "res://data/battle/scenarios/technical_hxb_contract_cpu_cpu.json"
const SEED := 4242
const SCREEN := Vector2i(1280, 720)

var _controller


func _init() -> void:
	process_frame.connect(_run, CONNECT_ONE_SHOT)


func _run() -> void:
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(OUT_DIR))
	root.size = SCREEN
	_controller = ControllerScript.new()
	root.add_child(_controller)
	await process_frame
	var started: Dictionary = _controller.startBattle(SCENARIO, SEED)
	if not bool(started.get("ok", false)):
		printerr("SPENT_SHADES_FAILED: %s" % str(started.get("error", "")))
		quit(1)
		return
	for _frame in range(8):
		await process_frame

	var adapter = _controller.adapter
	var ids: Array = adapter.shownModelIDs()
	ids.sort()
	if ids.size() < 4:
		printerr("SPENT_SHADES_FAILED: not enough models")
		quit(1)
		return

	await _shoot("00_none")

	## Half the pieces spent, so ready and used sit side by side in one frame.
	for index in range(ids.size()):
		if index % 2 == 0:
			adapter.setUnitSpent(int(ids[index]), true)
	await _shoot("01_whole_model")

	## Diagnostic: anything the drain covers turns magenta. Whatever stays its
	## own colour is geometry no unit treatment is reaching.
	var probeMaterial = adapter._spentMaterial
	probeMaterial.set_shader_parameter("tint", Vector3(2.0, 0.0, 2.0))
	await _shoot("01b_coverage_probe")
	probeMaterial.set_shader_parameter("tint", Vector3(0.36, 0.39, 0.46))

	## Ready, partly spent and spent in one frame, which is the only way to judge
	## whether the two depths are far enough apart to read at a glance.
	for index in range(ids.size()):
		adapter.setUnitSpent(int(ids[index]), false)
		adapter.setUnitPartlySpent(int(ids[index]), false)
	for index in range(ids.size()):
		if index % 3 == 1:
			adapter.setUnitPartlySpent(int(ids[index]), true)
		elif index % 3 == 2:
			adapter.setUnitSpent(int(ids[index]), true)
	await _shoot("02_three_states")

	print("SPENT_SHADES_OK models=%d" % ids.size())
	_controller.teardownBattle()
	quit(0)


func _shoot(name: String) -> void:
	await process_frame
	await process_frame
	var image := root.get_texture().get_image()
	image.save_png("%s/%s.png" % [ProjectSettings.globalize_path(OUT_DIR), name])
