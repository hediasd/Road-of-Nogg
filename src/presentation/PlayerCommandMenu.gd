## Fixed-screen player command menu.  It renders the controller's data-only
## menu models and keeps root-command and spell-list navigation independent.

class_name PlayerCommandMenu
extends PanelContainer

signal entry_activated(entry_id: String)
signal spell_activated(set_index: int, spell_index: int)

const ROOT := "root"
const SPELLS := "spells"
const BACK_ID := "__back"

var _status: Label
var _forecast: Label
var _root_column: VBoxContainer
var _spell_column: VBoxContainer
var _entries: Array = []
var _spells: Array = []
var _mode := ROOT
var _root_selected_id := ""
var _spell_selected_id := ""


func _ready() -> void:
	_style_panel()
	var body := VBoxContainer.new()
	body.add_theme_constant_override("separation", 6)
	add_child(body)
	_status = Label.new()
	_status.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	body.add_child(_status)
	_forecast = Label.new()
	_forecast.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_forecast.add_theme_color_override("font_color", Color(0.72, 0.9, 1.0))
	_forecast.visible = false
	body.add_child(_forecast)
	var columns := HBoxContainer.new()
	columns.add_theme_constant_override("separation", 8)
	body.add_child(columns)
	_root_column = VBoxContainer.new()
	_root_column.custom_minimum_size.x = 230
	columns.add_child(_root_column)
	_spell_column = VBoxContainer.new()
	_spell_column.custom_minimum_size.x = 270
	_spell_column.visible = false
	columns.add_child(_spell_column)
	_rebuild_root()


func setStatus(text: String) -> void:
	_status.text = text


func setForecast(text: String) -> void:
	_forecast.text = text
	_forecast.visible = not text.is_empty()


func showRoot(entries: Array) -> void:
	_mode = ROOT
	_entries = entries.duplicate(true)
	_spell_column.visible = false
	_rebuild_root()


func openSpells(spells: Array) -> void:
	_mode = SPELLS
	_spells = spells.duplicate(true)
	_root_selected_id = "magic"
	_spell_column.visible = true
	_rebuild_root()
	_rebuild_spells()


func closeSpells() -> bool:
	if _mode != SPELLS:
		return false
	_mode = ROOT
	_spell_column.visible = false
	_rebuild_root()
	return true


func isShowingSpells() -> bool:
	return _mode == SPELLS


func moveSelection(direction: int) -> void:
	var selectable = _spell_selectable_ids() if _mode == SPELLS else _root_selectable_ids()
	if selectable.is_empty():
		return
	var selected = _spell_selected_id if _mode == SPELLS else _root_selected_id
	var index = selectable.find(selected)
	index = 0 if index < 0 else posmod(index + direction, selectable.size())
	if _mode == SPELLS:
		_spell_selected_id = selectable[index]
		_rebuild_spells()
	else:
		_root_selected_id = selectable[index]
		_rebuild_root()


func acceptSelection() -> void:
	if _mode == ROOT:
		if not _root_selected_id.is_empty():
			_activate_root(_root_selected_id)
		return
	if _spell_selected_id == BACK_ID:
		closeSpells()
		return
	for spell in _spells:
		if _spell_id(spell) == _spell_selected_id and spell["ready"]:
			spell_activated.emit(spell["set_index"], spell["spell_index"])
			return


func _rebuild_root() -> void:
	if _root_column == null:
		return
	_clear_column(_root_column)
	_add_heading(_root_column, "Commands")
	var selectable = _root_selectable_ids()
	if not selectable.has(_root_selected_id):
		_root_selected_id = selectable.front() if not selectable.is_empty() else ""
	for entry in _entries:
		if not entry["visible"]:
			continue
		var entry_id = str(entry["id"])
		var button = _new_button(
			("› " if entry_id == _root_selected_id else "  ") + str(entry["label"]),
			not bool(entry["enabled"])
		)
		button.pressed.connect(_activate_root.bind(entry_id))
		_root_column.add_child(button)


func _rebuild_spells() -> void:
	if _spell_column == null:
		return
	_clear_column(_spell_column)
	_add_heading(_spell_column, "Spell")
	var selectable = _spell_selectable_ids()
	if not selectable.has(_spell_selected_id):
		_spell_selected_id = selectable.front() if not selectable.is_empty() else BACK_ID
	for spell in _spells:
		var spell_id = _spell_id(spell)
		var button = _new_button(
			("› " if spell_id == _spell_selected_id else "  ") + _spell_label(spell),
			not bool(spell["ready"])
		)
		button.pressed.connect(_activate_spell.bind(spell))
		_spell_column.add_child(button)
	var back = _new_button(("› " if _spell_selected_id == BACK_ID else "  ") + "< Back", false)
	back.pressed.connect(closeSpells)
	_spell_column.add_child(back)


func _activate_root(entry_id: String) -> void:
	_root_selected_id = entry_id
	_rebuild_root()
	entry_activated.emit(entry_id)


func _activate_spell(spell: Dictionary) -> void:
	if not spell["ready"]:
		return
	_spell_selected_id = _spell_id(spell)
	_rebuild_spells()
	spell_activated.emit(spell["set_index"], spell["spell_index"])


func _root_selectable_ids() -> Array:
	var ids: Array = []
	for entry in _entries:
		if entry["visible"] and entry["enabled"]:
			ids.append(str(entry["id"]))
	return ids


func _spell_selectable_ids() -> Array:
	var ids: Array = []
	for spell in _spells:
		if spell["ready"]:
			ids.append(_spell_id(spell))
	ids.append(BACK_ID)
	return ids


func _spell_label(spell: Dictionary) -> String:
	return "%s  Range %d  %s" % [
		spell["name"], spell["range"],
		"Ready" if spell["ready"] else "Cooldown %d" % spell["cooldown_remaining"]
	]


func _spell_id(spell: Dictionary) -> String:
	return "spell:%d:%d" % [spell["set_index"], spell["spell_index"]]


func _clear_column(column: VBoxContainer) -> void:
	for child in column.get_children():
		child.queue_free()


func _add_heading(column: VBoxContainer, text: String) -> void:
	var heading = Label.new()
	heading.text = text
	heading.add_theme_color_override("font_color", Color(0.55, 0.8, 1.0))
	column.add_child(heading)


func _new_button(text: String, disabled: bool) -> Button:
	var button = Button.new()
	button.alignment = HORIZONTAL_ALIGNMENT_LEFT
	button.custom_minimum_size.x = 230
	button.focus_mode = Control.FOCUS_NONE
	button.disabled = disabled
	button.text = text
	return button


func _style_panel() -> void:
	var style = StyleBoxFlat.new()
	style.bg_color = Color(0.025, 0.055, 0.11, 0.92)
	style.border_color = Color(0.2, 0.58, 0.9, 0.75)
	style.set_border_width_all(1)
	style.set_corner_radius_all(5)
	style.content_margin_left = 10
	style.content_margin_right = 10
	style.content_margin_top = 10
	style.content_margin_bottom = 10
	add_theme_stylebox_override("panel", style)
