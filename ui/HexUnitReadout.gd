## The unit card a click on a unit opens, docked bottom-left. Four rows, sized to the longest
## monster name rather than to a fixed share of the screen:
##
##     Polar Weather Wizard          name, in its side's colour
##     ^ Lv3 [===|===|==   ] 36/50   crown for a captain, level, HP bar with a tick every 10 HP
##     ATK 6  DEF 5  MOV 3           green when a buff or Resonance raises it, red when lowered
##     [LI]##.  +20%     ## 2  ## 3  element squares with charge cells, effects with turns left
##
## While the player aims, the same window shows the matchup instead (`showMatchup`): the target's
## HP as it would stand after the action, what the action does, and the target's elements and
## effects; or, for an area spell, the units it would hit. The matchup states what the action does
## and nothing about what the player should do: no threat, weakness or counter advice. That depth
## belongs to the STATUS sheet.
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
## Matchup kinds (see `HexMatchupFacts`).
const MATCHUP_AREA := "area"
## The part of the HP bar a blow would take away, and the part a heal would restore.
const LOST_CHUNK := Color(1.0, 0.353, 0.306)
const HEAL_CHUNK := Color(0.62, 1.0, 0.65)
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
## The aim matchup this card shows instead of the unit, or {} (see `showMatchup`).
var _matchup: Dictionary = {}
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
	if not _facts.is_empty() or not _matchup.is_empty():
		_rebuild()


func showFacts(facts: Dictionary) -> void:
	if facts.is_empty():
		hideReadout()
		return
	var wasVisible := visible
	_matchup = {}
	_facts = facts
	visible = true
	if is_node_ready():
		_rebuild()
		if not wasVisible:
			_window.open()


## While the player aims, the card shows the matchup instead of the unit. Same window and rows.
func showMatchup(matchup: Dictionary) -> void:
	if matchup.is_empty():
		return
	var wasVisible := visible
	_matchup = matchup
	visible = true
	if is_node_ready():
		_rebuild()
		if not wasVisible:
			_window.open()


func showingMatchup() -> bool:
	return visible and not _matchup.is_empty()


func hideReadout() -> void:
	_matchup = {}
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
	if not _matchup.is_empty():
		if str(_matchup.get("kind", "")) == MATCHUP_AREA:
			_rebuildArea()
		else:
			_rebuildSingle()
		return
	var f := _facts
	_addFittedRow([str(f.get("name", ""))], _sideColor(f))
	_buildVitals(f, int(f.get("hp", 0)), int(f.get("hp", 0)), int(f.get("max_hp", 1)))
	_buildStats(f.get("card_stats", []))
	_buildDetail(f)


# --- the unit ---------------------------------------------------------------------

## `^ Lv3 [===|===|==   ] 36/50`. With `after` different from `before`, the bar shows the chunk a
## blow takes (red) or a heal restores (pale green), and the numbers read `before > after` with the
## arrow drawn.
func _buildVitals(f: Dictionary, before: int, after: int, maxHp: int) -> void:
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

	var changed := after != before
	var arrow := _textWidth("0") * 0.75
	var numbersWidth := (_textWidth("%d" % before) + gap + arrow + _textWidth("%d" % after)) if changed \
		else _textWidth("%d/%d" % [before, maxHp])
	var right := rect.position.x + rect.size.x
	var barWidth := maxf(right - x - gap - numbersWidth, NoggThemeScript.HEX_ELEMENT_CELL)
	var height := NoggThemeScript.HEX_HP_BAR_HEIGHT * 2.0
	var top := rect.position.y + floorf((rect.size.y - height) / 2.0)
	var maximum := float(maxi(1, maxHp))
	_box(x, top, barWidth, height, NoggThemeScript.HEX_HP_BACK)
	var kept := floorf(barWidth * clampf(float(mini(before, after)) / maximum, 0.0, 1.0))
	var low := float(after) / maximum <= HexHpBarScript.LOW_FRACTION
	_box(x, top, kept, height, NoggThemeScript.HEX_HP_FILL_LOW if low else NoggThemeScript.HEX_HP_FILL)
	if changed:
		var span := floorf(barWidth * clampf(float(maxi(before, after)) / maximum, 0.0, 1.0)) - kept
		if span > 0.0:
			_box(x + kept, top, span, height, HEAL_CHUNK if after > before else LOST_CHUNK)
	var tick := maxf(1.0, floorf(float(NoggThemeScript.ui_scale) / 2.0))
	var hp := HP_TICK
	while hp < maxHp:
		_box(x + floorf(barWidth * float(hp) / maximum), top, tick, height, NoggThemeScript.WINDOW_FILL_DEEP)
		hp += HP_TICK

	var nx := x + barWidth + gap
	if changed:
		var first := _label("%d" % before, NoggThemeScript.TEXT_PRIMARY)
		first.position = Vector2(nx, rect.position.y + _centreY(first, rect))
		_overlay.add_child(first)
		nx += first.size.x + gap * 0.5
		_drawArrow(Vector2(nx, rect.position.y + rect.size.y * 0.5), arrow)
		nx += arrow + gap * 0.5
		var second := _label("%d" % after, NoggThemeScript.HEX_HP_FILL_LOW if after == 0 or low else NoggThemeScript.TEXT_PRIMARY)
		second.position = Vector2(nx, rect.position.y + _centreY(second, rect))
		_overlay.add_child(second)
	else:
		var current := _label("%d" % before, NoggThemeScript.HEX_HP_FILL_LOW if low else NoggThemeScript.TEXT_PRIMARY)
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


# --- the matchup ------------------------------------------------------------------

## One target: its name and the action; its HP after the action; what the action does; its elements
## and effects.
func _rebuildSingle() -> void:
	var m := _matchup
	var target: Dictionary = m.get("target", {})
	var name := str(target.get("name", ""))
	var action := str(m.get("action", ""))
	_window.add_row("", "", true)
	var rect := _window.row_rect(ROW_NAME)
	var nameText := _fitted([name], rect.size.x)
	var nameLabel := _label(nameText, _sideColor(target))
	nameLabel.position = Vector2(rect.position.x, rect.position.y + _centreY(nameLabel, rect))
	_overlay.add_child(nameLabel)
	var room := rect.size.x - nameLabel.size.x - _textWidth("  ")
	if _textWidth(action) <= room:
		var actionLabel := _label(action, NoggThemeScript.TEXT_DIM)
		actionLabel.position = Vector2(rect.position.x + nameLabel.size.x + _textWidth("  "),
			rect.position.y + _centreY(actionLabel, rect))
		_overlay.add_child(actionLabel)

	_buildVitals(target, int(m.get("hp", 0)), int(m.get("hp_after", 0)), int(m.get("max_hp", 1)))
	var outcome := _outcomeLine(m)
	_addFittedRow(outcome["texts"], outcome["color"])
	_buildDetail(target)


## An area spell, summed up rather than listed (four rows cannot list eight units): what it is and
## how many it hits; how many of those are on each side, red when the caster's own side is among
## them; the damage range; and how many it would defeat.
func _rebuildArea() -> void:
	var m := _matchup
	var targets: Array = m.get("targets", [])
	_addFittedRow([str(m.get("action", ""))], NoggThemeScript.TEXT_PRIMARY, "%d hit" % targets.size())
	if not bool(m.get("legal", false)):
		var reason := str(m.get("reason", ""))
		_addFittedRow([reason, "Not possible here"] if not reason.is_empty() else ["Not possible here"],
			NoggThemeScript.TEXT_ENEMY)
		_window.add_row("", "", true)
		_window.add_row("", "", true)
		return
	var allies := 0
	var low := -1
	var high := 0
	var defeated := 0
	var alliesDefeated := 0
	for target: Dictionary in targets:
		var ally := str(target.get("allegiance", "")) == HexUnitFactsScript.ALLEGIANCE_ALLY
		if ally:
			allies += 1
		var damage := int(target.get("damage", 0))
		if damage > 0:
			low = damage if low < 0 else mini(low, damage)
			high = maxi(high, damage)
		if bool(target.get("lethal", false)):
			defeated += 1
			if ally:
				alliesDefeated += 1
	var others := targets.size() - allies
	if allies > 0:
		_addFittedRow(["%s, %s" % [_count(allies, "ally", "allies"), _count(others, "enemy", "enemies")],
			_count(allies, "ally", "allies")], NoggThemeScript.TEXT_ENEMY)
	else:
		_addFittedRow([_count(others, "enemy", "enemies")], NoggThemeScript.TEXT_DIM)
	if low < 0:
		_window.add_row("No damage", "", true)
	elif low == high:
		_addFittedRow(["Deals %d each" % low, "Deals %d" % low], NoggThemeScript.TEXT_PRIMARY)
	else:
		_addFittedRow(["Deals %d to %d" % [low, high], "Deals %d-%d" % [low, high]], NoggThemeScript.TEXT_PRIMARY)
	if defeated == 0:
		_window.add_row("", "", true)
	elif alliesDefeated > 0:
		_addFittedRow(["Defeats %d, %s" % [defeated, _count(alliesDefeated, "ally", "allies")],
			"Defeats %d" % defeated], NoggThemeScript.TEXT_ENEMY)
	else:
		_addFittedRow(["Defeats %d" % defeated], NoggThemeScript.TEXT_ACCENT)


func _count(amount: int, one: String, many: String) -> String:
	return "%d %s" % [amount, one if amount == 1 else many]


## What the action does: `{texts, color}`, longest wording first.
func _outcomeLine(m: Dictionary) -> Dictionary:
	if not bool(m.get("legal", false)):
		var reason := str(m.get("reason", ""))
		var refused: Array[String] = []
		if not reason.is_empty():
			refused.append(reason)
		refused.append("Not possible here")
		return {"texts": refused, "color": NoggThemeScript.TEXT_ENEMY}
	var heal := int(m.get("heal", 0))
	if heal > 0:
		return {"texts": ["Restores %d HP" % heal, "+%d HP" % heal], "color": HEAL_CHUNK}
	var low := int(m.get("damage_min", 0))
	var high := int(m.get("damage_max", 0))
	if low <= 0:
		var effect := str(m.get("effect_text", ""))
		var quiet: Array[String] = []
		if not effect.is_empty():
			quiet.append(effect)
		quiet.append("No damage")
		return {"texts": quiet, "color": NoggThemeScript.TEXT_DIM}
	var chance := roundi(float(m.get("crit_chance", 0.0)) * 100.0)
	if bool(m.get("lethal", false)):
		return {"texts": ["Deals %d and defeats it" % low, "Defeats it"], "color": NoggThemeScript.TEXT_ACCENT}
	if bool(m.get("possibly_lethal", false)) and chance > 0:
		return {"texts": ["Deals %d, a crit defeats it (%d%%)" % [low, chance],
			"Deals %d, crit KO %d%%" % [low, chance]], "color": NoggThemeScript.TEXT_ACCENT}
	if high > low and chance > 0:
		return {"texts": ["Deals %d, crit %d (%d%%)" % [low, high, chance], "Deals %d-%d" % [low, high]],
			"color": NoggThemeScript.TEXT_PRIMARY}
	return {"texts": ["Deals %d" % low], "color": NoggThemeScript.TEXT_PRIMARY}


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


## A right-pointing triangle `width` wide, centred on `centre.y`.
func _drawArrow(left: Vector2, width: float) -> void:
	var arrow := Polygon2D.new()
	arrow.color = NoggThemeScript.TEXT_DIM
	var half := floorf(width * 0.6)
	arrow.polygon = PackedVector2Array([Vector2(0.0, -half), Vector2(width, 0.0), Vector2(0.0, half)])
	arrow.position = Vector2(left.x, floorf(left.y))
	_overlay.add_child(arrow)


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
