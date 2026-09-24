extends SceneTree

const HexBattleSetupUIScript = preload("res://src/presentation/battle/HexBattleSetupUI.gd")
const BattleScenarioFactoryScript = preload("res://src/factories/BattleScenarioFactory.gd")

const INVALID_SCENARIO_PATH := "user://hex_battle_setup_validation/invalid_scenario.json"

var failures: Array[String] = []
var _requests: Array[Dictionary] = []
var _ui: HexBattleSetupUI


func _init() -> void:
	_writeInvalidScenarioFixture()
	_ui = HexBattleSetupUIScript.new()
	root.add_child(_ui)
	_ui.battle_requested.connect(func(scenarioPath: String, seedValue: int) -> void:
		_requests.append({"path": scenarioPath, "seed": seedValue})
	)
	process_frame.connect(_run, CONNECT_ONE_SHOT)


func _run() -> void:
	_checkDiscoveredScenario()
	_checkSeedValidation()
	_checkShowErrorPreservesForm()
	_checkSelectionChangeClearsError()
	_checkInvalidScenario()
	_checkEmptyScenarioList()
	_cleanupFixture()

	if not failures.is_empty():
		for failure: String in failures:
			printerr("HPR_SETUP_FAILURE: %s" % failure)
		quit(1)
		return
	print("HPR_SETUP_OK")
	quit(0)


func _require(condition: bool, message: String) -> void:
	if not condition:
		failures.append(message)


func _checkDiscoveredScenario() -> void:
	_require(_ui._scenarioOption.item_count == 2, "setup UI should offer exactly two playable modes")
	_require(_ui._scenarioOption.get_item_text(0) == "CPU vs CPU",
		"first playable mode should be CPU vs CPU")
	_require(_ui._scenarioOption.get_item_text(1) == "Player vs CPU",
		"second playable mode should be Player vs CPU")
	_require(_ui._scenarioPaths == [
		"res://data/battle/scenarios/hexmap_cpu_cpu.json",
		"res://data/battle/scenarios/hexmap_player_cpu.json",
	], "playable modes should use the true hexmap scenarios")
	_require(_ui._root.find_child("SetupPanel", true, false) != null,
		"setup should display the centered battle panel")
	_require(_ui._teamColumns.size() == 2, "setup should display both team columns")
	for column in _ui._teamColumns:
		_require(column.get_child_count() == 5,
			"each true battle team should show its heading and four members")
	_require(not _ui.selectedScenarioPath().is_empty(), "setup UI discovered no scenario for valid-seed checks")
	if not _ui.selectedScenarioPath().is_empty():
		var loaded := BattleScenarioFactoryScript.loadFromPath(_ui.selectedScenarioPath())
		_require(loaded["success"], "discovered scenario is not loadable: %s" % loaded.get("error", ""))
	_ui._scenarioOption.select(1)
	_ui._scenarioOption.item_selected.emit(1)
	_require(_ui.selectedScenarioPath() == "res://data/battle/scenarios/hexmap_player_cpu.json",
		"Player vs CPU should select the playable player scenario")
	_ui._scenarioOption.select(0)
	_ui._scenarioOption.item_selected.emit(0)


func _checkSeedValidation() -> void:
	for invalidSeed in ["", "abc", "1.5"]:
		var countBefore := _requests.size()
		_ui._seedField.text = invalidSeed
		_ui._onStartPressed()
		_require(_requests.size() == countBefore,
			"invalid seed %s emitted battle_requested" % JSON.stringify(invalidSeed))
		_require(_ui._error.text == "Enter a whole-number seed.",
			"invalid seed %s did not show the whole-number error" % JSON.stringify(invalidSeed))

	for validSeed in [0, 42, -1]:
		var countBefore := _requests.size()
		_ui._seedField.text = str(validSeed)
		_ui._onStartPressed()
		_require(_requests.size() == countBefore + 1,
			"valid seed %d did not emit exactly once" % validSeed)
		if _requests.size() == countBefore + 1:
			_require(int(_requests.back()["seed"]) == validSeed,
				"valid seed %d emitted %s" % [validSeed, str(_requests.back()["seed"])])
		_require(_ui._error.text.is_empty(), "valid seed %d did not clear SetupError" % validSeed)


func _checkShowErrorPreservesForm() -> void:
	_ui._seedField.text = "42"
	var scenarioPath := _ui.selectedScenarioPath()
	var summaryBefore := _ui._summary.text
	_ui.showError("Start failed.")
	_require(_ui.selectedScenarioPath() == scenarioPath, "showError changed the selected scenario")
	_require(_ui._seedField.text == "42", "showError changed the seed field")
	_require(_ui._summary.text == summaryBefore, "showError overwrote ScenarioSummary")
	_require(_ui._error.text == "Start failed.", "showError did not update SetupError")


func _checkSelectionChangeClearsError() -> void:
	_ui.showError("Stale start error.")
	_ui._scenarioOption.item_selected.emit(_ui._scenarioOption.selected)
	_require(_ui._error.text.is_empty(), "scenario selection change did not clear SetupError")


func _checkInvalidScenario() -> void:
	var countBefore := _requests.size()
	var loaded := BattleScenarioFactoryScript.loadFromPath(INVALID_SCENARIO_PATH)
	_require(not loaded["success"], "scratch invalid scenario unexpectedly loaded")
	_ui._scenarioPaths = [INVALID_SCENARIO_PATH]
	_ui._scenarioOption.clear()
	_ui._scenarioOption.add_item("invalid_scenario")
	_ui._scenarioOption.select(0)
	_ui._seedField.text = "42"
	_ui._onStartPressed()
	_require(_requests.size() == countBefore, "invalid scenario emitted battle_requested")
	_require(_ui._error.text == str(loaded.get("error", "")),
		"invalid scenario error did not come from BattleScenarioFactory")


func _checkEmptyScenarioList() -> void:
	var countBefore := _requests.size()
	_ui._scenarioPaths.clear()
	_ui._scenarioOption.clear()
	_ui._seedField.text = "42"
	_ui._onStartPressed()
	_require(_requests.size() == countBefore, "empty scenario list emitted battle_requested")
	_require(_ui._error.text == "Choose a scenario first.",
		"empty scenario list did not show the selection error")


func _writeInvalidScenarioFixture() -> void:
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(INVALID_SCENARIO_PATH.get_base_dir()))
	var fixture := FileAccess.open(INVALID_SCENARIO_PATH, FileAccess.WRITE)
	if fixture == null:
		failures.append("could not create scratch invalid scenario fixture")
		return
	fixture.store_string("[]")
	fixture.close()


func _cleanupFixture() -> void:
	if FileAccess.file_exists(INVALID_SCENARIO_PATH):
		DirAccess.remove_absolute(ProjectSettings.globalize_path(INVALID_SCENARIO_PATH))
