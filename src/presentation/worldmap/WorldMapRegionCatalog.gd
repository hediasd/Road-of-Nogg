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
		if texturePath.is_empty() or tilesWide <= 0 or tilesTall <= 0:
			push_warning("WorldMapRegionCatalog: invalid entry '%s'" % nameKey)
			return false
		reference["TILES"] = Vector2i(tilesWide, tilesTall)
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
	var expected := Vector2(tiles.x * Uniforms.TILE_PIXELS, tiles.y * Uniforms.TILE_PIXELS)
	if texture.get_size() != expected:
		push_warning(
			(
				"WorldMapRegionCatalog: region '%s' texture is %s px but TILES_WIDE/"
				+ "TILES_TALL declare %s tiles (%s px)"
			)
			% [regionID, texture.get_size(), tiles, expected]
		)
		return {}

	return {
		"id": regionID,
		"texture": texture,
		"tiles": tiles,
	}
