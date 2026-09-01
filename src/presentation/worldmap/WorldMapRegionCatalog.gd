## Named world map regions: a texture plus the tile dimensions it is authored at.
##
## Follows the same JSON-catalog shape as `ElementReferences` / `ArchetypeReferences`,
## through the shared `JsonCatalogLoader`. The one thing specific to this catalog is
## `loadRegion()`'s dimension check: `WorldMapCameraRig`'s tiles-across and
## region-tiles-needed readouts are only honest if TILES_WIDE/TILES_TALL actually match
## the texture, so a mismatch fails loudly instead of silently rendering a stretched or
## clipped region.

class_name WorldMapRegionCatalog
extends RefCounted

const JSON_PATH := "res://data/worldmap/regions.json"
const JsonCatalogLoaderScript = preload("res://src/factories/JsonCatalogLoader.gd")
const Uniforms = preload("res://src/presentation/worldmap/WorldMapGroundUniforms.gd")

static var list: Array = []
static var _index: Dictionary = {}


static func _static_init() -> void:
	reloadCatalog()


static func reloadCatalog(path: String = JSON_PATH) -> bool:
	var loaded := JsonCatalogLoaderScript.loadNamedCatalog(path)
	if not loaded["success"]:
		push_warning("WorldMapRegionCatalog: %s" % loaded["error"])
		return false

	var newList: Array = []
	var newIndex: Dictionary = {}
	for reference in loaded["list"]:
		var nameKey := str(reference["NAME"])
		var texturePath := str(reference.get("TEXTURE", ""))
		var tilesWide := int(reference.get("TILES_WIDE", 0))
		var tilesTall := int(reference.get("TILES_TALL", 0))
		# Tile pixel size varies per region -- some art is drawn on an 8 px grid, some 16.
		var tilePixels := int(reference.get("TILE_PIXELS", Uniforms.DEFAULT_TILE_PIXELS))
		if texturePath.is_empty() or tilesWide <= 0 or tilesTall <= 0 or tilePixels <= 0:
			push_warning("WorldMapRegionCatalog: invalid entry '%s'" % nameKey)
			return false
		reference["TILES"] = Vector2i(tilesWide, tilesTall)
		reference["TILE_PIXELS"] = tilePixels
		# What lies beyond the edge, and the haze the map fades into, belong to the place.
		# Defaulted rather than required so an older entry still loads.
		reference["FOG_COLOR"] = Color(str(reference.get("FOG_COLOR", "cfe9f5")))
		reference["VOID_COLOR"] = Color(str(reference.get("VOID_COLOR", "000000")))
		newList.append(reference)
		newIndex[nameKey] = reference

	list = newList
	_index = newIndex
	return true


static func ids() -> Array[String]:
	var result: Array[String] = []
	for reference in list:
		result.append(str(reference["NAME"]))
	return result


static func has(regionID: String) -> bool:
	return _index.has(regionID)


static func description(regionID: String) -> String:
	if not _index.has(regionID):
		return ""
	return str(_index[regionID].get("DESCRIPTION", ""))


static func fogColorFor(regionID: String) -> Color:
	if not _index.has(regionID):
		return Color("cfe9f5")
	return _index[regionID]["FOG_COLOR"]


static func voidColorFor(regionID: String) -> Color:
	if not _index.has(regionID):
		return Color.BLACK
	return _index[regionID]["VOID_COLOR"]


static func tilePixelsFor(regionID: String) -> int:
	if not _index.has(regionID):
		return Uniforms.DEFAULT_TILE_PIXELS
	return _index[regionID]["TILE_PIXELS"]


static func tilesFor(regionID: String) -> Vector2i:
	if not _index.has(regionID):
		return Vector2i.ZERO
	return _index[regionID]["TILES"]


## Loads the region's texture and validates it against the catalog's declared tile
## dimensions. Returns `{}` on any failure -- unknown id, missing texture, or a size
## mismatch -- logging the reason via `push_warning` in each case, so a caller can test
## with a single emptiness check without needing three different error paths.
static func loadRegion(regionID: String) -> Dictionary:
	if not _index.has(regionID):
		push_warning("WorldMapRegionCatalog: unknown region '%s'" % regionID)
		return {}

	var reference: Dictionary = _index[regionID]
	var texturePath := str(reference["TEXTURE"])
	var texture := ResourceLoader.load(texturePath) as Texture2D
	if texture == null:
		push_warning(
			"WorldMapRegionCatalog: could not load texture at %s for region '%s'"
			% [texturePath, regionID]
		)
		return {}

	var tiles: Vector2i = reference["TILES"]
	var tilePixels: int = reference["TILE_PIXELS"]
	var expected := Vector2(tiles.x * tilePixels, tiles.y * tilePixels)
	if texture.get_size() != expected:
		push_warning(
			(
				"WorldMapRegionCatalog: region '%s' texture is %s px but TILES_WIDE/"
				+ "TILES_TALL/TILE_PIXELS declare %s tiles of %d px (%s px)"
			)
			% [regionID, texture.get_size(), tiles, tilePixels, expected]
		)
		return {}

	return {
		"id": regionID,
		"texture": texture,
		"tiles": tiles,
		"tile_pixels": tilePixels,
		"fog_color": reference["FOG_COLOR"],
		"void_color": reference["VOID_COLOR"],
	}
