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

## What a region's truth IS. A painted region is its PNG; an authored region is its tile data,
## and its PNG is baked from that. See the `KIND` note in `reloadCatalog`.
const KIND_PAINTED := "painted"
const KIND_AUTHORED := "authored"

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
		var blocksWide := int(reference.get("TILES_WIDE", 0))
		var blocksTall := int(reference.get("TILES_TALL", 0))
		# The grid the ART was drawn on, which is NOT the walk grid and never sizes the world.
		# It exists so the texture-size check below can be expressed in the units the artist
		# actually worked in; `temp2` is 31 x 22 blocks of 8 px, and saying so is how the check
		# stays readable. `TILE_PIXELS` is accepted as the old spelling so an unmigrated entry
		# still loads.
		var grid := int(reference.get("GRID", reference.get("TILE_PIXELS", Uniforms.TILE_PIXELS)))
		if texturePath.is_empty() or blocksWide <= 0 or blocksTall <= 0 or grid <= 0:
			push_warning("WorldMapRegionCatalog: invalid entry '%s'" % nameKey)
			return false
		reference["ART_BLOCKS"] = Vector2i(blocksWide, blocksTall)
		reference["GRID"] = grid
		# PAINTED or AUTHORED. A painted region is a hand-drawn PNG and is the truth about
		# itself -- `temp` and `temp2` are painted and nothing about how they load changes. An
		# authored region's truth is its tile data under `data/worldmap/authored/`, and its
		# TEXTURE is a BUILD ARTIFACT baked from that data: generated, never hand-edited, and
		# regenerable from the source alone. Defaulted to painted so every existing entry keeps
		# its behaviour without being touched.
		var kind := str(reference.get("KIND", KIND_PAINTED))
		if kind != KIND_PAINTED and kind != KIND_AUTHORED:
			push_warning(
				"WorldMapRegionCatalog: region '%s' has unknown KIND '%s'" % [nameKey, kind]
			)
			return false
		reference["KIND"] = kind
		# The world extent, and the only size anything downstream is allowed to use. A map pixel
		# is worth 1/TILE_PIXELS of a unit no matter what grid the art was drawn on, so a region
		# of 8 px blocks covers half the ground its block count suggests. This is deliberately a
		# float: `temp2` is 248 px wide, which is 15.5 walk tiles, and rounding that would either
		# stretch the art or drop a strip of it.
		reference["TILES"] = (
			Vector2(float(blocksWide), float(blocksTall)) * float(grid) / float(Uniforms.TILE_PIXELS)
		)
		# What lies beyond the edge, and the haze the map fades into, belong to the place.
		# Defaulted rather than required so an older entry still loads.
		reference["FOG_COLOR"] = Color(str(reference.get("FOG_COLOR", "cfe9f5")))
		reference["VOID_COLOR"] = Color(str(reference.get("VOID_COLOR", "000000")))
		reference["STRUCTURES"] = _structureRule(reference.get("STRUCTURES", {}))
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


## The region a scene opens on when none is named. Explicit rather than "whichever entry
## happens to be first", so reordering the file cannot silently change it.
static func defaultRegion() -> String:
	for reference in list:
		if bool(reference.get("DEFAULT", false)):
			return str(reference["NAME"])
	return str(list[0]["NAME"]) if list.size() > 0 else ""


## How a region's structures are told apart from its terrain, as data rather than as
## constants in `WorldMapProps`. A region whose palette gives buildings their own colours can
## declare them here and be found without a code change; one that omits the block declares
## that it has no findable structures, which is the honest default for a dithered map where
## no colour is exclusive to anything.
##
## The tolerances are load-bearing and deliberately not equality: the PNG round-trips through
## import, so a colour comes back near its authored value rather than on it.
static func _structureRule(raw: Variant) -> Dictionary:
	var source: Dictionary = raw if raw is Dictionary else {}
	var keys: Array[Color] = []
	for entry in source.get("KEY_COLORS", []):
		keys.append(Color(str(entry)))
	var doors: Array[Color] = []
	for entry in source.get("DOOR_COLORS", []):
		doors.append(Color(str(entry)))
	var emissive: Array[Color] = []
	for entry in source.get("EMISSIVE_COLORS", []):
		emissive.append(Color(str(entry)))
	var neighbourRaw := str(source.get("EMISSIVE_NEIGHBOUR", ""))
	var neighbour: Variant = Color(neighbourRaw) if not neighbourRaw.is_empty() else null
	return {
		"KEY_COLORS": keys,
		# Channel distance in 0-255, matching how the colours are written in the JSON.
		"KEY_TOLERANCE": float(source.get("KEY_TOLERANCE", 45.0)),
		# Colours that belong to a structure but are shared with the terrain -- temp2's door
		# orange is a terrain colour, so it cannot be part of the key. Counted as structure
		# only INSIDE a found bounding box; outside one it is terrain and stays terrain.
		"DOOR_COLORS": doors,
		"DOOR_TOLERANCE": float(source.get("DOOR_TOLERANCE", 42.0)),
		# Below this a component is dithering noise, not a building.
		"MIN_PIXELS": int(source.get("MIN_PIXELS", 8)),
		# Taller than this multiple of its width and it is a tower rather than a house.
		"TOWER_ASPECT": float(source.get("TOWER_ASPECT", 1.2)),
		# Pixels that light themselves after dark. Declared rather than derived: an emissive
		# mask is an art property, and the rule that finds temp2's windows -- white with a
		# dark-teal neighbour in the same row, which is how `TWTWTWTT` reads and which
		# correctly leaves the white lower wall alone -- is fitted to one map's art and is the
		# wrong shape for a pipeline. `EMISSIVE_NEIGHBOUR` names that companion colour; a
		# region that omits it lights only its EMISSIVE_COLORS.
		"EMISSIVE_COLORS": emissive,
		"EMISSIVE_TOLERANCE": float(source.get("EMISSIVE_TOLERANCE", 42.0)),
		"EMISSIVE_NEIGHBOUR": neighbour,
		# Rows to drop from a tower's foot: temp2 paints a ground shadow there, and standing
		# it up puts a dark band under the tower.
		"TOWER_TRIM_ROWS": int(source.get("TOWER_TRIM_ROWS", 0)),
	}


## Empty `KEY_COLORS` means the region has declared no structures. Callers use this rather
## than probing the dictionary, so "no block" and "an empty block" behave identically.
static func hasStructureRule(regionID: String) -> bool:
	if not _index.has(regionID):
		return false
	var rule: Dictionary = _index[regionID]["STRUCTURES"]
	var keys: Array = rule["KEY_COLORS"]
	return not keys.is_empty()


static func structureRuleFor(regionID: String) -> Dictionary:
	if not _index.has(regionID):
		return _structureRule({})
	return _index[regionID]["STRUCTURES"]


static func fogColorFor(regionID: String) -> Color:
	if not _index.has(regionID):
		return Color("cfe9f5")
	return _index[regionID]["FOG_COLOR"]


static func voidColorFor(regionID: String) -> Color:
	if not _index.has(regionID):
		return Color.BLACK
	return _index[regionID]["VOID_COLOR"]


## The region's world extent in walk tiles, which is one world unit each. Fractional for art
## drawn on a grid that does not divide the tile: see `TILES` in `reloadCatalog`.
static func tilesFor(regionID: String) -> Vector2:
	if not _index.has(regionID):
		return Vector2.ZERO
	return _index[regionID]["TILES"]


## The texture's pixel dimensions. Everything that works in map-pixel space -- the shadow mask,
## the cloud field, the prop atlas -- wants this rather than a tile count, and asking for it
## directly is what removed the last multiplication by a per-region tile size.
static func mapPixelsFor(regionID: String) -> Vector2i:
	if not _index.has(regionID):
		return Vector2i.ZERO
	var blocks: Vector2i = _index[regionID]["ART_BLOCKS"]
	return blocks * int(_index[regionID]["GRID"])


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
		# An authored region's texture is baked, so a missing one means the bake has not been
		# run -- a different problem from a painted region's art having gone missing, and worth
		# saying so rather than reporting "could not load" and leaving someone hunting for a PNG
		# that was never meant to be committed by hand.
		if str(reference["KIND"]) == KIND_AUTHORED:
			push_warning(
				(
					"WorldMapRegionCatalog: authored region '%s' has no baked texture at %s. "
					+ "Its source is %s; run the baker."
				)
				% [regionID, texturePath, tileDataPathFor(regionID)]
			)
			return {}
		push_warning(
			"WorldMapRegionCatalog: could not load texture at %s for region '%s'"
			% [texturePath, regionID]
		)
		return {}

	var blocks: Vector2i = reference["ART_BLOCKS"]
	var grid: int = reference["GRID"]
	var expected := Vector2(blocks.x * grid, blocks.y * grid)
	if texture.get_size() != expected:
		push_warning(
			(
				"WorldMapRegionCatalog: region '%s' texture is %s px but TILES_WIDE/"
				+ "TILES_TALL/GRID declare %s blocks of %d px (%s px)"
			)
			% [regionID, texture.get_size(), blocks, grid, expected]
		)
		return {}

	return {
		"id": regionID,
		"texture": texture,
		# World extent in walk tiles -- a float, and not the block count for art on a finer grid.
		"tiles": reference["TILES"],
		"map_px": blocks * grid,
		"fog_color": reference["FOG_COLOR"],
		"void_color": reference["VOID_COLOR"],
		"kind": reference["KIND"],
	}


static func kindFor(regionID: String) -> String:
	if not _index.has(regionID):
		return KIND_PAINTED
	return str(_index[regionID]["KIND"])


static func isAuthored(regionID: String) -> bool:
	return kindFor(regionID) == KIND_AUTHORED


## Where an authored region's tile data lives. Painted regions have none, and this returns the
## path they WOULD use rather than an empty string, so a diagnostic can name it.
static func tileDataPathFor(regionID: String) -> String:
	return "res://data/worldmap/authored/%s.json" % regionID


## An authored region's source. Returns null for a painted region, or when the file is missing
## or unreadable -- `WorldMapTileData` warns about which.
static func tileDataFor(regionID: String) -> WorldMapTileData:
	if not isAuthored(regionID):
		return null
	return WorldMapTileData.loadFrom(tileDataPathFor(regionID))
