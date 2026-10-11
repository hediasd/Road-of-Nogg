## The damage preview over a targeted unit: its HP bar above its head, with the segment the aimed
## action would take flashing, and the change beside it.
##
## SEPARATE FROM THE UNIT CARD. The docked card is the unit's general status and never turns into a
## preview; what an action would do is drawn here, on the unit it is about.
##
## NO FRAME. An area spell can touch eight units side by side, and framed boxes over each piled into
## a tower nobody could match back to its unit. A bar and a number are small enough to sit on their
## own unit, the way Into the Breach marks the health a blow will take. The text wears the theme's
## baked outline, the treatment `NoggTheme.OUTLINE_SIZE` exists for: text over an arbitrary bright
## background.
##
##     [######::::]  -3              one target, or each unit an area spell touches
##     [######::::]  -3              a single target also says what a crit would do
##      crit -5 7%
##     [::::::::::]  KO              lethal: the whole remaining bar flashes
##     [#######++ ]  +7              a heal: the restored segment flashes pale green
##
## Motion: an entrance fade, over an idle pulse of the flashing segment that never resolves, each on
## its own constants (docs/VFX_DESIGN.md, the house motion style). The numbers are
## `HexTargetPreviews`'; this control only draws them. An aim the rules refuse still shows what it
## would do, dimmed.

class_name SideTurnPreviewBox
extends Control

const NoggThemeScript = preload("res://ui/NoggTheme.gd")
const HexHpBarScript = preload("res://ui/HexHpBar.gd")

## The bar's size and border, in design units.
const BAR_WIDTH_UNITS := 40.0
## A pill's bar is narrower and carries its number above it, so the tags of neighbouring units in
## an area spell fit side by side (adjacent hexes sit about 32 design units apart on screen).
const PILL_BAR_WIDTH_UNITS := 24.0
const BAR_HEIGHT_UNITS := 5.0
const BAR_BORDER_UNITS := 1.0
const GAP_UNITS := 3.0
const ENTER_SECONDS := 0.14
## The flashing segment's idle pulse: from full to this alpha and back, every this many seconds.
const PULSE_LOW_ALPHA := 0.35
const PULSE_SECONDS := 0.9
const LOST_CHUNK := Color(1.0, 0.353, 0.306)
const HEAL_CHUNK := Color(0.62, 1.0, 0.65)
const BORDER := Color(0.0, 0.0, 0.0, 0.85)
## How much an aim the rules refuse is dimmed.
const REFUSED_ALPHA := 0.55

var targetID := -1
var worldAnchor := Vector3.ZERO
var compact := false
var _model: Dictionary = {}
var _chunk: ColorRect
var _clock := 0.0


func _init() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE


## `model` is one entry of `HexTargetPreviews.build`. `pill` leaves out the crit line, for when
## several units are touched at once.
func configure(model: Dictionary, pill: bool = false) -> void:
	_model = model.duplicate(true)
	targetID = int(model.get("monster_id", -1))
	worldAnchor = model.get("world_anchor", Vector3.ZERO)
	compact = pill
	for child in get_children():
		remove_child(child)
		child.queue_free()

	var unit := float(NoggThemeScript.ui_scale)
	var border := maxf(1.0, roundf(BAR_BORDER_UNITS * unit))
	var barWidth := roundf((PILL_BAR_WIDTH_UNITS if pill else BAR_WIDTH_UNITS) * unit)
	var barHeight := roundf(BAR_HEIGHT_UNITS * unit)
	var gap := roundf(GAP_UNITS * unit)
	var headline := _headline()
	var number := _label(str(headline["text"]), headline["color"])
	var lineHeight := number.size.y
	var outer := Vector2(barWidth + border * 2.0, barHeight + border * 2.0)

	# Single: [bar] -3, crit line below. Pill: the number centred above the bar.
	var barOrigin := Vector2(0.0, floorf((lineHeight - outer.y) / 2.0))
	if pill:
		var columnWidth := maxf(outer.x, number.size.x)
		number.position = Vector2(floorf((columnWidth - number.size.x) / 2.0), 0.0)
		barOrigin = Vector2(floorf((columnWidth - outer.x) / 2.0), lineHeight)
	else:
		number.position = Vector2(outer.x + gap, 0.0)
	_buildBar(barOrigin, border, barWidth, barHeight)
	add_child(number)
	var width := maxf(number.position.x + number.size.x, barOrigin.x + outer.x)
	var height := (lineHeight + outer.y) if pill else lineHeight
	var crit := "" if pill else _critText()
	if not crit.is_empty():
		var line := _label(crit, NoggThemeScript.TEXT_ACCENT if bool(_model.get("possibly_lethal", false)) 			else NoggThemeScript.TEXT_PRIMARY)
		line.position = Vector2(0.0, lineHeight)
		add_child(line)
		width = maxf(width, line.size.x)
		height += lineHeight
	size = Vector2(width, height)
	modulate.a = 1.0 if bool(model.get("legal", true)) else REFUSED_ALPHA
	_enter()


## The unit's HP bar as it would stand, in a dark border: what stays, and the segment the action
## takes (red) or restores (pale green), which pulses.
func _buildBar(origin: Vector2, border: float, barWidth: float, barHeight: float) -> void:
	_box(origin.x, origin.y, barWidth + border * 2.0, barHeight + border * 2.0, BORDER)
	var inner := origin + Vector2(border, border)
	var before := int(_model.get("hp", 0))
	var after := int(_model.get("hp_after", 0))
	var maximum := float(maxi(1, int(_model.get("max_hp", 1))))
	_box(inner.x, inner.y, barWidth, barHeight, NoggThemeScript.HEX_HP_BACK)
	var kept := floorf(barWidth * clampf(float(mini(before, after)) / maximum, 0.0, 1.0))
	var low := float(after) / maximum <= HexHpBarScript.LOW_FRACTION
	_box(inner.x, inner.y, kept, barHeight, NoggThemeScript.HEX_HP_FILL_LOW if low else NoggThemeScript.HEX_HP_FILL)
	var span := floorf(barWidth * clampf(float(maxi(before, after)) / maximum, 0.0, 1.0)) - kept
	_chunk = null
	if span > 0.0:
		_chunk = _box(inner.x + kept, inner.y, span, barHeight, HEAL_CHUNK if after > before else LOST_CHUNK)


func _process(delta: float) -> void:
	if _chunk == null:
		return
	_clock += delta
	var wave := 0.5 + 0.5 * cos(_clock * TAU / PULSE_SECONDS)
	_chunk.modulate.a = lerpf(PULSE_LOW_ALPHA, 1.0, wave)


func _enter() -> void:
	visible = true
	var settled := modulate.a
	modulate.a = 0.0
	create_tween().tween_property(self, "modulate:a", settled, ENTER_SECONDS)


## `-3`, `-12 KO`, `+7`: the change, in the colour of the bar's flashing segment.
func _headline() -> Dictionary:
	var heal := int(_model.get("heal", 0))
	if heal > 0:
		return {"text": "+%d" % heal, "color": HEAL_CHUNK}
	var damage := int(_model.get("damage", 0))
	if bool(_model.get("lethal", false)):
		return {"text": "-%d KO" % damage, "color": NoggThemeScript.TEXT_ACCENT}
	return {"text": "-%d" % damage, "color": LOST_CHUNK}


## `crit -5 7%` or `crit KO 7%` under a single target's bar, when a crit can happen and changes it.
func _critText() -> String:
	if int(_model.get("heal", 0)) > 0 or bool(_model.get("lethal", false)):
		return ""
	var chance := roundi(float(_model.get("crit_chance", 0.0)) * 100.0)
	if chance <= 0:
		return ""
	if bool(_model.get("possibly_lethal", false)):
		return "crit KO %d%%" % chance
	if int(_model.get("crit_damage", 0)) > int(_model.get("damage", 0)):
		return "crit -%d %d%%" % [int(_model.get("crit_damage", 0)), chance]
	return ""


func _box(x: float, y: float, width: float, height: float, color: Color) -> ColorRect:
	var rect := ColorRect.new()
	rect.mouse_filter = Control.MOUSE_FILTER_IGNORE
	rect.color = color
	rect.position = Vector2(x, y)
	rect.size = Vector2(width, height)
	add_child(rect)
	return rect


func _label(text: String, color: Color) -> Label:
	var label := Label.new()
	label.text = text
	label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	label.add_theme_color_override("font_color", color)
	label.add_theme_constant_override("outline_size", NoggThemeScript.OUTLINE_SIZE)
	# Measured with the game font: a label not yet in the tree reports the fallback font's size.
	var font := get_theme_default_font()
	if font == null:
		font = ThemeDB.fallback_font
	label.size = Vector2(
		font.get_string_size(text, HORIZONTAL_ALIGNMENT_LEFT, -1, NoggThemeScript.FONT_SIZE_BODY).x,
		font.get_height(NoggThemeScript.FONT_SIZE_BODY))
	return label


## What this tag says, for probes: `{label, value}` with the change and the crit line.
func forecastRows() -> Array[Dictionary]:
	return [{"label": str(_headline()["text"]), "value": "" if compact else _critText()}]
