## The damage preview over a targeted unit: a small Nogg window above the unit, saying what the
## aimed attack or spell would do to it.
##
## SEPARATE FROM THE UNIT CARD. The docked card is the unit's general status and never turns into a
## preview; what an action would do is drawn here, in a window of its own over each unit it touches.
##
## ALWAYS A WINDOW. Text never stands loose over the board: every preview is a `NoggWindow` with the
## shared frame and inset. When an area spell touches neighbouring units their windows may overlap;
## each stays on its own unit rather than being pushed away from it, and the screen cues draw the
## nearer unit's window on top.
##
##     .--------------------.
##     | -3       crit -5 7% |    the change; KO, or what a crit would do (single target only)
##     | [######::::] 39/42  |    the unit's HP bar, the segment taken (red) or restored (pale green)
##     '--------------------'     pulsing, and the HP it would be left with
##
## Several units touched: the same two rows, a narrower bar and no HP numbers, so the windows over a
## cluster stay small. The numbers are `HexTargetPreviews`'; this control only draws them. An aim the
## rules refuse still shows what it would do, dimmed. Motion: an entrance fade over an idle pulse of
## the changing segment, each on its own constants (docs/VFX_DESIGN.md).

class_name SideTurnPreviewBox
extends Control

const NoggWindowScript = preload("res://ui/NoggWindow.gd")
const NoggThemeScript = preload("res://ui/NoggTheme.gd")
const HexHpBarScript = preload("res://ui/HexHpBar.gd")

## The HP bar's width in design units: a single target's, and each one's when several are touched.
const BAR_UNITS := 48.0
const PILL_BAR_UNITS := 28.0
const ENTER_SECONDS := 0.14
## The changing segment's idle pulse: from full to this alpha and back, every this many seconds.
const PULSE_LOW_ALPHA := 0.35
const PULSE_SECONDS := 0.9
const LOST_CHUNK := Color(1.0, 0.353, 0.306)
const HEAL_CHUNK := Color(0.62, 1.0, 0.65)
## How much an aim the rules refuse is dimmed.
const REFUSED_ALPHA := 0.55

var _window: NoggWindow
var _overlay: Control
var targetID := -1
var worldAnchor := Vector3.ZERO
var compact := false
var _model: Dictionary = {}
var _chunk: ColorRect
var _clock := 0.0
var _covered := false


func _init() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	_window = NoggWindowScript.new()
	_window.set_input_transparent(true)
	add_child(_window)
	_overlay = Control.new()
	_overlay.name = "Overlay"
	_overlay.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_window.add_child(_overlay)


## `model` is one entry of `HexTargetPreviews.build`. `pill` is the narrower shape used when several
## units are touched at once.
func configure(model: Dictionary, pill: bool = false) -> void:
	_model = model.duplicate(true)
	targetID = int(model.get("monster_id", -1))
	worldAnchor = model.get("world_anchor", Vector3.ZERO)
	compact = pill
	_window.set_row_capacity(2)
	_window.move_child(_overlay, _window.get_child_count() - 1)

	var headline := _headline()
	var detail := "" if pill else _detail()
	var gap := _textWidth("  ")
	var barWidth := NoggThemeScript._scaled(PILL_BAR_UNITS if pill else BAR_UNITS)
	var after := "" if pill else _afterText()
	var content := _textWidth(str(headline["text"]))
	if not detail.is_empty():
		content += gap + _textWidth(detail)
	content = maxf(content, barWidth + ((gap * 0.5 + _textWidth(after)) if not after.is_empty() else 0.0))
	_window.size.x = ceilf(content) + float(NoggThemeScript.CONTENT_INSET) * 2.0
	size = _window.size

	_window.clear_rows()
	for child in _overlay.get_children():
		_overlay.remove_child(child)
		child.queue_free()
	var row := _window.add_row(str(headline["text"]), detail)
	_recolor(row, headline["color"], _detailColor())
	_window.add_row("", "", true)
	_buildBar(after)
	modulate.a = 1.0 if bool(model.get("legal", true)) else REFUSED_ALPHA
	_enter()


## Dims this window (the shared inactive tint) while a nearer unit's window covers part of it, so
## the front number reads and the ones behind recede instead of ghosting through it.
func setCovered(covered: bool) -> void:
	if covered == _covered:
		return
	_covered = covered
	_window.set_active(not covered)
	_overlay.modulate = NoggThemeScript.CONTENT_INACTIVE_MODULATE if covered else NoggThemeScript.CONTENT_ACTIVE_MODULATE


func isCovered() -> bool:
	return _covered


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


## `-3`, `-12 KO`, `+7`: the change, in the colour of the bar's changing segment.
func _headline() -> Dictionary:
	var heal := int(_model.get("heal", 0))
	if heal > 0:
		return {"text": "+%d" % heal, "color": HEAL_CHUNK}
	var damage := int(_model.get("damage", 0))
	if bool(_model.get("lethal", false)):
		return {"text": "-%d KO" % damage, "color": NoggThemeScript.TEXT_ACCENT}
	return {"text": "-%d" % damage, "color": LOST_CHUNK}


## `crit -5 7%` or `crit KO 7%`, when a crit can happen and changes the result.
func _detail() -> String:
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


func _detailColor() -> Color:
	return NoggThemeScript.TEXT_ACCENT if bool(_model.get("possibly_lethal", false)) else NoggThemeScript.TEXT_DIM


func _afterText() -> String:
	return "%d/%d" % [int(_model.get("hp_after", 0)), int(_model.get("max_hp", 1))]


## The unit's HP bar as it would stand: what stays, the segment taken or restored (pulsing), and,
## for a single target, the HP it would be left with.
func _buildBar(after: String) -> void:
	var rect := _window.row_rect(1)
	var gap := _textWidth(" ")
	var width := rect.size.x - ((_textWidth(after) + gap) if not after.is_empty() else 0.0)
	var height := NoggThemeScript.HEX_HP_BAR_HEIGHT * 2.0
	var top := rect.position.y + floorf((rect.size.y - height) / 2.0)
	var before := int(_model.get("hp", 0))
	var left := int(_model.get("hp_after", 0))
	var maximum := float(maxi(1, int(_model.get("max_hp", 1))))
	_box(rect.position.x, top, width, height, NoggThemeScript.HEX_HP_BACK)
	var kept := floorf(width * clampf(float(mini(before, left)) / maximum, 0.0, 1.0))
	var low := float(left) / maximum <= HexHpBarScript.LOW_FRACTION
	_box(rect.position.x, top, kept, height, NoggThemeScript.HEX_HP_FILL_LOW if low else NoggThemeScript.HEX_HP_FILL)
	var span := floorf(width * clampf(float(maxi(before, left)) / maximum, 0.0, 1.0)) - kept
	_chunk = null
	if span > 0.0:
		_chunk = _box(rect.position.x + kept, top, span, height, HEAL_CHUNK if left > before else LOST_CHUNK)
	if after.is_empty():
		return
	var numbers := _label(after, NoggThemeScript.HEX_HP_FILL_LOW if left == 0 or low else NoggThemeScript.TEXT_PRIMARY)
	numbers.position = Vector2(rect.position.x + width + gap, rect.position.y + floorf((rect.size.y - numbers.size.y) / 2.0))
	_overlay.add_child(numbers)


func _recolor(row: Control, labelColor: Color, valueColor: Color) -> void:
	if row == null or row.get_child_count() == 0:
		return
	var label := row.get_child(0).get_child(0) as Label
	if label != null:
		label.add_theme_color_override("font_color", labelColor)
	if row.get_child_count() > 1:
		var value := row.get_child(1) as Label
		if value != null:
			value.add_theme_color_override("font_color", valueColor)


func _box(x: float, y: float, width: float, height: float, color: Color) -> ColorRect:
	var rect := ColorRect.new()
	rect.mouse_filter = Control.MOUSE_FILTER_IGNORE
	rect.color = color
	rect.position = Vector2(x, y)
	rect.size = Vector2(width, height)
	_overlay.add_child(rect)
	return rect


func _label(text: String, color: Color) -> Label:
	var label := Label.new()
	label.text = text
	label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	label.add_theme_color_override("font_color", color)
	# Measured with the game font: a label not yet in the tree reports the fallback font's size.
	var font := get_theme_default_font()
	if font == null:
		font = ThemeDB.fallback_font
	label.size = Vector2(_textWidth(text), font.get_height(NoggThemeScript.FONT_SIZE_BODY))
	return label


func _textWidth(text: String) -> float:
	var font := get_theme_default_font()
	if font == null:
		font = ThemeDB.fallback_font
	return font.get_string_size(text, HORIZONTAL_ALIGNMENT_LEFT, -1, NoggThemeScript.FONT_SIZE_BODY).x


## What this window says, for probes: `{label, value}` per row.
func forecastRows() -> Array[Dictionary]:
	return [
		{"label": str(_headline()["text"]), "value": "" if compact else _detail()},
		{"label": "", "value": "" if compact else _afterText()},
	]
