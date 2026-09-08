extends SceneTree

const HexGridScript = preload("res://src/board/HexGrid.gd")
const WorldMapHexGridScript = preload(
	"res://src/presentation/worldmap/editor/WorldMapHexGrid.gd")

var failures: Array[String] = []


func _init() -> void:
	_checkConversions()
	_checkNeighbours()
	_checkDistanceAndTranslation()
	_checkDiscs()
	_checkWrapperParity()
	if not failures.is_empty():
		for failure: String in failures:
			printerr("HXB_GRID_FAILURE: %s" % failure)
		quit(1)
		return
	print("HXB_GRID_OK")
	quit(0)


func _require(condition: bool, message: String) -> void:
	if not condition:
		failures.append(message)


func _checkConversions() -> void:
	for y in range(-8, 9):
		for x in range(-8, 9):
			var cell := Vector2i(x, y)
			var axial: Vector2i = HexGridScript.offsetToAxial(cell)
			_require(HexGridScript.axialToOffset(axial) == cell,
				"offset/axial round trip failed at %s" % cell)


func _checkNeighbours() -> void:
	var expectedEven: Array[Vector2i] = [
		Vector2i(1, 1), Vector2i(1, 0), Vector2i(0, 0),
		Vector2i(-1, 0), Vector2i(-1, 1), Vector2i(0, 2),
	]
	var expectedOdd: Array[Vector2i] = [
		Vector2i(2, 1), Vector2i(2, 0), Vector2i(1, -1),
		Vector2i(0, 0), Vector2i(0, 1), Vector2i(1, 1),
	]
	_require(HexGridScript.neighbours(Vector2i(0, 1)) == expectedEven,
		"even-column neighbour order changed")
	_require(HexGridScript.neighbours(Vector2i(1, 0)) == expectedOdd,
		"odd-column neighbour order changed")

	for center in [Vector2i(-3, -2), Vector2i(0, 0), Vector2i(4, 5)]:
		var adjacent: Array[Vector2i] = HexGridScript.neighbours(center)
		var unique := {}
		for cell: Vector2i in adjacent:
			unique[cell] = true
			_require(HexGridScript.neighbours(cell).has(center),
				"neighbour relationship is not reciprocal: %s -> %s" % [center, cell])
		_require(unique.size() == 6, "expected six unique neighbours at %s" % center)


func _checkDistanceAndTranslation() -> void:
	for ay in range(-5, 6):
		for ax in range(-5, 6):
			var a := Vector2i(ax, ay)
			for by in range(-5, 6):
				for bx in range(-5, 6):
					var b := Vector2i(bx, by)
					_require(HexGridScript.distance(a, b) == HexGridScript.distance(b, a),
						"distance is asymmetric for %s and %s" % [a, b])
					var axialA: Vector2i = HexGridScript.offsetToAxial(a)
					var axialB: Vector2i = HexGridScript.offsetToAxial(b)
					var translatedA: Vector2i = HexGridScript.axialToOffset(
						axialA + Vector2i(7, -4))
					var translatedB: Vector2i = HexGridScript.axialToOffset(
						axialB + Vector2i(7, -4))
					_require(HexGridScript.distance(a, b) == HexGridScript.distance(
						translatedA, translatedB),
						"axial translation changed distance for %s and %s" % [a, b])


func _checkDiscs() -> void:
	var expectedCounts := {0: 1, 1: 7, 2: 19, 4: 61}
	for radius: int in expectedCounts:
		var cells: Array[Vector2i] = HexGridScript.disc(Vector2i(-3, 2), radius)
		_require(cells.size() == expectedCounts[radius],
			"radius %d disc had %d cells" % [radius, cells.size()])
		_require(cells.has(Vector2i(-3, 2)), "disc omitted its center")
		for index in range(1, cells.size()):
			var previous := cells[index - 1]
			var current := cells[index]
			_require(previous.y < current.y or
				(previous.y == current.y and previous.x < current.x),
				"disc is not in strict row-major order")
	_require(HexGridScript.disc(Vector2i.ZERO, -1).is_empty(),
		"negative-radius disc must be empty")


func _checkWrapperParity() -> void:
	for y in range(-8, 9):
		for x in range(-8, 9):
			var cell := Vector2i(x, y)
			_require(WorldMapHexGridScript.offsetToAxial(cell) ==
				HexGridScript.offsetToAxial(cell), "wrapper offset conversion drifted")
			_require(WorldMapHexGridScript.axialToOffset(cell) ==
				HexGridScript.axialToOffset(cell), "wrapper axial conversion drifted")
			_require(WorldMapHexGridScript.neighbours(cell) ==
				HexGridScript.neighbours(cell), "wrapper neighbours drifted")
			_require(WorldMapHexGridScript.distance(Vector2i.ZERO, cell) ==
				HexGridScript.distance(Vector2i.ZERO, cell), "wrapper distance drifted")
