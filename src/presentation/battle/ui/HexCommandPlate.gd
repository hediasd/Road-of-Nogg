## One plate on the command rail: a one-row `NoggWindow` carrying an icon and a label.
##
## A plate is its own framed box rather than a row inside a shared one -- that is the whole of the
## Brigandine reference's hierarchy, individual plates on a stable edge rather than one enclosing
## command box. The frame is still the shared window frame; the reference's slant is carried by the
## rail leaning, not by skewing pixel art that was authored square.
##
## Owns look only. Whether a plate is enabled, what it means, and what focusing it says are the
## rail's, which is handed them by the model.

class_name HexCommandPlate
extends Control

const NoggWindowScript = preload("res://src/presentation/theme/NoggWindow.gd")
const NoggThemeScript = preload("res://src/presentation/theme/NoggTheme.gd")
const ActionIconsScript = preload("res://src/presentation/ActionIcons.gd")

## Alpha a disabled plate's icon is drawn at. The label dims through the row's own `TEXT_DIM`.
const DISABLED_ICON_ALPHA := 0.4

signal row_built(row: Control)

var commandID := ""
var enabled := false

var _window: NoggWindow
var _icon: TextureRect
var _row: Control
var _label := ""
var _iconID := ""
var _focused := false


func _init() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	_window = NoggWindowScript.new()
	_window.row_built.connect(_onRowBuilt)
	add_child(_window)
	_icon = TextureRect.new()
	_icon.name = "Icon"
	_icon.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_icon.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	_icon.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	_icon.stretch_mode = TextureRect.STRETCH_SCALE
	add_child(_icon)


func _ready() -> void:
	_layout()
	_render()


## `entry` is one command from the rail model: id, label, icon, enabled.
func configure(entry: Dictionary, inputEnabled: bool) -> void:
	commandID = str(entry.get("id", ""))
	_label = str(entry.get("label", ""))
	_iconID = str(entry.get("icon", commandID))
	enabled = inputEnabled and bool(entry.get("enabled", false))
	if is_node_ready():
		_render()


func setFocused(focused: bool) -> void:
	_focused = focused
	_applyFocusTint()


func row() -> Control:
	return _row


func labelText() -> String:
	return _label


func plateSize() -> Vector2:
	return _window.size


func _layout() -> void:
	_window.size.x = NoggThemeScript.HEX_PLATE_WIDTH
	_window.set_row_capacity(1)
	_window.set_content_indent(NoggThemeScript.HEX_PLATE_ICON + NoggThemeScript.HEX_PLATE_ICON_GAP)
	size = _window.size
	var iconSize := NoggThemeScript.HEX_PLATE_ICON
	_icon.size = Vector2(iconSize, iconSize)
	_icon.position = Vector2(
		float(NoggThemeScript.CONTENT_INSET),
		floorf((_window.size.y - iconSize) / 2.0)
	)


func _render() -> void:
	_icon.texture = ActionIconsScript.texture_for(_iconID)
	_icon.modulate.a = 1.0 if enabled else DISABLED_ICON_ALPHA
	_window.set_full_rows([{"label": _label, "value": "", "disabled": not enabled}])


func _onRowBuilt(built: Control, _index: int) -> void:
	_row = built
	_applyFocusTint()
	row_built.emit(built)


## A focused, enabled plate's label turns accent gold -- the cursor says where focus is, the tint
## says the focused thing will answer a confirm. A focused disabled plate stays dim: it is focusable
## only so it can explain itself.
func _applyFocusTint() -> void:
	if _row == null or not is_instance_valid(_row):
		return
	var label := _row.get_child(0).get_child(0) as Label
	if not enabled:
		label.add_theme_color_override("font_color", NoggThemeScript.TEXT_DIM)
	elif _focused:
		label.add_theme_color_override("font_color", NoggThemeScript.TEXT_ACCENT)
	else:
		label.remove_theme_color_override("font_color")
