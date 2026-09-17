## WME-1's self-contained validation: the tile law holds, and nothing reads a per-region tile
## size as a world quantity any more.
##
## Three assertions, in the order they can fail:
##
##  1. GREP AUDIT. No file under `src/` reaches for a per-region tile size. This is the check
##     that actually enforces the law -- the other two only observe its consequences, and a
##     stale divisor left in one place would still produce plausible output everywhere else.
##  2. DERIVED EXTENT. A region's world size is its pixel size over 16, whatever grid its art
##     was drawn on. temp is unchanged at 48x64; temp2 is 15.5x11 rather than the 31x22 it
##     declares in blocks.
##  3. TILE CENTRING. Every structure's foot lands on the centre of a 16 px tile, on both axes.
##     Before this item, temp2's nine snapped to 8 px centres, half of which are the boundary
##     between two walk tiles -- buildings standing on tile lines, which is the exact defect
##     WORLDMAP_DESIGN.md section 9 was written to remove.

extends SceneTree

const Uniforms = preload("res://src/presentation/worldmap/WorldMapGroundUniforms.gd")
const RegionCatalog = preload("res://src/presentation/worldmap/WorldMapRegionCatalog.gd")
const FramingCatalog = preload("res://src/presentation/worldmap/WorldMapFramingCatalog.gd")

## Spellings that meant "this region's tile size in pixels". Each was a world quantity, and the
## law leaves no legitimate use for any of them in shipping code.
const FORBIDDEN := ["tilePixelsFor", "DEFAULT_TILE_PIXELS", "\"tile_pixels\"", "_tilePixels"]

## The one place the art grid is still allowed to be read, and only to size the texture check.
const GRID_READER := "res://src/presentation/worldmap/WorldMapRegionCatalog.gd"

var _failures := 0


func _initialize() -> void:
	_auditSources()
	_checkExtents()
	await _checkCentring()
	print("")
	print("probe_tile_law: %s" % ("PASS" if _failures == 0 else "%d FAILURE(S)" % _failures))
	if _failures == 0:
		print("WORLD MAP TILE LAW OK")
	quit(1 if _failures > 0 else 0)


func _fail(message: String) -> void:
	_failures += 1
	print("  FAIL  %s" % message)


func _auditSources() -> void:
	print("-- grep audit over src/ --")
	var hits := 0
	for path in _gdFilesUnder("res://src"):
		var text := FileAccess.get_file_as_string(path)
		if text.is_empty():
			continue
		for token in FORBIDDEN:
			if text.find(token) >= 0:
				_fail("%s still contains %s" % [path, token])
				hits += 1
		# GRID is a per-region art property. It may size the texture check and nothing else, so
		# only the catalog is allowed to name it at all.
		if text.find("\"GRID\"") >= 0 and path != GRID_READER:
			_fail("%s reads the art GRID; only the catalog may" % path)
			hits += 1
	if hits == 0:
		print("  ok    no source reads a per-region tile size")


func _gdFilesUnder(root: String) -> PackedStringArray:
	var found := PackedStringArray()
	var pending := [root]
	while not pending.is_empty():
		var dir: String = pending.pop_back()
		for name in DirAccess.get_directories_at(dir):
			pending.append("%s/%s" % [dir, name])
		for name in DirAccess.get_files_at(dir):
			if name.ends_with(".gd"):
				found.append("%s/%s" % [dir, name])
	return found


func _checkExtents() -> void:
	print("-- derived world extent --")
	for id in RegionCatalog.ids():
		var region := RegionCatalog.loadRegion(id)
		if region.is_empty():
			_fail("region '%s' failed to load" % id)
			continue
		var tiles: Vector2 = region["tiles"]
		var mapPx: Vector2i = region["map_px"]
		var expected := Vector2(mapPx) / float(Uniforms.TILE_PIXELS)
		if not tiles.is_equal_approx(expected):
			_fail("region '%s' is %s tiles but %s px says %s" % [id, tiles, mapPx, expected])
			continue
		print("  ok    %-6s %s px -> %s walk tiles" % [id, mapPx, tiles])


## The foot of a structure must sit on a tile CENTRE, which in map pixels is an odd multiple of
## half a tile: `(y + h) % 16 == 8`, and the same for the sprite's horizontal midpoint.
func _checkCentring() -> void:
	print("-- structures stand on tile centres --")
	var tile := Uniforms.TILE_PIXELS
	var half := tile / 2
	var viewport := SubViewport.new()
	viewport.own_world_3d = true
	viewport.size = Vector2i(640, 360)
	root.add_child(viewport)
	var map: Node3D = load("res://scenes/WorldMap.tscn").instantiate()
	viewport.add_child(map)
	var ground: WorldMapGround = map.get_node("Ground")
	var props: WorldMapProps = map.get_node("Props")

	for id in RegionCatalog.ids():
		var region := RegionCatalog.loadRegion(id)
		if region.is_empty():
			continue
		var framing := FramingCatalog.framingFor(FramingCatalog.OVERLAND).duplicate(true)
		var built := props.rebuild(region["texture"], id, Uniforms.BILLBOARD_FACE)
		ground.configure(
			region["tiles"], built["ground"], framing, region["fog_color"], region["void_color"]
		)
		await process_frame
		var count: int = built["count"]
		if count == 0:
			print("  ok    %-6s declares no structures" % id)
			continue
		var offCentre := 0
		for i in props.structureCount():
			var s: Dictionary = props.structureAt(i)
			var foot: int = int(s["y"]) + int(s["h"])
			var midX: int = int(s["x"]) + int(s["w"]) / 2
			if foot % tile != half or midX % tile != half:
				offCentre += 1
		if offCentre > 0:
			_fail("%s: %d of %d structures are off the tile centre" % [id, offCentre, count])
		else:
			print("  ok    %-6s all %d structures on tile centres" % [id, count])
	viewport.queue_free()
