## reload() must fail safely when the JSON file does not exist: no crash, the
## prior catalog stays intact, and the failure is surfaced through
## validateAll() rather than silently booting an empty roster.
extends "res://tests/TestCase.gd"


func describe() -> String:
	return "reload() rejects a missing JSON path without corrupting the live catalog"


func run() -> void:
	var namesBefore := MonsterReferences.getNames()
	var countBefore := MonsterReferences.list.size()

	var ok := MonsterReferences.reloadCatalog("res://tests/fixtures/does_not_exist.json")
	assertFalse(ok, "reload() reported success for a nonexistent path")

	assertEqual(MonsterReferences.list.size(), countBefore, "list size changed after a failed reload")
	assertEqual(MonsterReferences.getNames(), namesBefore, "catalog names changed after a failed reload")

	var validation := MonsterReferences.validateAll()
	assertFalse(validation["success"], "validateAll() did not surface the missing-file load error")

	## Restore the real catalog so later tests (and other tiers) don't inherit
	## this test's _load_error static state.
	assertTrue(MonsterReferences.reloadCatalog(), "failed to restore the production catalog after the test")
	assertTrue(MonsterReferences.validateAll()["success"], "production catalog did not validate after restore")
