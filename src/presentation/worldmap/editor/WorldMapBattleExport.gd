## Turns an authored region into the tactical half of a battle map: the HXB-5 map schema, written
## as plain data that `BattleMapFactory` reads with no knowledge that an editor exists.
##
## THE DEPENDENCY RUNS ONE WAY, AND ONLY ONE. This file imports the editor's document, height
## field, object and tactical layers; the runtime factory imports none of them and never will.
## What crosses the boundary is a JSON dictionary. That is what keeps simulation from becoming an
## editor consumer -- the failure this cycle's architecture section names outright -- and it is
## why the schema is built here by hand rather than by handing a document to the factory.
##
## THE VISUAL AND TACTICAL PRODUCTS ARE A MATCHED PAIR. Both carry the same `SOURCE` identity:
## the region's name, its revision, and a fingerprint of the document's own canonical bytes. A
## scene exported from one document and a map exported from another therefore cannot be mistaken
## for a pair, and `BattleMapAssetManifest` is what checks that at load.
##
## WHAT THIS REFUSES, AND WHY REFUSING IS THE FEATURE. The tactical model is one surface per cell
## at an integer elevation -- `SURFACE_MODEL: "single"`. Two authored things cannot be said in
## that model:
##
##   * SMOOTH TERRAIN. Heights live on the hex vertex lattice as continuous floats, and
##     `WorldMapHeightField`'s own note is explicit that nothing rounds them. A cell whose six
##     vertices disagree is a slope, and a slope flattened to one integer is a lie about where
##     the ground is -- the unit would stand somewhere the terrain is not. So a sloped cell is
##     named and refused rather than rounded.
##   * BRIDGES. A fixed-anchor deck is a second walkable surface over a cell that already has
##     one. `SURFACE_MODEL: "single"` has nowhere to put it, and silently dropping it would hand
##     the player a bridge they can see and cannot cross.
##
## Both refusals name the feature and the cell, because "this map is unsupported" without a
## coordinate is not something an author can act on. AUTHORED WATER IS NOT IN THAT LIST: water is
## decorative here, it blocks nothing, and refusing a map for having a lake in it would be the
## "do not block decorative water" instruction violated exactly.

class_name WorldMapBattleExport
extends RefCounted

const MapData = preload("res://src/presentation/worldmap/editor/WorldMapTileData.gd")
const HeightField = preload("res://src/presentation/worldmap/editor/WorldMapHeightField.gd")
const ObjectLayer = preload("res://src/presentation/worldmap/editor/WorldMapObjectLayer.gd")
const TacticalLayer = preload("res://src/presentation/worldmap/editor/WorldMapTacticalLayer.gd")
const SceneExport = preload("res://src/presentation/worldmap/editor/WorldMapSceneExport.gd")

## Where an exported tactical map lands -- the same directory `BattleMapFactory.loadDefinition`
## reads by id, so an exported map is loadable by name with no path plumbing.
const GENERATED_DIR := "res://data/battle/maps"

const FORMAT_VERSION := 1
const GRID_KIND := "hex_flat"
const COORDINATES := "odd_q_offset"
const SURFACE_MODEL := "single"

## World units per cell, and the elevation quantum. Matched to `WorldMapHexGrid`'s own
## `HEX_WIDTH`/`HEX_HEIGHT` so a battle cell is exactly the authored cell it came from rather
## than a rescaled copy of it -- HXB-9's board view reproduces these same numbers from the map,
## which is what makes the two agree about where a hex is.
const CELL_WIDTH := 2.0
const CELL_HEIGHT := 2.0
const HEIGHT_STEP := 0.5

## Elevation range the map schema accepts. Mirrored from `BattleMapFactory` rather than imported,
## because importing runtime constants here would be the same boundary crossing in the other
## direction; the probe asserts the two still agree.
const MIN_ELEVATION := 0
const MAX_ELEVATION := 8

## How far a cell's vertices may differ before it is a slope rather than a flat cell, and how far
## a height may sit off an exact `HEIGHT_STEP` multiple before it is unquantised. Both are
## authoring tolerances, not rendering ones: a value this close came from a flatten or a level
## brush, and a value further out came from sculpting.
const FLATNESS_EPSILON := 1e-4


static func generatedPathFor(mapID: String) -> String:
	return "%s/%s.json" % [GENERATED_DIR, mapID]


## The identity both products stamp. `FINGERPRINT` hashes the document's own canonical JSON --
## the same bytes `saveTo` writes -- so any authored change at all produces a different pair, and
## a stale product is detectable rather than merely suspected.
static func sourceIdentity(data: WorldMapTileData) -> Dictionary:
	var canonical := JSON.stringify(data.toDictionary(), "\t", true)
	var context := HashingContext.new()
	context.start(HashingContext.HASH_SHA256)
	context.update(canonical.to_utf8_buffer())
	return {
		"ID": data.region_name,
		"REVISION": 1,
		"FINGERPRINT": "sha256:%s" % context.finish().hex_encode(),
	}


## Everything about `data` that the single-surface tactical model cannot represent, as a list of
## `{FEATURE, CELL, DETAIL}` records. Empty means the map is exportable.
##
## Reported as a LIST rather than as the first failure found: an author who sculpted a hillside
## wants to know it is the hillside, not to fix one cell and be told about the next one.
static func unsupportedFeatures(data: WorldMapTileData, layerID := TacticalLayer.DEFAULT_LAYER) -> Array[Dictionary]:
	var found: Array[Dictionary] = []
	var playable := TacticalLayer.playableCells(data, layerID)
	var playableLookup: Dictionary = {}
	for cell: Vector2i in playable:
		playableLookup[cell] = true

	for cell: Vector2i in playable:
		var terrainID := TacticalLayer.terrainAt(data, cell, layerID)
		if TacticalLayer.terrainFor(terrainID).is_empty():
			found.append({
				"FEATURE": "unknown tactical terrain",
				"CELL": cell,
				"DETAIL": "'%s' is not in the ledger (%s)" % [
					terrainID, ", ".join(TacticalLayer.knownTerrainIDs())
				],
			})
			continue
		var slope := _slopeOf(data, cell)
		if slope > FLATNESS_EPSILON:
			found.append({
				"FEATURE": "smooth terrain",
				"CELL": cell,
				"DETAIL": "the cell's vertices span %.4f world units; a battle cell is flat" % slope,
			})
			continue
		var elevation := _elevationOf(data, cell)
		if elevation.is_empty():
			found.append({
				"FEATURE": "unquantised elevation",
				"CELL": cell,
				"DETAIL": "height %.4f is not a multiple of the %.2f elevation step" % [
					HeightField.centreHeight(data, cell), HEIGHT_STEP
				],
			})
			continue
		var step := int(elevation["STEP"])
		if step < MIN_ELEVATION or step > MAX_ELEVATION:
			found.append({
				"FEATURE": "elevation out of range",
				"CELL": cell,
				"DETAIL": "elevation %d is outside %d..%d" % [step, MIN_ELEVATION, MAX_ELEVATION],
			})

	for record in ObjectLayer.items(data):
		if str(record.get(ObjectLayer.K_ANCHOR, "")) != ObjectLayer.ANCHOR_FIXED:
			continue
		for cell in ObjectLayer.footprintCells(record):
			if not playableLookup.has(cell):
				continue
			found.append({
				"FEATURE": "bridge",
				"CELL": cell,
				"DETAIL": (
					"object '%s' decks a playable cell at a fixed height; one surface per cell "
					+ "cannot carry both"
				) % str(record.get(ObjectLayer.K_KIND, "")),
			})
			break

	return found


## The whole map as the HXB-5 schema, or a refusal naming what it could not represent.
##
## `mapID` defaults to the region's own name but is separable from it, because the two identify
## different things: the region is a place someone authored, and the map is one battle fought on
## it. A region could carry more than one, and `BattleMapFactory.loadDefinition` addresses a map
## by id, so tying the id to the region name would make that impossible for no gain. `SOURCE.ID`
## still carries the region, which is what keeps the pair traceable to its document.
static func buildDefinition(
	data: WorldMapTileData, visualScenePath := "", layerID := TacticalLayer.DEFAULT_LAYER,
	mapID := ""
) -> Dictionary:
	if data == null:
		return {"ok": false, "error": "no document is open"}
	if data.region_name.is_empty():
		return {"ok": false, "error": "the document has no name"}
	if data.layout != MapData.LAYOUT_HEX_FLAT:
		return {"ok": false, "error": "a battle map must be a hex_flat document; this one is %s" % data.layout}
	if not TacticalLayer.has(data, layerID):
		return {"ok": false, "error": "the document has no '%s' layer to export" % layerID}

	var playable := TacticalLayer.playableCells(data, layerID)
	if playable.is_empty():
		return {"ok": false, "error": "no cell has been painted onto the '%s' layer" % layerID}

	var unsupported := unsupportedFeatures(data, layerID)
	if not unsupported.is_empty():
		return {
			"ok": false,
			"error": _refusalText(unsupported),
			"unsupported": unsupported,
		}

	var terrainDefinitions: Array = []
	for terrainID: String in TacticalLayer.usedTerrainIDs(data, layerID):
		terrainDefinitions.append(TacticalLayer.terrainFor(terrainID))

	var mask: Array = []
	for row in range(data.size_tiles.y):
		var line := ""
		for col in range(data.size_tiles.x):
			line += "1" if TacticalLayer.isPlayable(data, Vector2i(col, row), layerID) else "0"
		mask.append(line)

	# The default is what most of the board is, so the override list carries the exceptions
	# rather than the board. Chosen by census rather than fixed to "clear": a map that is mostly
	# rough should not spell out every rough cell.
	var defaultTerrain := _mostCommonTerrain(data, playable, layerID)
	var overrides: Array = []
	for cell: Vector2i in playable:
		var terrainID := TacticalLayer.terrainAt(data, cell, layerID)
		var step := int(_elevationOf(data, cell)["STEP"])
		var record: Dictionary = {"CELL": [cell.x, cell.y]}
		var differs := false
		if terrainID != defaultTerrain:
			record["TERRAIN"] = terrainID
			differs = true
		if step != 0:
			record["ELEVATION"] = step
			differs = true
		if differs:
			overrides.append(record)

	return {
		"ok": true,
		"definition": {
			"FORMAT_VERSION": FORMAT_VERSION,
			"NAME": mapID if not mapID.is_empty() else data.region_name,
			"REVISION": 1,
			"GRID_KIND": GRID_KIND,
			"COORDINATES": COORDINATES,
			"SURFACE_MODEL": SURFACE_MODEL,
			"SIZE": [data.size_tiles.x, data.size_tiles.y],
			"CELL_METRICS": {
				"WIDTH": CELL_WIDTH, "HEIGHT": CELL_HEIGHT, "HEIGHT_STEP": HEIGHT_STEP,
			},
			"SOURCE": _sourceBlock(data, visualScenePath),
			"TERRAIN_DEFINITIONS": terrainDefinitions,
			"VALID_MASK": mask,
			"DEFAULT_SURFACE": {"TERRAIN": defaultTerrain, "ELEVATION": 0},
			"CELL_OVERRIDES": overrides,
		},
	}


## Builds the definition and writes it where `BattleMapFactory.loadDefinition` finds it by id.
static func exportDefinition(
	data: WorldMapTileData, visualScenePath := "", destination := "",
	layerID := TacticalLayer.DEFAULT_LAYER, mapID := ""
) -> Dictionary:
	var built := buildDefinition(data, visualScenePath, layerID, mapID)
	if not bool(built.get("ok", false)):
		return built
	var resolvedID: String = str((built["definition"] as Dictionary)["NAME"])
	var path := destination if not destination.is_empty() else generatedPathFor(resolvedID)
	DirAccess.make_dir_recursive_absolute(path.get_base_dir())
	var file := FileAccess.open(path, FileAccess.WRITE)
	if file == null:
		return {"ok": false, "error": "could not write %s" % path}
	# Wrapped in an array and tab-indented to match every other catalog in `data/`, which is what
	# `JsonCatalogLoader` reads and what keeps a hand diff of a generated map legible.
	file.store_string("%s\n" % JSON.stringify([built["definition"]], "\t"))
	file.close()
	return {"ok": true, "path": path, "definition": built["definition"]}


## Both halves in one call -- the scene the player sees and the map the simulation reads, from
## one document, stamped with one identity. Exported together on purpose: the risk this item
## names is a preview built from newer data than the export, and two separate user actions is
## exactly how the two drift apart.
static func exportBoth(data: WorldMapTileData, framing: Dictionary, mapID := "") -> Dictionary:
	var sceneResult := SceneExport.exportScene(data, framing)
	if not bool(sceneResult.get("ok", false)):
		return {"ok": false, "error": "visual export failed: %s" % str(sceneResult.get("error", ""))}
	var mapResult := exportDefinition(
		data, str(sceneResult.get("path", "")), "", TacticalLayer.DEFAULT_LAYER, mapID
	)
	if not bool(mapResult.get("ok", false)):
		return {
			"ok": false,
			"error": "tactical export failed: %s" % str(mapResult.get("error", "")),
			"scene_path": sceneResult.get("path", ""),
			"unsupported": mapResult.get("unsupported", []),
		}
	return {
		"ok": true,
		"scene_path": sceneResult["path"],
		"map_path": mapResult["path"],
		"definition": mapResult["definition"],
	}


static func _sourceBlock(data: WorldMapTileData, visualScenePath: String) -> Dictionary:
	var identity := sourceIdentity(data)
	identity["VISUAL_SCENE_PATH"] = visualScenePath
	identity["HEADLESS_ONLY"] = visualScenePath.is_empty()
	return identity


## How far apart a cell's six vertices are in world units. Zero for a flat cell, whatever the
## cell's own height is -- a plateau at elevation 3 is as flat as one at 0.
static func _slopeOf(data: WorldMapTileData, cell: Vector2i) -> float:
	if not HeightField.has(data):
		return 0.0
	var lowest := INF
	var highest := -INF
	for vertex in HeightField.cellVertices(cell):
		var height := HeightField.heightAt(data, vertex)
		lowest = minf(lowest, height)
		highest = maxf(highest, height)
	if lowest == INF:
		return 0.0
	return highest - lowest


## The cell's elevation as a step count, or an empty Dictionary when its height does not land on
## a step. Separated from the flatness test so the two failures report differently: a sloped cell
## and a cell sitting half a step up are different authoring mistakes with different fixes.
static func _elevationOf(data: WorldMapTileData, cell: Vector2i) -> Dictionary:
	if not HeightField.has(data):
		return {"STEP": 0}
	var height := HeightField.centreHeight(data, cell)
	var steps := height / HEIGHT_STEP
	var rounded := roundf(steps)
	if absf(steps - rounded) > FLATNESS_EPSILON / HEIGHT_STEP:
		return {}
	return {"STEP": int(rounded)}


static func _mostCommonTerrain(
	data: WorldMapTileData, playable: Array[Vector2i], layerID: String
) -> String:
	var census: Dictionary = {}
	for cell: Vector2i in playable:
		var terrainID := TacticalLayer.terrainAt(data, cell, layerID)
		census[terrainID] = int(census.get(terrainID, 0)) + 1
	var best := ""
	var bestCount := -1
	# Ties break on the id rather than on iteration order, so the same document always exports
	# the same bytes -- a generated file that reshuffles itself is a diff nobody made.
	for terrainID in TacticalLayer.usedTerrainIDs(data, layerID):
		var count := int(census.get(terrainID, 0))
		if count > bestCount:
			best = terrainID
			bestCount = count
	return best


static func _refusalText(unsupported: Array[Dictionary]) -> String:
	var first: Dictionary = unsupported[0]
	var cell: Vector2i = first["CELL"]
	var summary := "%s at cell (%d, %d): %s" % [
		str(first["FEATURE"]), cell.x, cell.y, str(first["DETAIL"])
	]
	if unsupported.size() > 1:
		summary += " (and %d more unsupported cell%s)" % [
			unsupported.size() - 1, "" if unsupported.size() == 2 else "s"
		]
	return summary
