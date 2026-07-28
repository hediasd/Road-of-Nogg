## reloadCatalog() must fail safely when the JSON is syntactically valid but
## has the wrong shape (an object where a monster array is expected): no
## crash, the prior catalog stays intact, and the failure is surfaced through
## validateAll(). The fixture is deliberately valid JSON, not broken syntax —
## a genuine parse error would make Godot's own JSON.parse_string() log an
## engine-level "ERROR: Parse JSON failed" line that the CI harness treats as
## an unconditional failure regardless of what the test itself asserts.
extends "res://tests/TestCase.gd"


func describe() -> String:
	return "reloadCatalog() rejects a wrong-shaped JSON root without corrupting the live catalog"


func run() -> void:
	var namesBefore := MonsterReferences.getNames()
	var countBefore := MonsterReferences.list.size()

	var ok := MonsterReferences.reloadCatalog("res://tests/fixtures/corrupt_monsters.json")
	assertFalse(ok, "reload() reported success for malformed JSON")

	assertEqual(MonsterReferences.list.size(), countBefore, "list size changed after a failed reload")
	assertEqual(MonsterReferences.getNames(), namesBefore, "catalog names changed after a failed reload")

	var validation := MonsterReferences.validateAll()
	assertFalse(validation["success"], "validateAll() did not surface the corrupt-JSON load error")

	## Restore the real catalog so later tests (and other tiers) don't inherit
	## this test's _load_error static state.
	assertTrue(MonsterReferences.reloadCatalog(), "failed to restore the production catalog after the test")
	assertTrue(MonsterReferences.validateAll()["success"], "production catalog did not validate after restore")
