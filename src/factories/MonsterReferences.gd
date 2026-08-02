class_name MonsterReferences

const JSON_PATH := "res://data/monsters.json"
const JsonCatalogLoaderScript = preload("res://src/factories/JsonCatalogLoader.gd")
const REQUIRED_STATS := ["HP", "ATK", "DEF", "SPD", "MOVE"]
const STAT_DEFAULTS := {
	"HP": 1,
	"ATK": 1,
	"DEF": 1,
	"SPD": 1,
	"MOVE": 1,
	"LUCK": 0,
	"JUMP": 1,
	"HP_GROWTH": 0,
	"ATK_GROWTH": 0,
	"DEF_GROWTH": 0
}
const LEGACY_TOP_LEVEL_STATS := [
	"HP", "ATK", "DEF", "SPD", "MOVE", "LUCK", "JUMP",
	"BASE_HP", "BASE_ATK", "BASE_DEF",
	"HP_GROWTH", "ATK_GROWTH", "DEF_GROWTH"
]

static var list: Array = []
static var _name_index: Dictionary = {}
static var _load_error: String = ""


static func _static_init():
	reloadCatalog()


## Named reloadCatalog(), not reload(): MonsterReferences is itself a
## GDScript resource, and Script.reload(keep_state: bool) is an engine method.
static func reloadCatalog(path: String = JSON_PATH) -> bool:
	var loaded := JsonCatalogLoaderScript.loadNamedCatalog(path)
	if not loaded["success"]:
		return _fail(str(loaded["error"]))

	var newList: Array = []
	var newIndex: Dictionary = {}
	for reference in loaded["list"]:
		var normalized := _normalizeReference(reference)
		if not normalized["success"]:
			return _fail(str(normalized["error"]))
		var catalogEntry: Dictionary = normalized["reference"]
		newList.append(catalogEntry)
		newIndex[catalogEntry["NAME"]] = catalogEntry

	list = newList
	_name_index = newIndex
	_load_error = ""
	return true


static func _normalizeReference(reference: Dictionary) -> Dictionary:
	var nameKey := str(reference.get("NAME", ""))
	for key in LEGACY_TOP_LEVEL_STATS:
		if reference.has(key):
			return _normalizationFailure(
				"Monster '%s' uses legacy top-level stat '%s'" % [nameKey, key]
			)

	var statsValue = reference.get("STATS")
	if not statsValue is Dictionary:
		return _normalizationFailure(
			"Monster '%s' has no STATS dictionary" % nameKey
		)
	var stats: Dictionary = statsValue.duplicate(true)
	for key in REQUIRED_STATS:
		if not stats.has(key):
			return _normalizationFailure(
				"Monster '%s' STATS has no '%s'" % [nameKey, key]
			)
	for key in STAT_DEFAULTS:
		stats[key] = int(stats.get(key, STAT_DEFAULTS[key]))

	reference["STATS"] = stats
	reference["FAMILY"] = str(reference.get("FAMILY", "none"))
	reference["SPECIES"] = str(reference.get("SPECIES", "none"))
	reference["ASCENDS_FROM"] = str(reference.get("ASCENDS_FROM", ""))
	return {"success": true, "reference": reference, "error": ""}


static func _normalizationFailure(message: String) -> Dictionary:
	return {"success": false, "reference": {}, "error": message}


static func _fail(message: String) -> bool:
	_load_error = message
	push_warning("MonsterReferences: %s" % _load_error)
	return false


static func getReference(name: String) -> Dictionary:
	if _name_index.has(name):
		return _name_index[name]
	push_error("MonsterReferences: Unknown monster '%s'." % name)
	return {}


static func hasReference(name: String) -> bool:
	return _name_index.has(name)


static func getNames() -> Array[String]:
	var names: Array[String] = []
	for name in _name_index:
		names.append(name)
	names.sort()
	return names


## How many times this monster has ascended: 0 for a basic monster, 1 for one
## that ascends from a basic one, and so on up the ASCENDS_FROM chain.
##
## This is the single tier source for presentation. It walks the catalog rather
## than reading a stored depth so a longer chain needs no data migration, and it
## guards against a malformed self-referential or cyclic chain instead of
## hanging. An unknown ancestor ends the walk at the depth reached so far.
static func ascensionTier(name: String) -> int:
	var tier := 0
	var seen := {name: true}
	var current := name
	while _name_index.has(current):
		var ancestor := str(_name_index[current].get("ASCENDS_FROM", ""))
		if ancestor.is_empty() or seen.has(ancestor):
			break
		seen[ancestor] = true
		current = ancestor
		tier += 1
	return tier
