## The docked actor and target readouts, and the forecast for the command being aimed.
##
## THE SQUARE BATTLE'S TWO STATUS WINDOWS, KEPT. Actor bottom-left, target bottom-right, fixed
## docks computed from the viewport alone, so nothing reflows when one opens or closes. Each is a
## `NoggWindow` that opens when it has a unit to show and closes when it does not, driven off the
## last requested state rather than `visible` (a closing window is still visible for its tween,
## and re-closing it every refresh would restart the close forever). See
## `BattlePresentationController._renderStatusWindow` in the frozen reference.
##
## ADDED FOR HEX, AND WHY. Two rows the square window did not have: the unit's side and party
## (hex battles are party battles, and a commander's death withdraws the whole party), and its
## active effects with durations. Level moves into the heading. That is six rows, which still
## fits under the party and command windows at 1280x720 (see HexBattleHud._layout).
##
## RENDERS A MODEL, READS NO STATE. `HexBattleHud` builds every model from displayed state and
## the simulator; this node draws what it is given. Rows rebuild only when a model changes, so a
## per-frame refresh costs a dictionary compare.
##
## INPUT-TRANSPARENT. The windows overlap the board at every resolution; a readout that ate
## clicks would make the tiles under it unpickable.

class_name HexInspectionPanel
extends Control

const NoggWindowScript = preload("res://src/presentation/theme/NoggWindow.gd")
const NoggThemeScript = preload("res://src/presentation/theme/NoggTheme.gd")
const ResonanceBarScript = preload("res://src/presentation/theme/ResonanceBar.gd")

const STATUS_ROWS := 6
const FORECAST_ROWS := 3

var actorWindow: NoggWindow
var targetWindow: NoggWindow
var forecastWindow: NoggWindow

## window name -> the model or line list it last drew. Only set once a draw actually happened, so
## a request that arrives before the window is ready is retried by the next refresh.
var _drawn: Dictionary = {}
## window name -> the open state last requested. See the file note on why not `visible`.
var _requestedOpen: Dictionary = {}


func _init() -> void:
	name = "InspectionPanel"
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	actorWindow = _buildWindow("ActorStatus", NoggThemeScript.STATUS_WINDOW_WIDTH, STATUS_ROWS)
	targetWindow = _buildWindow("TargetStatus", NoggThemeScript.STATUS_WINDOW_WIDTH, STATUS_ROWS)
	forecastWindow = _buildWindow("Forecast", NoggThemeScript.FORECAST_WIDTH, FORECAST_ROWS)


func _buildWindow(windowName: String, width: float, rows: int) -> NoggWindow:
	var window: NoggWindow = NoggWindowScript.new()
	window.name = windowName
	window.size.x = width
	window.set_row_capacity(rows)
	window.set_input_transparent(true)
	# Starts hidden rather than open-then-closed: a Control defaults to visible.
	window.visible = false
	add_child(window)
	return window


## Docks all three windows for a viewport size. Actor and target sit in the bottom corners; the
## forecast stacks above the target, right-aligned with it, because the target is what it is about.
func layoutFor(viewportSize: Vector2) -> void:
	var margin: float = NoggThemeScript.SCREEN_MARGIN
	var statusHeight: float = NoggThemeScript.window_height(STATUS_ROWS)
	actorWindow.position = Vector2(margin, viewportSize.y - statusHeight - margin)
	targetWindow.position = Vector2(
		viewportSize.x - targetWindow.size.x - margin, viewportSize.y - statusHeight - margin)
	var forecastHeight: float = NoggThemeScript.window_height(FORECAST_ROWS)
	forecastWindow.position = Vector2(
		viewportSize.x - forecastWindow.size.x - margin,
		targetWindow.position.y - forecastHeight - NoggThemeScript.FORECAST_GAP)


func showActor(model: Dictionary) -> void:
	_renderStatus(actorWindow, model)


func showTarget(model: Dictionary) -> void:
	_renderStatus(targetWindow, model)


## Up to FORECAST_ROWS lines of text. An empty list closes the window.
func showForecast(lines: Array) -> void:
	var key := forecastWindow.name
	if _drawn.has(key) and _drawn[key] == lines:
		return
	if not forecastWindow.is_node_ready():
		return
	_drawn[key] = lines.duplicate()
	forecastWindow.clear_rows()
	_setOpen(forecastWindow, not lines.is_empty())
	for index in mini(lines.size(), FORECAST_ROWS):
		forecastWindow.add_row(str(lines[index]))


## What each window last drew, for probes. Empty when closed.
func drawnModel(window: NoggWindow):
	return _drawn.get(window.name, {})


func _renderStatus(window: NoggWindow, model: Dictionary) -> void:
	var key := window.name
	if _drawn.has(key) and _drawn[key] == model:
		return
	if not window.is_node_ready():
		return
	_drawn[key] = model.duplicate(true)
	window.clear_rows()
	_setOpen(window, not model.is_empty())
	if model.is_empty():
		return

	window.add_row(str(model.get("name", "")), "Lv %d" % int(model.get("level", 0)))
	window.add_row(str(model.get("side", "")), str(model.get("state", "")))

	var elements: Array = model.get("elements", [])
	var hpCells: Array[Dictionary] = [{
		"label": "HP",
		"value": "%s/%s" % [_stat(int(model.get("hp", 0))), _stat(int(model.get("max_hp", 0)))],
	}]
	_appendResonance(hpCells, elements, 0)
	var hpHandles := window.add_stat_row(hpCells)
	# Gold only below one third, as the square window did: healthy HP should not pull the eye.
	if not hpHandles.is_empty():
		var low := int(model.get("hp", 0)) * 3 < int(model.get("max_hp", 0))
		(hpHandles[0]["value"] as Label).add_theme_color_override(
			"font_color", NoggThemeScript.TEXT_ACCENT if low else NoggThemeScript.TEXT_PRIMARY)

	var attackCells: Array[Dictionary] = [
		{"label": "ATK", "value": _stat(int(model.get("atk", 0)))},
		{"label": "DEF", "value": _stat(int(model.get("def", 0)))},
	]
	_appendResonance(attackCells, elements, 1)
	window.add_stat_row(attackCells)

	var movementCells: Array[Dictionary] = [
		{"label": "SPD", "value": _stat(int(model.get("speed", 0)))},
		{"label": "MOV", "value": _stat(int(model.get("move", 0)))},
	]
	_appendResonance(movementCells, elements, 2)
	window.add_stat_row(movementCells)

	var effects: Array = model.get("effects", [])
	if effects.is_empty():
		window.add_row("No effects", "", true)
	else:
		var parts: Array[String] = []
		for entry in effects:
			var effect: Dictionary = entry
			var turns := int(effect.get("turns", -1))
			parts.append(
				str(effect.get("label", "")) + (" %d" % turns if turns >= 0 else ""))
		window.add_row("  ".join(parts))


## Column 3 of a stat row: the element's code and its drawn three-cell Resonance bar. The same
## primitive and column the square window used, unchanged.
func _appendResonance(cells: Array[Dictionary], elements: Array, index: int) -> void:
	if index >= elements.size():
		return
	var element: Dictionary = elements[index]
	cells.append({
		"column": 2,
		"label": str(element.get("code", "")),
		"control": ResonanceBarScript.new(
			str(element.get("element", "")), int(element.get("charge", 0))),
	})


## Zero-padded to three digits so a value holds its place in the fixed cell as it changes.
static func _stat(value: int) -> String:
	return "%03d" % value


func _setOpen(window: NoggWindow, wanted: bool) -> void:
	if bool(_requestedOpen.get(window.name, false)) == wanted:
		return
	_requestedOpen[window.name] = wanted
	if wanted:
		window.open()
	else:
		window.close()


func isRequestedOpen(window: NoggWindow) -> bool:
	return bool(_requestedOpen.get(window.name, false))
