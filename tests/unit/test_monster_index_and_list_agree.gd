## MonsterReferences maintains both a list and an O(1) lookup index.
## This gate ensures they stay synchronized and that every entry in list
## can be found by name via getReference().
extends "res://tests/TestCase.gd"


func describe() -> String:
	return "monster index and list are synchronized, with no orphaned entries"


func run() -> void:
	## Every name in the list must be findable by index
	for reference in MonsterReferences.list:
		var name = str(reference.get("NAME", ""))
		assertTrue(not name.is_empty(), "list contains an entry without NAME")
		assertTrue(
			MonsterReferences.hasReference(name),
			"list contains %s but it's not in the index" % name
		)
		var indexed = MonsterReferences.getReference(name)
		assertEqual(
			indexed,
			reference,
			"index entry for %s does not match list entry" % name
		)

	## getNames() must return exactly what's in the index, and be sorted
	var names = MonsterReferences.getNames()
	assertEqual(names.size(), MonsterReferences.list.size(), "getNames() count mismatch")
	var sorted_copy = names.duplicate()
	sorted_copy.sort()
	assertEqual(names, sorted_copy, "getNames() is not sorted")
