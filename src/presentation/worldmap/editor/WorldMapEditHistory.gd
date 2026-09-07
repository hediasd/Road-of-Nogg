## Undo and redo for a `WorldMapTileData`, at STROKE granularity: a drag across forty cells is
## one undo entry, not forty.
##
## COMMANDS STORE THE DELTA, NOT A SNAPSHOT. A full-region snapshot per stroke is unaffordable
## at real region sizes -- a 155-tile region is tens of thousands of cells, and most of them are
## untouched by any one stroke. A command instead carries `{layerID, changes}`, where `changes`
## maps each touched cell to its `before` and `after` value, so its cost is proportional to what
## the stroke actually painted.
##
## EVERY MUTATION GOES THROUGH A COMMAND. There is no path in this file that writes to a
## `WorldMapTileData` outside of `paintCell`, and that is deliberate: a brush that mutated data
## directly and only sometimes remembered to call this file would produce an undo stack that
## lies about what happened.
##
## COALESCING IS EXPLICIT, NOT INFERRED. `beginStroke` opens a command and `endStroke` closes it;
## nothing here guesses where a stroke starts or ends from timing or mouse state. A drag tool
## opens on press and closes on release; a tool with no release of its own -- a flood fill
## triggered by a single click -- opens and closes within the same call. Both are the same API
## used two different ways, which is what keeps `WorldMapBrushes` (WME-9) simple: every brush
## looks like `beginStroke()`, some `paintCell()` calls, `endStroke()`.
##
## MULTIPLE WRITES TO ONE CELL WITHIN A STROKE COLLAPSE TO ONE DELTA. A drag that crosses the
## same cell twice, or a brush that paints then re-paints a cell before releasing, must undo to
## the value the cell held BEFORE the stroke -- not to an intermediate value from partway through
## it. So `changes[cell].before` is pinned on the cell's first write in the open stroke, and
## `.after` is updated on every write; a cell whose net effect is zero (painted back to what it
## started as) is dropped when the stroke closes, and a stroke that nets to nothing anywhere is
## not pushed at all -- matching `WorldMapTileData.setCell`'s own "returns whether anything
## changed" contract one level up.
##
## THE RISK THIS FILE HAS TO NOT HAVE: a command capturing a reference rather than a copy, so
## undoing corrupts the history it undid from. Every value stored here is a `String` or a
## `Vector2i`, both value types in GDScript, and `beginStroke` allocates a genuinely new
## `Dictionary` rather than clearing and reusing one -- Dictionaries ARE reference types, and
## reusing one across strokes would let a later stroke silently rewrite an earlier, already-
## pushed command. `probe_edit_history.gd` proves this by fuzzing a hundred randomised strokes
## and undoing every one, asserting the data lands back on its exact starting bytes.

class_name WorldMapEditHistory
extends RefCounted

## Commands, not cells. A stroke touching a thousand cells still counts as one entry, and one
## entry is what a user experiences as "one undo".
const DEFAULT_MAX_DEPTH := 100

var maxDepth := DEFAULT_MAX_DEPTH

var _undoStack: Array[Dictionary] = []
var _redoStack: Array[Dictionary] = []
## The command currently being built, or null when no stroke is open. `paintCell` refuses to
## run without one -- see the class note on why nothing here mutates data outside a command.
var _open: Dictionary = {}


## Opens a new command. Warns and discards whatever was open rather than losing it silently --
## a caller opening a second stroke without closing the first is a bug in that caller, not a
## normal path this file should paper over.
func beginStroke(layerID: String) -> void:
	if not _open.is_empty():
		push_warning(
			"WorldMapEditHistory: beginStroke while '%s' was still open; discarding it"
			% str(_open.get("layerID", "?"))
		)
	_open = {"layerID": layerID, "changes": {}}


## Whether a stroke is currently open.
func isStrokeOpen() -> bool:
	return not _open.is_empty()


## Writes one cell through the open stroke and records the delta. Returns whether the cell
## actually changed, mirroring `WorldMapTileData.setCell`'s own contract. Requires an open
## stroke -- see the class note on why every mutation goes through a command.
func paintCell(data: WorldMapTileData, cell: Vector2i, tileID: String) -> bool:
	if _open.is_empty():
		push_warning("WorldMapEditHistory: paintCell with no open stroke; call beginStroke first")
		return false
	var layerID: String = _open["layerID"]
	var before := data.getCell(layerID, cell)
	if not data.setCell(layerID, cell, tileID):
		return false

	var changes: Dictionary = _open["changes"]
	if changes.has(cell):
		# Second-or-later write to this cell in the same stroke: keep the ORIGINAL before, only
		# advance after. See the class note -- this is what makes undo land on the pre-stroke
		# value rather than an intermediate one.
		changes[cell]["after"] = tileID
	else:
		changes[cell] = {"before": before, "after": tileID}
	return true


## Closes the open stroke. Cells whose net effect is zero are dropped, and a stroke with nothing
## left after that is not pushed at all -- returns `false` in that case, `true` if a command was
## recorded. Either way clears the redo stack: a new edit invalidates whatever could have been
## redone, which is the ordinary meaning of "redo" in every editor this one is patterned on.
func endStroke() -> bool:
	if _open.is_empty():
		push_warning("WorldMapEditHistory: endStroke with no open stroke")
		return false
	var command := _open
	_open = {}

	var changes: Dictionary = command["changes"]
	var netChanges: Dictionary = {}
	for cell in changes:
		var delta: Dictionary = changes[cell]
		if delta["before"] != delta["after"]:
			netChanges[cell] = delta
	if netChanges.is_empty():
		return false
	command["changes"] = netChanges

	_undoStack.append(command)
	_redoStack.clear()
	while _undoStack.size() > maxDepth:
		_undoStack.pop_front()
	return true


func canUndo() -> bool:
	return not _undoStack.is_empty()


func canRedo() -> bool:
	return not _redoStack.is_empty()


func undoCount() -> int:
	return _undoStack.size()


func redoCount() -> int:
	return _redoStack.size()


## Applies the most recent command's `before` values and moves it to the redo stack. Returns
## `{layerID, cells}` naming exactly what changed, so a caller can invalidate a renderer's cache
## for those cells and nothing more -- the same set a forward edit would have marked dirty,
## which is the whole point: an undo that invalidates less than the forward edit did leaves
## stale pixels with nothing to report it, the same failure a skipped shadow-mask rebake is.
## Returns an empty dictionary when there is nothing to undo.
func undo(data: WorldMapTileData) -> Dictionary:
	if _undoStack.is_empty():
		return {}
	var command: Dictionary = _undoStack.pop_back()
	var layerID: String = command["layerID"]
	var changes: Dictionary = command["changes"]
	for cell in changes:
		data.setCell(layerID, cell, changes[cell]["before"])
	_redoStack.append(command)
	return {"layerID": layerID, "cells": changes.keys()}


## Re-applies the most recently undone command's `after` values. Symmetric with `undo` --
## same return shape, same "nothing to do" empty dictionary.
func redo(data: WorldMapTileData) -> Dictionary:
	if _redoStack.is_empty():
		return {}
	var command: Dictionary = _redoStack.pop_back()
	var layerID: String = command["layerID"]
	var changes: Dictionary = command["changes"]
	for cell in changes:
		data.setCell(layerID, cell, changes[cell]["after"])
	_undoStack.append(command)
	return {"layerID": layerID, "cells": changes.keys()}


## Drops all history. Not used by ordinary undo/redo -- for switching to a different open
## document, where the old stack no longer refers to anything on screen.
func clear() -> void:
	_undoStack.clear()
	_redoStack.clear()
	_open = {}
