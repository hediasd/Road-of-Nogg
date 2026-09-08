## Choose a scenario and a seed, then start. The whole of setup.
##
## SCENARIO, NOT ROSTER. The square battle's setup composed a battle from monster picks and team
## counts; a hex battle is fought from an authored scenario that already binds a map to parties and
## their deployment (HXB-5). So this offers the scenarios on disk rather than rebuilding a party
## editor, and the "party composition" it exposes is what the chosen scenario declares.
##
## THE SEED IS SHOWN AND EDITABLE, because a seeded preset that cannot be reproduced on purpose is
## not reproducible in the sense that matters -- someone has to be able to type back the seed from
## a battle they want to see again.

class_name HexBattleSetupUI
extends CanvasLayer

const NoggThemeScript = preload("res://src/presentation/theme/NoggTheme.gd")
const BattleScenarioFactoryScript = preload("res://src/factories/BattleScenarioFactory.gd")

const SCENARIO_DIR := "res://data/battle/scenarios"

signal battle_requested(scenarioPath: String, seedValue: int)

var _root: Control
var _scenarioOption: OptionButton
var _seedField: LineEdit
var _summary: Label
var _scenarioPaths: Array[String] = []


func _init() -> void:
	name = "HexBattleSetupUI"
	layer = 2

	_root = Control.new()
	_root.name = "SetupRoot"
	_root.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(_root)

	var column := VBoxContainer.new()
	column.name = "SetupColumn"
	column.position = Vector2(NoggThemeScript.SCREEN_MARGIN, NoggThemeScript.SCREEN_MARGIN)
	column.add_theme_constant_override("separation", 8)
	_root.add_child(column)

	var title := Label.new()
	title.text = "Hex battle"
	title.add_theme_color_override("font_color", NoggThemeScript.TEXT_ACCENT)
	column.add_child(title)

	_scenarioOption = OptionButton.new()
	_scenarioOption.name = "ScenarioOption"
	column.add_child(_scenarioOption)
	_scenarioOption.item_selected.connect(func(_index: int): _refreshSummary())

	var seedRow := HBoxContainer.new()
	var seedLabel := Label.new()
	seedLabel.text = "Seed"
	seedRow.add_child(seedLabel)
	_seedField = LineEdit.new()
	_seedField.name = "SeedField"
	_seedField.text = "1"
	_seedField.custom_minimum_size.x = 120.0
	seedRow.add_child(_seedField)
	column.add_child(seedRow)

	_summary = Label.new()
	_summary.name = "ScenarioSummary"
	_summary.add_theme_color_override("font_color", NoggThemeScript.TEXT_DIM)
	column.add_child(_summary)

	var startButton := Button.new()
	startButton.name = "StartButton"
	startButton.text = "Start battle"
	startButton.pressed.connect(_onStartPressed)
	column.add_child(startButton)

	_populateScenarios()


## Every scenario on disk, sorted. Scanned rather than listed in a constant, so a scenario added
## by HXB-10's authoring route appears here without this file being edited.
func _populateScenarios() -> void:
	_scenarioPaths.clear()
	_scenarioOption.clear()
	var dir := DirAccess.open(SCENARIO_DIR)
	if dir == null:
		_summary.text = "No scenario directory at %s." % SCENARIO_DIR
		return
	var names := dir.get_files()
	names.sort()
	for fileName in names:
		if not fileName.ends_with(".json"):
			continue
		var path := "%s/%s" % [SCENARIO_DIR, fileName]
		_scenarioPaths.append(path)
		_scenarioOption.add_item(fileName.get_basename())
	if not _scenarioPaths.is_empty():
		_scenarioOption.select(0)
	_refreshSummary()


## What the chosen scenario actually contains -- party count, controllers and map. Read from the
## scenario itself rather than described here, so the summary cannot drift from the file.
func _refreshSummary() -> void:
	var path := selectedScenarioPath()
	if path.is_empty():
		_summary.text = "No scenarios available."
		return
	var loaded := BattleScenarioFactoryScript.loadFromPath(path)
	if not loaded["success"]:
		_summary.text = "Unreadable: %s" % str(loaded.get("error", ""))
		return
	var scenario = loaded["scenario"]
	var playerParties := 0
	var cpuParties := 0
	var members := 0
	for party in scenario.parties:
		members += party.memberIDs.size()
		if party.controller == "player":
			playerParties += 1
		else:
			cpuParties += 1
	_summary.text = "%d parties (%d player, %d CPU), %d members, map %s" % [
		scenario.parties.size(), playerParties, cpuParties, members, str(scenario.mapID)
	]


func selectedScenarioPath() -> String:
	var index := _scenarioOption.selected if _scenarioOption != null else -1
	if index < 0 or index >= _scenarioPaths.size():
		return ""
	return _scenarioPaths[index]


func selectedSeed() -> int:
	var text := _seedField.text.strip_edges() if _seedField != null else ""
	return int(text) if text.is_valid_int() else 0


func setVisibleUI(shown: bool) -> void:
	_root.visible = shown


func _onStartPressed() -> void:
	var path := selectedScenarioPath()
	if path.is_empty():
		_summary.text = "Choose a scenario first."
		return
	battle_requested.emit(path, selectedSeed())
