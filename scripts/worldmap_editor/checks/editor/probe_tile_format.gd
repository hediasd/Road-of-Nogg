## WME-5's self-contained validation: the authored-region format round-trips exactly, refuses
## what it cannot trust, and does not disturb how a painted region loads.
##
## The property that matters most here is not "it parses" but "it re-saves byte-identically".
## Several agent sessions share one working tree, so a serialisation that reshuffles itself
## turns every save into a merge conflict that is not a real disagreement -- which makes
## determinism a correctness concern, and one that is asserted rather than assumed.

extends SceneTree

const MapData = preload("res://src/presentation/worldmap/editor/WorldMapTileData.gd")
const TilesetCatalog = preload("res://src/presentation/worldmap/editor/WorldMapTilesetCatalog.gd")
const RegionCatalog = preload("res://src/presentation/worldmap/WorldMapRegionCatalog.gd")
const Uniforms = preload("res://src/presentation/worldmap/WorldMapGroundUniforms.gd")

const SCRATCH := "user://probe_scratch/worldmap/_probe_tile_format.json"
const SCRATCH_REGIONS := "user://probe_scratch/worldmap/_probe_regions.json"

var _failures := 0


func _initialize() -> void:
	DirAccess.make_dir_recursive_absolute(SCRATCH.get_base_dir())
	_checkRoundTrip()
	_checkResaveIsByteIdentical()
	_checkRLE()
	_checkVersionRefusal()
	_checkLayerAgnostic()
	_checkCellAccess()
	_checkRegionKind()
	_checkRealAuthoredRegion()
	_checkPaintedPathUnchanged()

	for path in [SCRATCH, SCRATCH_REGIONS]:
		if FileAccess.file_exists(path):
			DirAccess.remove_absolute(ProjectSettings.globalize_path(path))

	print("")
	print("probe_tile_format: %s" % ("PASS" if _failures == 0 else "%d FAILURE(S)" % _failures))
	if _failures == 0:
		print("WORLD MAP TILE FORMAT OK")
	quit(1 if _failures > 0 else 0)


func _fail(message: String) -> void:
	_failures += 1
	print("  FAIL  %s" % message)


## A small map with content in it, so a round trip has something to lose.
func _sample() -> WorldMapTileData:
	var data: WorldMapTileData = MapData.create("probe_sample", Vector2i(4, 3))
	data.description = "probe fixture"
	data.palette_region = "temp2"
	data.fog_color = Color("bae8e2")
	data.void_color = Color("37aeae")
	data.layers["ground"]["TILESET"] = "temp2_ground"
	for x in 4:
		data.setCell("ground", Vector2i(x, 0), "t00%d" % x)
	data.setCell("ground", Vector2i(1, 1), "t007")
	data.setCell("overlay", Vector2i(3, 2), "r001")
	return data


func _checkRoundTrip() -> void:
	print("-- save then load reproduces the map exactly --")
	var original := _sample()
	if not original.saveTo(SCRATCH):
		_fail("could not write the scratch map")
		return
	var reloaded: WorldMapTileData = MapData.loadFrom(SCRATCH)
	if reloaded == null:
		_fail("could not read the scratch map back")
		return
	if original.toDictionary() != reloaded.toDictionary():
		_fail("the round-tripped map differs from the original")
		return
	if reloaded.size_tiles != Vector2i(4, 3) or reloaded.palette_region != "temp2":
		_fail("metadata did not survive: %s %s" % [reloaded.size_tiles, reloaded.palette_region])
		return
	if reloaded.getCell("ground", Vector2i(1, 1)) != "t007":
		_fail("a ground cell did not survive")
		return
	if reloaded.getCell("overlay", Vector2i(3, 2)) != "r001":
		_fail("an overlay cell did not survive")
		return
	print("  ok    identical dictionary, metadata and cells on both layers")


func _checkResaveIsByteIdentical() -> void:
	print("-- re-saving an unchanged map produces identical bytes --")
	var first := FileAccess.get_file_as_bytes(SCRATCH)
	var reloaded: WorldMapTileData = MapData.loadFrom(SCRATCH)
	if reloaded == null:
		_fail("could not reload for the re-save check")
		return
	reloaded.saveTo(SCRATCH)
	var second := FileAccess.get_file_as_bytes(SCRATCH)
	if first != second:
		_fail("a no-op re-save changed %d bytes" % absi(first.size() - second.size()))
		return
	print("  ok    %d bytes, unchanged across a save/load/save cycle" % second.size())


func _checkRLE() -> void:
	print("-- run-length encoding --")
	var cells := PackedStringArray(["a", "a", "a", "b", "-", "-", "c"])
	var runs := MapData.encodeRLE(cells)
	if runs != ["3:a", "1:b", "2:-", "1:c"]:
		_fail("unexpected encoding: %s" % [runs])
		return
	if MapData.decodeRLE(runs, 7) != cells:
		_fail("decode did not reproduce the input")
		return
	# A run list that does not add up is a mangled file and must fail loudly rather than pad.
	if not MapData.decodeRLE(["3:a"], 7).is_empty():
		_fail("a short run list was accepted")
		return
	if not MapData.decodeRLE(["nonsense"], 7).is_empty():
		_fail("a malformed run was accepted")
		return
	print("  ok    encodes, decodes, and refuses both a short list and a malformed run")


func _checkVersionRefusal() -> void:
	print("-- version handling --")
	var current := _sample().toDictionary()
	if MapData.fromDictionary(current) == null:
		_fail("the current version was refused")
		return
	var future := current.duplicate(true)
	future["FORMAT_VERSION"] = MapData.FORMAT_VERSION + 1
	if MapData.fromDictionary(future) != null:
		_fail("a FUTURE version was accepted; unknown fields would be dropped silently")
		return
	var ancient := current.duplicate(true)
	ancient["FORMAT_VERSION"] = 0
	if MapData.fromDictionary(ancient) != null:
		_fail("an unreadable old version was accepted")
		return
	print("  ok    version %d accepted; future and unreadable versions refused" % MapData.FORMAT_VERSION)


## The format does not enumerate layers, so it must read a layer it has never heard of. This is
## what makes adding elevation, props or a travel graph a data change rather than a migration.
func _checkLayerAgnostic() -> void:
	print("-- a layer the format has never heard of survives a round trip --")
	var data := _sample()
	data.addGridLayer("height", TilesetCatalog.GRID_TILE, "")
	data.setCell("height", Vector2i(2, 2), "h3")
	data.addListLayer("graph")
	data.layers["graph"]["ITEMS"] = [{"ID": "node_a", "AT": [1, 1]}]
	data.saveTo(SCRATCH)

	var reloaded: WorldMapTileData = MapData.loadFrom(SCRATCH)
	if reloaded == null:
		_fail("a map with unknown layers failed to load")
		return
	if reloaded.getCell("height", Vector2i(2, 2)) != "h3":
		_fail("the unknown grid layer lost its cell")
		return
	var items: Array = reloaded.layers["graph"]["ITEMS"]
	if items.size() != 1 or str((items[0] as Dictionary)["ID"]) != "node_a":
		_fail("the unknown list layer lost its items: %s" % [items])
		return
	if reloaded.layerIDs() != ["ground", "overlay", "height", "graph"]:
		_fail("layer order was not preserved: %s" % [reloaded.layerIDs()])
		return
	print("  ok    a grid layer and a list layer both survived, in declaration order")


func _checkCellAccess() -> void:
	print("-- cell access and layer sizing --")
	var data: WorldMapTileData = MapData.create("sizing", Vector2i(4, 3))
	if data.layerSize("ground") != Vector2i(4, 3):
		_fail("tile-grade layer is %s, expected (4, 3)" % data.layerSize("ground"))
		return
	# The cel grid is the tile grid times the fixed ratio -- the payoff of the tile law making
	# that ratio a constant rather than a per-region property.
	var expectedCel := Vector2i(4, 3) * Uniforms.CELS_PER_TILE
	if data.layerSize("overlay") != expectedCel:
		_fail("cel-grade layer is %s, expected %s" % [data.layerSize("overlay"), expectedCel])
		return
	if data.getCell("ground", Vector2i(0, 0)) != MapData.EMPTY:
		_fail("a new map's cells are not empty")
		return
	# Out of bounds reads are ordinary -- a brush dragged past the edge asks about them.
	if data.getCell("ground", Vector2i(99, 99)) != MapData.EMPTY:
		_fail("an out-of-bounds read did not return EMPTY")
		return
	if data.setCell("ground", Vector2i(99, 99), "t000"):
		_fail("an out-of-bounds write reported success")
		return
	# setCell returns whether anything changed, which is what lets a drag coalesce without
	# recording no-op strokes.
	if not data.setCell("ground", Vector2i(1, 1), "t000"):
		_fail("a real write reported no change")
		return
	if data.setCell("ground", Vector2i(1, 1), "t000"):
		_fail("rewriting the same value reported a change")
		return
	print("  ok    tile %s / cel %s, bounds respected, no-op writes report no change" % [
		data.layerSize("ground"), data.layerSize("overlay")
	])


## The catalog is exercised against a scratch file rather than the shipped `regions.json`, so an
## authored entry can be tested before the baker exists to give one a texture.
func _checkRegionKind() -> void:
	print("-- regions declare painted or authored --")
	var scratch := [
		{
			"NAME": "probe_painted", "KIND": "painted",
			"TEXTURE": "res://assets/worldmap/regions/temp2.png",
			"TILES_WIDE": 31, "TILES_TALL": 22, "GRID": 8,
		},
		{
			"NAME": "probe_authored", "KIND": "authored",
			"TEXTURE": "res://assets/worldmap/regions/generated/probe_authored.png",
			"TILES_WIDE": 15, "TILES_TALL": 11, "GRID": 16,
		},
	]
	var file := FileAccess.open(SCRATCH_REGIONS, FileAccess.WRITE)
	file.store_string(JSON.stringify(scratch, "\t"))
	file.close()

	if not RegionCatalog.reloadCatalog(SCRATCH_REGIONS):
		_fail("the scratch region catalog failed to load")
		RegionCatalog.reloadCatalog()
		return
	var painted := RegionCatalog.kindFor("probe_painted")
	var authored := RegionCatalog.kindFor("probe_authored")
	if painted != RegionCatalog.KIND_PAINTED or authored != RegionCatalog.KIND_AUTHORED:
		_fail("kinds read back as '%s' and '%s'" % [painted, authored])
	elif RegionCatalog.isAuthored("probe_painted") or not RegionCatalog.isAuthored("probe_authored"):
		_fail("isAuthored disagrees with kindFor")
	# An authored region with no bake yet must fail to load, and say why.
	elif not RegionCatalog.loadRegion("probe_authored").is_empty():
		_fail("an authored region loaded despite having no baked texture")
	else:
		print("  ok    both kinds parse; an unbaked authored region refuses to load")

	# A region declaring a kind that does not exist is refused outright rather than defaulted.
	var bad := [{
		"NAME": "probe_bad", "KIND": "sideways",
		"TEXTURE": "res://assets/worldmap/regions/temp2.png",
		"TILES_WIDE": 31, "TILES_TALL": 22, "GRID": 8,
	}]
	file = FileAccess.open(SCRATCH_REGIONS, FileAccess.WRITE)
	file.store_string(JSON.stringify(bad, "\t"))
	file.close()
	if RegionCatalog.reloadCatalog(SCRATCH_REGIONS):
		_fail("a region with an unknown KIND was accepted")
	else:
		print("  ok    an unknown KIND is refused rather than defaulted")

	RegionCatalog.reloadCatalog()


func _checkRealAuthoredRegion() -> void:
	print("-- the committed temp2_authored map --")
	var path: String = MapData.pathFor("temp2_authored")
	var data: WorldMapTileData = MapData.loadFrom(path)
	if data == null:
		_fail("could not load %s" % path)
		return
	if data.size_tiles != Vector2i(15, 11):
		_fail("expected 15 x 11 tiles, got %s" % data.size_tiles)
		return
	# Every ground cell must name a tile that the declared tileset actually holds. A map
	# referencing an id its tileset does not carry is exactly the corruption WME-4's stable ids
	# exist to prevent, so it is worth asserting the map is currently clean.
	var reference: Dictionary = TilesetCatalog.tilesetFor(str(data.layers["ground"]["TILESET"]))
	var known := {}
	for tile in reference.get("TILES", []):
		known[str((tile as Dictionary)["ID"])] = true
	var empty := 0
	var unknown := 0
	for y in 11:
		for x in 15:
			var id := data.getCell("ground", Vector2i(x, y))
			if id == MapData.EMPTY:
				empty += 1
			elif not known.has(id):
				unknown += 1
	if empty > 0 or unknown > 0:
		_fail("ground has %d empty and %d unknown-id cells of 165" % [empty, unknown])
		return
	print("  ok    165 ground cells, all naming tiles the temp2_ground ledger holds")


## The whole point of `KIND` defaulting to painted: nothing about how the existing regions load
## may change. Asserted against the real catalog, after the scratch one has been unloaded.
func _checkPaintedPathUnchanged() -> void:
	print("-- painted regions load exactly as before --")
	for id in ["temp", "temp2"]:
		var region := RegionCatalog.loadRegion(id)
		if region.is_empty():
			_fail("painted region '%s' failed to load" % id)
			return
		if str(region["kind"]) != RegionCatalog.KIND_PAINTED:
			_fail("region '%s' is not painted" % id)
			return
		if not (region["tiles"] is Vector2) or not (region["map_px"] is Vector2i):
			_fail("region '%s' changed the shape of its record" % id)
			return
	print("  ok    temp and temp2 both load, still painted, record shape unchanged")
