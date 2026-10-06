## Shared file/parse/shape/index boundary for authored JSON catalogs.
## Domain wrappers remain responsible for coercion and semantic validation.

extends RefCounted

## Creator-only notes on any catalog entry: the real-world source of an object
## rooted in a real concept, plus trivia. Validated and REMOVED here, before any
## wrapper sees the entry, so no runtime reference, screen, AI decision or save
## can hold it -- a guarantee a grep audit of the presentation code could only
## approximate. It lives here rather than in each wrapper so that every catalog,
## including ones not yet written, inherits it. Read it from the JSON file. See
## docs/REFERENCE_CATALOGS.md, "Inner descriptions".
const INNER_DESCRIPTION_KEY := "INNER_DESCRIPTION"


static func loadNamedCatalog(path: String, rootKey: String = "") -> Dictionary:
	var parsedResult := _loadJson(path)
	if not parsedResult["success"]:
		return parsedResult

	var entriesValue = parsedResult["value"]
	if not rootKey.is_empty():
		if not entriesValue is Dictionary:
			return _failure("JSON root is not a dictionary")
		if not entriesValue.has(rootKey):
			return _failure("JSON root has no \"%s\" key" % rootKey)
		entriesValue = entriesValue[rootKey]
	if not entriesValue is Array:
		return _failure(
			"JSON %s is not an array" % (
				"root" if rootKey.is_empty() else "\"%s\" value" % rootKey
			)
		)

	var entries: Array = []
	var nameIndex: Dictionary = {}
	for rawEntry in entriesValue:
		if not rawEntry is Dictionary:
			return _failure("JSON catalog contains a non-dictionary entry")
		var reference: Dictionary = rawEntry.duplicate(true)
		var nameKey := str(reference.get("NAME", ""))
		if nameKey.is_empty():
			return _failure("JSON catalog contains an entry without NAME")
		if nameIndex.has(nameKey):
			return _failure("JSON catalog contains duplicate NAME \"%s\"" % nameKey)
		if reference.has(INNER_DESCRIPTION_KEY):
			if not reference[INNER_DESCRIPTION_KEY] is String:
				return _failure(
					"JSON catalog entry \"%s\" has a non-string %s"
					% [nameKey, INNER_DESCRIPTION_KEY]
				)
			reference.erase(INNER_DESCRIPTION_KEY)
		entries.append(reference)
		nameIndex[nameKey] = reference

	return {
		"success": true,
		"list": entries,
		"index": nameIndex,
		"error": ""
	}


static func _loadJson(path: String) -> Dictionary:
	if not FileAccess.file_exists(path):
		return _failure("JSON file not found at %s" % path)
	var jsonText := FileAccess.get_file_as_string(path)
	if jsonText.is_empty():
		return _failure("JSON file is empty or unreadable")

	var parser := JSON.new()
	var parseError := parser.parse(jsonText)
	if parseError != OK:
		return _failure(
			"JSON parse failed at line %d: %s" % [
				parser.get_error_line(), parser.get_error_message()
			]
		)
	return {"success": true, "value": parser.data, "error": ""}


static func _failure(message: String) -> Dictionary:
	return {
		"success": false,
		"list": [],
		"index": {},
		"value": null,
		"error": message
	}
