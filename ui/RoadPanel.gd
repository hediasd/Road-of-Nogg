## The road screen's window: the company with each monster's level, Belief and place in the field,
## the selected stop with its enemies, and the actions. A separate centred window reports what a
## battle paid.
##
## PASSIVE. The controller hands it a model Dictionary (`present`, `showResult`) and it redraws from
## scratch; every button only emits what the player asked for. It holds no road state, so it can
## never disagree with it.
##
## LAYOUT. Only the company list scrolls. The stop, its enemies, the travel action and the footer
## are pinned below it, so the action the player came for is never scrolled out of reach.
##
## Nogg window language: halo, body and rim share the window bounds and only the content is inset
## (UI_DESIGN.md), game fonts through `build_game_theme`, colours from NoggTheme tokens.

extends CanvasLayer

const NoggThemeScript = preload("res://ui/NoggTheme.gd")

signal field_toggled(slot: int)
signal captain_chosen(slot: int)
signal ascend_requested(slot: int)
signal stop_stepped(step: int)
signal travel_requested()
signal new_road_requested()
signal setup_requested()
signal result_closed()

## Design widths, in the setup screen's units (scaled by ui_scale / 2), and the most of the
## screen width the side window may take.
const PANEL_WIDTH := 560.0
const PANEL_MAX_SHARE := 0.44
const RESULT_WIDTH := 640.0
const RESULT_HEIGHT := 380.0
const ROW_SEPARATION := 6
const SECTION_SEPARATION := 10

var _root: Control
var _company: VBoxContainer
var _stopSection: VBoxContainer
var _resultRoot: Control
var _resultContent: VBoxContainer
var _coveredWidth := 0.0
## Set when the player pressed NEW ROAD once; the second press confirms.
var _confirmingNewRoad := false
var _model: Dictionary = {}


func _init() -> void:
	name = "RoadPanel"
	# Above an embedded battle's HUD and drawer, so the result window reads over the battle it
	# reports.
	layer = NoggThemeScript.PROMPT_LAYER


func _ready() -> void:
	NoggThemeScript.configure_for_window_height(get_window().size.y)
	var sizeScale := float(NoggThemeScript.ui_scale) / 2.0
	var viewportSize := get_viewport().get_visible_rect().size
	var margin := NoggThemeScript.HEX_SCREEN_MARGIN

	_root = Control.new()
	_root.name = "RoadRoot"
	_root.set_anchors_preset(Control.PRESET_FULL_RECT)
	_root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_root.theme = NoggThemeScript.build_game_theme()
	add_child(_root)
	var width := minf(PANEL_WIDTH * sizeScale, viewportSize.x * PANEL_MAX_SHARE)
	_coveredWidth = width + margin * 2.0
	var window := _window("RoadWindow", Vector2(width, viewportSize.y - margin * 2.0))
	window["frame"].position = Vector2(viewportSize.x - width - margin, margin)
	_root.add_child(window["frame"])
	var content: VBoxContainer = window["content"]

	var scroll := ScrollContainer.new()
	scroll.name = "CompanyScroll"
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	content.add_child(scroll)
	_company = VBoxContainer.new()
	_company.name = "Company"
	_company.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_company.add_theme_constant_override("separation", SECTION_SEPARATION)
	scroll.add_child(_company)
	content.add_child(HSeparator.new())
	_stopSection = VBoxContainer.new()
	_stopSection.name = "Stop"
	_stopSection.add_theme_constant_override("separation", ROW_SEPARATION)
	content.add_child(_stopSection)

	_resultRoot = Control.new()
	_resultRoot.name = "ResultRoot"
	_resultRoot.set_anchors_preset(Control.PRESET_FULL_RECT)
	_resultRoot.theme = NoggThemeScript.build_game_theme()
	_resultRoot.visible = false
	add_child(_resultRoot)
	var shade := ColorRect.new()
	shade.color = NoggThemeScript.HEX_MODAL_SHADE
	shade.set_anchors_preset(Control.PRESET_FULL_RECT)
	_resultRoot.add_child(shade)
	var resultSize := Vector2(
		minf(RESULT_WIDTH * sizeScale, viewportSize.x - margin * 2.0),
		minf(RESULT_HEIGHT * sizeScale, viewportSize.y - margin * 2.0))
	var result := _window("ResultWindow", resultSize)
	result["frame"].position = (viewportSize - resultSize) * 0.5
	_resultRoot.add_child(result["frame"])
	_resultContent = result["content"]
	if not _model.is_empty():
		_rebuild()


## The screen width, in pixels, the side window and its margins take from the right edge.
func coveredWidth() -> float:
	return _coveredWidth


## Redraws the side window. See WorldMapRoadController._panelModel for the shape.
func present(model: Dictionary) -> void:
	_model = model.duplicate(true)
	_confirmingNewRoad = false
	if _company != null:
		_rebuild()


func setVisibleUI(shown: bool) -> void:
	if _root != null:
		_root.visible = shown


## The centred report of one battle: `{title, lines: Array[String]}`.
func showResult(report: Dictionary) -> void:
	_clear(_resultContent)
	_resultContent.add_child(NoggThemeScript.make_banner_label(str(report.get("title", ""))))
	for line in report.get("lines", []):
		var label := Label.new()
		label.text = str(line)
		label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		_resultContent.add_child(label)
	var spacer := Control.new()
	spacer.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_resultContent.add_child(spacer)
	var close := _button("CONTINUE", func() -> void: result_closed.emit())
	close.name = "ContinueButton"
	_resultContent.add_child(close)
	_resultRoot.visible = true
	close.call_deferred("grab_focus")


func hideResult() -> void:
	_resultRoot.visible = false


func isShowingResult() -> bool:
	return _resultRoot != null and _resultRoot.visible


func _rebuild() -> void:
	_clear(_company)
	_company.add_child(_heading("COMPANY  %d/%d FIELDED" % [int(_model.get("field_count", 0)), int(_model.get("field_size", 0))]))
	for entry: Dictionary in _model.get("company", []):
		_company.add_child(_companyRow(entry))

	_clear(_stopSection)
	var stop: Dictionary = _model.get("stop", {})
	if not stop.is_empty():
		var stepper := HBoxContainer.new()
		stepper.add_theme_constant_override("separation", ROW_SEPARATION)
		var previous := _button("<", func() -> void: stop_stepped.emit(-1))
		previous.name = "PreviousStop"
		stepper.add_child(previous)
		var stopTitle := _heading("STOP %d OF %d" % [int(stop["index"]) + 1, int(stop["count"])])
		stopTitle.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		stopTitle.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		stepper.add_child(stopTitle)
		var next := _button(">", func() -> void: stop_stepped.emit(1))
		next.name = "NextStop"
		stepper.add_child(next)
		_stopSection.add_child(stepper)
		_stopSection.add_child(_dim("%s, map %s" % [str(stop["status_text"]), str(stop["map"])]))
		for enemy: Dictionary in stop["enemies"]:
			var row := Label.new()
			row.text = "%s  Lv%d%s" % [str(enemy["name"]), int(enemy["level"]), "  Captain" if bool(enemy["captain"]) else ""]
			row.clip_text = true
			row.add_theme_color_override("font_color", NoggThemeScript.TEXT_ENEMY)
			_stopSection.add_child(row)

	var travel := _button(str(_model.get("travel_label", "TRAVEL")), func() -> void: travel_requested.emit())
	travel.name = "TravelButton"
	travel.disabled = not bool(_model.get("can_travel", false))
	_stopSection.add_child(travel)

	var notice := str(_model.get("notice", ""))
	if not notice.is_empty():
		var noticeLabel := Label.new()
		noticeLabel.name = "Notice"
		noticeLabel.text = notice
		noticeLabel.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		noticeLabel.add_theme_color_override("font_color", NoggThemeScript.TEXT_ACCENT)
		_stopSection.add_child(noticeLabel)

	var footer := HBoxContainer.new()
	footer.add_theme_constant_override("separation", ROW_SEPARATION)
	var setup := _button("SETUP", func() -> void: setup_requested.emit())
	setup.name = "SetupButton"
	setup.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	footer.add_child(setup)
	var newRoad := _button("NEW ROAD", _onNewRoadPressed)
	newRoad.name = "NewRoadButton"
	newRoad.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	footer.add_child(newRoad)
	_stopSection.add_child(footer)


func _companyRow(entry: Dictionary) -> Control:
	var slot := int(entry["slot"])
	var block := VBoxContainer.new()
	block.name = "Slot%d" % slot
	block.add_theme_constant_override("separation", 2)

	var top := HBoxContainer.new()
	top.add_theme_constant_override("separation", ROW_SEPARATION)
	var fielded := CheckBox.new()
	fielded.name = "Fielded"
	fielded.button_pressed = bool(entry["fielded"])
	fielded.tooltip_text = "Field this monster in the next battle."
	fielded.toggled.connect(func(_on: bool) -> void: field_toggled.emit(slot))
	top.add_child(fielded)
	var nameLabel := Label.new()
	nameLabel.text = str(entry["name"])
	nameLabel.clip_text = true
	nameLabel.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	if not bool(entry["fielded"]):
		nameLabel.add_theme_color_override("font_color", NoggThemeScript.TEXT_DIM)
	top.add_child(nameLabel)
	var level := Label.new()
	level.text = "Lv%d" % int(entry["level"])
	top.add_child(level)
	var captain := _button("CAPTAIN" if bool(entry["captain"]) else "LEAD", func() -> void: captain_chosen.emit(slot))
	captain.name = "Captain"
	captain.disabled = bool(entry["captain"]) or not bool(entry["fielded"])
	captain.tooltip_text = "This monster commands. If it falls, the battle is lost."
	top.add_child(captain)
	block.add_child(top)

	var belief := _dim(str(entry["belief_text"]))
	belief.name = "Belief"
	block.add_child(belief)
	if not bool(entry["can_ascend"]) and not str(entry.get("ascension_text", "")).is_empty():
		var ascension := _dim(str(entry["ascension_text"]))
		ascension.name = "AscensionHint"
		block.add_child(ascension)
	if bool(entry["can_ascend"]):
		var ascend := _button("ASCEND INTO %s" % str(entry["ascends_into"]).to_upper(), func() -> void: ascend_requested.emit(slot))
		ascend.name = "Ascend"
		ascend.clip_text = true
		block.add_child(ascend)
	return block


func _onNewRoadPressed() -> void:
	if not _confirmingNewRoad:
		_confirmingNewRoad = true
		var button := _stopSection.find_child("NewRoadButton", true, false) as Button
		if button != null:
			button.text = "CONFIRM: ERASE"
		return
	_confirmingNewRoad = false
	new_road_requested.emit()


## A Nogg window of `size`: `{frame: Control, content: VBoxContainer}`, the content inset.
func _window(windowName: String, size: Vector2) -> Dictionary:
	var frame := Control.new()
	frame.name = windowName
	frame.custom_minimum_size = size
	frame.size = size
	var halo := NoggThemeScript.build_window_halo()
	if halo != null:
		frame.add_child(halo)
	frame.add_child(NoggThemeScript.build_window_body())
	var rim := NoggThemeScript.build_window_frame()
	if rim != null:
		frame.add_child(rim)
	var inset := MarginContainer.new()
	inset.set_anchors_preset(Control.PRESET_FULL_RECT)
	for side in ["left", "top", "right", "bottom"]:
		inset.add_theme_constant_override("margin_%s" % side, NoggThemeScript.CONTENT_INSET)
	frame.add_child(inset)
	var content := VBoxContainer.new()
	content.name = "Content"
	content.add_theme_constant_override("separation", SECTION_SEPARATION)
	inset.add_child(content)
	return {"frame": frame, "content": content}


func _clear(container: Node) -> void:
	for child in container.get_children():
		container.remove_child(child)
		child.queue_free()


func _heading(text: String) -> Label:
	var label := Label.new()
	label.text = text
	label.add_theme_color_override("font_color", NoggThemeScript.TEXT_ACCENT)
	return label


func _dim(text: String) -> Label:
	var label := Label.new()
	label.text = text
	label.clip_text = true
	label.add_theme_color_override("font_color", NoggThemeScript.TEXT_DIM)
	return label


func _button(text: String, pressed: Callable) -> Button:
	var button := Button.new()
	button.text = text
	button.pressed.connect(pressed)
	return button
