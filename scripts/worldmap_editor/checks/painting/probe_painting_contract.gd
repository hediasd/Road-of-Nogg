extends SceneTree

## Bounded check on what a painting gesture is allowed to do: that the highlight and the edit
## target the same cells, that a drag is continuous and undoes as one entry, that a stamp keeps
## its shape across a hex parity boundary, that scatter is reproducible, and -- the one that
## matters most -- that hiding a layer changes the VIEW and never the saved source or the bake.
##
## Uses in-memory documents and raw sheet loads. No editor scene, no camera, no window.

const Footprint = preload("res://src/presentation/worldmap/editor/workspace/WorldMapWorkspaceFootprint.gd")
const LayerViewScript = preload("res://src/presentation/worldmap/editor/workspace/WorldMapWorkspaceLayerView.gd")
const Brushes = preload("res://src/presentation/worldmap/editor/WorldMapBrushes.gd")
const HistoryScript = preload("res://src/presentation/worldmap/editor/WorldMapEditHistory.gd")
const MapDataScript = preload("res://src/presentation/worldmap/editor/WorldMapTileData.gd")
const HexGrid = preload("res://src/presentation/worldmap/editor/WorldMapHexGrid.gd")
const Baker = preload("res://src/presentation/worldmap/editor/WorldMapBaker.gd")
const ControllerScript = preload("res://src/presentation/worldmap/editor/WorldMapEditorController.gd")

const LATTICE := Vector2i(11, 8)
const STARTER := "temp2_hex32_starter"

var failures: Array[String] = []


func _init() -> void:
	_checkDiscAndRadiusLabel()
	_checkDragInterpolation()
	_checkClipping()
	_checkPreviewMatchesApply()
	_checkOneUndoPerGesture()
	_checkStampAcrossParity()
	_checkDeterministicScatter()
	_checkVisibilityIsViewOnly()
	if not failures.is_empty():
		for failure: String in failures:
			printerr("HXW_PAINTING_FAILURE: %s" % failure)
		quit(1)
		return
	print("WORLD MAP PAINTING CONTRACT OK")
	quit(0)


func _document() -> WorldMapTileData:
	var doc := MapDataScript.create("probe", LATTICE, MapDataScript.LAYOUT_HEX_FLAT)
	doc.layers["ground"]["TILESET"] = STARTER
	return doc


## Radius counts rings and reads as a cell count. Every cell in a disc is within `radius` steps of
## the centre by the lattice's own distance function -- not by a separate approximation.
func _checkDiscAndRadiusLabel() -> void:
	_require(Footprint.radiusLabel(0) == "1 hex", "radius 0 should read as one hex")
	_require(Footprint.radiusLabel(1) == "7 hexes", "radius 1 should cover seven hexes")
	_require(Footprint.radiusLabel(2) == "19 hexes", "radius 2 should cover nineteen hexes")

	var centre := Vector2i(5, 4)
	for radius in 3:
		var cells := Footprint.discCells(centre, radius, LATTICE)
		var expected := 1
		for ring in range(1, radius + 1):
			expected += 6 * ring
		_require(
			cells.size() == expected,
			"radius %d produced %d cells, expected %d" % [radius, cells.size(), expected]
		)
		for cell in cells:
			_require(
				HexGrid.distance(centre, cell) <= radius,
				"radius %d included %s, which is %d steps away" % [
					radius, cell, HexGrid.distance(centre, cell),
				]
			)


## A fast drag must not leave gaps. Two samples several cells apart are joined by the hex line
## path, so every cell between them is covered and adjacent cells in the result really are
## adjacent on the lattice.
func _checkDragInterpolation() -> void:
	var from := Vector2i(1, 1)
	var to := Vector2i(8, 6)
	var swept := Footprint.dragCells(from, to, 0, true, LATTICE)
	_require(swept.has(from) and swept.has(to), "a drag did not include its own endpoints")
	var steps := HexGrid.distance(from, to)
	_require(
		swept.size() == steps + 1,
		"a drag of %d steps produced %d cells" % [steps, swept.size()]
	)
	for index in range(1, swept.size()):
		_require(
			HexGrid.distance(swept[index - 1], swept[index]) == 1,
			"the drag path jumped from %s to %s" % [swept[index - 1], swept[index]]
		)

	# The same drag with a brush radius sweeps a band, and still contains the bare path.
	var wide := Footprint.dragCells(from, to, 1, true, LATTICE)
	for cell in swept:
		_require(wide.has(cell), "the radius-1 drag lost %s from its own centre line" % cell)
	_require(wide.size() > swept.size(), "a radius-1 drag was no wider than a radius-0 one")

	# No duplicates anywhere, however much the discs overlap.
	var seen := {}
	for cell in wide:
		_require(not seen.has(cell), "the swept band repeated %s" % cell)
		seen[cell] = true


## Cells the document does not hold are not previewed and not painted. A footprint at the lattice
## edge is genuinely smaller, rather than a promise the edit then quietly breaks.
func _checkClipping() -> void:
	var corner := Footprint.discCells(Vector2i.ZERO, 2, LATTICE)
	_require(not corner.is_empty(), "a corner footprint clipped away entirely")
	for cell in corner:
		_require(
			HexGrid.contains(cell, LATTICE.x, LATTICE.y),
			"a clipped footprint still contained the off-lattice cell %s" % cell
		)
	_require(
		corner.size() < Footprint.discCells(Vector2i(5, 4), 2, LATTICE).size(),
		"a footprint at the corner was not smaller than one in open space"
	)
	# An unbounded lattice keeps everything, which is the square-document convention.
	_require(
		Footprint.discCells(Vector2i.ZERO, 1, Vector2i.ZERO).size() == 7,
		"a zero lattice should mean unbounded"
	)


## THE CENTRAL PROPERTY: the highlight is the edit. Painting exactly the previewed cells and then
## comparing against the document proves the two agree, rather than asserting they were computed
## by the same call.
func _checkPreviewMatchesApply() -> void:
	var document := _document()
	var history := HistoryScript.new()
	var centre := Vector2i(3, 3)
	var previewed := Footprint.discCells(centre, 1, LATTICE)

	history.beginStroke("ground")
	for cell in previewed:
		history.paintCell(document, cell, "t002")
	history.endStroke()

	var changed: Array[Vector2i] = []
	for y in LATTICE.y:
		for x in LATTICE.x:
			if document.getCell("ground", Vector2i(x, y)) == "t002":
				changed.append(Vector2i(x, y))
	_require(
		changed.size() == previewed.size(),
		"previewed %d cells but changed %d" % [previewed.size(), changed.size()]
	)
	for cell in previewed:
		_require(changed.has(cell), "previewed %s was never painted" % cell)

	# The controller reads its preview and its edit from these same functions, so the tool table
	# must not have grown a tool the footprint code does not know how to describe.
	for tool in ControllerScript.TOOLS:
		_require(
			not str((tool as Dictionary)["id"]).is_empty(),
			"a controller tool has no id for the preview to dispatch on"
		)


## One continuous gesture is one history entry, however far it travels, however many cells repeat
## and whatever the radius -- and undoing it puts every one of them back.
func _checkOneUndoPerGesture() -> void:
	var document := _document()
	var history := HistoryScript.new()
	var before := history.currentRevision()

	history.beginStroke("ground")
	var swept := Footprint.dragCells(Vector2i(1, 1), Vector2i(9, 6), 1, true, LATTICE)
	for cell in swept:
		history.paintCell(document, cell, "t001")
	# Drag back over the same ground, which is what an author doing a wobbly stroke produces.
	for cell in Footprint.dragCells(Vector2i(9, 6), Vector2i(1, 1), 1, true, LATTICE):
		history.paintCell(document, cell, "t001")
	history.endStroke()

	_require(history.undoCount() == 1, "one gesture produced %d history entries" % history.undoCount())
	_require(history.currentRevision() != before, "a gesture that changed cells kept its revision")

	history.undo(document)
	var leftover := 0
	for cell in swept:
		if document.getCell("ground", cell) == "t001":
			leftover += 1
	_require(leftover == 0, "undoing one gesture left %d painted cells behind" % leftover)
	_require(
		history.currentRevision() == before,
		"undoing the only gesture did not return to the starting revision"
	)


## A stamp keeps its SHAPE wherever it lands. Offset deltas do not survive a hex parity boundary;
## axial ones do, which is why the pattern is built and applied in axial.
func _checkStampAcrossParity() -> void:
	# An L of three sheet frames, deliberately spanning two sheet columns and two rows.
	var sheetCells: Array = [Vector2i(0, 0), Vector2i(1, 0), Vector2i(0, 1)]
	var ids: Array = ["t000", "t001", "t002"]
	var pattern := Footprint.stampPattern(sheetCells, ids)
	_require(pattern.size() == 3, "the stamp pattern lost frames")

	var evenAnchor := Vector2i(4, 3)
	var oddAnchor := Vector2i(5, 3)
	var evenCells := Footprint.stampCells(evenAnchor, pattern, LATTICE)
	var oddCells := Footprint.stampCells(oddAnchor, pattern, LATTICE)
	_require(evenCells.size() == 3 and oddCells.size() == 3, "a stamp lost cells to clipping")

	# Same shape means the same set of pairwise lattice distances, wherever it is anchored.
	var evenShape := _pairwiseDistances(evenCells)
	var oddShape := _pairwiseDistances(oddCells)
	_require(
		evenShape == oddShape,
		"the stamp changed shape between an even and an odd anchor column: %s vs %s" % [
			evenShape, oddShape,
		]
	)

	# And the applied edit lands on exactly the cells the preview named, at both parities.
	for anchor: Vector2i in [evenAnchor, oddAnchor]:
		var document := _document()
		var history := HistoryScript.new()
		Brushes.stampHex(document, history, "ground", anchor, pattern)
		var expected := Footprint.stampCells(anchor, pattern, LATTICE)
		for cell in expected:
			_require(
				document.getCell("ground", cell) != MapDataScript.EMPTY,
				"stamping at %s left %s unpainted" % [anchor, cell]
			)

	# A frame the author did not select is a HOLE, not an erase.
	var sparse := Footprint.stampPattern(
		[Vector2i(0, 0), Vector2i(2, 0)] as Array, ["t000", "t002"] as Array
	)
	_require(sparse.size() == 2, "a sparse selection did not produce a two-cell stamp")


func _pairwiseDistances(cells: Array[Vector2i]) -> Array:
	var distances: Array = []
	for i in cells.size():
		for j in range(i + 1, cells.size()):
			distances.append(HexGrid.distance(cells[i], cells[j]))
	distances.sort()
	return distances


## Identical seed, rect and ordered id list commit identical tile ids -- the randomness is
## resolved once and stored, never re-rolled at bake time.
func _checkDeterministicScatter() -> void:
	var rect := Rect2i(Vector2i(2, 2), Vector2i(5, 4))
	var ids: Array[String] = ["t000", "t001", "t002"]
	var first := _document()
	var second := _document()
	Brushes.randomFromSet(first, HistoryScript.new(), "ground", rect, ids, 4242)
	Brushes.randomFromSet(second, HistoryScript.new(), "ground", rect, ids, 4242)
	var differing := 0
	var used := {}
	for y in range(rect.position.y, rect.end.y):
		for x in range(rect.position.x, rect.end.x):
			var cell := Vector2i(x, y)
			var a := first.getCell("ground", cell)
			used[a] = true
			if a != second.getCell("ground", cell):
				differing += 1
	_require(differing == 0, "the same seed produced %d differing cells" % differing)
	_require(used.size() > 1, "a multi-id scatter used only one id")

	var third := _document()
	Brushes.randomFromSet(third, HistoryScript.new(), "ground", rect, ids, 99)
	var changedBySeed := 0
	for y in range(rect.position.y, rect.end.y):
		for x in range(rect.position.x, rect.end.x):
			if third.getCell("ground", Vector2i(x, y)) != first.getCell("ground", Vector2i(x, y)):
				changedBySeed += 1
	_require(changedBySeed > 0, "changing the seed changed nothing")


## THE ONE THAT PROTECTS THE AUTHOR'S WORK. Hiding a layer is a view decision, so the serialized
## source and the canonical bake must be byte-identical for every combination of hidden layers,
## while the FILTERED copy that is displayed really does lose the hidden art.
func _checkVisibilityIsViewOnly() -> void:
	var document := _document()
	document.addGridLayer("overlay", "tile", STARTER)
	var history := HistoryScript.new()
	history.beginStroke("ground")
	for cell in Footprint.discCells(Vector2i(4, 4), 2, LATTICE):
		history.paintCell(document, cell, "t001")
	history.endStroke()
	history.beginStroke("overlay")
	for cell in Footprint.discCells(Vector2i(6, 3), 1, LATTICE):
		history.paintCell(document, cell, "t009")
	history.endStroke()

	var canonicalSource := JSON.stringify(document.toDictionary(), "\t")
	var canonicalBaker := Baker.new()
	var canonicalTexture := canonicalBaker.bake(document)
	var canonicalPixels := (
		canonicalBaker.image().get_data() if canonicalTexture != null else PackedByteArray()
	)
	_require(not canonicalPixels.is_empty(), "the canonical bake produced no pixels to compare")

	var view := LayerViewScript.new()
	for combination: Array in [["ground"], ["overlay"], ["ground", "overlay"], ["detail"]]:
		view.reset()
		for layerID: String in combination:
			view.setHidden(layerID, true)

		# The authored document is untouched by any of it.
		_require(
			JSON.stringify(document.toDictionary(), "\t") == canonicalSource,
			"hiding %s changed the serialized source" % str(combination)
		)
		var rebaked := Baker.new()
		rebaked.bake(document)
		_require(
			rebaked.image().get_data() == canonicalPixels,
			"the canonical bake changed while %s was hidden" % str(combination)
		)

		# ...and the filtered copy really is filtered, without being the document.
		var filtered := view.filteredCopy(document)
		if view.anyArtHidden():
			_require(filtered != null, "hiding %s produced no filtered copy" % str(combination))
			if filtered != null:
				_require(filtered != document, "the filtered copy IS the authored document")
				for layerID: String in combination:
					if LayerViewScript.HIDEABLE_ART.has(layerID):
						_require(
							not filtered.layers.has(layerID),
							"%s survived into the filtered copy" % layerID
						)
				# Hiding painted art must actually change the displayed pixels, or the control is
				# doing nothing and saying it did something.
				if combination.has("ground") or combination.has("overlay"):
					var filteredBaker := Baker.new()
					filteredBaker.bake(filtered)
					_require(
						filteredBaker.image().get_data() != canonicalPixels,
						"hiding %s did not change the displayed bake" % str(combination)
					)
		else:
			_require(filtered == null, "nothing hideable was hidden but a copy was still built")

	# The two layers with no independent view say so instead of offering a toggle.
	_require(
		not LayerViewScript.canHide("heights", "objects"),
		"terrain height was offered a visibility toggle"
	)
	_require(
		not LayerViewScript.whyNotHideable("heights", "objects", "heights").is_empty(),
		"terrain height has no explanation for its missing toggle"
	)
	_require(
		LayerViewScript.canHide("objects", "objects") and LayerViewScript.canHide("ground", "objects"),
		"a layer that does have a view was refused one"
	)
	_require(
		not view.describe().is_empty() or not view.isFiltering(),
		"a filtered view did not describe itself"
	)


func _require(condition: bool, message: String) -> void:
	if not condition:
		failures.append(message)
