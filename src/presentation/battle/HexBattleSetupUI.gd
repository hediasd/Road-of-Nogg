## The playable hex battle's setup screen. Authored scenarios supply parties and
## deployment; this form chooses controller mode and a reproducible seed.
class_name HexBattleSetupUI
extends CanvasLayer

const NoggThemeScript = preload("res://src/presentation/theme/NoggTheme.gd")
const BattleScenarioFactoryScript = preload("res://src/factories/BattleScenarioFactory.gd")

const BATTLE_MODES := [
	{"label": "CPU vs CPU", "path": "res://data/battle/scenarios/hexmap_cpu_cpu.json"},
	{"label": "Player vs CPU", "path": "res://data/battle/scenarios/hexmap_player_cpu.json"},
]

signal battle_requested(scenarioPath: String, seedValue: int)

var _root: Control
var _scenarioOption: OptionButton
var _seedField: LineEdit
var _summary: Label
var _error: Label
var _teamColumns: Array[VBoxContainer] = []
var _scenarioPaths: Array[String] = []


func _init() -> void:
	name = "HexBattleSetupUI"
	layer = 2


func _ready() -> void:
	NoggThemeScript.configure_for_window_height(get_window().size.y)
	_buildForm()
	_populateScenarios()


func _buildForm() -> void:
	_root = Control.new()
	_root.name = "SetupRoot"
	_root.set_anchors_preset(Control.PRESET_FULL_RECT)
	_root.theme = NoggThemeScript.build_game_theme()
	add_child(_root)

	var dim := ColorRect.new()
	dim.name = "Backdrop"
	dim.color = NoggThemeScript.WINDOW_FILL_DEEP
	dim.set_anchors_preset(Control.PRESET_FULL_RECT)
	dim.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_root.add_child(dim)

	var center := CenterContainer.new()
	center.name = "SetupCenter"
	center.set_anchors_preset(Control.PRESET_FULL_RECT)
	_root.add_child(center)

	var scroll := ScrollContainer.new()
	scroll.name = "SetupScroll"
	var viewportSize := get_viewport().get_visible_rect().size
	scroll.custom_minimum_size = Vector2(
		minf(820.0, viewportSize.x - 32.0),
		minf(610.0, viewportSize.y - 32.0))
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	center.add_child(scroll)

	var panel := PanelContainer.new()
	panel.name = "SetupPanel"
	panel.custom_minimum_size = scroll.custom_minimum_size
	scroll.add_child(panel)

	var content := VBoxContainer.new()
	content.name = "SetupContent"
	content.add_theme_constant_override("separation", 12)
	panel.add_child(content)

	var title := NoggThemeScript.make_banner_label("BATTLE SETUP")
	title.name = "SetupTitle"
	content.add_child(title)

	var subtitle := Label.new()
	subtitle.text = "Choose a battle mode and seed, then confirm."
	subtitle.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	content.add_child(subtitle)

	var generalGrid := GridContainer.new()
	generalGrid.name = "BattleOptions"
	generalGrid.columns = 2
	generalGrid.add_theme_constant_override("h_separation", 18)
	generalGrid.add_theme_constant_override("v_separation", 8)
	content.add_child(generalGrid)

	var modeLabel := Label.new()
	modeLabel.text = "Battle mode"
	generalGrid.add_child(modeLabel)
	_scenarioOption = OptionButton.new()
	_scenarioOption.name = "ScenarioOption"
	_scenarioOption.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_scenarioOption.tooltip_text = "Choose who controls Team 1."
	generalGrid.add_child(_scenarioOption)
	_scenarioOption.item_selected.connect(_onScenarioSelected)

	var mapLabel := Label.new()
	mapLabel.text = "Map"
	generalGrid.add_child(mapLabel)
	var mapValue := Label.new()
	mapValue.text = "Hexmap"
	mapValue.add_theme_color_override("font_color", NoggThemeScript.TEXT_ACCENT)
	generalGrid.add_child(mapValue)

	var seedLabel := Label.new()
	seedLabel.text = "Seed"
	generalGrid.add_child(seedLabel)
	_seedField = LineEdit.new()
	_seedField.name = "SeedField"
	_seedField.text = "1"
	_seedField.tooltip_text = "Use the same seed to reproduce a battle."
	_seedField.text_submitted.connect(func(_value: String) -> void: _onStartPressed())
	generalGrid.add_child(_seedField)

	var teams := HBoxContainer.new()
	teams.name = "Teams"
	teams.size_flags_vertical = Control.SIZE_EXPAND_FILL
	teams.add_theme_constant_override("separation", 24)
	content.add_child(teams)
	for teamID in [1, 2]:
		var column := VBoxContainer.new()
		column.name = "Team%d" % teamID
		column.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		column.add_theme_constant_override("separation", 4)
		teams.add_child(column)
		var heading := Label.new()
		heading.text = "TEAM %d" % teamID
		heading.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		heading.add_theme_color_override("font_color", NoggThemeScript.TEXT_ACCENT)
		column.add_child(heading)
		_teamColumns.append(column)

	_summary = Label.new()
	_summary.name = "ScenarioSummary"
	_summary.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_summary.add_theme_color_override("font_color", NoggThemeScript.TEXT_DIM)
	content.add_child(_summary)

	_error = Label.new()
	_error.name = "SetupError"
	_error.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_error.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_error.add_theme_color_override("font_color", NoggThemeScript.HEX_HP_FILL_LOW)
	content.add_child(_error)

	var startButton := Button.new()
	startButton.name = "StartButton"
	startButton.text = "CONFIRM AND LOAD BATTLE"
	startButton.custom_minimum_size.y = 48
	startButton.pressed.connect(_onStartPressed)
	content.add_child(startButton)
	startButton.call_deferred("grab_focus")

	# The skin's rim overlays the content without changing its measured size.
	var frame := NoggThemeScript.build_window_frame()
	if frame != null:
		frame.mouse_filter = Control.MOUSE_FILTER_IGNORE
		panel.add_child(frame)


func _populateScenarios() -> void:
	_scenarioPaths.clear()
	_scenarioOption.clear()
	for mode: Dictionary in BATTLE_MODES:
		_scenarioPaths.append(str(mode["path"]))
		_scenarioOption.add_item(str(mode["label"]))
	_scenarioOption.select(0)
	_refreshSummary()


func _refreshSummary() -> void:
	for column in _teamColumns:
		for index in range(column.get_child_count() - 1, 0, -1):
			var row := column.get_child(index)
			column.remove_child(row)
			row.queue_free()
	var path := selectedScenarioPath()
	if path.is_empty():
		_summary.text = "No battle mode available."
		return
	var loaded := BattleScenarioFactoryScript.loadFromPath(path)
	if not loaded["success"]:
		_summary.text = "Unreadable: %s" % str(loaded.get("error", ""))
		return
	var scenario = loaded["scenario"]
	var memberCount := 0
	for party in scenario.parties:
		memberCount += party.memberIDs.size()
		var column: VBoxContainer = _teamColumns[party.teamID - 1] if party.teamID in [1, 2] else null
		if column == null:
			continue
		for memberID in party.memberIDs:
			var row := Label.new()
			var nameText := str(party.monsterNames[memberID])
			var level := int(party.memberLevels[memberID])
			row.text = "%s  Lv%d%s" % [
				nameText, level, "  (Captain)" if memberID == party.commanderID else ""]
			row.clip_text = true
			column.add_child(row)
	_summary.text = "%d parties, %d members, map %s" % [
		scenario.parties.size(), memberCount, str(scenario.mapID)]


func _onScenarioSelected(_index: int) -> void:
	_clearError()
	_refreshSummary()


func selectedScenarioPath() -> String:
	var index := _scenarioOption.selected if _scenarioOption != null else -1
	if index < 0 or index >= _scenarioPaths.size():
		return ""
	return _scenarioPaths[index]


func selectedSeed() -> int:
	var seedText := _seedField.text.strip_edges() if _seedField != null else ""
	return int(seedText) if seedText.is_valid_int() else 0


func showError(message: String) -> void:
	if _error != null:
		_error.text = message


func _clearError() -> void:
	showError("")


func setVisibleUI(shown: bool) -> void:
	if _root != null:
		_root.visible = shown


func _onStartPressed() -> void:
	var seedText := _seedField.text.strip_edges() if _seedField != null else ""
	if not seedText.is_valid_int():
		showError("Enter a whole-number seed.")
		return
	var path := selectedScenarioPath()
	if path.is_empty():
		showError("Choose a scenario first.")
		return
	var loaded := BattleScenarioFactoryScript.loadFromPath(path)
	if not loaded["success"]:
		showError(str(loaded.get("error", "")))
		return
	_clearError()
	battle_requested.emit(path, selectedSeed())
