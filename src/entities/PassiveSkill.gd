## PassiveSkill — Pure data class representing one passive ability on a monster.
## Passives react to game events (ON_TURN_END, ON_DEATH, etc.) or
## modify calculations (damage_reduction) instead of active spell casts.

class_name PassiveSkill

var name: String = ""
var trigger: String = ""      # "ON_TURN_END", "ON_DEATH", "ON_DAMAGE_TAKEN", etc.
var effect_type: String = ""  # "damage_reduction", "aoe_damage", "stat_buff"
var value: float = 0.0        # Meaning depends on effect_type (e.g. 0.10 = 10%, 15 = flat dmg)
var element: String = "none"  # For elemental effects (e.g. "ice" for Snowfall)
var radius: int = 0           # For AOE effects


func _init(paramDict: Dictionary) -> void:
	name        = paramDict.get("NAME", "")
	trigger     = paramDict.get("TRIGGER", "")
	effect_type = paramDict.get("EFFECT_TYPE", "")
	value       = paramDict.get("VALUE", 0.0)
	element     = paramDict.get("ELEMENT", "none")
	radius      = paramDict.get("RADIUS", 0)


func _to_string() -> String:
	return name
