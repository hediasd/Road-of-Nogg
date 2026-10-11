## The unit card a click on a unit opens, docked bottom-left. Four rows, sized to the longest
## monster name rather than to a fixed share of the screen:
##
##     Polar Weather Wizard          name, in its side's colour
##     ^ Lv3 [===|===|==   ] 36/50   crown for a captain, level, HP bar with a tick every 10 HP
##     ATK 6  DEF 5  MOV 3           green when a buff or Resonance raises it, red when lowered
##     [LI]##.  +20%     ## 2  ## 3  element squares with charge cells, effects with turns left
##
## The card is the unit's general status only. What an aimed attack or spell would do is drawn over
## the targeted units by the screen cues (`SideTurnPreviewBox`), never here.
##
## A READOUT, NOT A MENU. Input-transparent, so it can sit over the board without making the tiles
## under it unclickable (the reason `NoggWindow.set_input_transparent` exists). Pointing at an
## effect is answered by the HUD asking `effectAt()`, not by this box taking mouse input.
##
## FIXED CAPACITY. Four rows whatever is shown, so nothing ever makes the box jump (UI_DESIGN §4,
## "size on open, then hold"). Effects that do not fit collapse into a `+N` cell, which the HUD
## explains with the names it hides; the full list is on the STATUS sheet.
##
## OPENS ONCE. The window plays its open animation when it appears, not each time the pointer
## sweeps onto another unit; after that the content swaps in place.
##
## TEXT IS FITTED, NEVER CLIPPED. Every string the card draws is measured against its room and,
## where it must, hard-cut (UI_DESIGN §7, no ellipsis glyph). Symbols are drawn, not typed (§3).

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

const ROWS := 4
const ROW_NAME := 0
const ROW_VITALS := 1
const ROW_STATS := 2
const ROW_DETAIL := 3
## A charge bar has as many cells as Resonance has tiers.
const RESONANCE_CELLS := 3
## One tick on the HP bar per this many hit points, so a glance reads quantity, not just a share.
const HP_TICK := 10
## A stat raised above, or lowered below, what the unit's level makes it.
const STAT_UP := Color(0.62, 1.0, 0.65)
const STAT_DOWN := Color(1.0, 0.353, 0.306)
## An uncharged cell: the dim text colour, thinned, so it reads as an empty slot on the box fill.
const EMPTY_CELL := Color(0.510, 0.486, 0.588, 0.45)

## The allegiance words. The card no longer prints them -- a unit's side is its name's colour, and a
## captain wears a drawn crown -- but the STATUS sheet still does, and reads them from here.
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
	_facts = facts
	visible = true
	if is_node_ready():
		_rebuild()
		if not wasVisible:
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
	var f := _facts
	_addFittedRow([str(f.get("name", ""))], _sideColor(f))
	_buildVitals(f)
	_buildStats(f.get("card_stats", []))
	_buildDetail(f)


# --- the unit ---------------------------------------------------------------------

## `^ Lv3 [===|===|==   ] 36/50`: a crown for a captain, the level, the HP bar with a tick every 10 HP,
## and current/max with the maximum dimmed.
func _buildVitals(f: Dictionary) -> void:
	_window.add_row("", "", true)
	var rect := _window.row_rect(ROW_VITALS)
	var gap := NoggThemeScript.HEX_PLATE_GAP * 2.0
	var x := rect.position.x
	if bool(f.get("commander", false)):
		x += _drawCrown(Vector2(x, rect.position.y), rect.size.y) + gap
	var level := _label("Lv%d" % int(f.get("level", 1)), NoggThemeScript.TEXT_ACCENT)
	level.position = Vector2(x, rect.position.y + _centreY(level, rect))
	_overlay.add_child(level)
	x += level.size.x + gap

	var hp := int(f.get("hp", 0))
	var maxHp := int(f.get("max_hp", 1))
	var right := rect.position.x + rect.size.x
	var barWidth := maxf(right - x - gap - _textWidth("%d/%d" % [hp, maxHp]), NoggThemeScript.HEX_ELEMENT_CELL)
	var height := NoggThemeScript.HEX_HP_BAR_HEIGHT * 2.0
	var top := rect.position.y + floorf((rect.size.y - height) / 2.0)
	var maximum := float(maxi(1, maxHp))
	_box(x, top, barWidth, height, NoggThemeScript.HEX_HP_BACK)
	var low := float(hp) / maximum <= HexHpBarScript.LOW_FRACTION
	_box(x, top, floorf(barWidth * clampf(float(hp) / maximum, 0.0, 1.0)), height,
		NoggThemeScript.HEX_HP_FILL_LOW if low else NoggThemeScript.HEX_HP_FILL)
	var tick := maxf(1.0, floorf(float(NoggThemeScript.ui_scale) / 2.0))
	var mark := HP_TICK
	while mark < maxHp:
		_box(x + floorf(barWidth * float(mark) / maximum), top, tick, height, NoggThemeScript.WINDOW_FILL_DEEP)
		mark += HP_TICK

	var nx := x + barWidth + gap
	var current := _label("%d" % hp, NoggThemeScript.HEX_HP_FILL_LOW if low else NoggThemeScript.TEXT_PRIMARY)
	current.position = Vector2(nx, rect.position.y + _centreY(current, rect))
	_overlay.add_child(current)
	var total := _label("/%d" % maxHp, NoggThemeScript.TEXT_DIM)
	total.position = Vector2(nx + current.size.x, rect.position.y + _centreY(total, rect))
	_overlay.add_child(total)


## `ATK 6  DEF 5  MOV 3`: dim labels, bright values, green or red where the battle has moved a stat
## off what the unit's level makes it.
func _buildStats(stats: Array) -> void:
	_window.add_row("", "", true)
	var rect := _window.row_rect(ROW_STATS)
	var x := rect.position.x
	var right := rect.position.x + rect.size.x
	for stat: Dictionary in stats:
		var label := _label(str(stat.get("label", "")) + " ", NoggThemeScript.TEXT_DIM)
		var delta := int(stat.get("delta", 0))
		var color := NoggThemeScript.TEXT_PRIMARY
		if delta > 0:
			color = STAT_UP
		elif delta < 0:
			color = STAT_DOWN
		var value := _label("%d" % int(stat.get("value", 0)), color)
		if x + label.size.x + value.size.x > right:
			label.queue_free()
			value.queue_free()
			return
		label.position = Vector2(x, rect.position.y + _centreY(label, rect))
		_overlay.add_child(label)
		x += label.size.x
		value.position = Vector2(x, rect.position.y + _centreY(value, rect))
		_overlay.add_child(value)
		x += value.size.x + _textWidth("  ")


## Element squares, each followed by its charge cells once it holds a charge, and the bonus the
## highest gives; then the effects, each a swatch and its turns left, folding into `+N`.
func _buildDetail(f: Dictionary) -> void:
	_window.add_row("", "", true)
	var rect := _window.row_rect(ROW_DETAIL)
	var x := rect.position.x
	var gap := NoggThemeScript.HEX_PLATE_GAP
	var cell := NoggThemeScript.HEX_ELEMENT_CELL * 0.5
	var elements: Array = f.get("elements", [])
	var charges: Array = f.get("resonance", [])
	for index in range(elements.size()):
		var square: HexElementSquare = HexElementSquareScript.new()
		square.setElement(elements[index])
		square.position = Vector2(x, rect.position.y + floorf((rect.size.y - NoggThemeScript.HEX_ELEMENT_CELL) / 2.0))
		_overlay.add_child(square)
		x += square.size.x + gap
		var charge := int((charges[index] as Dictionary).get("charge", 0)) if index < charges.size() else 0
		if charge > 0:
			var color: Color = (elements[index] as Dictionary).get("color", NoggThemeScript.TEXT_PRIMARY)
			for pip in range(RESONANCE_CELLS):
				_box(x, rect.position.y + floorf((rect.size.y - cell) / 2.0), cell, cell,
					color if pip < charge else EMPTY_CELL)
				x += cell + gap * 0.5
		x += gap * 2.0
	var bonus := int(f.get("resonance_bonus", 0))
	if bonus > 0:
		var text := _label("+%d%%" % bonus, NoggThemeScript.TEXT_DIM)
		text.position = Vector2(x, rect.position.y + _centreY(text, rect))
		_overlay.add_child(text)
		x += text.size.x + gap * 3.0
	_buildEffects(f.get("effects", []), x + gap, rect)


func _buildEffects(effects: Array, startX: float, rect: Rect2) -> void:
	var chip := NoggThemeScript.HEX_ELEMENT_CELL * 0.5
	var gap := NoggThemeScript.HEX_PLATE_ICON_GAP
	var right := rect.position.x + rect.size.x
	var x := startX
	var overflowWidth := _textWidth("+9") + gap
	for index in range(effects.size()):
		var fact: Dictionary = effects[index]
		var text := "%d" % int(fact.get("turns", 0))
		var cellWidth := chip + gap * 0.5 + _textWidth(text)
		var remaining := effects.size() - index
		var reserve := overflowWidth if remaining > 1 else 0.0
		if x + cellWidth + reserve > right:
			_addOverflowCell(effects.slice(index), x, rect)
			return
		var swatch := ColorRect.new()
		swatch.mouse_filter = Control.MOUSE_FILTER_IGNORE
		swatch.color = StatusEffectIconsScript.chip_color(fact.get("raw", {}))
		swatch.size = Vector2(chip, chip)
		swatch.position = Vector2(x, rect.position.y + floorf((rect.size.y - chip) / 2.0))
		_overlay.add_child(swatch)
		var label := _label(text, NoggThemeScript.TEXT_PRIMARY)
		label.position = Vector2(x + chip + gap * 0.5, rect.position.y + _centreY(label, rect))
		_overlay.add_child(label)
		_effectCells.append({"rect": Rect2(Vector2(x, rect.position.y), Vector2(cellWidth, rect.size.y)), "fact": fact})
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


# --- drawing helpers --------------------------------------------------------------

## A unit's name colour: its side's, as seen from the player's party; plain when there is no
## point of view (a CPU-only battle).
func _sideColor(f: Dictionary) -> Color:
	match str(f.get("allegiance", HexUnitFactsScript.ALLEGIANCE_UNKNOWN)):
		HexUnitFactsScript.ALLEGIANCE_ALLY:
			return NoggThemeScript.TEXT_ALLY
		HexUnitFactsScript.ALLEGIANCE_ENEMY:
			return NoggThemeScript.TEXT_ENEMY
	return NoggThemeScript.TEXT_PRIMARY


## A captain's crown in the accent colour, a row tall at most; returns its width. Drawn rather than
## typed: the face has no such glyph.
func _drawCrown(origin: Vector2, rowHeight: float) -> float:
	var height := floorf(rowHeight * 0.45)
	var width := floorf(height * 1.4)
	var top := origin.y + floorf((rowHeight - height) / 2.0)
	var crown := Polygon2D.new()
	crown.name = "Crown"
	crown.color = NoggThemeScript.TEXT_ACCENT
	crown.polygon = PackedVector2Array([
		Vector2(0.0, height), Vector2(0.0, height * 0.25), Vector2(width * 0.25, height * 0.6),
		Vector2(width * 0.5, 0.0), Vector2(width * 0.75, height * 0.6), Vector2(width, height * 0.25),
		Vector2(width, height),
	])
	crown.position = Vector2(origin.x, top)
	_overlay.add_child(crown)
	return width


func _box(x: float, y: float, width: float, height: float, color: Color) -> void:
	var rect := ColorRect.new()
	rect.mouse_filter = Control.MOUSE_FILTER_IGNORE
	rect.color = color
	rect.position = Vector2(x, y)
	rect.size = Vector2(width, height)
	_overlay.add_child(rect)


## Adds a window row holding the first of `texts` that fits beside `value`, or the last one hard-cut
## to fit, in `color`. Through the window's own row, so centring and inset are the window's.
func _addFittedRow(texts: Array, color: Color, value: String = "") -> void:
	var room := _window.size.x - float(NoggThemeScript.CONTENT_INSET) * 2.0
	if not value.is_empty():
		room -= _textWidth(value) + _textWidth("  ")
	var row := _window.add_row(_fitted(texts, room), value)
	var label := row.get_child(0).get_child(0) as Label if row != null and row.get_child_count() > 0 else null
	if label != null and color != NoggThemeScript.TEXT_PRIMARY:
		label.add_theme_color_override("font_color", color)


## The first of `texts` that fits `room`, or the last one cut to fit.
func _fitted(texts: Array, room: float) -> String:
	for candidate in texts:
		var text := str(candidate)
		if not text.is_empty() and _textWidth(text) <= room:
			return text
	var cut := str(texts[texts.size() - 1]) if not texts.is_empty() else ""
	while cut.length() > 1 and _textWidth(cut) > room:
		cut = cut.substr(0, cut.length() - 1)
	return cut.strip_edges()


func _label(text: String, color: Color) -> Label:
	var label := Label.new()
	label.text = text
	label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	label.add_theme_color_override("font_color", color)
	# Measured with the game font: a label not yet in the tree reports the fallback font's size.
	label.size = Vector2(_textWidth(text), _lineHeight())
	return label


func _lineHeight() -> float:
	var font := get_theme_default_font()
	if font == null:
		font = ThemeDB.fallback_font
	return font.get_height(NoggThemeScript.FONT_SIZE_BODY)


func _centreY(label: Label, rect: Rect2) -> float:
	return floorf((rect.size.y - label.size.y) / 2.0)


func _textWidth(text: String) -> float:
	var font := get_theme_default_font()
	if font == null:
		font = ThemeDB.fallback_font
	return font.get_string_size(
		text, HORIZONTAL_ALIGNMENT_LEFT, -1, NoggThemeScript.FONT_SIZE_BODY
	).x
