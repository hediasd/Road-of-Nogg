## The status icon rows over the hex battle's units: one `StatusBadgeRow` per affected unit, placed
## at the unit's projected head each frame.
##
## REUSES `StatusBadgeRow` UNCHANGED. It already is the compact above-unit presentation -- colour
## chips at rest, the icon and turns only under the pointer, an overflow counter past five -- and
## was built as a projected Control precisely so it stays sharp at native resolution. This file
## only supplies what its old host did: an anchor, the unit's effects, the pointer, and a frame
## tick. Its layout, hover growth and drawing are not touched.
##
## A unit with no effects has no row at all, so an unaffected board carries no chrome over it.

class_name HexStatusBadgeOverlay
extends Control

const StatusBadgeRowScript = preload("res://src/presentation/StatusBadgeRow.gd")
const NoggThemeScript = preload("res://src/presentation/theme/NoggTheme.gd")

var _rows: Dictionary = {}  ## monsterID -> StatusBadgeRow


func _init() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	set_anchors_preset(Control.PRESET_FULL_RECT)


## `entries`: Array of {id: int, anchor: Vector2 (screen point above the unit's head, or null when
## off screen), effects: Array of raw effect dictionaries}.
func sync(entries: Array, pointer: Vector2, delta: float) -> void:
	var seen: Dictionary = {}
	for entry in entries:
		var monsterID := int(entry.get("id", -1))
		var effects: Array = entry.get("effects", [])
		var anchor = entry.get("anchor")
		if effects.is_empty() or anchor == null:
			continue
		seen[monsterID] = true
		var row: StatusBadgeRow = _rows.get(monsterID)
		if row == null:
			row = StatusBadgeRowScript.new()
			row.name = "Badges_%d" % monsterID
			add_child(row)
			_rows[monsterID] = row
		row.set_effects(effects)
		var point: Vector2 = anchor
		row.position = Vector2(
			floorf(point.x - row.size.x * 0.5),
			floorf(point.y - row.size.y - NoggThemeScript.STATUS_BADGE_LIFT)
		)
		row.visible = true
		row.set_hover_point(pointer - row.position)
		row.advance(delta)
	for monsterID in _rows.keys():
		if seen.has(monsterID):
			continue
		var stale: StatusBadgeRow = _rows[monsterID]
		_rows.erase(monsterID)
		remove_child(stale)
		stale.queue_free()


func rowCount() -> int:
	return _rows.size()


func clearRows() -> void:
	for monsterID in _rows.keys():
		var row: StatusBadgeRow = _rows[monsterID]
		remove_child(row)
		row.queue_free()
	_rows.clear()
