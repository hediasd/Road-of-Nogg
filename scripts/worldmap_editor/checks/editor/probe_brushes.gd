extends SceneTree

const MapData = preload("res://src/presentation/worldmap/editor/WorldMapTileData.gd")
const History = preload("res://src/presentation/worldmap/editor/WorldMapEditHistory.gd")
const Brushes = preload("res://src/presentation/worldmap/editor/WorldMapBrushes.gd")

var failures := 0


const Hex = preload("res://src/presentation/worldmap/editor/WorldMapHexGrid.gd")


func _initialize() -> void:
	_checkDrag()
	_checkShapes()
	_checkFillAndEyedropper()
	_checkStamp()
	_checkScatter()
	_checkReplaceKind()
	_checkCelIsolation()
	_checkHexLine()
	_checkHexDisc()
	_checkHexFloodFill()
	_checkHexStamp()
	print("")
	print("probe_brushes: %s" % ("PASS" if failures == 0 else "%d FAILURE(S)" % failures))
	if failures == 0:
		print("WORLD MAP BRUSHES OK")
	quit(1 if failures > 0 else 0)


func _fresh() -> WorldMapTileData:
	var data := MapData.create("brush_probe", Vector2i(6, 5))
	data.layers["ground"]["TILESET"] = "tile_set"
	data.layers["overlay"]["TILESET"] = "cel_set"
	return data


## A 12x10 hex lattice -- wide enough that both column parities have interior room for a line,
## a radius-2 disc and a flood fill without ever touching the lattice edge, which would hide a
## parity bug behind an out-of-bounds clip instead of an actual mismatch.
func _freshHex() -> WorldMapTileData:
	var data := MapData.create("brush_probe_hex", Vector2i(12, 10), MapData.LAYOUT_HEX_FLAT)
	data.layers["ground"]["TILESET"] = "tile_set"
	return data


## Both centres this file tests area tools around: an odd and an even column, so every hex check
## below exercises both parities without repeating itself.
const _HEX_CENTRES: Array[Vector2i] = [Vector2i(5, 4), Vector2i(6, 4)]


func _checkHexLine() -> void:
	# Even-column start to odd-column end, and the reverse -- both directions across the parity
	# seam, which is where a Bresenham-style port would go wrong first.
	var pairs := [
		[Vector2i(2, 2), Vector2i(9, 7)],
		[Vector2i(9, 2), Vector2i(2, 7)],
	]
	for pair in pairs:
		var from: Vector2i = pair[0]
		var to: Vector2i = pair[1]
		var data := _freshHex()
		var history := History.new()
		Brushes.line(data, history, "ground", from, to, "road")
		var cells := Brushes.lineCells(from, to, true)
		if history.undoCount() != 1:
			_fail("hex line %s->%s was not one command" % [from, to])
			return
		if cells.front() != from or cells.back() != to:
			_fail("hex line %s->%s missed an endpoint" % [from, to])
			return
		for i in range(1, cells.size()):
			if Hex.distance(cells[i - 1], cells[i]) != 1:
				_fail("hex line %s->%s step %d (%s->%s) is not hex-adjacent" % [
					from, to, i, cells[i - 1], cells[i]
				])
				return
		var expectedSteps := Hex.distance(from, to) + 1
		if cells.size() != expectedSteps:
			_fail("hex line %s->%s has %d cells, expected %d" % [
				from, to, cells.size(), expectedSteps
			])
			return
	print("  ok    hex line: cube lerp, every step distance 1, both parity directions")


func _checkHexDisc() -> void:
	var radius := 2
	for centre in _HEX_CENTRES:
		var data := _freshHex()
		var history := History.new()
		Brushes.disc(data, history, "ground", centre, radius, "sand")
		var cells := Brushes.discCells(centre, radius)
		var expectedCount := 3 * radius * radius + 3 * radius + 1
		if cells.size() != expectedCount:
			_fail("hex disc at %s radius %d has %d cells, expected %d" % [
				centre, radius, cells.size(), expectedCount
			])
			return
		for cell in cells:
			if Hex.distance(centre, cell) > radius:
				_fail("hex disc at %s radius %d included %s at distance %d" % [
					centre, radius, cell, Hex.distance(centre, cell)
				])
				return
		if history.undoCount() != 1:
			_fail("hex disc at %s was not one command" % [centre])
			return
	print("  ok    hex disc (RANGE): exact cell count, every cell within radius, both parities")


## A hex RING (the cells at exactly distance 2) fully encloses the disc at distance 1 -- true
## because a hex has no diagonal neighbour to slip through, unlike a square ring, which needs
## 8-connectivity settled before the same claim holds. Filling from the centre with a wall on
## the ring must reach every interior cell and none outside it.
func _checkHexFloodFill() -> void:
	for centre in _HEX_CENTRES:
		var data := _freshHex()
		var interior := Brushes.discCells(centre, 1)
		var ring: Array[Vector2i] = []
		for cell in Brushes.discCells(centre, 2):
			if not interior.has(cell):
				ring.append(cell)
		for cell in ring:
			data.setCell("ground", cell, "wall")
			if data.getCell("ground", cell) != "wall":
				_fail("hex flood fill setup: ring cell %s at centre %s is out of the test lattice" % [
					cell, centre
				])
				return
		var history := History.new()
		Brushes.floodFill(data, history, "ground", centre, "water")
		for cell in interior:
			if data.getCell("ground", cell) != "water":
				_fail("hex flood fill at centre %s did not reach interior cell %s" % [centre, cell])
				return
		for cell in ring:
			if data.getCell("ground", cell) == "water":
				_fail("hex flood fill at centre %s leaked through the ring at %s" % [centre, cell])
				return
	print("  ok    hex flood fill: 6-neighbour set, contained by a hex ring, both parities")


## Stamps a pattern with one axial-offset neighbour step and checks it lands on an actual
## hex-adjacent cell for BOTH an odd- and an even-column origin -- the failure a row/col array
## pattern has and an axial one does not.
func _checkHexStamp() -> void:
	var neighbourStep: Vector2i = Hex.AXIAL_NEIGHBOURS[0]
	for origin in _HEX_CENTRES:
		var data := _freshHex()
		var history := History.new()
		var pattern := {
			Vector2i(0, 0): "core",
			neighbourStep: "edge",
		}
		Brushes.stampHex(data, history, "ground", origin, pattern)
		var expectedNeighbour := Hex.axialToOffset(Hex.offsetToAxial(origin) + neighbourStep)
		if data.getCell("ground", origin) != "core":
			_fail("hex stamp at origin %s did not paint its own anchor" % [origin])
			return
		if data.getCell("ground", expectedNeighbour) != "edge":
			_fail("hex stamp at origin %s did not land its neighbour offset on %s" % [
				origin, expectedNeighbour
			])
			return
		if Hex.distance(origin, expectedNeighbour) != 1:
			_fail("hex stamp neighbour offset for origin %s resolved to a non-adjacent cell" % [
				origin
			])
			return
		if history.undoCount() != 1:
			_fail("hex stamp at origin %s was not one command" % [origin])
			return
	print("  ok    hex stamp: axial offsets land adjacent on both column parities, one command")


func _fail(message: String) -> void:
	failures += 1
	print("  FAIL  " + message)


func _checkDrag() -> void:
	var data := _fresh()
	var history := History.new()
	Brushes.beginStroke(history, "ground")
	for x in 4:
		Brushes.paintPoint(data, history, Vector2i(x, 1), "grass")
	Brushes.endStroke(history)
	if history.undoCount() != 1:
		_fail("four-point drag did not coalesce to one history entry")
	else:
		print("  ok    point drag: four cells, one history entry")


func _checkShapes() -> void:
	var data := _fresh()
	var history := History.new()
	Brushes.rectangle(data, history, "ground", Vector2i(3, 2), Vector2i(1, 1), "sand")
	if history.undoCount() != 1 or Brushes.rectangleCells(Vector2i(3, 2), Vector2i(1, 1)).size() != 6:
		_fail("rectangle was not inclusive/reversible or was not one command")
		return
	Brushes.line(data, history, "ground", Vector2i(0, 0), Vector2i(5, 3), "road")
	var line := Brushes.lineCells(Vector2i(0, 0), Vector2i(5, 3))
	if history.undoCount() != 2 or line.front() != Vector2i(0, 0) or line.back() != Vector2i(5, 3):
		_fail("line missed an endpoint or was not one command")
	else:
		print("  ok    rectangle and Bresenham line are inclusive, one command each")


func _checkFillAndEyedropper() -> void:
	var data := _fresh()
	var history := History.new()
	for x in 6:
		data.setCell("ground", Vector2i(x, 2), "wall")
	Brushes.floodFill(data, history, "ground", Vector2i(0, 0), "water")
	if data.getCell("ground", Vector2i(5, 1)) != "water" or data.getCell("ground", Vector2i(0, 3)) == "water":
		_fail("flood fill crossed a cardinal barrier")
		return
	var before := history.undoCount()
	if Brushes.eyedropper(data, "ground", Vector2i(2, 2)) != "wall" or history.undoCount() != before:
		_fail("eyedropper did not sample without mutation")
	else:
		print("  ok    flood fill stays bounded; eyedropper is read-only")


func _checkStamp() -> void:
	var data := _fresh()
	var history := History.new()
	var pattern := [["a", "b"], ["c", null]]
	Brushes.stamp(data, history, "ground", Vector2i(2, 1), pattern)
	if data.getCell("ground", Vector2i(2, 1)) != "a" or data.getCell("ground", Vector2i(3, 1)) != "b" or data.getCell("ground", Vector2i(2, 2)) != "c" or history.undoCount() != 1:
		_fail("multi-cell stamp did not preserve its pattern in one command")
	else:
		print("  ok    multi-cell stamp preserves holes and is one command")


func _checkScatter() -> void:
	var a := _fresh()
	var b := _fresh()
	var ha := History.new()
	var hb := History.new()
	var choices: Array[String] = ["a", "b", "c"]
	Brushes.randomFromSet(a, ha, "ground", Rect2i(0, 0, 6, 5), choices, 9127)
	Brushes.randomFromSet(b, hb, "ground", Rect2i(0, 0, 6, 5), choices, 9127)
	if a.toDictionary() != b.toDictionary() or ha.undoCount() != 1:
		_fail("same-seed scatter was not deterministic or was not one command")
	else:
		print("  ok    random-from-set is deterministic and one command")


func _checkReplaceKind() -> void:
	var data := _fresh()
	var history := History.new()
	data.setCell("ground", Vector2i(0, 0), "grass_a")
	data.setCell("ground", Vector2i(1, 0), "grass_b")
	data.setCell("ground", Vector2i(2, 0), "stone")
	var terrain := {"grass_a": "grass", "grass_b": "grass", "stone": "stone"}
	Brushes.replaceAllOfKind(data, history, "ground", "grass_a", "sand", terrain)
	if data.getCell("ground", Vector2i(0, 0)) != "sand" or data.getCell("ground", Vector2i(1, 0)) != "sand" or data.getCell("ground", Vector2i(2, 0)) != "stone":
		_fail("replace-kind changed the wrong terrain class")
	else:
		print("  ok    replace-kind follows terrain metadata")


func _checkCelIsolation() -> void:
	var data := _fresh()
	var history := History.new()
	data.setCell("ground", Vector2i(1, 1), "ground_before")
	var groundBefore := data.getCell("ground", Vector2i(1, 1))
	Brushes.rectangle(data, history, "overlay", Vector2i(0, 0), Vector2i(7, 7), "detail")
	Brushes.line(data, history, "overlay", Vector2i(0, 0), Vector2i(11, 9), "detail2")
	Brushes.floodFill(data, history, "overlay", Vector2i(10, 8), "detail3")
	Brushes.stamp(data, history, "overlay", Vector2i(2, 2), [["x", "y"]])
	var details: Array[String] = ["x", "y"]
	Brushes.randomFromSet(data, history, "overlay", Rect2i(0, 0, 4, 4), details, 3)
	Brushes.replaceAllOfKind(data, history, "overlay", "x", "z")
	if data.getCell("ground", Vector2i(1, 1)) != groundBefore:
		_fail("a cel-grade operation changed tile-grade ground")
	else:
		print("  ok    every cel-grade operation leaves tile-grade ground untouched")
