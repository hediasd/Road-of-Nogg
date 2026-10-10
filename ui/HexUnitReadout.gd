## The unit card a click on a unit opens. Six rows: the name and level; whose side it is on and
## what it is (race, family); its HP as a bar with the numbers; ATK, DEF and MOV; each element's
## Resonance charge with the bonus the highest gives; and its active effects, or where it stands in
## its side's turn when it has none.
##
## A READOUT, NOT A MENU. Input-transparent, so it can sit over the board without making the tiles
## under it unclickable (the reason `NoggWindow.set_input_transparent` exists). Pointing at an
## effect is answered by the HUD asking `effectAt()`, not by this box taking mouse input.
##
## FIXED CAPACITY. Six rows whatever the unit, so selecting a unit with no effects and then one
## with five never makes the box jump (UI_DESIGN §4, "size on open, then hold"). Effects that do not
## fit the last row collapse into a `+N` cell, which the HUD explains with the names it hides; the
## full list is on the STATUS sheet.
##
## COLUMNS HOLD STILL. The side word always starts its row, and the level is the name row's
## right-aligned value, so sweeping the cursor across the board does not redraw a column in a new
## place. The level is no longer zero-padded: its left edge steps once, at level 10, the cap.
## Text the card draws itself is measured and shortened rather than ever clipped.

class_name HexUnitReadout
extends Control

const NoggWindowScript = preload("res://ui/NoggWindow.gd")
const NoggThemeScript = preload("res://ui/NoggTheme.gd")
const StatusEffectIconsScript = preload("res://ui/StatusEffectIcons.gd")
const HexElementSquareScript = preload("res://ui/HexElementSquare.gd")
const HexHpBarScript = preload("res://ui/HexHpBar.gd")
## For the `allegiance` vocabulary only. This control renders a `HexUnitFacts` dictionary, so the
## names of the values in it are the one thing it may legitimately know; it still never builds one,
## and still never sees a `Monster` or a `BattleState`.
const HexUnitFactsScript = preload("res://ui/HexUnitFacts.gd")

const ROWS := 6
const ROW_NAME := 0
const ROW_SIDE := 1
const ROW_HP := 2
const ROW_STATS := 3
const ROW_RESONANCE := 4
const ROW_EFFECTS := 5
## A charge bar has as many cells as Resonance has tiers.
const RESONANCE_CELLS := 3
## An uncharged cell: the dim text colour, thinned, so it reads as an empty slot on the box fill.
const EMPTY_CELL := Color(0.510, 0.486, 0.588, 0.45)
## The last row when the unit carries no effect: where it stands in its side's turn.
const TURN_TEXT := {
	"ready": "Ready to move and act",
	"moved": "Moved, can still act",
	"acted": "Acted, can still move",
	"spent": "Done this turn",
	"waiting": "Waiting for its side",
}

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

	_window.add_row(str(_facts.get("name", "")), "Lv %d" % int(_facts.get("level", 1)))
	_buildSideRow()
	_buildHpRow()
	var stats: Dictionary = _facts.get("stats", {})
	_window.add_row("ATK %d  DEF %d  MOV %d" % [
		int(stats.get("ATK", 0)), int(stats.get("DEF", 0)), int(stats.get("MOV", 0))])
	_buildResonanceRow()
	if (_facts.get("effects", []) as Array).is_empty():
		_window.add_row(TURN_TEXT.get(str(_facts.get("turn", "")), ""), "", true)
	else:
		_buildEffectsRow()


## `ALLY  Sephilim - Elgladion`: whose side, in its colour, then what the unit is. The taxonomy
## is measured against the row and loses the family, then itself, rather than ever clipping.
func _buildSideRow() -> void:
	_window.add_row("", "", true)
	var rect := _window.row_rect(ROW_SIDE)
	var x := rect.position.x
	var allegiance := str(_facts.get("allegiance", HexUnitFactsScript.ALLEGIANCE_UNKNOWN))
	if allegiance != HexUnitFactsScript.ALLEGIANCE_UNKNOWN:
		var ally := allegiance == HexUnitFactsScript.ALLEGIANCE_ALLY
		var word := ALLY_TAG if ally else ENEMY_TAG
		if bool(_facts.get("commander", false)):
			word = COMMANDER_TAG
		var tag := _label(word, NoggThemeScript.TEXT_ALLY if ally else NoggThemeScript.TEXT_ENEMY)
		tag.position = Vector2(x, rect.position.y + _centreY(tag, rect))
		_overlay.add_child(tag)
		x += tag.size.x + _textWidth("  ")
	var room := rect.position.x + rect.size.x - x
	for text in _taxonomyCandidates():
		if _textWidth(text) <= room:
			var kind := _label(text, NoggThemeScript.TEXT_DIM)
			kind.position = Vector2(x, rect.position.y + _centreY(kind, rect))
			_overlay.add_child(kind)
			return


## Longest first: race and family, then race alone.
func _taxonomyCandidates() -> Array[String]:
	var race := _named(str(_facts.get("race", "")))
	var family := _named(str(_facts.get("family", "")))
	var candidates: Array[String] = []
	if not race.is_empty() and not family.is_empty():
		candidates.append("%s - %s" % [race, family])
	if not race.is_empty():
		candidates.append(race)
	return candidates


## A taxonomy value worth printing, capitalized, or "" for none and placeholders.
func _named(value: String) -> String:
	var lowered := value.strip_edges().to_lower()
	if lowered.is_empty() or lowered == "none" or lowered == "tbc":
		return ""
	return value.capitalize()


## A bar across the row, the numbers at its right end in the bar's own warning colour.
func _buildHpRow() -> void:
	var hp := int(_facts.get("hp", 0))
	var maxHp := int(_facts.get("max_hp", 1))
	var numbers := "%d/%d" % [hp, maxHp]
	_window.add_row("", "", true)
	var rect := _window.row_rect(ROW_HP)
	var bar: HexHpBar = HexHpBarScript.new()
	bar.setValues(hp, maxHp)
	var gap := NoggThemeScript.HEX_PLATE_GAP * 2.0
	var height := NoggThemeScript.HEX_HP_BAR_HEIGHT * 2.0
	var width := maxf(rect.size.x - _textWidth(numbers) - gap, NoggThemeScript.HEX_HP_BAR_WIDTH)
	bar.position = Vector2(rect.position.x, rect.position.y + floorf((rect.size.y - height) / 2.0))
	bar.size = Vector2(width, height)
	_overlay.add_child(bar)
	var low := bar.fraction() <= HexHpBarScript.LOW_FRACTION
	var label := _label(numbers, NoggThemeScript.HEX_HP_FILL_LOW if low else NoggThemeScript.TEXT_PRIMARY)
	label.position = Vector2(rect.position.x + width + gap, rect.position.y + _centreY(label, rect))
	_overlay.add_child(label)


## Each element's square and its three Resonance cells, filled to the charge, and the ATK/DEF bonus
## the highest charge gives at the right end. This is where the signature mechanic shows in battle.
func _buildResonanceRow() -> void:
	var bonus := int(_facts.get("resonance_bonus", 0))
	_window.add_row("", "+%d%%" % bonus if bonus > 0 else "")
	var rect := _window.row_rect(ROW_RESONANCE)
	var x := rect.position.x
	var cell := NoggThemeScript.HEX_ELEMENT_CELL * 0.75
	var gap := NoggThemeScript.HEX_PLATE_GAP
	var colors := {}
	for element: Dictionary in _facts.get("elements", []):
		colors[str(element.get("name", ""))] = element.get("color", NoggThemeScript.TEXT_PRIMARY)
	var elements: Array = _facts.get("elements", [])
	var charges: Array = _facts.get("resonance", [])
	for index in range(elements.size()):
		var square: HexElementSquare = HexElementSquareScript.new()
		square.setElement(elements[index])
		square.position = Vector2(x, rect.position.y + floorf((rect.size.y - NoggThemeScript.HEX_ELEMENT_CELL) / 2.0))
		_overlay.add_child(square)
		x += square.size.x + gap
		var charge := int((charges[index] as Dictionary).get("charge", 0)) if index < charges.size() else 0
		for pip in range(RESONANCE_CELLS):
			var swatch := ColorRect.new()
			swatch.mouse_filter = Control.MOUSE_FILTER_IGNORE
			swatch.color = colors.get(str(elements[index].get("name", "")), NoggThemeScript.TEXT_PRIMARY) 				if pip < charge else EMPTY_CELL
			swatch.size = Vector2(cell, cell)
			swatch.position = Vector2(x, rect.position.y + floorf((rect.size.y - cell) / 2.0))
			_overlay.add_child(swatch)
			x += cell + gap * 0.5
		x += gap * 2.0


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
