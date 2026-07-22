extends Factory

class_name MonsterFactory

static var uniqueMonsterIDMaker

static func _static_init():
	references = preload("res://src/factories/MonsterReferences.gd")
	uniqueMonsterIDMaker = 100
	pass


static func createMonster(name : String = "Defaultgon"):
	var parameters = getReference(name)
	var newMonster = Monster.new(parameters, uniqueMonsterIDMaker)
	uniqueMonsterIDMaker += 1
	return newMonster
