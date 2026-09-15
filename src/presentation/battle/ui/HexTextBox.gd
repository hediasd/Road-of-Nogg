## A framed box of sentence-level text: a command's hint or refusal, an effect or spell explained,
## the aim prompt. The one surface in the hex HUD that holds sentences, so routine telemetry --
## hover, damage, a status tick -- has nowhere to become a dialog.
##
## Same `NoggWindow` frame as every other box. Text is word-wrapped into the window's own rows
## rather than laid out by an autowrapping `Label`, so line pitch is exactly `ROW_HEIGHT` and the
## box height stays a function of its row count (UI_DESIGN §4, trait 6).

class_name HexTextBox
extends Control

const NoggWindowScript = preload("res://src/presentation/theme/NoggWindow.gd")
const NoggThemeScript = preload("res://src/presentation/theme/NoggTheme.gd")

var _window: NoggWindow
var _lines: Array[String] = []
var _title := ""
var _titleValue := ""
var _maxRows := 3
var _shown := false
var _body := ""


func _init() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	_window = NoggWindowScript.new()
	# A readout: it must never swallow a click meant for the board or a plate under it.
	_window.set_input_transparent(true)
	add_child(_window)
	visible = false


func _ready() -> void:
	if _shown:
		_rebuild(_body)


func setWidth(width: float) -> void:
	_window.size.x = width
	size.x = width


func boxSize() -> Vector2:
	return _window.size


## Shows `body`, wrapped to at most `maxRows` rows, under an optional accent title row. An empty
## body and title hides the box instead of showing an empty frame.
func showText(body: String, title: String = "", titleValue: String = "", maxRows: int = 3) -> void:
	if body.strip_edges().is_empty() and title.is_empty():
		hideBox()
		return
	_title = title
	_titleValue = titleValue
	_maxRows = maxi(1, maxRows)
	_body = body
	if is_node_ready():
		_rebuild(body)
	var wasShown := _shown
	_shown = true
	visible = true
	if not wasShown and is_inside_tree():
		_window.open()


func hideBox() -> void:
	_shown = false
	visible = false


func isShown() -> bool:
	return _shown


func _rebuild(body: String) -> void:
	var available: float = _window.size.x - float(NoggThemeScript.CONTENT_INSET) * 2.0
	_lines = wrapText(body, available, _font(), NoggThemeScript.FONT_SIZE_BODY)
	var bodyRows := mini(_lines.size(), _maxRows - (1 if not _title.is_empty() else 0))
	bodyRows = maxi(bodyRows, 0)
	var rows := bodyRows + (1 if not _title.is_empty() else 0)
	_window.set_row_capacity(maxi(rows, 1))
	size.y = _window.size.y
	_window.clear_rows()
	if not _title.is_empty():
		var titleRow := _window.add_row(_title, _titleValue)
		var label := titleRow.get_child(0).get_child(0) as Label
		label.add_theme_color_override("font_color", NoggThemeScript.TEXT_ACCENT)
	for index in range(bodyRows):
		var line := _lines[index]
		if index == bodyRows - 1 and _lines.size() > bodyRows:
			line = line.trim_suffix(".") + "..."
		_window.add_row(line)


func _font() -> Font:
	var font := get_theme_default_font()
	return font if font != null else ThemeDB.fallback_font


## Greedy word wrap against measured glyph widths. Public so the probe can check it without a
## window.
static func wrapText(text: String, width: float, font: Font, fontSize: int) -> Array[String]:
	var lines: Array[String] = []
	var current := ""
	for word in text.split(" ", false):
		var candidate := word if current.is_empty() else current + " " + word
		if current.is_empty() or font.get_string_size(
			candidate, HORIZONTAL_ALIGNMENT_LEFT, -1, fontSize
		).x <= width:
			current = candidate
		else:
			lines.append(current)
			current = word
	if not current.is_empty():
		lines.append(current)
	return lines
