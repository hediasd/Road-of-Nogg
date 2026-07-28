## Utility script to generate res://data/monsters.json from MonsterReferences.
## Run once, then delete. Ensures provable parity with authored GDScript.

extends SceneTree

func _init() -> void:
	await get_root().tree_entered
	_dump_and_exit()

func _dump_and_exit() -> void:
	var MonsterReferencesScript = preload("res://src/factories/MonsterReferences.gd")

	# The authored list exists only inside _static_init(), which we must force.
	# GDScript's static_init() runs automatically once at script load, so list
	# should already be initialized. Read it directly.
	var raw_list = MonsterReferencesScript.list

	if raw_list == null or raw_list.is_empty():
		print_debug("DUMP ERROR: MonsterReferences.list is empty or uninitialized")
		get_tree().quit(1)
		return

	# Build the output: strip the normalized fields (BASE_*, JUMP, FAMILY/ASCENDS_FROM defaulting).
	var output: Array[Dictionary] = []
	for reference in raw_list:
		var entry: Dictionary = {}
		# Keep all authored keys except the derived ones.
		for key in reference:
			if key not in ["BASE_HP", "BASE_ATK", "BASE_DEF", "HP_GROWTH", "ATK_GROWTH", "DEF_GROWTH", "JUMP", "ASCENDS_FROM"]:
				entry[key] = reference[key]
			elif key == "ASCENDS_FROM" and reference[key] != "":
				# ASCENDS_FROM is authored if non-empty, strip only the empty defaulting.
				entry[key] = reference[key]
		output.append(entry)

	# Write to data/monsters.json.
	var file = FileAccess.open("res://data/monsters.json", FileAccess.WRITE)
	if file == null:
		print_debug("DUMP ERROR: could not open res://data/monsters.json for write")
		get_tree().quit(1)
		return

	file.store_string(JSON.stringify(output, "\t"))
	print_debug("SUCCESS: wrote %d monsters to res://data/monsters.json" % output.size())
	get_tree().quit(0)
