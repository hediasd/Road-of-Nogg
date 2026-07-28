## StatusEffectReferences — Static registry of every status/buff/debuff effect
## name the battle simulation knows about. Same data-driven pattern as
## SpellReferences.gd/RaceReferences.gd: content is data, resolvers stay
## general. Owns default DURATION/DAMAGE_PER_TURN and whether an effect counts
## as NEGATIVE for cleanse purposes.

class_name StatusEffectReferences

static var list: Array = [
	{"NAME": "burn",       "DURATION": 3, "DAMAGE_PER_TURN": 2, "NEGATIVE": true},
	{"NAME": "poison",     "DURATION": 4, "DAMAGE_PER_TURN": 1, "NEGATIVE": true},
	{"NAME": "petrify",    "DURATION": 2, "DAMAGE_PER_TURN": 0, "NEGATIVE": true},
	{"NAME": "spd_debuff", "DURATION": 4, "DAMAGE_PER_TURN": 0, "NEGATIVE": true},
	{"NAME": "chill",      "DURATION": 3, "DAMAGE_PER_TURN": 0, "NEGATIVE": true},
	{"NAME": "guard",      "DURATION": 4, "DAMAGE_PER_TURN": 0, "NEGATIVE": false},
	{"NAME": "focus",      "DURATION": 4, "DAMAGE_PER_TURN": 0, "NEGATIVE": false},
	{"NAME": "atk_buff",   "DURATION": 3, "DAMAGE_PER_TURN": 0, "NEGATIVE": false},
	{"NAME": "def_buff",   "DURATION": 3, "DAMAGE_PER_TURN": 0, "NEGATIVE": false},
	{"NAME": "spd_buff",   "DURATION": 4, "DAMAGE_PER_TURN": 0, "NEGATIVE": false},
	{"NAME": "move_buff",  "DURATION": 4, "DAMAGE_PER_TURN": 0, "NEGATIVE": false}
]


static func getReference(name: String) -> Dictionary:
	for reference in list:
		if reference["NAME"] == name:
			return reference
	push_error("StatusEffectReferences: Unknown status effect '%s'." % name)
	return {"NAME": name, "DURATION": 2, "DAMAGE_PER_TURN": 0, "NEGATIVE": false}


static func hasReference(name: String) -> bool:
	for reference in list:
		if reference["NAME"] == name:
			return true
	return false


static func isNegative(name: String) -> bool:
	return bool(getReference(name).get("NEGATIVE", false))


static func getDuration(name: String) -> int:
	return int(getReference(name).get("DURATION", 2))


static func getDamagePerTurn(name: String) -> int:
	return int(getReference(name).get("DAMAGE_PER_TURN", 0))
