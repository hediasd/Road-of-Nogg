extends Factory

class_name MonsterFactory

static var uniqueMonsterIDMaker

static func _static_init():
	references = preload("res://src/factories/MonsterReferences.gd")
	uniqueMonsterIDMaker = 100
	pass


static func createMonster(name: String = "Defaultgon", uniqueID: int = -1, level: int = 1) -> Monster:
	var parameters = getReference(name)
	assert(not parameters.is_empty(), "Unknown monster reference: %s." % name)
	if parameters.is_empty():
		return null
	if uniqueID < 0:
		uniqueID = uniqueMonsterIDMaker
		uniqueMonsterIDMaker += 1
	var leveledParameters = parameters.duplicate(true)
	leveledParameters["LEVEL"] = level
	return Monster.new(leveledParameters, uniqueID)
