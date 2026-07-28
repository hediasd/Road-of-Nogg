class_name SpellFactory

static var uniqueSpellIDMaker
static var references

static func _static_init():
	references = preload("res://src/factories/SpellReferences.gd")
	uniqueSpellIDMaker = 100
	pass


static func createSpell(name : String):
	var parameters = references.getReference(name)
	assert(not parameters.is_empty(), "Unknown spell reference: %s." % name)
	if parameters.is_empty():
		return null
	var newSpell = Spell.new(parameters)
	#uniqueSpellIDMaker += 1
	return newSpell
