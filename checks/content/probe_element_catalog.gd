extends SceneTree

## The element catalog holds single elements and their two- and three-element
## combinations in one file. Singles keep their exact contract (`list`,
## `STANDARD`, `CODES`, `code()`, `isValid()` mean one element); combinations
## are reachable only through `COMBINATIONS` and `getCombination()`, in any
## order and case; and every malformed combination rejects the reload while the
## live catalog survives.

const ElementReferencesScript = preload("res://content/ElementReferences.gd")

const FIXTURE_PATH := "user://probe_element_catalog_fixture.json"
const SINGLES := [
	"fire", "ice", "wood", "steel", "darkness", "light",
	"earth", "water", "thunder", "wind", "none",
]
const TRIPLES := ["fire+darkness+light", "ice+water+wind", "wood+earth+thunder"]

var failures: Array[String] = []


func _init() -> void:
	_check(ElementReferencesScript.reloadCatalog(), "production element catalog did not load")
	_checkSingles()
	_checkCombinations()
	_checkFileSlots()
	_checkRejections()
	_check(ElementReferencesScript.reloadCatalog(), "production element catalog did not reload")
	_checkLiveIsProduction("after the probe")
	_finish()


## Singles are untouched by the combinations sharing their file.
func _checkSingles() -> void:
	_check(Array(ElementReferencesScript.STANDARD) == SINGLES,
		"STANDARD is %s, expected the 11 single elements" % [ElementReferencesScript.STANDARD])
	_check(ElementReferencesScript.list.size() == 11, "list holds %d entries, expected 11" % ElementReferencesScript.list.size())
	_check(ElementReferencesScript.CODES.size() == 11, "CODES holds %d entries, expected 11" % ElementReferencesScript.CODES.size())
	_check(ElementReferencesScript.code("fire") == "FI", "fire's code changed")
	_check(ElementReferencesScript.isValid("fire"), "fire is not a valid element")
	_check(not ElementReferencesScript.isValid("fire+darkness"), "a combination counts as an element")


func _checkCombinations() -> void:
	_check(ElementReferencesScript.COMBINATIONS.size() == 48,
		"COMBINATIONS holds %d entries, expected 48" % ElementReferencesScript.COMBINATIONS.size())
	var pair := ElementReferencesScript.getCombination(["darkness", "fire"])
	_check(pair.get("NAME", "") == "fire+darkness", "reversed pair lookup returned %s" % [pair])
	_check(pair.get("ELEMENTS", []) == ["fire", "darkness"], "pair ELEMENTS not canonical: %s" % [pair])
	_check(ElementReferencesScript.getCombination(["FIRE", "Darkness"]) == pair, "lookup is case-sensitive")
	var triple := ElementReferencesScript.getCombination(["light", "fire", "darkness"])
	_check(triple.get("NAME", "") == "fire+darkness+light", "triple lookup returned %s" % [triple])
	_check(ElementReferencesScript.getCombination(["fire", "ice", "wood"]).is_empty(),
		"a triple with no entry was found")
	_check(ElementReferencesScript.getCombination(["fire", "plasma"]).is_empty(), "an unknown element was found")
	_check(ElementReferencesScript.getCombination(["fire", "none"]).is_empty(), "none was combinable")
	_check(ElementReferencesScript.getCombination(["fire"]).is_empty(), "a single element was a combination")
	pair["NAME"] = "mutated"
	_check(ElementReferencesScript.getCombination(["fire", "darkness"]).get("NAME", "") == "fire+darkness",
		"getCombination handed out the live entry")


## The authored file: every entry carries an inner-description slot (the
## loader strips it at runtime, so only the file can show it), the pairs are
## every unordered pair of the ten elements in canonical order, and the
## triples are the three placeholders.
func _checkFileSlots() -> void:
	var entries: Array = JSON.parse_string(FileAccess.get_file_as_string(ElementReferencesScript.JSON_PATH))
	for entry: Dictionary in entries:
		_check(entry.get("INNER_DESCRIPTION", null) == "", "%s has no empty INNER_DESCRIPTION slot" % entry.get("NAME", "?"))
	var combinable := SINGLES.slice(0, 10)
	var expectedPairs: Array[String] = []
	for first in combinable.size():
		for second in range(first + 1, combinable.size()):
			expectedPairs.append("%s+%s" % [combinable[first], combinable[second]])
	var names: Array = entries.map(func(entry: Dictionary) -> String: return str(entry["NAME"]))
	_check(names.slice(0, 11) == SINGLES, "single elements moved: %s" % [names.slice(0, 11)])
	_check(names.slice(11, 56) == expectedPairs, "pairs are not every pair in canonical order")
	_check(names.slice(56) == TRIPLES, "triples are %s" % [names.slice(56)])


func _checkRejections() -> void:
	_expectLoad(true, [_combo("fire+darkness", ["darkness", "fire"])], "a valid combination in any order")
	_check(ElementReferencesScript.getCombination(["fire", "darkness"]).get("ELEMENTS", []) == ["fire", "darkness"],
		"a loaded combination kept its authored order")
	_check(ElementReferencesScript.reloadCatalog(), "production element catalog did not reload")

	_expectLoad(false, [_combo("fire", ["fire"])], "a one-element combination")
	_expectLoad(false, [_combo("fire+ice+wood+steel", ["fire", "ice", "wood", "steel"])],
		"a four-element combination")
	_expectLoad(false, [_combo("fire+plasma", ["fire", "plasma"])], "an unknown element")
	_expectLoad(false, [_combo("fire+none", ["fire", "none"])], "the none sentinel")
	_expectLoad(false, [_combo("fire+fire", ["fire", "fire"])], "a repeated element")
	var coded := _combo("fire+ice", ["fire", "ice"])
	coded["CODE"] = "FX"
	_expectLoad(false, [coded], "a combination with a CODE")
	_expectLoad(false, [_combo("ice+fire", ["fire", "ice"])], "a non-canonical NAME")
	_expectLoad(false, [_combo("fire+ice", ["fire", "ice"]), _combo("fire+ice", ["ice", "fire"])],
		"a repeated set")
	_expectLoad(false, [_combo("fire+ice", "fire")], "ELEMENTS that is not an array")
	_expectLoad(false, [_combo("fire+ice", ["fire", "ice"]), {"NAME": "plasma", "CODE": "PL"}],
		"a single element after a combination")


## Writes the production singles plus `combinations`, reloads, and requires the
## result. A failed reload must leave the production catalog live.
func _expectLoad(expected: bool, combinations: Array, label: String) -> void:
	var singles: Array = []
	for reference: Dictionary in ElementReferencesScript.list:
		singles.append({"NAME": reference["NAME"], "CODE": reference["CODE"]})
	var file := FileAccess.open(FIXTURE_PATH, FileAccess.WRITE)
	file.store_string(JSON.stringify(singles + combinations))
	file.close()
	var loaded := ElementReferencesScript.reloadCatalog(FIXTURE_PATH)
	_check(loaded == expected, "%s: expected load %s, got %s" % [label, expected, loaded])
	if not expected:
		_checkLiveIsProduction(label)


func _checkLiveIsProduction(label: String) -> void:
	_check(ElementReferencesScript.STANDARD.size() == 11 and ElementReferencesScript.COMBINATIONS.size() == 48,
		"%s: the live catalog is not production (%d singles, %d combinations)" % [
			label, ElementReferencesScript.STANDARD.size(), ElementReferencesScript.COMBINATIONS.size()])


func _combo(name: String, elements) -> Dictionary:
	return {"NAME": name, "ELEMENTS": elements}


func _check(condition: bool, message: String) -> void:
	if not condition:
		failures.append(message)


func _finish() -> void:
	DirAccess.remove_absolute(ProjectSettings.globalize_path(FIXTURE_PATH))
	if failures.is_empty():
		print("ELEMENT_CATALOG_OK")
		quit(0)
		return
	for failure in failures:
		printerr("ELEMENT_CATALOG_FAILURE: %s" % failure)
	quit(1)
