## AUTHORED WATER -- WMH-11. Lakes and simple river sections: which cells are wet, and what
## height each one's surface sits at. No flow, no simulation, no tide.
##
## WATER IS NOT A TERRAIN TYPE, which is the risk this item names and the reason for every shape
## below. A lowered basin is terrain; whether it holds water is a separate authored fact. Nothing
## here writes to a height layer and nothing in `WorldMapHeightField` reads this one, so a dry
## basin and a flooded one differ only in this layer -- and an author can express both.
##
## DRY IS NOT HEIGHT ZERO. The store is text (`WorldMapTileData.KIND_WATER`), because a dense
## float array cannot say "dry" without inventing a sentinel, and a map whose ground sits at 0
## would then be indistinguishable from one flooded to 0. `EMPTY` is already this format's word
## for "nothing here"; dryness is spelled the way absence is spelled everywhere else.
##
## ONE VALUE PER CELL, not per vertex. The terrain is a vertex lattice because a hillside is
## continuous; a water surface is not -- it is flat across a body and steps between bodies. A
## lake stays level because every cell in it was given the same height, and a river descends
## because each cell was given a lower one. That is also why there is no interpolation here: a
## water surface that sloped between neighbouring cells could not be flat by construction.
##
## THE LOOK IS THE REGION'S OWN SEA. `void_color` is already what lies beyond the map's edge --
## `WorldMapGroundUniforms` is explicit that it belongs to the place, not the framing: temp's sea
## is deep blue, temp2's teal -- and the shore tint is that colour carried toward the region's own
## `fog_color`. So an authored lake and the ocean past the map edge are the same water, and no
## colour was imported from anywhere.
class_name WorldMapWaterLayer
extends RefCounted

const MapData = preload("res://src/presentation/worldmap/editor/WorldMapTileData.gd")
const HeightField = preload("res://src/presentation/worldmap/editor/WorldMapHeightField.gd")
const HexGrid = preload("res://src/presentation/worldmap/editor/WorldMapHexGrid.gd")

## The layer water lives in unless told otherwise.
const DEFAULT_LAYER := "water"

## How deep water has to be before it reads as open water rather than shallows. The shoreline
## band is the interpolation across this distance, and it is a LOOK constant, not a physical one:
## at 0.75 world units a band is roughly half a hex wide on the gentle slopes WMH-8's smoothing
## produces, which is wide enough to read at pitch 60 and narrow enough not to swallow a pond.
const SHORE_DEPTH := 0.75

## How far the shore tint carries the sea colour toward the region's haze. Enough to draw a
## contour, short of turning the shallows into fog.
const SHORE_MIX := 0.45


## Ensures a water layer exists, sized for this map's lattice, and returns its block. A map
## gains one dry -- adding water to a document changes nothing about how it renders until a cell
## is actually flooded.
static func ensureLayer(data: WorldMapTileData, layerID := DEFAULT_LAYER) -> Dictionary:
	if data.layers.has(layerID):
		return data.layers[layerID]
	data.addWaterLayer(layerID)
	return data.layers[layerID]


static func has(data: WorldMapTileData, layerID := DEFAULT_LAYER) -> bool:
	return (
		data.layers.has(layerID)
		and str((data.layers[layerID] as Dictionary).get("KIND", "")) == MapData.KIND_WATER
	)


static func isWet(data: WorldMapTileData, cell: Vector2i, layerID := DEFAULT_LAYER) -> bool:
	return data.getWater(layerID, cell) != MapData.EMPTY


## The height this cell's water surface sits at. Meaningless for a dry cell, which is why callers
## ask `isWet` first -- returning 0.0 here is a value, not an answer, and treating it as one is
## exactly the confusion `EMPTY` exists to prevent.
static func surfaceAt(data: WorldMapTileData, cell: Vector2i, layerID := DEFAULT_LAYER) -> float:
	var stored := data.getWater(layerID, cell)
	return 0.0 if stored == MapData.EMPTY else float(stored)


## Floods one cell to `height`. Stored through `WorldMapTileData._heightsAsStrings`' own rule so
## a whole number writes as `2` rather than `2.0000` and a flat lake's runs stay short.
static func setSurface(
	data: WorldMapTileData, cell: Vector2i, height: float, layerID := DEFAULT_LAYER
) -> bool:
	ensureLayer(data, layerID)
	return data.setWater(layerID, cell, _heightText(height))


static func dry(data: WorldMapTileData, cell: Vector2i, layerID := DEFAULT_LAYER) -> bool:
	if not has(data, layerID):
		return false
	return data.setWater(layerID, cell, MapData.EMPTY)


static func _heightText(height: float) -> String:
	return (
		str(int(round(height))) if is_equal_approx(height, round(height))
		else "%.4f" % height
	)


## Every wet cell, in cell order. The list a mesh, an export or a clearance check walks.
static func wetCells(data: WorldMapTileData, layerID := DEFAULT_LAYER) -> Array[Vector2i]:
	var out: Array[Vector2i] = []
	if not has(data, layerID):
		return out
	for row in data.size_tiles.y:
		for col in data.size_tiles.x:
			var cell := Vector2i(col, row)
			if isWet(data, cell, layerID):
				out.append(cell)
	return out


static func wetCount(data: WorldMapTileData, layerID := DEFAULT_LAYER) -> int:
	return wetCells(data, layerID).size()


## How deep the water is over a point of terrain: surface minus ground. Negative where the ground
## stands above the water line, which is what makes an island in a lake expressible without any
## separate notion of one.
static func depthAt(
	data: WorldMapTileData, cell: Vector2i, local: Vector2,
	layerID := DEFAULT_LAYER, heightsLayer := HeightField.DEFAULT_LAYER
) -> float:
	if not isWet(data, cell, layerID):
		return 0.0
	var ground := (
		HeightField.sample(data, local, heightsLayer)
		if HeightField.has(data, heightsLayer) else 0.0
	)
	return surfaceAt(data, cell, layerID) - ground


## The water surface, as one fan per wet cell -- the same six triangles WMH-8 fans a hex into and
## WMH-10 paints detail onto, so water, terrain and detail all cut a hex the same way.
##
## Every vertex of a cell sits at THAT CELL'S surface height, so two neighbouring cells flooded to
## different heights meet at a visible step rather than being smoothed into a slope. That is the
## whole difference between a river that descends and a river that leaks uphill, and it is why
## this mesh does not share vertices between cells the way the terrain mesh does.
##
## Vertex colours carry the shoreline: `void_color` in open water, mixed toward `fog_color` as the
## ground rises to meet the surface. The material reads them as albedo and is unshaded, so the
## band costs no shader and no texture -- see the class note on why these two colours.
static func buildSurfaceMesh(
	data: WorldMapTileData, layerID := DEFAULT_LAYER,
	heightsLayer := HeightField.DEFAULT_LAYER
) -> ArrayMesh:
	var cells := wetCells(data, layerID)
	if cells.is_empty():
		return null

	var deep := data.void_color
	var shore := deep.lerp(data.fog_color, SHORE_MIX)
	var positions := PackedVector3Array()
	var colors := PackedColorArray()
	var indices := PackedInt32Array()

	for cell in cells:
		var surface := surfaceAt(data, cell, layerID)
		var centre: Vector2 = HexGrid.cellCentre(cell)
		var base := positions.size()
		positions.append(Vector3(centre.x, surface, centre.y))
		colors.append(_shoreColor(data, cell, centre, surface, deep, shore, layerID, heightsLayer))
		for i in HeightField.CORNER_OFFSETS.size():
			var corner: Vector2 = centre + HeightField.CORNER_OFFSETS[i]
			positions.append(Vector3(corner.x, surface, corner.y))
			colors.append(
				_shoreColor(data, cell, corner, surface, deep, shore, layerID, heightsLayer)
			)
		for i in HeightField.CORNER_OFFSETS.size():
			var a := base + 1 + i
			var b := base + 1 + (i + 1) % HeightField.CORNER_OFFSETS.size()
			# Wound so the surface faces up, matching the terrain mesh and a PlaneMesh.
			indices.append(base)
			indices.append(b)
			indices.append(a)

	var arrays := []
	arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX] = positions
	arrays[Mesh.ARRAY_COLOR] = colors
	arrays[Mesh.ARRAY_INDEX] = indices
	var mesh := ArrayMesh.new()
	mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
	return mesh


static func _shoreColor(
	data: WorldMapTileData, cell: Vector2i, local: Vector2, surface: float,
	deep: Color, shore: Color, layerID: String, heightsLayer: String
) -> Color:
	var ground := (
		HeightField.sample(data, local, heightsLayer)
		if HeightField.has(data, heightsLayer) else 0.0
	)
	var depth := surface - ground
	return shore.lerp(deep, clampf(depth / SHORE_DEPTH, 0.0, 1.0))


## The material the surface is drawn with: unshaded, vertex-coloured, no shadows. The ground is
## unlit art and so is this -- a lit water plane over an unlit map would be the one surface in
## the scene reacting to a sun nothing else knows about.
static func buildMaterial() -> StandardMaterial3D:
	var material := StandardMaterial3D.new()
	material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	material.vertex_color_use_as_albedo = true
	# WITHOUT THIS the sea renders visibly paler than the same colour drawn past the map's edge.
	# `void_color` and `fog_color` are sRGB -- they come from the region catalog as hex -- and a
	# vertex colour is taken as LINEAR unless a material says otherwise, so the identical value
	# comes out brightened. Found by looking: an authored lake and the ocean beyond the edge are
	# meant to be the same water, and in the first render they plainly were not.
	material.vertex_color_is_srgb = true
	material.cull_mode = BaseMaterial3D.CULL_DISABLED
	return material
