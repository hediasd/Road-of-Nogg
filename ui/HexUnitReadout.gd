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
## Matchup kinds and rows (see `HexMatchupFacts`).
const MATCHUP_AREA := "area"
const AREA_ROWS := 4
## The part of the HP bar a blow would take away, and the part a heal would restore.
const LOST_CHUNK := Color(1.0, 0.353, 0.306)
const HEAL_CHUNK := Color(0.62, 1.0, 0.65)
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
	if not _facts.is_empty():
		_rebuild()


func showFacts(facts: Dictionary) -> void:
	if facts.is_empty():
		hideReadout()
		return
	var wasVisible := visible
	var sameUnit := _matchup.is_empty() and int(_facts.get("id", -1)) == int(facts.get("id", -2))
	_matchup = {}
	_facts = facts
	visible = true
	if is_node_ready():
		_rebuild()
		if not wasVisible or not sameUnit:
			_window.open()


## While the player aims, the card shows the matchup instead of the unit: one target's HP after
## the blow, the damage and crit, its weakness or resistance to the action, and whether it can hit
## the acting unit next turn; or, for an area spell, every unit it would hit. Same window, same six
## rows, so aiming never makes the box jump. The window opens again only when what it is about
## changes (another target, or a single target becoming an area).
func showMatchup(matchup: Dictionary) -> void:
	if matchup.is_empty():
		return
	var wasVisible := visible
	var sameSubject := not _matchup.is_empty() and _matchupKey(_matchup) == _matchupKey(matchup)
	_matchup = matchup
	visible = true
	if is_node_ready():
		_rebuild()
		if not wasVisible or not sameSubject:
			_window.open()


func showingMatchup() -> bool:
	return visible and not _matchup.is_empty()


func _matchupKey(matchup: Dictionary) -> String:
	return "%s|%s|%d" % [str(matchup.get("kind", "")), str(matchup.get("action", "")),
		int(matchup.get("target_id", -1))]


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


# --- the matchup ------------------------------------------------------------------

func _rebuildSingle() -> void:
	var m := _matchup
	_addFittedRow([str(m.get("target_name", ""))], NoggThemeScript.TEXT_PRIMARY,
		"Lv %d" % int(m.get("target_level", 1)))

	_window.add_row("", "", true)
	var rect := _window.row_rect(ROW_SIDE)
	var x := _sideWord(m, rect)
	var action := str(m.get("action", ""))
	var elements: Array = m.get("elements", [])
	var candidates: Array[String] = []
	if not elements.is_empty():
		candidates.append("%s, %s" % [action, ", ".join(PackedStringArray(elements)).capitalize()])
	candidates.append(action)
	_placeFitted(candidates, x, rect, NoggThemeScript.TEXT_DIM)

	_buildChangeBar(int(m.get("hp", 0)), int(m.get("hp_after", 0)), int(m.get("max_hp", 1)))

	var outcome := _outcomeLine(m)
	_addFittedRow(outcome["texts"], outcome["color"])
	var matchupLine := _matchupLine(m.get("matchup", {}), bool(m.get("reactive", false)))
	_addFittedRow(matchupLine["texts"], matchupLine["color"])
	var threat := _threatLine(m)
	_addFittedRow(threat["texts"], threat["color"])


func _rebuildArea() -> void:
	var m := _matchup
	var targets: Array = m.get("targets", [])
	var legal := bool(m.get("legal", false))
	_addFittedRow([str(m.get("action", ""))], NoggThemeScript.TEXT_PRIMARY, "%d hit" % targets.size())
	_window.add_row("", "", true)
	var rect := _window.row_rect(ROW_SIDE)
	var elements: Array = m.get("elements", [])
	var element := ", ".join(PackedStringArray(elements)).capitalize() if not elements.is_empty() else "No element"
	var alliesHit := int(m.get("allies_hit", 0))
	if not legal:
		var reason := str(m.get("reason", ""))
		_placeFitted([reason, "Not possible here"] if not reason.is_empty() else ["Not possible here"],
			rect.position.x, rect, NoggThemeScript.TEXT_ENEMY)
	elif alliesHit > 0:
		var allies := "%d all%s" % [alliesHit, "y" if alliesHit == 1 else "ies"]
		_placeFitted(["%s, hits %s" % [element, allies], "Hits %s" % allies], rect.position.x, rect,
			NoggThemeScript.TEXT_ENEMY)
	else:
		_placeFitted([element], rect.position.x, rect, NoggThemeScript.TEXT_DIM)
	for index in range(AREA_ROWS):
		if index == AREA_ROWS - 1 and targets.size() > AREA_ROWS:
			_window.add_row("+%d more" % (targets.size() - index), "", true)
			continue
		if index >= targets.size():
			_window.add_row("", "", true)
			continue
		var target: Dictionary = targets[index]
		var damage := int(target.get("damage", 0))
		var value := ""
		if damage > 0:
			value = ("-%d KO" % damage) if bool(target.get("lethal", false)) else ("-%d" % damage)
		var ally := str(target.get("allegiance", "")) == HexUnitFactsScript.ALLEGIANCE_ALLY
		var tag := ""
		match str((target.get("matchup", {}) as Dictionary).get("kind", "")):
			"weak":
				tag = " weak"
			"resist":
				tag = " resists"
		var name := str(target.get("name", ""))
		_addFittedRow([name + tag, name], NoggThemeScript.TEXT_ALLY if ally else NoggThemeScript.TEXT_PRIMARY, value)


## The side word at the start of `rect`'s row; returns where the next text may start.
func _sideWord(m: Dictionary, rect: Rect2) -> float:
	var allegiance := str(m.get("allegiance", HexUnitFactsScript.ALLEGIANCE_UNKNOWN))
	if allegiance == HexUnitFactsScript.ALLEGIANCE_UNKNOWN:
		return rect.position.x
	var ally := allegiance == HexUnitFactsScript.ALLEGIANCE_ALLY
	var word := ALLY_TAG if ally else ENEMY_TAG
	if bool(m.get("commander", false)):
		word = COMMANDER_TAG
	var tag := _label(word, NoggThemeScript.TEXT_ALLY if ally else NoggThemeScript.TEXT_ENEMY)
	tag.position = Vector2(rect.position.x, rect.position.y + _centreY(tag, rect))
	_overlay.add_child(tag)
	return rect.position.x + tag.size.x + _textWidth("  ")


## The HP bar as it would stand after the action: what stays, and the chunk lost or restored in its
## own colour, with `before->after` at the end.
func _buildChangeBar(before: int, after: int, maxHp: int) -> void:
	_window.add_row("", "", true)
	var rect := _window.row_rect(ROW_HP)
	var numbers := "%d->%d" % [before, after]
	var gap := NoggThemeScript.HEX_PLATE_GAP * 2.0
	var height := NoggThemeScript.HEX_HP_BAR_HEIGHT * 2.0
	var width := maxf(rect.size.x - _textWidth(numbers) - gap, NoggThemeScript.HEX_HP_BAR_WIDTH)
	var top := rect.position.y + floorf((rect.size.y - height) / 2.0)
	var maximum := float(maxi(1, maxHp))
	_bar(rect.position.x, top, width, height, NoggThemeScript.HEX_HP_BACK)
	var kept := floorf(width * clampf(float(mini(before, after)) / maximum, 0.0, 1.0))
	var low := float(after) / maximum <= HexHpBarScript.LOW_FRACTION
	_bar(rect.position.x, top, kept, height,
		NoggThemeScript.HEX_HP_FILL_LOW if low else NoggThemeScript.HEX_HP_FILL)
	var changed := floorf(width * clampf(float(maxi(before, after)) / maximum, 0.0, 1.0)) - kept
	if changed > 0.0:
		_bar(rect.position.x + kept, top, changed, height, HEAL_CHUNK if after > before else LOST_CHUNK)
	var label := _label(numbers,
		NoggThemeScript.HEX_HP_FILL_LOW if after == 0 else NoggThemeScript.TEXT_PRIMARY)
	label.position = Vector2(rect.position.x + width + gap, rect.position.y + _centreY(label, rect))
	_overlay.add_child(label)


func _bar(x: float, y: float, width: float, height: float, color: Color) -> void:
	var rect := ColorRect.new()
	rect.mouse_filter = Control.MOUSE_FILTER_IGNORE
	rect.color = color
	rect.position = Vector2(x, y)
	rect.size = Vector2(width, height)
	_overlay.add_child(rect)


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


func _matchupLine(matchup: Dictionary, reactive: bool) -> Dictionary:
	var element := str(matchup.get("element", "")).capitalize()
	var percent := int(matchup.get("percent", 0))
	var texts: Array[String] = []
	var color := NoggThemeScript.TEXT_DIM
	match str(matchup.get("kind", "")):
		"weak":
			texts = ["Weak to %s, %+d%%" % [element, percent], "Weak, %+d%%" % percent]
			color = NoggThemeScript.TEXT_ACCENT
		"resist":
			texts = ["Resists %s, %+d%%" % [element, percent], "Resists, %+d%%" % percent]
		"neutral":
			texts = ["No weakness to %s" % element, "No weakness"]
		"quiet":
			return {"texts": [], "color": color}
		_:
			texts = ["No element, race does not matter", "No element"]
	if reactive:
		var withRisk: Array[String] = []
		for text in texts:
			withRisk.append(text + ", strikes back")
		withRisk.append_array(texts)
		texts = withRisk
	return {"texts": texts, "color": color}


func _threatLine(m: Dictionary) -> Dictionary:
	var threat := int(m.get("threat", -1))
	if threat < 0:
		return {"texts": [], "color": NoggThemeScript.TEXT_DIM}
	if bool(m.get("threat_lethal", false)):
		return {"texts": ["Can defeat you next turn", "Can defeat you"], "color": NoggThemeScript.TEXT_ENEMY}
	if threat > 0:
		return {"texts": ["Can hit you for %d next turn" % threat, "Can hit you for %d" % threat],
			"color": NoggThemeScript.TEXT_PRIMARY}
	return {"texts": ["Cannot reach you next turn", "Can't reach you next", "Can't reach you"],
		"color": NoggThemeScript.TEXT_DIM}


## Adds a window row holding the first of `texts` that fits beside `value`, or the last one
## shortened with "..." when none does, in `color`. Through the window's own row, so its
## centring and inset are the window's, and it can never clip.
func _addFittedRow(texts: Array, color: Color, value: String = "") -> void:
	var room := _window.size.x - float(NoggThemeScript.CONTENT_INSET) * 2.0
	if not value.is_empty():
		room -= _textWidth(value) + _textWidth("  ")
	var chosen := ""
	for candidate in texts:
		var text := str(candidate)
		if not text.is_empty() and _textWidth(text) <= room:
			chosen = text
			break
	if chosen.is_empty() and not texts.is_empty():
		chosen = _ellipsized(str(texts[texts.size() - 1]), room)
	var row := _window.add_row(chosen, value)
	var label := row.get_child(0).get_child(0) as Label if row != null and row.get_child_count() > 0 else null
	if label != null and color != NoggThemeScript.TEXT_PRIMARY:
		label.add_theme_color_override("font_color", color)


## `text` cut to fit `room` with "..." at its end.
func _ellipsized(text: String, room: float) -> String:
	if _textWidth(text) <= room:
		return text
	var cut := text
	while cut.length() > 1 and _textWidth(cut + "...") > room:
		cut = cut.substr(0, cut.length() - 1)
	return cut.strip_edges() + "..."


## Draws the first of `texts` that fits between `x` and the end of `rect`; draws nothing if none
## does, so the card never clips or overruns its inset.
func _placeFitted(texts: Array, x: float, rect: Rect2, color: Color) -> void:
	var room := rect.position.x + rect.size.x - x
	for value in texts:
		var text := str(value)
		if text.is_empty() or _textWidth(text) > room:
			continue
		var label := _label(text, color)
		label.position = Vector2(x, rect.position.y + _centreY(label, rect))
		_overlay.add_child(label)
		return


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
