extends SceneTree

## Every content catalog accepts a creator-only `INNER_DESCRIPTION` string on an
## entry, rejects any other type without disturbing the live catalog, and never
## publishes the field in its runtime references. The rule lives once, in
## `JsonCatalogLoader`; this probe walks every catalog that reaches it.

const JsonCatalogLoaderScript = preload("res://content/JsonCatalogLoader.gd")
const ElementReferencesScript = preload("res://content/ElementReferences.gd")
const SpellReferencesScript = preload("res://content/SpellReferences.gd")
const StatusEffectReferencesScript = preload("res://content/StatusEffectReferences.gd")
const PassiveSkillReferencesScript = preload("res://content/PassiveSkillReferences.gd")
const ArchetypeReferencesScript = preload("res://content/ArchetypeReferences.gd")
const MonsterReferencesScript = preload("res://content/MonsterReferences.gd")
const RaceReferencesScript = preload("res://content/RaceReferences.gd")

const KEY := "INNER_DESCRIPTION"
const FIXTURE_PATH := "user://probe_inner_description_fixture.json"
const TAXONOMY_PATH := "res://data/taxonomy.json"
## Catalogs no runtime wrapper loads yet; the loader is proven on them directly.
const UNWRAPPED_CATALOGS := ["res://data/settlements.json"]
const PROBE_SOURCE := "Source: probe fixture."

var failures: Array[String] = []


func _init() -> void:
	_checkLoaderContract()
	for catalog: Dictionary in _wrappedCatalogs():
		_checkWrappedCatalog(catalog)
	_checkTaxonomySection("families")
	_checkTaxonomySection("species")
	for path: String in UNWRAPPED_CATALOGS:
		_checkUnwrappedCatalog(path)
	_finish()


func _wrappedCatalogs() -> Array[Dictionary]:
	return [
		{"label": "elements", "path": ElementReferencesScript.JSON_PATH, "rootKey": "",
			"reload": ElementReferencesScript.reloadCatalog,
			"list": func() -> Array: return ElementReferencesScript.list},
		{"label": "spells", "path": SpellReferencesScript.JSON_PATH, "rootKey": "",
			"reload": SpellReferencesScript.reloadCatalog,
			"list": func() -> Array: return SpellReferencesScript.list},
		{"label": "status effects", "path": StatusEffectReferencesScript.JSON_PATH, "rootKey": "",
			"reload": StatusEffectReferencesScript.reloadCatalog,
			"list": func() -> Array: return StatusEffectReferencesScript.list},
		{"label": "passives", "path": PassiveSkillReferencesScript.JSON_PATH, "rootKey": "",
			"reload": PassiveSkillReferencesScript.reloadCatalog,
			"list": func() -> Array: return PassiveSkillReferencesScript.list},
		{"label": "archetypes", "path": ArchetypeReferencesScript.JSON_PATH, "rootKey": "",
			"reload": ArchetypeReferencesScript.reloadCatalog,
			"list": func() -> Array: return ArchetypeReferencesScript.list},
		{"label": "monsters", "path": MonsterReferencesScript.JSON_PATH, "rootKey": "",
			"reload": MonsterReferencesScript.reloadCatalog,
			"list": func() -> Array: return MonsterReferencesScript.list},
		{"label": "races", "path": RaceReferencesScript.JSON_PATH, "rootKey": "races",
			"reload": RaceReferencesScript.reloadCatalog,
			"list": func() -> Array: return RaceReferencesScript.list},
	]


## The shared boundary itself: a string is accepted and removed from both the
## list and the name index; every other type is rejected with a message that
## names the entry; an entry without the key is untouched.
func _checkLoaderContract() -> void:
	_writeFixture([{"NAME": "Probe Entry", "OTHER": "kept", KEY: PROBE_SOURCE}])
	var loaded := JsonCatalogLoaderScript.loadNamedCatalog(FIXTURE_PATH)
	_check(loaded["success"], "loader rejected a string %s: %s" % [KEY, loaded["error"]])
	if loaded["success"]:
		var entry: Dictionary = loaded["list"][0]
		_check(not entry.has(KEY), "loader published %s in its list" % KEY)
		_check(not (loaded["index"]["Probe Entry"] as Dictionary).has(KEY),
			"loader published %s in its name index" % KEY)
		_check(entry.get("OTHER", "") == "kept", "loader dropped a sibling field with %s" % KEY)

	_writeFixture([{"NAME": "Plain Entry", "OTHER": "kept"}])
	loaded = JsonCatalogLoaderScript.loadNamedCatalog(FIXTURE_PATH)
	_check(loaded["success"] and loaded["list"][0] == {"NAME": "Plain Entry", "OTHER": "kept"},
		"an entry without %s did not load unchanged" % KEY)

	for wrongValue in [7, null, ["a"], {"a": "b"}, true]:
		_writeFixture([{"NAME": "Probe Entry", KEY: wrongValue}])
		loaded = JsonCatalogLoaderScript.loadNamedCatalog(FIXTURE_PATH)
		var error := str(loaded["error"])
		_check(not loaded["success"], "loader accepted a %s of %s" % [KEY, str(wrongValue)])
		_check(error.contains("Probe Entry") and error.contains(KEY),
			"rejection of %s did not name the entry and the key: %s" % [str(wrongValue), error])


## Each wrapper accepts the field on a real entry, publishes references without
## it, and on a wrong type keeps the catalog that was live before the reload.
func _checkWrappedCatalog(catalog: Dictionary) -> void:
	var label := str(catalog["label"])
	var reload: Callable = catalog["reload"]
	var liveList: Callable = catalog["list"]
	var path := str(catalog["path"])
	var rootKey := str(catalog["rootKey"])

	_check(reload.call(path), "%s: production catalog did not load" % label)
	var productionNames := _names(liveList.call())
	var production = _readJson(path)

	var withString = production.duplicate(true)
	_entries(withString, rootKey)[0][KEY] = PROBE_SOURCE
	_writeFixture(withString)
	_check(reload.call(FIXTURE_PATH), "%s: rejected a string %s" % [label, KEY])
	_check(_names(liveList.call()) == productionNames, "%s: string %s changed the entries" % [label, KEY])
	for reference: Dictionary in liveList.call():
		if reference.has(KEY):
			_fail("%s: '%s' publishes %s" % [label, reference.get("NAME", ""), KEY])

	var withNumber = production.duplicate(true)
	_entries(withNumber, rootKey)[0][KEY] = 7
	_writeFixture(withNumber)
	_check(not reload.call(FIXTURE_PATH), "%s: accepted a numeric %s" % [label, KEY])
	_check(_names(liveList.call()) == productionNames,
		"%s: a rejected reload did not preserve the live catalog" % label)

	_check(reload.call(path), "%s: production catalog did not reload" % label)


## Families and species have no runtime wrapper -- nothing loads them -- so the
## boundary is proven on them directly through the shared loader.
func _checkTaxonomySection(section: String) -> void:
	var taxonomy = _readJson(TAXONOMY_PATH)
	var entries: Array = taxonomy[section]
	if entries.is_empty():
		entries.append({"NAME": "Probe %s" % section})
	entries[0][KEY] = PROBE_SOURCE
	_writeFixture(taxonomy)
	var loaded := JsonCatalogLoaderScript.loadNamedCatalog(FIXTURE_PATH, section)
	_check(loaded["success"], "%s: rejected a string %s: %s" % [section, KEY, loaded["error"]])
	if loaded["success"]:
		_check(not (loaded["list"][0] as Dictionary).has(KEY), "%s: published %s" % [section, KEY])

	entries[0][KEY] = 7
	_writeFixture(taxonomy)
	loaded = JsonCatalogLoaderScript.loadNamedCatalog(FIXTURE_PATH, section)
	_check(not loaded["success"], "%s: accepted a numeric %s" % [section, KEY])


## A catalog with no wrapper: production loads through the shared loader with
## every field stripped, and a wrong type on its first entry is rejected.
func _checkUnwrappedCatalog(path: String) -> void:
	var loaded := JsonCatalogLoaderScript.loadNamedCatalog(path)
	_check(loaded["success"], "%s: production catalog did not load: %s" % [path, loaded["error"]])
	if loaded["success"]:
		for reference: Dictionary in loaded["list"]:
			_check(not reference.has(KEY), "%s: '%s' published %s" % [path, reference.get("NAME", ""), KEY])
	var withNumber = _readJson(path)
	withNumber[0][KEY] = 7
	_writeFixture(withNumber)
	_check(not JsonCatalogLoaderScript.loadNamedCatalog(FIXTURE_PATH)["success"],
		"%s: accepted a numeric %s" % [path, KEY])


func _entries(root, rootKey: String) -> Array:
	return root if rootKey.is_empty() else root[rootKey]


func _names(references: Array) -> Array:
	return references.map(func(reference: Dictionary) -> String: return str(reference.get("NAME", "")))


func _readJson(path: String):
	return JSON.parse_string(FileAccess.get_file_as_string(path))


func _writeFixture(value) -> void:
	var file := FileAccess.open(FIXTURE_PATH, FileAccess.WRITE)
	file.store_string(JSON.stringify(value))
	file.close()


func _check(condition: bool, message: String) -> void:
	if not condition:
		_fail(message)


func _fail(message: String) -> void:
	failures.append(message)


func _finish() -> void:
	DirAccess.remove_absolute(ProjectSettings.globalize_path(FIXTURE_PATH))
	if failures.is_empty():
		print("INNER_DESCRIPTION_OK")
		quit(0)
		return
	for failure in failures:
		printerr("INNER_DESCRIPTION_FAILURE: %s" % failure)
	quit(1)
