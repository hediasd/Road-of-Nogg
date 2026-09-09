extends SceneTree

const MapDataScript = preload("res://src/presentation/worldmap/editor/WorldMapTileData.gd")
const HistoryScript = preload("res://src/presentation/worldmap/editor/WorldMapEditHistory.gd")

var failures: Array[String] = []


func _init() -> void:
	_checkUndoRedoAndBranching()
	_checkEvictionAndNetZero()
	_checkClearAllocatesFreshIdentity()
	if not failures.is_empty():
		for failure: String in failures:
			printerr("HXW_HISTORY_FAILURE: %s" % failure)
		quit(1)
		return
	print("WORLD MAP HISTORY REVISION OK")
	quit(0)


func _document():
	return MapDataScript.create("history_revision_probe", Vector2i(4, 2))


func _paint(history, data, cell: Vector2i, value: String) -> bool:
	history.beginStroke("ground")
	var changed: bool = history.paintCell(data, cell, value)
	return changed and history.endStroke()


func _require(condition: bool, message: String) -> void:
	if not condition:
		failures.append(message)


func _allUnique(values: Array[int]) -> bool:
	var seen: Dictionary = {}
	for value: int in values:
		if seen.has(value):
			return false
		seen[value] = true
	return true


func _checkUndoRedoAndBranching() -> void:
	var data = _document()
	var history = HistoryScript.new()
	var initial: int = history.currentRevision()
	_require(_paint(history, data, Vector2i(0, 0), "t000"), "first stroke did not commit")
	var saved: int = history.currentRevision()
	_require(saved != initial, "first committed state reused the initial revision")
	var undoResult: Dictionary = history.undo(data)
	_require(undoResult.get("layerID", "") == "ground" and undoResult.get("cells", []).has(Vector2i(0, 0)),
		"undo no longer returns its ground touched region")
	_require(history.currentRevision() == initial and data.getCell("ground", Vector2i(0, 0)) == "-",
		"undo did not restore the initial state and revision")
	var redoResult: Dictionary = history.redo(data)
	_require(redoResult.get("layerID", "") == "ground" and redoResult.get("cells", []).has(Vector2i(0, 0)),
		"redo no longer returns its ground touched region")
	_require(history.currentRevision() == saved and data.getCell("ground", Vector2i(0, 0)) == "t000",
		"redo did not restore the saved state and revision")
	history.undo(data)
	_require(_paint(history, data, Vector2i(0, 0), "t001"), "branch stroke did not commit")
	_require(history.currentRevision() != saved, "divergent state at old depth reused saved revision")
	_require(data.getCell("ground", Vector2i(0, 0)) == "t001" and not history.canRedo(),
		"branch stroke did not preserve content or clear redo")


func _checkEvictionAndNetZero() -> void:
	var data = _document()
	var history = HistoryScript.new()
	history.maxDepth = 2
	var revisions: Array[int] = [history.currentRevision()]
	for column in 3:
		_require(_paint(history, data, Vector2i(column, 0), "t%03d" % column),
			"capacity probe stroke %d did not commit" % column)
		revisions.append(history.currentRevision())
	_require(history.undoCount() == 2, "maxDepth eviction changed undo count")
	_require(_allUnique(revisions), "eviction reused a revision identity")
	var beforeNetZero: int = history.currentRevision()
	history.beginStroke("ground")
	history.paintCell(data, Vector2i(3, 1), "t009")
	history.paintCell(data, Vector2i(3, 1), "-")
	_require(not history.endStroke(), "net-zero stroke committed")
	_require(history.currentRevision() == beforeNetZero and data.getCell("ground", Vector2i(3, 1)) == "-",
		"net-zero stroke changed revision or document")


func _checkClearAllocatesFreshIdentity() -> void:
	var data = _document()
	var history = HistoryScript.new()
	var initial: int = history.currentRevision()
	_require(_paint(history, data, Vector2i(0, 0), "t000"), "clear setup stroke did not commit")
	var committed: int = history.currentRevision()
	history.clear()
	var cleared: int = history.currentRevision()
	_require(cleared != initial and cleared != committed, "clear reused a prior revision")
	_require(history.undoCount() == 0 and history.redoCount() == 0 and not history.isStrokeOpen(),
		"clear changed existing stack or stroke semantics")
	_require(_paint(history, data, Vector2i(1, 0), "t001"), "post-clear stroke did not commit")
	_require(history.currentRevision() != cleared and history.currentRevision() != committed,
		"post-clear committed state reused a revision")
