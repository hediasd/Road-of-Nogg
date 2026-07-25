extends Factory

class_name MonsterFactory

static var uniqueMonsterIDMaker

static func _static_init():
	references = preload("res://src/factories/MonsterReferences.gd")
	uniqueMonsterIDMaker = 100
	pass


static func createMonster(name: String = "Defaultgon", uniqueID: int = -1) -> Monster:
	var parameters = getReference(name)
	if uniqueID < 0:
		uniqueID = uniqueMonsterIDMaker
		uniqueMonsterIDMaker += 1
	return Monster.new(parameters, uniqueID)
