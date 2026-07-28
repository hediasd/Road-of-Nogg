## PassiveSkillReferences — Static registry of all passive skill definitions.
## Same data-driven pattern as SpellReferences.gd.
## Add new passives here; the engine will read them automatically.

class_name PassiveSkillReferences

static var list: Array

static func _static_init() -> void:
	list = [
		{
			"NAME"        = "Tough Skin",
			"TRIGGER"     = "ON_DAMAGE_TAKEN",
			"EFFECT_TYPE" = "damage_reduction",
			"VALUE"       = 0.10,       # Reduces incoming damage by 10%
			"ELEMENT"     = "none",
			"RADIUS"      = 0
		},{
			"NAME"        = "Snowfall",
			"TRIGGER"     = "ON_DEATH",
			"EFFECT_TYPE" = "aoe_damage",
			"VALUE"       = 15.0,       # Flat ICE damage dealt to all in radius
			"ELEMENT"     = "ice",
			"RADIUS"      = 3
		},{
			"NAME"        = "Storm Surge",
			"TRIGGER"     = "ON_TARGETED",
			"EFFECT_TYPE" = "retaliate_damage",
			"VALUE"       = 3,          # Flat THUNDER damage back to attacker
			"ELEMENT"     = "thunder",
			"RADIUS"      = 0
		}
	]
	pass


static func getReference(passiveName: String) -> Dictionary:
	for ref in list:
		if ref["NAME"] == passiveName:
			return ref
	push_error("PassiveSkillReferences: Unknown passive '%s'" % passiveName)
	return {}


static func hasReference(passiveName: String) -> bool:
	for ref in list:
		if ref["NAME"] == passiveName:
			return true
	return false
