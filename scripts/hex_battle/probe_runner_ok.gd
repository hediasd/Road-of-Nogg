extends SceneTree

const RunBattleScript = preload("res://scripts/battle/run_battle.gd")
const SCENARIO_PATH := "res://data/battle/scenarios/proving_ground_cpu_cpu.json"


func _init() -> void:
	var first := RunBattleScript.run(SCENARIO_PATH, 7, "", "")
	var second := RunBattleScript.run(SCENARIO_PATH, 7, "", "")
	if not first.get("ok", false) or not second.get("ok", false):
		printerr("HXB_RUNNER_DETERMINISM_FAILURE: seeded battle did not complete")
		quit(1)
		return
	if str(first.get("line", "")) != str(second.get("line", "")):
		printerr("HXB_RUNNER_DETERMINISM_FAILURE: equal seeds produced different records")
		quit(1)
		return
	print("HXB_RUNNER_OK")
	quit(0)
