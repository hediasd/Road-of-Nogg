## WMH-11's self-contained validation: authored water coverage and surface height round-trip
## through save and export, and a basin with no water stays dry.
##
## THE LAST CHECK IS THE ITEM'S NAMED RISK, and it is the reason several of the others exist:
## water quietly becoming a terrain type would make "a lowered basin nobody flooded" impossible
## to express. So this file checks both halves of that separately -- a deep basin is dry unless
## flooded, AND a cell flooded to exactly 0.0 over flat ground is wet. If "dry" and "height zero"
## were the same value, the second check is the one that would fail.
##
## The re-save comparison is here because of Gate 3: `WorldMapTileData.saveTo` promises a
## byte-identical file for an unchanged document, and the object layer broke that promise for
## four items without anything noticing. A fifth layer kind gets the check on its first day.

extends SceneTree

const MapData = preload("res://src/presentation/worldmap/editor/WorldMapTileData.gd")
const Water = preload("res://src/presentation/worldmap/editor/WorldMapWaterLayer.gd")
const SceneExport = preload("res://src/presentation/worldmap/editor/WorldMapSceneExport.gd")

const TEST_NAME := "_probe_water_layer_test"
const LATTICE := Vector2i(11, 8)

var _failures := 0


func _initialize() -> void:
	_cleanup()
	_checkDryIsNotZero()
	_checkBasinWithoutWaterStaysDry()
	_checkLakeIsFlatAndRiverSteps()
	_checkRoundTrip()
	_checkSurfaceMesh()
	_checkShorelineBand()
	_checkExport()
	_cleanup()

	print("")
	print("probe_water_layer: %s" % ("PASS" if _failures == 0 else "%d FAILURE(S)" % _failures))
	if _failures == 0:
		print("WORLD MAP WATER LAYER OK")
	quit(1 if _failures > 0 else 0)


func _fail(message: String) -> void:
	_failures += 1
	print("  FAIL  %s" % message)


func _ok(message: String) -> void:
	print("  ok    %s" % message)


func _cleanup() -> void:
	for path in [MapData.pathFor(TEST_NAME), MapData.pathFor(TEST_NAME + "_resave")]:
		if FileAccess.file_exists(path):
			DirAccess.remove_absolute(ProjectSettings.globalize_path(path))


func _newMap() -> WorldMapTileData:
	var data := MapData.create(TEST_NAME, LATTICE, MapData.LAYOUT_HEX_FLAT)
	data.layers["ground"]["TILESET"] = "temp2_hex32_ground"
	data.void_color = Color("37aeae")
	data.fog_color = Color("bae8e2")
	return data


## Dry and flooded-to-zero are different states. The whole risk this item names lives in this
## check: if water were stored as a float with 0 meaning "none", a lake at sea level would be
## indistinguishable from no lake at all.
func _checkDryIsNotZero() -> void:
	print("-- a cell flooded to 0.0 is wet; an untouched cell is dry --")
	var data := _newMap()
	Water.ensureLayer(data)
	var flooded := Vector2i(2, 2)
	var untouched := Vector2i(5, 5)
	Water.setSurface(data, flooded, 0.0)
	if not Water.isWet(data, flooded):
		_fail("a cell flooded to 0.0 reads dry")
		return
	if Water.isWet(data, untouched):
		_fail("an untouched cell reads wet")
		return
	if not is_equal_approx(Water.surfaceAt(data, flooded), 0.0):
		_fail("the flooded cell's surface reads %.3f" % Water.surfaceAt(data, flooded))
		return
	if not Water.dry(data, flooded) or Water.isWet(data, flooded):
		_fail("drying the cell did not return it to dry")
		return
	_ok("0.0 is a height, EMPTY is dryness, and they are not the same value")


## The item's risk, stated as terrain: sculpting a basin must not flood it.
func _checkBasinWithoutWaterStaysDry() -> void:
	print("-- a sculpted basin nobody flooded stays dry --")
	var data := _newMap()
	WorldMapHeightField.ensureLayer(data)
	var basin := WorldMapBrushes.discCells(Vector2i(5, 4), 2)
	WorldMapHeightField.flatten(data, basin, -2.0)
	if WorldMapHeightField.centreHeight(data, Vector2i(5, 4)) > -1.5:
		_fail("test setup: the basin is not actually lowered")
		return
	Water.ensureLayer(data)
	if Water.wetCount(data) != 0:
		_fail("a basin with no authored water reports %d wet cells" % Water.wetCount(data))
		return
	if Water.buildSurfaceMesh(data) != null:
		_fail("a map with no wet cell still built a water surface")
		return
	_ok("a 2.0-deep basin holds no water until something says it does")


func _checkLakeIsFlatAndRiverSteps() -> void:
	print("-- a lake is level, a river descends --")
	var data := _newMap()
	Water.ensureLayer(data)
	var lake := WorldMapBrushes.discCells(Vector2i(3, 3), 2)
	for cell in lake:
		Water.setSurface(data, cell, 1.5)
	var levels := {}
	for cell in lake:
		levels[Water.surfaceAt(data, cell)] = true
	if levels.size() != 1:
		_fail("a lake painted at one height reports %d distinct levels" % levels.size())
		return

	var river := [Vector2i(8, 1), Vector2i(8, 2), Vector2i(8, 3), Vector2i(8, 4)]
	for i in river.size():
		Water.setSurface(data, river[i], 3.0 - 0.5 * float(i))
	for i in range(1, river.size()):
		var above := Water.surfaceAt(data, river[i - 1])
		var below := Water.surfaceAt(data, river[i])
		if below >= above:
			_fail("river step %d did not descend: %.2f then %.2f" % [i, above, below])
			return
	_ok("%d lake cells at one level; a %d-cell river steps down without interpolating"
		% [lake.size(), river.size()])


func _checkRoundTrip() -> void:
	print("-- coverage and heights survive a save, a reload and a re-save --")
	var data := _newMap()
	Water.ensureLayer(data)
	for cell in WorldMapBrushes.discCells(Vector2i(4, 4), 2):
		Water.setSurface(data, cell, 1.25)
	Water.setSurface(data, Vector2i(9, 6), -0.5)
	var wet := Water.wetCount(data)

	var path := MapData.pathFor(TEST_NAME)
	if not data.saveTo(path):
		_fail("could not save the water map")
		return
	var reopened := MapData.loadFrom(path)
	if reopened == null:
		_fail("could not reload the water map")
		return
	if reopened.toDictionary() != data.toDictionary():
		_fail("reloading did not reproduce the document")
		return
	if Water.wetCount(reopened) != wet:
		_fail("reloaded map has %d wet cells, expected %d" % [Water.wetCount(reopened), wet])
		return
	if not is_equal_approx(Water.surfaceAt(reopened, Vector2i(9, 6)), -0.5):
		_fail("a negative surface height did not survive: %.3f"
			% Water.surfaceAt(reopened, Vector2i(9, 6)))
		return

	var first := FileAccess.get_file_as_string(path)
	var scratch := MapData.pathFor(TEST_NAME + "_resave")
	reopened.saveTo(scratch)
	var second := FileAccess.get_file_as_string(scratch)
	if first != second:
		_fail("re-saving an unchanged water map rewrote it (%d -> %d bytes)"
			% [first.length(), second.length()])
		return
	_ok("%d wet cells round-tripped, negative heights included, and the re-save is byte-equal"
		% wet)


func _checkSurfaceMesh() -> void:
	print("-- the surface sits at the authored height, not at the terrain's --")
	var data := _newMap()
	WorldMapHeightField.ensureLayer(data)
	var basin := WorldMapBrushes.discCells(Vector2i(5, 4), 2)
	WorldMapHeightField.flatten(data, basin, -2.0)
	Water.ensureLayer(data)
	for cell in basin:
		Water.setSurface(data, cell, -0.5)

	var mesh := Water.buildSurfaceMesh(data)
	if mesh == null:
		_fail("a flooded basin built no water surface")
		return
	var arrays := mesh.surface_get_arrays(0)
	var positions: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
	if positions.is_empty():
		_fail("the water surface has no vertices")
		return
	for point in positions:
		if not is_equal_approx(point.y, -0.5):
			_fail("a water vertex sits at %.3f, expected the authored -0.5" % point.y)
			return
	# Seven vertices per wet cell: the hex centre plus its six corners, one fan each.
	if positions.size() != basin.size() * 7:
		_fail("%d wet cells produced %d vertices, expected %d"
			% [basin.size(), positions.size(), basin.size() * 7])
		return
	if WorldMapHeightField.centreHeight(data, Vector2i(5, 4)) > -1.5:
		_fail("the terrain under the water moved")
		return
	_ok("%d cells of water flat at -0.5 over ground at -2.0" % basin.size())


## The look the user chose: sea colour in open water, carried toward the region's haze as the
## ground rises to meet the surface. Checked as an ordering rather than as exact colours -- the
## claim is that depth drives the tint, not that it drives it by a particular amount.
func _checkShorelineBand() -> void:
	print("-- the shoreline reads as a band, and it comes from the region's own colours --")
	var data := _newMap()
	WorldMapHeightField.ensureLayer(data)
	# A ramp: deep at one end, breaking the surface at the other.
	var deepCell := Vector2i(3, 4)
	var shallowCell := Vector2i(6, 4)
	WorldMapHeightField.flatten(data, [deepCell], -3.0)
	WorldMapHeightField.flatten(data, [shallowCell], -0.05)
	Water.ensureLayer(data)
	for cell in [deepCell, shallowCell]:
		Water.setSurface(data, cell, 0.0)

	var mesh := Water.buildSurfaceMesh(data)
	var arrays := mesh.surface_get_arrays(0)
	var colors: PackedColorArray = arrays[Mesh.ARRAY_COLOR]
	if colors.is_empty():
		_fail("the water surface carries no vertex colours")
		return
	# Vertex 0 is the first wet cell's centre, in cell order: (3,4) comes before (6,4).
	var overDeep := colors[0]
	var overShallow := colors[7]
	var sea := data.void_color
	var haze := data.fog_color
	if overDeep.get_luminance() >= overShallow.get_luminance():
		_fail("the shallow end is not lighter than the deep end (%.3f vs %.3f)"
			% [overShallow.get_luminance(), overDeep.get_luminance()])
		return
	# Open water is the region's sea exactly -- the shore tint is a departure from it, not a
	# separate palette.
	if not overDeep.is_equal_approx(sea):
		_fail("open water is %s, not the region's own sea %s" % [overDeep, sea])
		return
	var expectedShore := sea.lerp(haze, Water.SHORE_MIX)
	if overShallow.get_luminance() > expectedShore.get_luminance() + 0.001:
		_fail("the shallows overshoot the shore tint")
		return
	_ok("open water is the region's sea %s; shallows carry it toward the haze" % sea.to_html(false))


func _checkExport() -> void:
	print("-- a wet map exports a Water node; a dry one exports none --")
	var dryMap := _newMap()
	Water.ensureLayer(dryMap)
	var dryRoot := Node3D.new()
	if SceneExport.buildWater(dryRoot, dryMap, null) != null:
		_fail("a map with a water layer but no wet cell exported a Water node")
		dryRoot.free()
		return
	if dryRoot.get_child_count() != 0:
		_fail("a dry map added %d children" % dryRoot.get_child_count())
		dryRoot.free()
		return
	dryRoot.free()

	var wetMap := _newMap()
	Water.ensureLayer(wetMap)
	for cell in WorldMapBrushes.discCells(Vector2i(5, 4), 1):
		Water.setSurface(wetMap, cell, 0.75)
	var wetRoot := Node3D.new()
	var node := SceneExport.buildWater(wetRoot, wetMap, null)
	if node == null:
		_fail("a wet map exported no Water node")
		wetRoot.free()
		return
	if node.name != "Water":
		_fail("the water node is named '%s'" % node.name)
		wetRoot.free()
		return
	var material := node.material_override as StandardMaterial3D
	if material == null or not material.vertex_color_use_as_albedo:
		_fail("the water material does not read its vertex colours")
		wetRoot.free()
		return
	if material.shading_mode != BaseMaterial3D.SHADING_MODE_UNSHADED:
		_fail("the water material is lit while the map it sits on is not")
		wetRoot.free()
		return
	# A defect this file could not see until someone looked at a render: `void_color` is sRGB, a
	# vertex colour is taken as LINEAR unless the material says otherwise, and the first build
	# drew an authored lake visibly paler than the identical colour past the map's edge. Every
	# colour assertion above passed throughout, because they check the stored value and the bug
	# was in how it was interpreted. Asserted here so the fix cannot be undone silently.
	if not material.vertex_color_is_srgb:
		_fail("water vertex colours are not marked sRGB; the sea will render paler than the void")
		wetRoot.free()
		return
	if node.cast_shadow != GeometryInstance3D.SHADOW_CASTING_SETTING_OFF:
		_fail("the water casts shadows")
		wetRoot.free()
		return
	wetRoot.free()
	_ok("dry maps export nothing; a wet one exports one unshaded, vertex-coloured Water node")
