## The horizontal strip of portrait tiles across the top of the screen.
##
## Replaces the three-row `NoggWindow` turn order. That window stopped at the
## round boundary, so it structurally could not show the thing that most
## punishes a player who did not see it coming: because a round re-sorts every
## living unit by speed, a fast unit acting last in one round and first in the
## next takes **two turns back to back**. This rail runs deep enough to cross the
## boundary and marks it, so the double turn reads off the tiles themselves.
##
## **The queue number is round-relative.** A number that only restates
## left-to-right position is redundant - the row already encodes that. Numbering
## restarts after the divider, so the rail reads `... 3, 4 | 1, 2 ...` and a unit
## appearing on both sides carries a high number and then `1`.
##
## **The model and the overlays never share a quadrant.** The miniature is drawn
## offset down and to the right, so the head sits centre-right and the base
## bleeds off the bottom-right corner - the standard bust crop. That leaves the
## top-left genuinely empty for the number rather than stacking one on the other.

class_name TurnOrderRail
extends Control

const NoggThemeScript = preload("res://src/presentation/theme/NoggTheme.gd")

## A 3x5 cell per digit, drawn rather than typed. The shipping bitmap face floors
## to whole multiples of 12 device pixels, far too large for a tile corner;
## `StatusEffectIcons` already establishes drawing symbols instead of typing them.
const DIGIT_GLYPHS := {
	"0": ["111", "101", "101", "101", "111"],
	"1": ["010", "110", "010", "010", "111"],
	"2": ["111", "001", "111", "100", "111"],
	"3": ["111", "001", "111", "001", "111"],
	"4": ["101", "101", "111", "001", "001"],
	"5": ["111", "100", "111", "001", "111"],
	"6": ["111", "100", "111", "101", "111"],
	"7": ["111", "001", "010", "010", "010"],
	"8": ["111", "101", "111", "101", "111"],
	"9": ["111", "101", "111", "001", "111"],
}

## How far the miniature overflows its tile, and where its top-left sits inside
## it. Together these are the bust crop.
const PORTRAIT_SPAN := 1.30
const PORTRAIT_OFFSET := Vector2(0.14, 0.06)

signal entry_hovered(monster_id: int)

## `{id, portrait, team, ordinal, hp_ratio, active, projected, divider_before}`.
var _entries: Array = []
var _hovered: int = -1


func _init() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST


## Returns whether anything changed, so a caller polling every frame skips the
## redraw on the frames where the queue is identical - which is nearly all.
func set_entries(entries: Array) -> bool:
	if not _entries_differ(entries):
		return false
	_entries = entries
	_hovered = mini(_hovered, _entries.size() - 1)
	_resize()
	queue_redraw()
	return true


func _entries_differ(built: Array) -> bool:
	if built.size() != _entries.size():
		return true
	for index in range(built.size()):
		var a: Dictionary = built[index]
		var b: Dictionary = _entries[index]
		for field in ["id", "ordinal", "active", "projected", "divider_before"]:
			if a[field] != b[field]:
				return true
		if not is_equal_approx(a["hp_ratio"], b["hp_ratio"]):
			return true
	return false


## `local_point` is the pointer in this rail's space, or null. Emits the hovered
## unit's id so the board can highlight it, and -1 when the pointer leaves.
func set_hover_point(local_point) -> bool:
	var found := -1
	if local_point != null:
		var point: Vector2 = local_point
		for index in range(_entries.size()):
			if _tile_rect(index).has_point(point):
				found = index
				break
	if found == _hovered:
		return false
	_hovered = found
	queue_redraw()
	entry_hovered.emit(-1 if found == -1 else int(_entries[found]["id"]))
	return true


func hovered_monster_id() -> int:
	if _hovered == -1 or _hovered >= _entries.size():
		return -1
	return int(_entries[_hovered]["id"])


func _tile_stride() -> float:
	return NoggThemeScript.TURN_RAIL_TILE + NoggThemeScript.TURN_RAIL_GAP


## Tiles after the round divider are pushed right by the divider's own gap, so
## the boundary reads as a break in the rhythm and not only as a drawn line.
func _tile_rect(index: int) -> Rect2:
	var x := 0.0
	for step in range(index):
		x += _tile_stride()
		if bool(_entries[step + 1]["divider_before"]):
			x += NoggThemeScript.TURN_RAIL_DIVIDER_GAP
	var tile: float = NoggThemeScript.TURN_RAIL_TILE
	var top := 0.0 if bool(_entries[index]["active"]) else NoggThemeScript.TURN_RAIL_ACTIVE_LIFT
	return Rect2(Vector2(x, top), Vector2(tile, tile))


func _resize() -> void:
	if _entries.is_empty():
		size = Vector2.ZERO
		return
	var last := _tile_rect(_entries.size() - 1)
	size = Vector2(
		last.position.x + last.size.x,
		NoggThemeScript.TURN_RAIL_TILE + NoggThemeScript.TURN_RAIL_ACTIVE_LIFT
	)


func _draw() -> void:
	for index in range(_entries.size()):
		if bool(_entries[index]["divider_before"]):
			_draw_divider(index)
		_draw_tile(index)


## A dashed vertical rule in the accent colour. Everything past it is a forecast
## of the next round, not a fact about this one.
func _draw_divider(index: int) -> void:
	var rect := _tile_rect(index)
	var x := rect.position.x - NoggThemeScript.TURN_RAIL_DIVIDER_GAP * 0.5
	var width: float = NoggThemeScript.TURN_RAIL_DIVIDER_WIDTH
	var dash: float = width * 3.0
	var at := 0.0
	while at < size.y:
		draw_rect(
			Rect2(Vector2(x, at), Vector2(width, minf(dash, size.y - at))),
			NoggThemeScript.TEXT_ACCENT,
			true
		)
		at += dash * 2.0


func _draw_tile(index: int) -> void:
	var entry: Dictionary = _entries[index]
	var rect := _tile_rect(index)
	var frame: float = NoggThemeScript.TURN_RAIL_FRAME
	var alpha := NoggThemeScript.TURN_RAIL_PROJECTED_ALPHA if bool(entry["projected"]) else 1.0

	# Body first, then the portrait over it, then the frame on top so the team
	# colour is never overdrawn by a miniature bleeding past the edge.
	var body := rect.grow(-frame)
	draw_rect(rect.grow(1.0), _ink(alpha), true)
	draw_rect(body, _fill(alpha), true)

	var portrait: Texture2D = entry["portrait"]
	if portrait != null:
		_draw_portrait(portrait, body, alpha)

	var team: Color = entry["team"]
	_draw_frame(rect, frame, Color(team.r, team.g, team.b, alpha))
	_draw_health(body, float(entry["hp_ratio"]), alpha)
	_draw_ordinal(rect, int(entry["ordinal"]), alpha)

	if bool(entry["active"]):
		_draw_frame(rect.grow(frame), frame, _with_alpha(NoggThemeScript.TEXT_ACCENT, alpha))
	if index == _hovered:
		_draw_frame(rect.grow(frame), frame, _with_alpha(NoggThemeScript.FRAME_ACTIVE, alpha))


## Draws the miniature offset down and to the right, clipped to the tile body.
##
## The offset is the bust crop: the head lands centre-right of the frame and the
## base leaves through the bottom-right corner, which is what keeps the top-left
## genuinely empty for the queue number instead of stacking one over the other.
##
## **Clipping is done by mapping the visible rectangle back to a source region**,
## because `_draw` has no scissor and `draw_texture_rect` will happily paint
## outside its container. The first version relied on the tile bounds implicitly
## and every portrait spilled its plinth across the neighbouring tiles.
func _draw_portrait(portrait: Texture2D, body: Rect2, alpha: float) -> void:
	var span := body.size.x * PORTRAIT_SPAN
	var destination := Rect2(
		body.position + Vector2(body.size.x * PORTRAIT_OFFSET.x, body.size.y * PORTRAIT_OFFSET.y),
		Vector2(span, span)
	)
	var visible := destination.intersection(body)
	if visible.size.x <= 0.0 or visible.size.y <= 0.0:
		return
	var source_size := portrait.get_size()
	var region := Rect2(
		Vector2(
			(visible.position.x - destination.position.x) / destination.size.x * source_size.x,
			(visible.position.y - destination.position.y) / destination.size.y * source_size.y
		),
		Vector2(
			visible.size.x / destination.size.x * source_size.x,
			visible.size.y / destination.size.y * source_size.y
		)
	)
	draw_texture_rect_region(portrait, visible, region, Color(1.0, 1.0, 1.0, alpha))


func _draw_frame(rect: Rect2, width: float, colour: Color) -> void:
	draw_rect(Rect2(rect.position, Vector2(rect.size.x, width)), colour, true)
	draw_rect(Rect2(
		Vector2(rect.position.x, rect.position.y + rect.size.y - width),
		Vector2(rect.size.x, width)
	), colour, true)
	draw_rect(Rect2(rect.position, Vector2(width, rect.size.y)), colour, true)
	draw_rect(Rect2(
		Vector2(rect.position.x + rect.size.x - width, rect.position.y),
		Vector2(width, rect.size.y)
	), colour, true)


## A strip along the tile's bottom edge, inside the frame. It answers "is this
## one nearly dead" without the player having to find the unit on the board.
func _draw_health(body: Rect2, ratio: float, alpha: float) -> void:
	var height: float = NoggThemeScript.TURN_RAIL_HEALTH
	var strip := Rect2(
		Vector2(body.position.x, body.position.y + body.size.y - height),
		Vector2(body.size.x, height)
	)
	draw_rect(strip, _ink(alpha * 0.9), true)
	var clamped := clampf(ratio, 0.0, 1.0)
	if clamped <= 0.0:
		return
	# The same one-third threshold the docked status window applies to its HP
	# value, so the two surfaces cannot disagree about when a unit is in trouble.
	var critical := clamped * 3.0 < 1.0
	var colour := NoggThemeScript.TEXT_ACCENT if critical else NoggThemeScript.TEXT_HEAL
	draw_rect(
		Rect2(strip.position, Vector2(round(strip.size.x * clamped), strip.size.y)),
		_with_alpha(colour, alpha),
		true
	)


func _draw_ordinal(rect: Rect2, ordinal: int, alpha: float) -> void:
	var cell: float = maxf(1.0, float(NoggThemeScript.ui_scale))
	var text := str(ordinal)
	var origin := rect.position + Vector2(cell * 2.0, cell * 2.0)
	for index in range(text.length()):
		var glyph: Array = DIGIT_GLYPHS.get(text.substr(index, 1), [])
		for row in range(glyph.size()):
			var line: String = glyph[row]
			for column in range(line.length()):
				if line[column] != "1":
					continue
				var at := origin + Vector2(float(index * 4 + column) * cell, float(row) * cell)
				draw_rect(Rect2(at + Vector2(cell, cell), Vector2(cell, cell)), _ink(alpha))
				draw_rect(
					Rect2(at, Vector2(cell, cell)),
					_with_alpha(NoggThemeScript.TEXT_PRIMARY, alpha)
				)


func _with_alpha(colour: Color, alpha: float) -> Color:
	return Color(colour.r, colour.g, colour.b, colour.a * alpha)


func _ink(alpha: float) -> Color:
	return Color(0.0, 0.0, 0.0, 0.88 * alpha)


func _fill(alpha: float) -> Color:
	return _with_alpha(NoggThemeScript.WINDOW_FILL, alpha)
