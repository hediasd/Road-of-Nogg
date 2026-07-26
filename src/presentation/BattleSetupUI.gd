class_name BattleSetupUI
extends RefCounted

const RenderPresetCatalogScript = preload("res://src/presentation/RenderPresetCatalog.gd")


static func build(
		root: Node,
		callbacks: Dictionary,
		mapNames: Array[String],
		monsterNames: Array[String],
		presetNames: Array[String]) -> Dictionary:
	var canvas = CanvasLayer.new()
	canvas.layer = 20
	root.add_child(canvas)

	var dim = ColorRect.new()
	dim.color = Color(0.015, 0.025, 0.06, 0.82)
	dim.set_anchors_preset(Control.PRESET_FULL_RECT)
	canvas.add_child(dim)

	var center = CenterContainer.new()
	center.set_anchors_preset(Control.PRESET_FULL_RECT)
	canvas.add_child(center)

	var panel = PanelContainer.new()
	panel.custom_minimum_size = Vector2(820, 610)
	center.add_child(panel)

	var style = StyleBoxFlat.new()
	style.bg_color = Color(0.04, 0.06, 0.12, 0.96)
	style.border_color = Color(0.25, 0.62, 0.95, 0.9)
	style.set_border_width_all(2)
	style.set_corner_radius_all(8)
	style.content_margin_left = 24
	style.content_margin_right = 24
	style.content_margin_top = 20
	style.content_margin_bottom = 20
	panel.add_theme_stylebox_override("panel", style)

	var content = VBoxContainer.new()
	content.add_theme_constant_override("separation", 10)
	panel.add_child(content)

	var title = Label.new()
	title.text = "BATTLE SETUP"
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	title.add_theme_font_size_override("font_size", 28)
	content.add_child(title)

	var subtitle = Label.new()
	subtitle.text = "Defaults are ready — confirm immediately or customize."
	subtitle.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	content.add_child(subtitle)

	var generalGrid = GridContainer.new()
	generalGrid.columns = 2
	generalGrid.add_theme_constant_override("h_separation", 18)
	generalGrid.add_theme_constant_override("v_separation", 8)
	content.add_child(generalGrid)

	var modeOption = _addOptionRow(
		generalGrid,
		"Battle mode",
		["CPU vs CPU", "Player vs CPU"],
		["cpu_vs_cpu", "player_vs_cpu"],
		"Choose who controls Team 1."
	)
	var mapOption = _addOptionRow(generalGrid, "Map", mapNames, mapNames, "Battlefield and deployment slots.")

	var seedLabel = Label.new()
	seedLabel.text = "Seed"
	generalGrid.add_child(seedLabel)
	var seedInput = SpinBox.new()
	seedInput.min_value = 0
	seedInput.max_value = 2147483647
	seedInput.value = 42
	seedInput.tooltip_text = "Controls deterministic random teams and battle outcomes."
	seedInput.value_changed.connect(callbacks["seed_changed"])
	generalGrid.add_child(seedInput)

	var renderingGrid = GridContainer.new()
	renderingGrid.columns = 6
	renderingGrid.add_theme_constant_override("h_separation", 8)
	content.add_child(renderingGrid)
	var renderModeOption = _addOptionRow(
		renderingGrid,
		"Look",
		RenderPresetCatalogScript.labels(),
		RenderPresetCatalogScript.values(),
		"Quick visual presets. Manual changes become Custom."
	)
	var geometryOption = _addOptionRow(
		renderingGrid,
		"Geometry",
		["Vertex jitter", "Stable"],
		["jitter", "stable"],
		"Toggle screen-space vertex snapping independently."
	)
	var upscaleOption = _addOptionRow(
		renderingGrid,
		"Upscale",
		["Sharp pixels", "Smooth"],
		["nearest", "linear"],
		"Choose crisp nearest-neighbor pixels or smooth world upscaling."
	)
	for option in [renderModeOption, geometryOption, upscaleOption]:
		option.custom_minimum_size.x = 118
	renderModeOption.item_selected.connect(callbacks["rendering_preset_selected"])
	geometryOption.item_selected.connect(callbacks["rendering_feature_selected"])
	upscaleOption.item_selected.connect(callbacks["rendering_feature_selected"])

	var teams = HBoxContainer.new()
	teams.size_flags_vertical = Control.SIZE_EXPAND_FILL
	teams.add_theme_constant_override("separation", 24)
	content.add_child(teams)

	var team1 = _buildTeamColumn(teams, 1, presetNames, monsterNames, callbacks)
	var team2 = _buildTeamColumn(teams, 2, presetNames, monsterNames, callbacks)

	var duplicateNote = Label.new()
	duplicateNote.text = "Duplicates are allowed, but varied teams are recommended."
	duplicateNote.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	duplicateNote.modulate = Color(0.95, 0.8, 0.35)
	content.add_child(duplicateNote)

	var errorLabel = Label.new()
	errorLabel.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	errorLabel.modulate = Color(1.0, 0.35, 0.35)
	errorLabel.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	content.add_child(errorLabel)

	var confirmButton = Button.new()
	confirmButton.text = "CONFIRM AND LOAD BATTLE"
	confirmButton.custom_minimum_size = Vector2(0, 48)
	confirmButton.tooltip_text = "Load the selected map, teams, and controllers."
	confirmButton.pressed.connect(callbacks["confirmed"])
	content.add_child(confirmButton)
	confirmButton.call_deferred("grab_focus")

	return {
		"canvas": canvas,
		"mode_option": modeOption,
		"map_option": mapOption,
		"render_mode_option": renderModeOption,
		"geometry_option": geometryOption,
		"upscale_option": upscaleOption,
		"seed_input": seedInput,
		"team_1_preset": team1["preset"],
		"team_2_preset": team2["preset"],
		"team_1_slots": team1["slots"],
		"team_2_slots": team2["slots"],
		"duplicate_note": duplicateNote,
		"error_label": errorLabel,
		"confirm_button": confirmButton
	}


static func _buildTeamColumn(
		parent: Control,
		team: int,
		presetNames: Array[String],
		monsterNames: Array[String],
		callbacks: Dictionary) -> Dictionary:
	var column = VBoxContainer.new()
	column.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	parent.add_child(column)

	var heading = Label.new()
	heading.text = "TEAM %d" % team
	heading.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	heading.add_theme_font_size_override("font_size", 20)
	column.add_child(heading)

	var preset = _newOption(presetNames, presetNames)
	preset.tooltip_text = "Choose a team preset; individual slots remain editable."
	preset.item_selected.connect(callbacks["preset_selected"].bind(team))
	column.add_child(preset)

	var slots: Array[OptionButton] = []
	for index in range(4):
		var row = HBoxContainer.new()
		column.add_child(row)
		var label = Label.new()
		label.text = "%d." % (index + 1)
		label.custom_minimum_size.x = 24
		row.add_child(label)
		var option = _newOption(monsterNames, monsterNames)
		option.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		option.tooltip_text = "Monster slot %d. Duplicate selections are allowed." % (index + 1)
		option.item_selected.connect(callbacks["monster_selected"].bind(team, index))
		row.add_child(option)
		slots.append(option)

	return {"preset": preset, "slots": slots}


static func _addOptionRow(
		grid: GridContainer,
		labelText: String,
		labels: Array[String],
		values: Array[String],
		tooltip: String) -> OptionButton:
	var label = Label.new()
	label.text = labelText
	grid.add_child(label)
	var option = _newOption(labels, values)
	option.tooltip_text = tooltip
	grid.add_child(option)
	return option


static func _newOption(labels: Array[String], values: Array[String]) -> OptionButton:
	var option = OptionButton.new()
	option.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	for index in range(labels.size()):
		option.add_item(labels[index])
		option.set_item_metadata(index, values[index])
	return option
