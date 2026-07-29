class_name RaceReferences

const JSON_PATH := "res://data/races.json"

static var list: Array
static var _name_index: Dictionary = {}
static var _load_error: String = ""

static func _static_init():
	reloadCatalog()

## Named reloadCatalog(), not reload() — see MonsterReferences.gd for why:
## Script.reload(keep_state: bool) is a real engine method that would shadow
## a plain `reload()` and throw a String-to-bool argument error instead.
static func reloadCatalog(path: String = JSON_PATH) -> bool:
	## Load from JSON, normalize, index. Returns true on success. On failure,
	## list/index are left at their prior value and _load_error is set. `path`
	## is overridable so tests can exercise failure modes against fixtures
	## without touching the production catalog.
	var new_list: Array = []
	var new_index: Dictionary = {}

	if not ResourceLoader.exists(path):
		_load_error = "JSON file not found at %s" % path
		push_warning("RaceReferences: %s" % _load_error)
		return false

	var json_text = FileAccess.get_file_as_string(path)
	if json_text == null or json_text.is_empty():
		_load_error = "JSON file is empty or unreadable"
		push_warning("RaceReferences: %s" % _load_error)
		return false

	var parsed = JSON.parse_string(json_text)
	if parsed == null or not parsed is Array:
		_load_error = "JSON parse failed or root is not an array"
		push_warning("RaceReferences: %s" % _load_error)
		return false

	for entry in parsed:
		if not entry is Dictionary:
			_load_error = "JSON contains non-dictionary entry"
			push_warning("RaceReferences: %s" % _load_error)
			return false

		var reference := entry.duplicate(true) as Dictionary

		# Every RESISTANCES value is authored as a multiplier like 0.8/1.2, so
		# JSON.parse_string's float-only numeric type already matches the
		# schema here — unlike monsters.json's HP/ATK/etc, there is no int
		# field to coerce. Still explicit float()-cast defensively, so a
		# hand-edited "1" (parsed as an int-valued float, fine) or a
		# accidentally-quoted "0.8" (a String) can't silently misbehave in
		# getDamageMultiplier()'s float() call three lines away.
		var resistances: Dictionary = reference.get("RESISTANCES", {})
		var coerced_resistances: Dictionary = {}
		for element in resistances:
			coerced_resistances[element] = float(resistances[element])
		reference["RESISTANCES"] = coerced_resistances

		new_list.append(reference)
		var name_key = str(reference.get("NAME", ""))
		if not name_key.is_empty():
			new_index[name_key] = reference

	list = new_list
	_name_index = new_index
	_load_error = ""
	return true


static func getReference(name: String) -> Dictionary:
	if _name_index.has(name):
		return _name_index[name]
	return _name_index.get("none", {"NAME": "none", "RESISTANCES": {}})


static func hasReference(name: String) -> bool:
	return _name_index.has(name)


static func getDamageMultiplier(race_name: String, element: String) -> float:
	var race = getReference(race_name)
	if race["RESISTANCES"].has(element):
		return float(race["RESISTANCES"][element])
	return 1.0
