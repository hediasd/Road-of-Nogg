## TestRunner — discovers, orders, executes, and structurally enforces the
## tests/ layout described in AUDIT_REMEDIATION_PLAN.md (Phase 3).
##
## The naming/placement/one-case-per-file rules are checked on every run,
## across every tier, regardless of which tier is being executed — otherwise
## the convention would only be enforced when someone happens to run the tier
## a violation lives in.
extends RefCounted

const TIERS := ["unit", "integration", "scene"]
const FRAMEWORK_FILES := ["TestCase.gd", "TestRunner.gd", "run_tests.gd"]


func runTier(tree: SceneTree, tier: String) -> Dictionary:
	var violations: Array[String] = []
	var filesByTier: Dictionary = {}
	for t in TIERS:
		filesByTier[t] = _discoverSorted("res://tests/%s" % t)

	_checkTopLevelCompliance(violations)
	for t in TIERS:
		for path in filesByTier[t]:
			_checkFileCompliance(path, violations)

	var passed := 0
	var failed := 0
	var failureDetails: Array[String] = []

	if violations.is_empty():
		var tiersToRun: Array = TIERS if tier == "all" else [tier]
		for t in tiersToRun:
			for path in filesByTier.get(t, []):
				var result := await _runOne(tree, path)
				if result["failures"].is_empty():
					passed += 1
					print("PASS %s :: %s" % [path, result["description"]])
				else:
					failed += 1
					print("FAIL %s :: %s" % [path, result["description"]])
					for message in result["failures"]:
						failureDetails.append("%s :: %s" % [path, message])

	return {
		"violations": violations,
		"passed": passed,
		"failed": failed,
		"failureDetails": failureDetails
	}


func _runOne(tree: SceneTree, path: String) -> Dictionary:
	var script: GDScript = load(path)
	var instance = script.new()
	instance._tree = tree
	await instance.run()
	return {"description": instance.describe(), "failures": instance._failures}


func _discoverSorted(dirPath: String) -> Array[String]:
	var result: Array[String] = []
	var dir := DirAccess.open(dirPath)
	if dir == null:
		return result
	dir.list_dir_begin()
	var entry := dir.get_next()
	while entry != "":
		if entry not in [".", ".."] and not dir.current_is_dir() and entry.ends_with(".gd"):
			result.append("%s/%s" % [dirPath, entry])
		entry = dir.get_next()
	dir.list_dir_end()
	result.sort()
	return result


func _checkTopLevelCompliance(violations: Array[String]) -> void:
	var dir := DirAccess.open("res://tests")
	if dir == null:
		violations.append("res://tests directory is missing.")
		return
	dir.list_dir_begin()
	var entry := dir.get_next()
	while entry != "":
		if (
			entry not in [".", ".."]
			and not dir.current_is_dir()
			and entry.ends_with(".gd")
			and entry not in FRAMEWORK_FILES
		):
			violations.append(
				"tests/%s must live under unit/, integration/, or scene/, not tests/ directly." % entry
			)
		entry = dir.get_next()
	dir.list_dir_end()


func _checkFileCompliance(path: String, violations: Array[String]) -> void:
	var fileName := path.get_file()
	if not fileName.begins_with("test_"):
		violations.append(
			"%s does not follow the test_<behavior>.gd naming convention." % path
		)
	var script: GDScript = load(path)
	for method in script.get_script_method_list():
		var methodName: String = method["name"]
		if methodName.begins_with("test_"):
			violations.append(
				"%s declares a stray '%s' method; override run() instead of declaring test_* methods." % [path, methodName]
			)
