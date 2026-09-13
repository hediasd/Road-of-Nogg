## The round, and the order parties activate in this round. It replaces the square battle's
## individual speed rail.
##
## PARTY ORDER, NOT MEMBER ORDER. Under the approved activation model the simulator freezes a
## party order at the start of a round and opens one party at a time; inside a party the player
## picks who acts. So this lists parties, never members, and says of each whether it is acting,
## still to come, finished for the round, or out. It shows nothing before the first round opens,
## because there is no order yet to show.
##
## RENDERS A MODEL, READS NO STATE. `HexBattleHud.partyOrderModel` builds it from the simulator's
## `partyOrder` and `pendingPartyIDs`. Input-transparent: it is a readout.

class_name HexPartyOrderPanel
extends Control

const NoggWindowScript = preload("res://src/presentation/theme/NoggWindow.gd")
const NoggThemeScript = preload("res://src/presentation/theme/NoggTheme.gd")

const STATUS_ACTIVE := "ACTIVE"
const STATUS_NEXT := "NEXT"
const STATUS_DONE := "DONE"
const STATUS_OUT := "OUT"

var _window: NoggWindow
var _drawn = null
var _rowCount := 0


func _init() -> void:
	name = "PartyOrderPanel"
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	_window = NoggWindowScript.new()
	_window.size.x = NoggThemeScript.STATUS_WINDOW_WIDTH
	_window.set_input_transparent(true)
	_window.visible = false
	add_child(_window)


## `model` keys: round (int), parties (Array of Dictionaries with id, label, team, status). Status
## is one of the STATUS_* words, or "#n" for the n-th party still to come after NEXT. Parties are
## drawn in the supplied order, which is the round's frozen order.
func updateModel(model: Dictionary) -> void:
	if _drawn != null and _drawn == model:
		return
	if not _window.is_node_ready():
		return
	_drawn = model.duplicate(true)
	_window.clear_rows()
	var parties: Array = model.get("parties", [])
	if parties.is_empty():
		_rowCount = 0
		_window.set_row_capacity(1)
		_window.visible = false
		return
	_rowCount = parties.size() + 1
	_window.set_row_capacity(_rowCount)
	_window.visible = true
	_window.add_row("Round %d" % int(model.get("round", 0)), "", true)
	for entry in parties:
		var party: Dictionary = entry
		var status := str(party.get("status", ""))
		# Finished and out parties dim, the same language a spent command row uses.
		_window.add_row(
			str(party.get("label", "")),
			"T%d %s" % [int(party.get("team", 0)), status],
			status == STATUS_DONE or status == STATUS_OUT)


func windowSize() -> Vector2:
	if _rowCount == 0:
		return Vector2.ZERO
	return Vector2(_window.size.x, NoggThemeScript.window_height(_rowCount))


func window() -> NoggWindow:
	return _window
