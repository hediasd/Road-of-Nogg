## The compact readout a click on a unit opens: the unit's name, then whose side it is on and what
## level it is, an HP bar with its numbers, the unit's element squares, and its active effects with
## the turns each has left.
##
## A READOUT, NOT A MENU. Input-transparent, so it can sit over the board without making the tiles
## under it unclickable (the reason `NoggWindow.set_input_transparent` exists). Pointing at an
## effect is answered by the HUD asking `effectAt()`, not by this box taking mouse input.
##
## FIXED CAPACITY. Five rows whatever the unit, so selecting a unit with no effects and then one
## with five never makes the box jump (UI_DESIGN §4, "size on open, then hold"). Effects that do not
## fit the last row collapse into a `+N` cell, which the HUD explains with the names it hides; the
## full list is on the STATUS sheet.
##
## NOTHING ON THIS PLATE MOVES BETWEEN UNITS. The level is zero-padded and the allegiance word is
## laid out in a field the width of the longest one, so sweeping the cursor across the board never
## redraws a column in a new place. Holding a column still is the same rule as holding the box
## size still, applied one level down.

class_name HexUnitReadout
extends Control

const NoggWindowScript = preload("res://src/presentation/theme/NoggWindow.gd")
const NoggThemeScript = preload("res://src/presentation/theme/NoggTheme.gd")
const StatusEffectIconsScript = preload("res://src/presentation/StatusEffectIcons.gd")
const HexElementSquareScript = preload("res://src/presentation/battle/ui/HexElementSquare.gd")
const HexHpBarScript = preload("res://src/presentation/battle/ui/HexHpBar.gd")
## For the `allegiance` vocabulary only. This control renders a `HexUnitFacts` dictionary, so the
## names of the values in it are the one thing it may legitimately know; it still never builds one,
## and still never sees a `Monster` or a `BattleState`.
const HexUnitFactsScript = preload("res://src/presentation/battle/ui/HexUnitFacts.gd")

const ROWS := 5
const ROW_NAME := 0
const ROW_TAG := 1
const ROW_HP := 2
const ROW_KIND := 3
const ROW_EFFECTS := 4

## The allegiance words, and the one a commander takes instead.
##
## A COMMANDER SPENDS ITS SIDE WORD ON ITS RANK. `COMMANDER` replaces `ALLY`/`ENEMY` rather than
## joining it, so a commander's side is carried by the word's colour alone. That is the one place
## on this plate where colour is not backing up a word but standing in for one, and it is the
## channel a colourblind player does not have. Chosen knowingly; `ENEMY CMDR` is the alternative
## if the trade is ever reconsidered.
const ALLY_TAG := "ALLY"
const ENEMY_TAG := "ENEMY"
const COMMANDER_TAG := "COMMANDER"

var _window: NoggWindow
var _overlay: Control
var _facts: Dictionary = {}
## Hit rects of the effect cells, in this control's space: {rect, fact} or {rect, overflow: Array}.
var _effectCells: Array = []


func _init() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	_window = NoggWindowScript.new()
	_window.set_input_transparent(true)
	add_child(_window)
	# Inside the window, not beside it: the HP bar, element squares and effect swatches have to
	# scale and fade with the window's open animation, or they sit on screen before the text pops in.
	_overlay = Control.new()
	_overlay.name = "Overlay"
	_overlay.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_window.add_child(_overlay)
	visible = false


func _ready() -> void:
	_window.size.x = NoggThemeScript.HEX_READOUT_WIDTH
	_window.set_row_capacity(ROWS)
	size = _window.size
	# Added before the window built its chrome; keep it drawn over the rows, as the status sheet does.
	_window.move_child(_overlay, _window.get_child_count() - 1)
	if not _facts.is_empty():
		_rebuild()


func showFacts(facts: Dictionary) -> void:
	if facts.is_empty():
		hideReadout()
		return
	var wasVisible := visible
	var sameUnit := int(_facts.get("id", -1)) == int(facts.get("id", -2))
	_facts = facts
	visible = true
	if is_node_ready():
		_rebuild()
		if not wasVisible or not sameUnit:
			_window.open()


func hideReadout() -> void:
	_facts = {}
	_effectCells.clear()
	visible = false


func unitID() -> int:
	return int(_facts.get("id", -1))


func facts() -> Dictionary:
	return _facts


func boxSize() -> Vector2:
	return _window.size


## The effect cell under `globalPoint`: `{"fact": effectFacts}` for one effect, `{"overflow": [..]}`
## for the `+N` cell, or empty.
func effectAt(globalPoint: Vector2) -> Dictionary:
	if not visible:
		return {}
	var local := globalPoint - global_position
	for cell in _effectCells:
		if (cell["rect"] as Rect2).has_point(local):
			return cell
	return {}


func effectCellRect(cell: Dictionary) -> Rect2:
	var rect: Rect2 = cell.get("rect", Rect2())
	return Rect2(global_position + rect.position, rect.size)


func _rebuild() -> void:
	for child in _overlay.get_children():
		_overlay.remove_child(child)
		child.queue_free()
	_effectCells.clear()
	_window.clear_rows()

	_window.add_row(str(_facts.get("name", "")))
	_buildTagRow()

	var hp := int(_facts.get("hp", 0))
	var maxHp := int(_facts.get("max_hp", 1))
	_window.add_row("HP", "%d/%d" % [hp, maxHp])
	var hpRect := _window.row_rect(ROW_HP)
	var bar: HexHpBar = HexHpBarScript.new()
	bar.setValues(hp, maxHp)
	var labelWidth := _textWidth("HP ")
	bar.position = Vector2(
		hpRect.position.x + labelWidth,
		hpRect.position.y + floorf((hpRect.size.y - NoggThemeScript.HEX_HP_BAR_HEIGHT) / 2.0)
	)
	bar.size = Vector2(NoggThemeScript.HEX_HP_BAR_WIDTH, NoggThemeScript.HEX_HP_BAR_HEIGHT)
	_overlay.add_child(bar)

	_buildKindRow()
	_buildEffectsRow()


## `ENEMY Lv.06`: the side word and the level, as one right-aligned pair.
##
## THE TAG SITS IN A FIXED FIELD. `COMMANDER` is nine characters against `ENEMY`'s five, so a word
## laid out flush against the level would move its own left edge by four cells every time the
## cursor crossed a commander -- the jitter the zero-padded level exists to remove, reintroduced
## right beside it. The field is measured off the longest word rather than assumed, which is
## `docs/UI_DESIGN.md` §8's rule applied to a word instead of a window.
##
## `Lv.%02d` grows to six characters past level 99 and the pair steps left once. A real step, not
## a hidden one: it happens at a level nothing reaches today, and it happens once.
func _buildTagRow() -> void:
	var level := "Lv.%02d" % int(_facts.get("level", 1))
	_window.add_row("", level)

	var allegiance := str(_facts.get("allegiance", HexUnitFactsScript.ALLEGIANCE_UNKNOWN))
	if allegiance == HexUnitFactsScript.ALLEGIANCE_UNKNOWN:
		return
	var ally := allegiance == HexUnitFactsScript.ALLEGIANCE_ALLY
	var word := ALLY_TAG if ally else ENEMY_TAG
	if bool(_facts.get("commander", false)):
		word = COMMANDER_TAG
	var label := _label(word, NoggThemeScript.TEXT_ALLY if ally else NoggThemeScript.TEXT_ENEMY)

	var rect := _window.row_rect(ROW_TAG)
	var pairWidth := (
		_textWidth(COMMANDER_TAG) + NoggThemeScript.HEX_PLATE_ICON_GAP + _textWidth(level)
	)
	label.position = Vector2(
		rect.position.x + rect.size.x - pairWidth,
		rect.position.y + _centreY(label, rect)
	)
	_overlay.add_child(label)


## Element squares first, then the taxonomy the unit is read by.
func _buildKindRow() -> void:
	var elements: Array = _facts.get("elements", [])
	var squareSpan := 0.0
	for element in elements:
		squareSpan += NoggThemeScript.HEX_ELEMENT_CELL * 2.0 + NoggThemeScript.HEX_PLATE_GAP
	var indentText := ""
	var race := str(_facts.get("race", "none"))
	var species := str(_facts.get("species", "none"))
	var kind := species if species != "none" and species != "" else race
	# Rows are plain text; the squares are drawn over the row's leading space, so the text is
	# pushed right by whole spaces rather than by a per-row indent NoggWindow does not have.
	var spaceWidth := maxf(_textWidth(" "), 1.0)
	indentText = " ".repeat(int(ceil(squareSpan / spaceWidth)))
	_window.add_row(indentText + (kind.capitalize() if kind != "none" else ""), "", false)
	var rect := _window.row_rect(ROW_KIND)
	var x := rect.position.x
	for element in elements:
		var square: HexElementSquare = HexElementSquareScript.new()
		square.setElement(element)
		square.position = Vector2(
			x, rect.position.y + floorf((rect.size.y - NoggThemeScript.HEX_ELEMENT_CELL) / 2.0)
		)
		_overlay.add_child(square)
		x += square.size.x + NoggThemeScript.HEX_PLATE_GAP


## `Burn 2  Poison 3  +2`: a chip in the effect's badge colour, its name, its turns left.
func _buildEffectsRow() -> void:
	var effects: Array = _facts.get("effects", [])
	if effects.is_empty():
		_window.add_row("No effects", "", true)
		return
	_window.add_row("", "", true)
	# Read after the row exists: row_rect() answers an empty rect for a row not yet added.
	var rect := _window.row_rect(ROW_EFFECTS)
	var chip := NoggThemeScript.HEX_ELEMENT_CELL * 0.5
	var gap := NoggThemeScript.HEX_PLATE_ICON_GAP
	var right := rect.position.x + rect.size.x
	var x := rect.position.x
	var overflowWidth := _textWidth("+9") + gap
	for index in range(effects.size()):
		var fact: Dictionary = effects[index]
		var text := "%s %d" % [str(fact.get("label", "")), int(fact.get("turns", 0))]
		var cellWidth := chip + gap * 0.5 + _textWidth(text)
		var remaining := effects.size() - index
		var reserve := overflowWidth if remaining > 1 else 0.0
		if x + cellWidth + reserve > right:
			_addOverflowCell(effects.slice(index), x, rect)
			return
		var cellRect := Rect2(Vector2(x, rect.position.y), Vector2(cellWidth, rect.size.y))
		var swatch := ColorRect.new()
		swatch.mouse_filter = Control.MOUSE_FILTER_IGNORE
		swatch.color = StatusEffectIconsScript.chip_color(fact.get("raw", {}))
		swatch.size = Vector2(chip, chip)
		swatch.position = Vector2(x, rect.position.y + floorf((rect.size.y - chip) / 2.0))
		_overlay.add_child(swatch)
		var label := _label(text, NoggThemeScript.TEXT_PRIMARY)
		label.position = Vector2(x + chip + gap * 0.5, rect.position.y + _centreY(label, rect))
		_overlay.add_child(label)
		_effectCells.append({"rect": cellRect, "fact": fact})
		x += cellWidth + gap


func _addOverflowCell(hidden: Array, x: float, rect: Rect2) -> void:
	var text := "+%d" % hidden.size()
	var label := _label(text, NoggThemeScript.TEXT_ACCENT)
	label.position = Vector2(x, rect.position.y + _centreY(label, rect))
	_overlay.add_child(label)
	_effectCells.append({
		"rect": Rect2(Vector2(x, rect.position.y), Vector2(_textWidth(text), rect.size.y)),
		"overflow": hidden,
	})


func _label(text: String, color: Color) -> Label:
	var label := Label.new()
	label.text = text
	label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	label.add_theme_color_override("font_color", color)
	label.size = label.get_minimum_size()
	return label


func _centreY(label: Label, rect: Rect2) -> float:
	return floorf((rect.size.y - label.size.y) / 2.0)


func _textWidth(text: String) -> float:
	var font := get_theme_default_font()
	if font == null:
		font = ThemeDB.fallback_font
	return font.get_string_size(
		text, HORIZONTAL_ALIGNMENT_LEFT, -1, NoggThemeScript.FONT_SIZE_BODY
	).x
