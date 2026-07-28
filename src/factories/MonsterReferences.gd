class_name MonsterReferences

const CatalogValidatorScript = preload("res://src/factories/CatalogValidator.gd")
const JSON_PATH := "res://data/monsters.json"

static var list: Array
static var _name_index: Dictionary = {}
static var _load_error: String = ""

static func _static_init():
	reloadCatalog()

## Named reloadCatalog(), not reload(): `MonsterReferences` is itself a
## GDScript resource, and `Script.reload(keep_state: bool)` is a real engine
## method on that base class. A static function named plain `reload()` gets
## shadowed by it — calls resolve to the engine's reload and throw a
## String-to-bool argument error instead of running this body.
static func reloadCatalog(path: String = JSON_PATH) -> bool:
	## Load from JSON, normalize, index, and validate. Returns true on success.
	## On failure, list/index are left at their prior value and _load_error is
	## set. `path` is overridable so tests can exercise failure modes against
	## fixtures without touching the production catalog.
	var new_list: Array = []
	var new_index: Dictionary = {}

	# Load and parse JSON
	if not ResourceLoader.exists(path):
		_load_error = "JSON file not found at %s" % path
		push_warning("MonsterReferences: %s" % _load_error)
		return false

	var json_text = FileAccess.get_file_as_string(path)
	if json_text == null or json_text.is_empty():
		_load_error = "JSON file is empty or unreadable"
		push_warning("MonsterReferences: %s" % _load_error)
		return false

	var parsed = JSON.parse_string(json_text)
	if parsed == null or not parsed is Array:
		_load_error = "JSON parse failed or root is not an array"
		push_warning("MonsterReferences: %s" % _load_error)
		return false

	# Process each entry: int-coerce numerics, set defaults, build index
	for entry in parsed:
		if not entry is Dictionary:
			_load_error = "JSON contains non-dictionary entry"
			push_warning("MonsterReferences: %s" % _load_error)
			return false

		var reference := entry.duplicate(true) as Dictionary

		# Int-coerce all numeric stat fields (JSON.parse_string returns floats)
		for key in ["HP", "ATK", "DEF", "SPD", "MOVE", "LUCK"]:
			if reference.has(key):
				reference[key] = int(reference[key])

		# Set normalized defaults
		reference["BASE_HP"] = int(reference.get("BASE_HP", reference.get("HP", 1)))
		reference["BASE_ATK"] = int(reference.get("BASE_ATK", reference.get("ATK", 1)))
		reference["BASE_DEF"] = int(reference.get("BASE_DEF", reference.get("DEF", 1)))
		reference["HP_GROWTH"] = int(reference.get("HP_GROWTH", 0))
		reference["ATK_GROWTH"] = int(reference.get("ATK_GROWTH", 0))
		reference["DEF_GROWTH"] = int(reference.get("DEF_GROWTH", 0))
		reference["JUMP"] = int(reference.get("JUMP", 1))
		reference["FAMILY"] = str(reference.get("FAMILY", "none"))
		reference["ASCENDS_FROM"] = str(reference.get("ASCENDS_FROM", ""))

		new_list.append(reference)
		var name_key = str(reference.get("NAME", ""))
		if not name_key.is_empty():
			new_index[name_key] = reference

	# Atomically commit: only update state on success
	list = new_list
	_name_index = new_index
	_load_error = ""
	return true

static func getReference(name: String) -> Dictionary:
	## O(1) lookup via index. Returns empty dict if not found.
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


static func validateAll() -> Dictionary:
	## Validate the catalog. Include load errors if present.
	var result = CatalogValidatorScript.validateMonsters(list)
	if not _load_error.is_empty():
		if result["errors"] is Array:
			result["errors"].insert(0, "Catalog load error: %s" % _load_error)
		result["success"] = false
	return result
