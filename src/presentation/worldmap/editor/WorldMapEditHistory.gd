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
## undoing corrupts the history it undid from. `beginStroke` allocates a genuinely new
## `Dictionary` rather than clearing and reusing one -- Dictionaries ARE reference types, and
## reusing one across strokes would let a later stroke silently rewrite an earlier, already-
## pushed command. `probe_edit_history.gd` proves this by fuzzing a hundred randomised strokes
## and undoing every one, asserting the data lands back on its exact starting bytes.
##
## WMH-9: ONE STACK, THREE KINDS OF DELTA. A command's value was always a tile-id `String`; it is
## now a `float` for a height-vertex edit or a whole object RECORD (a `Dictionary`, `{}` meaning
## "did not exist") for an object edit -- so a command carries `Vector2i` tile cells, `Vector3i`
## height vertices, or `String` object ids as its `changes` keys, whichever kind it is. A stroke
## is homogeneous: the first paint call inside it claims a kind, and a call of a different kind
## is refused rather than silently mixed. The STACK stays singular on purpose -- the item text is
## explicit that separate stacks per kind would undo in an order the user never actually
## performed, which defeats what "undo" means to someone who just sculpted a hill and then
## painted a road over part of it.
##
## Every value type gets a genuine COPY before it is stored, the same discipline the class note
## above already held for tile edits -- `record.duplicate(true)` for an object's Dictionary, and
## a `float`/`Vector3i`/`String` needing no duplication because GDScript already copies those by
## value.
##
## FLOAT EQUALITY IS TOLERANT, NOT EXACT, because it has to be: `endStroke()`'s net-change filter
## used to be a plain `!=`, which is exactly right for a tile-id `String` and exactly wrong for a
## `float` height, where a no-op sculpt (raise then lower back to the same value through a
## different arithmetic path) can land one bit off its starting value and would otherwise push a
## command that undoes to something indistinguishable from what it already was. `_valuesEqual`
## uses `is_equal_approx` for floats, matching `WorldMapTileData.setCell`'s own "did anything
## really change" contract, and recurses through an object record's own fields for the same
## reason -- its `HEIGHT` field is a float too.

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
	if not _claimKind("tile"):
		return false
	var layerID: String = _open["layerID"]
	var before := data.getCell(layerID, cell)
	if not data.setCell(layerID, cell, tileID):
		return false
	_recordDelta(cell, before, tileID)
	return true


## Writes one height-lattice vertex through the open stroke, the vertex-edit counterpart to
## `paintCell`. Same contract: requires an open stroke, returns whether the vertex actually
## changed (`WorldMapHeightField.setHeightAt`'s own tolerant check), and a stroke that mixes this
## with a tile or an object edit is refused rather than silently allowed.
func paintHeight(data: WorldMapTileData, vertex: Vector3i, height: float) -> bool:
	if _open.is_empty():
		push_warning("WorldMapEditHistory: paintHeight with no open stroke; call beginStroke first")
		return false
	if not _claimKind("height"):
		return false
	var layerID: String = _open["layerID"]
	var before := WorldMapHeightField.heightAt(data, vertex, layerID)
	if not WorldMapHeightField.setHeightAt(data, vertex, height, layerID):
		return false
	_recordDelta(vertex, before, height)
	return true


## Places an object through the open stroke and records it as a creation (`before = {}`). Mirrors
## `WorldMapObjectLayer.place`'s own signature; the id it allocates is captured in the delta, so
## redoing a placement re-inserts that exact id rather than allocating a new one -- see
## `_applyObjectState`.
func placeObject(
	data: WorldMapTileData, kind: String, cell: Vector2i,
	facing := 0, footprint := 0, anchor := WorldMapObjectLayer.ANCHOR_TERRAIN, height := 0.0
) -> Dictionary:
	if _open.is_empty():
		push_warning("WorldMapEditHistory: placeObject with no open stroke; call beginStroke first")
		return {}
	if not _claimKind("object"):
		return {}
	var layerID: String = _open["layerID"]
	var record := WorldMapObjectLayer.place(data, kind, cell, layerID, facing, footprint, anchor, height)
	_recordDelta(str(record[WorldMapObjectLayer.K_ID]), {}, record.duplicate(true))
	return record


## Removes an object by id through the open stroke and records it as a deletion (`after = {}`).
## Returns `false` for an id that does not exist -- there is nothing to undo to, and pushing a
## no-op deletion would be exactly the risk `_valuesEqual` exists to catch for other kinds.
func removeObject(data: WorldMapTileData, id: String) -> bool:
	if _open.is_empty():
		push_warning("WorldMapEditHistory: removeObject with no open stroke; call beginStroke first")
		return false
	if not _claimKind("object"):
		return false
	var layerID: String = _open["layerID"]
	var before: Dictionary = WorldMapObjectLayer.find(data, id, layerID)
	if before.is_empty():
		return false
	var captured := before.duplicate(true)
	if not WorldMapObjectLayer.remove(data, id, layerID):
		return false
	_recordDelta(id, captured, {})
	return true


## Moves an object by id through the open stroke. Records the WHOLE record's before and after
## rather than a `CELL`-only delta, so every object edit shares one shape regardless of which
## field actually changed -- `_applyObjectState` needs no per-field cases.
func moveObject(data: WorldMapTileData, id: String, cell: Vector2i) -> bool:
	if _open.is_empty():
		push_warning("WorldMapEditHistory: moveObject with no open stroke; call beginStroke first")
		return false
	if not _claimKind("object"):
		return false
	var layerID: String = _open["layerID"]
	var before: Dictionary = WorldMapObjectLayer.find(data, id, layerID)
	if before.is_empty():
		return false
	var captured := before.duplicate(true)
	if not WorldMapObjectLayer.move(data, id, cell, layerID):
		return false
	_recordDelta(id, captured, WorldMapObjectLayer.find(data, id, layerID).duplicate(true))
	return true


## Rotates an object by id through the open stroke. Same shape as `moveObject`.
func setObjectFacing(data: WorldMapTileData, id: String, facing: int) -> bool:
	if _open.is_empty():
		push_warning(
			"WorldMapEditHistory: setObjectFacing with no open stroke; call beginStroke first"
		)
		return false
	if not _claimKind("object"):
		return false
	var layerID: String = _open["layerID"]
	var before: Dictionary = WorldMapObjectLayer.find(data, id, layerID)
	if before.is_empty():
		return false
	var captured := before.duplicate(true)
	if not WorldMapObjectLayer.setFacing(data, id, facing, layerID):
		return false
	_recordDelta(id, captured, WorldMapObjectLayer.find(data, id, layerID).duplicate(true))
	return true


## Claims `kind` for the currently open stroke on its first paint call, or confirms it matches on
## every later one. A stroke mixing tile, height and object edits has no single meaning for
## `undo()` to dispatch on, so the second kind is refused rather than folded in.
func _claimKind(kind: String) -> bool:
	var current := str(_open.get("kind", ""))
	if current.is_empty():
		_open["kind"] = kind
		return true
	if current != kind:
		push_warning(
			"WorldMapEditHistory: stroke already carries '%s' edits; refusing a '%s' one"
			% [current, kind]
		)
		return false
	return true


## Coalescing, generalised over whatever key a kind uses (`Vector2i`, `Vector3i` or `String`).
## Second-or-later write to the same key in one stroke keeps the ORIGINAL before and only
## advances after -- see the class note on why that is what makes undo land on the pre-stroke
## value rather than an intermediate one.
func _recordDelta(key, before, after) -> void:
	var changes: Dictionary = _open["changes"]
	if changes.has(key):
		changes[key]["after"] = after
	else:
		changes[key] = {"before": before, "after": after}


## Value equality tolerant of float drift -- see the class note on why an exact `!=` is wrong for
## a height. Recurses through arrays and dictionaries so an object record's own equality means
## the same thing throughout, including its `HEIGHT` field.
static func _valuesEqual(a, b) -> bool:
	if (a is float or a is int) and (b is float or b is int):
		return is_equal_approx(float(a), float(b))
	if a is Dictionary and b is Dictionary:
		if a.size() != b.size():
			return false
		for key in a:
			if not b.has(key) or not _valuesEqual(a[key], b[key]):
				return false
		return true
	if a is Array and b is Array:
		if a.size() != b.size():
			return false
		for index in a.size():
			if not _valuesEqual(a[index], b[index]):
				return false
		return true
	return a == b


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
		if not _valuesEqual(delta["before"], delta["after"]):
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
## stale pixels with nothing to report it, the same failure a skipped shadow-mask rebake is. The
## key still comes back under `"cells"` for every kind, tile, height or object alike -- the field
## always means "what changed", and only its shape (`Vector2i`, `Vector3i` or `String`) differs.
## Returns an empty dictionary when there is nothing to undo.
func undo(data: WorldMapTileData) -> Dictionary:
	if _undoStack.is_empty():
		return {}
	var command: Dictionary = _undoStack.pop_back()
	_apply(data, command, "before")
	_redoStack.append(command)
	return {"layerID": command["layerID"], "cells": (command["changes"] as Dictionary).keys()}


## Re-applies the most recently undone command's `after` values. Symmetric with `undo` --
## same return shape, same "nothing to do" empty dictionary.
func redo(data: WorldMapTileData) -> Dictionary:
	if _redoStack.is_empty():
		return {}
	var command: Dictionary = _redoStack.pop_back()
	_apply(data, command, "after")
	_undoStack.append(command)
	return {"layerID": command["layerID"], "cells": (command["changes"] as Dictionary).keys()}


## Writes every delta's `side` ("before" for undo, "after" for redo) back to `data`, dispatching
## on the command's kind -- the one place that has to know a tile write, a height write and an
## object write are three different calls, so `undo`/`redo` themselves do not.
func _apply(data: WorldMapTileData, command: Dictionary, side: String) -> void:
	var layerID: String = command["layerID"]
	var changes: Dictionary = command["changes"]
	var kind := str(command.get("kind", "tile"))
	match kind:
		"height":
			for vertex in changes:
				WorldMapHeightField.setHeightAt(data, vertex, changes[vertex][side], layerID)
		"object":
			for id in changes:
				_applyObjectState(data, layerID, str(id), changes[id][side])
		_:
			for cell in changes:
				data.setCell(layerID, cell, changes[cell][side])


## Restores one object id to `state`: `{}` means the object must not exist (undoing a placement,
## or redoing a deletion), and a non-empty record is written back either by re-inserting it --
## which is what undoing a DELETION or redoing a PLACEMENT needs, and why the id is preserved
## from the delta rather than reallocated through `WorldMapObjectLayer.place()` -- or, if the
## object is already present (undoing/redoing a move or a facing change), by overwriting its
## fields in place.
func _applyObjectState(data: WorldMapTileData, layerID: String, id: String, state: Dictionary) -> void:
	if state.is_empty():
		WorldMapObjectLayer.remove(data, id, layerID)
		return
	var existing: Dictionary = WorldMapObjectLayer.find(data, id, layerID)
	if existing.is_empty():
		var block := WorldMapObjectLayer.ensureLayer(data, layerID)
		(block["ITEMS"] as Array).append(state.duplicate(true))
		return
	for key in state:
		existing[key] = state[key]


## Drops all history. Not used by ordinary undo/redo -- for switching to a different open
## document, where the old stack no longer refers to anything on screen.
func clear() -> void:
	_undoStack.clear()
	_redoStack.clear()
	_open = {}
