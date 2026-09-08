## Where the player is pointing on a hex board, and how a keyboard or pad reaches all six
## neighbours of it.
##
## FOUR ARROWS DO NOT GIVE SIX DIRECTIONS, and pretending otherwise is the specific claim this
## item forbids. A square board's cursor works because its four neighbours are exactly the four
## the arrows name. A flat-top hex has six, none of them straight up or down on screen, so any
## mapping has to be chosen and then shown to work.
##
## WHAT IS CHOSEN HERE: the direction is resolved in SCREEN SPACE, against the camera as it
## currently sits. The six neighbour centres are projected to the viewport, each becomes a
## direction from the cursor's own projected centre, and the input vector picks the closest by
## angle. So "up-left" means the neighbour that is up and to the left ON SCREEN, whatever the
## camera has been rotated to -- which is what a player means by it, and which no fixed
## axial-to-arrow table can stay true to once the camera moves.
##
## That makes eight-way input (arrows plus diagonals, or a stick) reach all six naturally, and
## four-way input reach six through the same resolver, because with six candidates spread around
## a circle the four cardinal vectors still land on four distinct neighbours and the remaining two
## are reachable by their nearer diagonal. `neighbourFor` is a pure function of the projected
## geometry, which is what lets the probe check the mapping without a camera or an input device.
##
## TIES ARE BROKEN DETERMINISTICALLY, by the neighbour's own index in `HexGrid`'s established
## order, so a cursor sitting exactly between two candidates does not flicker between them from
## frame to frame.

class_name HexBattleCursor
extends RefCounted

const HexGridScript = preload("res://src/board/HexGrid.gd")

## Below this the input vector carries no direction at all -- a stick at rest, or two opposed keys.
const DEADZONE := 0.2

var _cell: Vector2i = Vector2i(-1, -1)
var _valid := false


func cell() -> Vector2i:
	return _cell


func hasCell() -> bool:
	return _valid


func clear() -> void:
	_cell = Vector2i(-1, -1)
	_valid = false


## Places the cursor, refusing a cell the map does not carry. Returns whether it moved.
func moveTo(cell: Vector2i, map: BattleMapDefinition) -> bool:
	if map != null and not map.containsCell(cell):
		return false
	if _valid and cell == _cell:
		return false
	_cell = cell
	_valid = true
	return true


## The neighbour a screen-space input vector points at, or the cursor's own cell when nothing
## does.
##
## `project` maps a cell to a viewport point; the caller supplies it so this file needs no camera
## and no scene. `input` is in screen axes, y growing downward, as Godot reports it.
func neighbourFor(input: Vector2, project: Callable, map: BattleMapDefinition) -> Vector2i:
	if not _valid or input.length() < DEADZONE or not project.is_valid():
		return _cell
	var origin: Vector2 = project.call(_cell)
	var wanted := input.normalized()
	var best := _cell
	var bestScore := -INF
	var index := -1
	for neighbour: Vector2i in HexGridScript.neighbours(_cell):
		index += 1
		# An off-board neighbour is not a direction the cursor can go. Skipped rather than
		# clamped: clamping would silently redirect the player to a cell they did not aim at.
		if map != null and not map.containsCell(neighbour):
			continue
		var projected: Vector2 = project.call(neighbour)
		var offset: Vector2 = projected - origin
		if offset.length() < 0.001:
			continue
		# Dot product against the normalised offset is the cosine of the angle between them, so
		# the largest is the closest in direction regardless of how far the neighbour projects.
		var score := wanted.dot(offset.normalized())
		if score > bestScore:
			bestScore = score
			best = neighbour
	# Facing away from every candidate is not a move. Without this a hard "down" on a cursor at
	# the bottom edge would still pick whichever neighbour was least wrong.
	if bestScore <= 0.0:
		return _cell
	return best


## Every neighbour the cursor could step to, in `HexGrid`'s order, restricted to the board. What
## the probe enumerates and what an overlay draws.
func reachableNeighbours(map: BattleMapDefinition) -> Array[Vector2i]:
	var result: Array[Vector2i] = []
	if not _valid:
		return result
	for neighbour: Vector2i in HexGridScript.neighbours(_cell):
		if map == null or map.containsCell(neighbour):
			result.append(neighbour)
	return result
