## What a battle map needs on disk besides its own JSON, and whether it is there.
##
## WHY THIS EXISTS AT ALL. An authored battle map is two products from one document: the tactical
## JSON under `data/battle/maps`, which is committed, and the visual scene under
## `scenes/worldmap/generated`, which is NOT -- `.gitignore` excludes that directory because
## `ResourceSaver.save()` assigns fresh resource ids on every write, so a committed export would
## show a spurious diff each time anyone re-exported it. The bake the scene samples is committed,
## because that one is byte-deterministic.
##
## So a fresh checkout has the map and the art but not the scene, and the map's own
## `VISUAL_SCENE_PATH` points at a file that is not there yet. That is a real state the project
## is in by policy, not an accident, and the answer is to make the dependency DECLARED and
## CHECKABLE rather than discovered as a load failure: this file is what packaging asks "what
## must exist before you ship this map", and what an author asks "why will this map not load".
##
## READS DATA, NOT THE EDITOR. Everything here comes from the map JSON itself. Nothing in this
## file imports `src/presentation/worldmap/editor/**`, and nothing may -- a packaged game has no
## editor in it, and a manifest that needed one to answer "is this map complete" would be
## unusable exactly where it matters.

class_name BattleMapAssetManifest
extends RefCounted

const MAP_DIR := "res://data/battle/maps"

## A product's `KIND`, telling a caller what to do about a missing one: a bake is committed, so
## its absence is a broken checkout, while a scene is generated, so its absence is a re-export.
const KIND_COMMITTED := "committed"
const KIND_GENERATED := "generated"


static func mapPathFor(mapID: String) -> String:
	return "%s/%s.json" % [MAP_DIR, mapID]


## Every resource `mapID` needs, as `{PATH, KIND, PRESENT, REASON}` records.
##
## A headless-only map needs nothing and returns an empty list; that is not a failure, it is what
## `HEADLESS_ONLY` means. A map naming a visual scene needs that scene, and needs it to be
## regenerated after checkout because the repository does not carry it.
static func productsFor(mapID: String) -> Array[Dictionary]:
	var raw := _readMap(mapID)
	if raw.is_empty():
		return []
	var source: Dictionary = raw.get("SOURCE", {}) if raw.get("SOURCE") is Dictionary else {}
	var scenePath := str(source.get("VISUAL_SCENE_PATH", ""))
	var products: Array[Dictionary] = []
	if scenePath.is_empty():
		return products
	products.append({
		"PATH": scenePath,
		"KIND": KIND_GENERATED,
		"PRESENT": ResourceLoader.exists(scenePath),
		"REASON": (
			"exported from the authored region '%s'; generated scenes are not committed, so "
			+ "re-export before packaging"
		) % str(source.get("ID", "")),
	})
	return products


## The products a caller must produce before this map will load. Empty means the map is ready.
static func missingProducts(mapID: String) -> Array[Dictionary]:
	var missing: Array[Dictionary] = []
	for product: Dictionary in productsFor(mapID):
		if not bool(product.get("PRESENT", false)):
			missing.append(product)
	return missing


static func isReady(mapID: String) -> bool:
	return missingProducts(mapID).is_empty()


## One line an author or a packaging step can act on, naming the map, what is missing, and why.
static func describe(mapID: String) -> String:
	var missing := missingProducts(mapID)
	if missing.is_empty():
		return "%s: ready" % mapID
	var parts: Array[String] = []
	for product: Dictionary in missing:
		parts.append("%s (%s -- %s)" % [
			str(product["PATH"]), str(product["KIND"]), str(product["REASON"])
		])
	return "%s: missing %s" % [mapID, ", ".join(parts)]


## The source identity a map was stamped with, or an empty Dictionary. Lets a caller check that a
## scene and a map came from the same document revision without loading either product.
static func sourceIdentityFor(mapID: String) -> Dictionary:
	var raw := _readMap(mapID)
	if raw.is_empty() or not raw.get("SOURCE") is Dictionary:
		return {}
	return (raw["SOURCE"] as Dictionary).duplicate(true)


## Whether an exported scene came from the same authored document as `mapID`. A pair that
## disagrees is a stale half, which is the failure mode of exporting the two products separately.
##
## The scene stamps `worldmap_source` with the authored document's PATH, so the comparison
## rebuilds that path from the map's own `SOURCE.ID`. The directory literal below is knowledge of
## where authored documents live, not a dependency on the editor that writes them -- this file
## imports no editor class and must not, since a packaged game ships without one.
const AUTHORED_DIR := "res://data/worldmap/authored"
const SCENE_SOURCE_META := "worldmap_source"


static func authoredPathFor(sourceID: String) -> String:
	return "%s/%s.json" % [AUTHORED_DIR, sourceID]


static func productsAgree(mapID: String, sceneRoot: Node) -> bool:
	if sceneRoot == null:
		return false
	var identity := sourceIdentityFor(mapID)
	if identity.is_empty():
		return false
	if not sceneRoot.has_meta(SCENE_SOURCE_META):
		return false
	return str(sceneRoot.get_meta(SCENE_SOURCE_META)) == authoredPathFor(str(identity.get("ID", "")))


static func _readMap(mapID: String) -> Dictionary:
	var path := mapPathFor(mapID)
	if not FileAccess.file_exists(path):
		return {}
	var file := FileAccess.open(path, FileAccess.READ)
	if file == null:
		return {}
	var parsed = JSON.parse_string(file.get_as_text())
	file.close()
	# Catalogs in `data/` are arrays of records; a battle map file holds exactly one.
	if parsed is Array and parsed.size() == 1 and parsed[0] is Dictionary:
		return parsed[0]
	if parsed is Dictionary:
		return parsed
	return {}
