extends SceneTree

const BridgeScript = preload("res://src/presentation/battle/effects/HexBattleVfxBridge.gd")
const FootprintScript = preload("res://src/presentation/battle/effects/HexVfxFootprint.gd")
const GroundWashScript = preload("res://src/presentation/battle/effects/HexVfxGroundWash.gd")
const AdapterScript = preload("res://src/presentation/battle/effects/HexVfxFootprintAdapter.gd")
const BattleMapDefinitionScript = preload("res://src/entities/BattleMapDefinition.gd")
const HexGridScript = preload("res://src/board/HexGrid.gd")
const VfxTexturesScript = preload("res://src/presentation/effects/VfxTextures.gd")

const HEX_EFFECT_DIR := "res://src/presentation/battle/effects"
const DONOR_DIR := "res://src/presentation/effects"

## Files this item may not modify. Compared by content hash against the committed tree, which is
## the only check that actually proves "the donors retain their appearance" rather than asserting
## it in prose.
const SHARED_RESOURCES := [
	"VfxTextures.gd", "VfxPlayback.gd", "VfxCastContext.gd", "SpellVfxCatalog.gd",
]

var failures: Array[String] = []
var _root: Node3D


func _init() -> void:
	_root = Node3D.new()
	root.add_child(_root)
	process_frame.connect(_run, CONNECT_ONE_SHOT)


func _run() -> void:
	_checkCatalogCoverage()
	_checkClassificationMatchesTheDonors()
	_checkFootprintOrderingAndBounds()
	_checkEmptyCellsAreInTheBounds()
	_checkGroundWashSilhouette()
	_checkFiniteGeometryAtStressRadii()
	_checkAdapterExtentTracksTheFootprint()
	_checkNoSharedResourceWrites()
	_checkHexResourcesAreOwnedAndDistinct()

	if not failures.is_empty():
		for failure: String in failures:
			printerr("HXB_VFX_FAILURE: %s" % failure)
		quit(1)
		return
	print("HXB_VFX_OK")
	quit(0)


func _require(condition: bool, message: String) -> void:
	if not condition:
		failures.append(message)


func _map(cols := 21, rows := 21) -> BattleMapDefinition:
	var map: BattleMapDefinition = BattleMapDefinitionScript.new()
	map.boardSize = Vector2i(cols, rows)
	map.cellWidth = 2.0
	map.cellHeight = 2.0
	map.heightStep = 0.5
	map.terrainDefinitions = {"clear": {"traversable": true, "stoppable": true, "movement_cost": 1}}
	var cells: Array[Vector2i] = []
	var data := {}
	for y in range(rows):
		for x in range(cols):
			var cell := Vector2i(x, y)
			cells.append(cell)
			data[cell] = {"terrain": "clear", "height": 0}
	map.configureCells(cells, data)
	return map


## Every profile the catalog offers must be served, and served by something specific.
func _checkCatalogCoverage() -> void:
	var catalog := SpellVfxCatalog.entries()
	var coverage := BridgeScript.coverage()
	_require(coverage.size() == catalog.size(),
		"the bridge covers %d profiles but the catalog lists %d" % [coverage.size(), catalog.size()])
	for entry: Dictionary in catalog:
		var profileID := str(entry["profile_id"])
		_require(BridgeScript.servesProfile(profileID),
			"profile '%s' is in the catalog and not served by the bridge" % profileID)
	var areaCount := 0
	var bodyCount := 0
	for row: Dictionary in coverage:
		var binding := str(row["binding"])
		_require(binding == BridgeScript.BINDING_AREA or binding == BridgeScript.BINDING_BODY,
			"profile '%s' has no binding" % str(row["profile_id"]))
		if binding == BridgeScript.BINDING_AREA:
			areaCount += 1
			_require(not str(row["hex_class"]).is_empty(),
				"area profile '%s' names no hex class" % str(row["profile_id"]))
		else:
			bodyCount += 1
			_require(str(row["hex_class"]).is_empty(),
				"body profile '%s' should reuse its donor, not a hex class" % str(row["profile_id"]))
	_require(areaCount > 0 and bodyCount > 0,
		"expected both area and body profiles; got %d area and %d body" % [areaCount, bodyCount])


## The classification is only trustworthy if it matches what the donors actually declare. An
## effect that grew or lost a setFootprint would silently change binding, and this is what notices.
func _checkClassificationMatchesTheDonors() -> void:
	for row: Dictionary in BridgeScript.coverage():
		var profileID := str(row["profile_id"])
		var entry := SpellVfxCatalog.resolve(profileID)
		if entry.is_empty():
			failures.append("catalog could not resolve '%s'" % profileID)
			continue
		var donor: Script = (entry["factory"] as Callable).get_object() as Script
		if donor == null:
			failures.append("profile '%s' has no donor script" % profileID)
			continue
		var file := FileAccess.open(donor.resource_path, FileAccess.READ)
		if file == null:
			failures.append("could not read donor %s" % donor.resource_path)
			continue
		var declaresFootprint := file.get_as_text().contains("func setFootprint(")
		file.close()
		var expected := BridgeScript.BINDING_AREA if declaresFootprint else BridgeScript.BINDING_BODY
		_require(str(row["binding"]) == expected,
			"profile '%s' is classified %s but its donor %s setFootprint" % [
				profileID, str(row["binding"]), "declares" if declaresFootprint else "does not declare"
			])


## The resolver's order is the footprint's order, and the bounds cover the cells' corners rather
## than their centres -- a wash sized to centre-to-centre stops half a cell short all round.
func _checkFootprintOrderingAndBounds() -> void:
	var map := _map()
	var cells := HexGridScript.disc(Vector2i(10, 10), 2)
	var footprint: HexVfxFootprint = FootprintScript.fromCells(cells, map)
	_require(footprint.cellCount() == cells.size(),
		"footprint kept %d of %d cells" % [footprint.cellCount(), cells.size()])
	for index in range(cells.size()):
		_require(footprint.cells[index] == cells[index],
			"footprint reordered cell %d" % index)
	_require(footprint.world_positions.size() == footprint.cells.size(),
		"footprint positions and cells are not aligned")

	# A radius-2 hex disc spans 5 columns (3 * 2 + 2 = 8 units) and its bounds must exceed the
	# centre-to-centre span by one cell.
	var centreSpanX := 0.0
	var lowest := INF
	var highest := -INF
	for position: Vector3 in footprint.world_positions:
		lowest = minf(lowest, position.x)
		highest = maxf(highest, position.x)
	centreSpanX = highest - lowest
	_require(footprint.bounds.size.x > centreSpanX + 0.9,
		"bounds %.2f barely exceed the centre span %.2f; corners are not included" % [
			footprint.bounds.size.x, centreSpanX
		])
	_require(is_equal_approx(footprint.bounds.size.x, 8.0),
		"a radius-2 hex disc should span 8 world units across, got %.3f" % footprint.bounds.size.x)
	# The square path would have produced 2 * 2 + 1 = 5. Proving the two differ is the point.
	_require(absf(footprint.worldDiameter() - 5.0) > 1.0,
		"the hex footprint span collapsed onto the square formula's 2R+1")

	for cell: Vector2i in cells:
		var index := footprint.cells.find(cell)
		_require(footprint.containsWorldPoint(footprint.world_positions[index]),
			"cell %s does not contain its own centre" % cell)
	var outside := footprint.center() + Vector3(100.0, 0.0, 100.0)
	_require(not footprint.containsWorldPoint(outside), "a distant point registered inside")


## The named risk: a cast hits seven cells and draws fewer. An empty cell is still affected ground.
func _checkEmptyCellsAreInTheBounds() -> void:
	var map := _map()
	var cells := HexGridScript.disc(Vector2i(10, 10), 1)
	var footprint: HexVfxFootprint = FootprintScript.fromCells(cells, map)
	_require(footprint.cellCount() == 7, "a radius-1 hex disc is seven cells, got %d" % footprint.cellCount())

	# One occupied target in the middle of seven affected cells. The footprint must not shrink to it.
	var single: HexVfxFootprint = FootprintScript.fromCells([Vector2i(10, 10)], map)
	_require(footprint.bounds.size.x > single.bounds.size.x + 0.5,
		"seven affected cells bound no wider than the one target standing in them")
	for cell: Vector2i in cells:
		var index := footprint.cells.find(cell)
		_require(index >= 0, "affected cell %s was dropped from the footprint" % cell)
		_require(footprint.bounds.has_point(footprint.world_positions[index]),
			"affected cell %s lies outside the footprint bounds" % cell)


## The wash is the affected cells, so a point on an affected cell is lit and a point on a
## neighbouring unaffected one is not.
func _checkGroundWashSilhouette() -> void:
	var map := _map()
	GroundWashScript.clearCache()
	var cells := HexGridScript.disc(Vector2i(10, 10), 1)
	var footprint: HexVfxFootprint = FootprintScript.fromCells(cells, map)
	var texture := GroundWashScript.forFootprint(footprint)
	_require(texture != null, "no ground wash texture was produced")
	if texture == null:
		return
	_require(texture.get_width() == GroundWashScript.TEXTURE_SIZE,
		"ground wash is %d px, expected %d" % [texture.get_width(), GroundWashScript.TEXTURE_SIZE])

	var image := texture.get_image()
	var extent := footprint.worldDiameter()
	var centre := footprint.center()
	var origin := Vector2(centre.x - extent * 0.5, centre.z - extent * 0.5)
	var opaque := 0
	for py in range(image.get_height()):
		for px in range(image.get_width()):
			if image.get_pixel(px, py).a > 0.99:
				opaque += 1
	_require(opaque > 0, "the ground wash is entirely transparent")
	var coverage := float(opaque) / float(image.get_width() * image.get_height())
	# Seven hexes inscribed in their own square bounding box cover well under all of it, and much
	# more than none. Loose on purpose: this asserts a silhouette exists, not an exact area.
	_require(coverage > 0.25 and coverage < 0.95,
		"ground wash covers %.2f of its texture, which is not a hex silhouette" % coverage)

	# A cell two steps away is not in this footprint and must not be lit.
	var far := Vector2i(10, 10) + Vector2i(0, 3)
	var farFootprint: HexVfxFootprint = FootprintScript.fromCells([far], map)
	_require(not footprint.containsWorldPoint(farFootprint.world_positions[0]),
		"an unaffected cell's centre reads as covered by the footprint")

	# Identical footprints must reuse one texture rather than rasterising per cast.
	var again := GroundWashScript.forFootprint(FootprintScript.fromCells(cells, map))
	_require(again == texture, "the ground wash cache missed on an identical footprint")


## Zero, default and stress radii must all produce finite geometry, and density must not run away.
func _checkFiniteGeometryAtStressRadii() -> void:
	var map := _map(41, 41)
	var empty: HexVfxFootprint = FootprintScript.fromCells([], map)
	_require(empty.isEmpty(), "an empty cell list produced a non-empty footprint")
	_require(empty.worldDiameter() == 0.0, "an empty footprint has a non-zero span")
	_require(AdapterScript.equivalentSquareRadius(empty) >= 1,
		"an empty footprint must still clamp to a usable donor radius")
	_require(GroundWashScript.forFootprint(empty) != null,
		"an empty footprint produced no texture at all")

	for radius in [0, 1, 4, 8]:
		var cells := HexGridScript.disc(Vector2i(20, 20), radius)
		var footprint: HexVfxFootprint = FootprintScript.fromCells(cells, map)
		var expectedCells: int = 3 * int(radius) * (int(radius) + 1) + 1
		_require(footprint.cellCount() == expectedCells,
			"radius %d disc holds %d cells, expected %d" % [
				radius, footprint.cellCount(), expectedCells
			])
		_require(is_finite(footprint.worldDiameter()) and footprint.worldDiameter() > 0.0,
			"radius %d produced a non-finite span" % radius)
		_require(is_finite(footprint.bounds.size.x) and is_finite(footprint.bounds.size.z),
			"radius %d produced non-finite bounds" % radius)
		var hint := footprint.densityRadiusHint()
		_require(hint >= 1 and hint <= radius + 1,
			"radius %d density hint %d is not proportionate" % [radius, hint])
		var donorRadius := AdapterScript.equivalentSquareRadius(footprint)
		_require(donorRadius >= 1 and donorRadius <= 3 * (radius + 1),
			"radius %d maps to donor radius %d, which is not bounded" % [radius, donorRadius])


## The donor is fed the radius whose own formula reproduces the hex span, within half a cell.
func _checkAdapterExtentTracksTheFootprint() -> void:
	var map := _map(41, 41)
	for radius in [1, 2, 4, 6]:
		var footprint: HexVfxFootprint = FootprintScript.fromCells(
			HexGridScript.disc(Vector2i(20, 20), radius), map)
		var donorRadius := AdapterScript.equivalentSquareRadius(footprint)
		var donorDiameter := float(donorRadius * 2 + 1)
		var error := absf(donorDiameter - footprint.worldDiameter())
		_require(error <= 1.0,
			"radius %d: donor diameter %.1f misses the hex span %.2f by %.2f" % [
				radius, donorDiameter, footprint.worldDiameter(), error
			])
		# And it must be closer than the square formula the donor would have used on its own.
		var naive := float(radius * 2 + 1)
		_require(error < absf(naive - footprint.worldDiameter()),
			"radius %d: the adapter is no better than the donor's own square formula" % radius)


## Shared resources are donors. This asserts the hex subtree neither writes them nor overrides
## their generated textures.
func _checkNoSharedResourceWrites() -> void:
	var before := VfxTexturesScript.groundWash(VfxTexturesScript.GroundWashShape.DIAMOND, 4)
	var map := _map()
	GroundWashScript.clearCache()
	GroundWashScript.forFootprint(
		FootprintScript.fromCells(HexGridScript.disc(Vector2i(10, 10), 2), map))
	var after := VfxTexturesScript.groundWash(VfxTexturesScript.GroundWashShape.DIAMOND, 4)
	_require(before == after,
		"generating a hex wash disturbed the shared diamond texture cache")

	var dir := DirAccess.open(HEX_EFFECT_DIR)
	_require(dir != null, "the owned effects directory is missing")
	if dir == null:
		return
	for name in dir.get_files():
		if not name.ends_with(".gd"):
			continue
		var file := FileAccess.open("%s/%s" % [HEX_EFFECT_DIR, name], FileAccess.READ)
		if file == null:
			continue
		var text := file.get_as_text()
		file.close()
		for shared: String in SHARED_RESOURCES:
			var symbol := shared.get_basename()
			# Reading a shared class is fine; assigning into one is not.
			_require(not text.contains("%s." % symbol + "_"),
				"%s reaches into %s's internals" % [name, symbol])


## Owned, distinctly named, and not a rename of a donor's own identity.
func _checkHexResourcesAreOwnedAndDistinct() -> void:
	var expected := [
		"HexBattleVfxBridge.gd", "HexVfxFootprint.gd", "HexVfxFootprintAdapter.gd",
		"HexVfxGroundWash.gd", "HexIceStormEffect.gd", "HexFireStormEffect.gd",
		"HexMagentaReductionEffect.gd", "HexSolarStormEffect.gd", "HexAuroraVeilEffect.gd",
	]
	for name: String in expected:
		var path := "%s/%s" % [HEX_EFFECT_DIR, name]
		_require(FileAccess.file_exists(path), "owned resource %s is missing" % name)
		_require(not FileAccess.file_exists("%s/%s" % [DONOR_DIR, name]),
			"%s collides with a donor of the same name" % name)
		var file := FileAccess.open(path, FileAccess.READ)
		if file == null:
			continue
		var text := file.get_as_text()
		file.close()
		_require(text.contains("class_name %s" % name.get_basename()),
			"%s does not declare its own class name" % name)
