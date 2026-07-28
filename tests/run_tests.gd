## Single entry point for the tests/ suite. Discovery, ordering, structural
## enforcement, and execution all live in tests/TestRunner.gd; this script
## only resolves the requested tier and reports the outcome.
##
## Usage: godot --headless -s res://tests/run_tests.gd -- unit|integration|scene|all
## (default: all)
extends SceneTree

const TestRunnerScript = preload("res://tests/TestRunner.gd")

const VALID_TIERS := ["unit", "integration", "scene", "all"]


func _init() -> void:
	call_deferred("_run")


func _run() -> void:
	var tier := "all"
	for arg in OS.get_cmdline_user_args():
		if arg in VALID_TIERS:
			tier = arg

	var runner := TestRunnerScript.new()
	var result: Dictionary = await runner.runTier(self, tier)

	if not result["violations"].is_empty():
		for violation in result["violations"]:
			push_error("TEST_STRUCTURE_VIOLATION: %s" % violation)
		quit(1)
		return

	if result["failed"] > 0:
		for detail in result["failureDetails"]:
			push_error("TEST_FAILED: %s" % detail)
		quit(1)
		return

	print("TESTS_OK tier=%s passed=%d failed=%d" % [tier, result["passed"], result["failed"]])
	quit(0)
