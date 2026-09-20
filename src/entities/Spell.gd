class_name Spell

var uniqueID: int
var name: String = "Dump"

var min_range: int = 0
var range: int = 1
var max_height_delta: int = 1
var damage: int = 0
var element: String = "none"
var damage_lines: Array = [] # Array of Dictionary: { "damage": int, "element": String }
var targetType: String = "single"  # "single", "area", "self"
var radius: int = 0
var area_shape: String = "circle" # "circle", "cross", "line", "cone"

var heals: bool = false              # If true, restores HP instead of dealing damage
var can_target_empty: bool = false   # If true, an empty non-self center may be confirmed
var inflicts_status: String = ""     # e.g. "burn", "poison". Empty = no status.
var removes_status: String = ""      # e.g. "petrify". Empty = no status removal.
var bypass_los: bool = false         # If true, LoS check is skipped for this spell
var buffs_atk: int = 0               # If > 0, grants a timed ATK buff to the target (self-cast)
var buff_duration: int = 0           # Duration in turns for any stat buff this spell provides
var reverts_damage: bool = false     # If true, reverts damage dealt by target in previous turn
var cooldown: int = 0                # Cooldown in turns before this spell can be cast again
var sequence_level: int = 0
var resonance_element: String = "none"
var effects: Array = []
var self_radius: int = 0
var aoe_targets: String = "self"
var heal_amount: int = 0




var ownerID: int
var castByTeam: int
var position: Vector2

func _init(parameterDictionary) -> void:

	#uniqueID = _uniqueID

	name = parameterDictionary["NAME"] if (parameterDictionary.has("NAME")) else "Dump"

	radius = parameterDictionary["RADIUS"] if (parameterDictionary.has("RADIUS")) else 1
	min_range = parameterDictionary["MIN_RANGE"] if (parameterDictionary.has("MIN_RANGE")) else 0
	range = parameterDictionary["RANGE"] if (parameterDictionary.has("RANGE")) else 1
	max_height_delta = parameterDictionary["MAX_HEIGHT_DELTA"] if (parameterDictionary.has("MAX_HEIGHT_DELTA")) else 1
	damage = parameterDictionary["DAMAGE"] if (parameterDictionary.has("DAMAGE")) else 0
	element = parameterDictionary["ELEMENT"] if (parameterDictionary.has("ELEMENT")) else "none"

	if parameterDictionary.has("DAMAGE_LINES"):
		## Copy rather than alias: reference catalogs are shared, read-only inputs
		## and every Spell instance would otherwise point at the same array.
		damage_lines = parameterDictionary["DAMAGE_LINES"].duplicate(true)
		for line in damage_lines:
			damage += line.get("damage", 0)
	else:
		damage_lines = [{"damage": damage, "element": element}]

	targetType = parameterDictionary["TARGET_TYPE"] if (parameterDictionary.has("TARGET_TYPE")) else "single"
	area_shape = parameterDictionary["AREA_SHAPE"] if (parameterDictionary.has("AREA_SHAPE")) else "circle"
	heals = parameterDictionary["HEALS"] if (parameterDictionary.has("HEALS")) else false
	can_target_empty = bool(parameterDictionary.get("CAN_TARGET_EMPTY", false))
	inflicts_status = parameterDictionary["INFLICTS_STATUS"] if (parameterDictionary.has("INFLICTS_STATUS")) else ""
	removes_status = parameterDictionary["REMOVES_STATUS"] if (parameterDictionary.has("REMOVES_STATUS")) else ""
	bypass_los = parameterDictionary["BYPASS_LOS"] if (parameterDictionary.has("BYPASS_LOS")) else false
	buffs_atk = parameterDictionary["BUFFS_ATK"] if (parameterDictionary.has("BUFFS_ATK")) else 0
	buff_duration = parameterDictionary["BUFF_DURATION"] if (parameterDictionary.has("BUFF_DURATION")) else 0
	reverts_damage = parameterDictionary["REVERTS_DAMAGE"] if (parameterDictionary.has("REVERTS_DAMAGE")) else false
	cooldown = parameterDictionary["COOLDOWN"] if (parameterDictionary.has("COOLDOWN")) else 0
	sequence_level = clampi(int(parameterDictionary.get("SEQUENCE_LEVEL", 0)), 0, 4)
	resonance_element = str(parameterDictionary.get("RESONANCE_ELEMENT", element))
	effects = parameterDictionary.get("EFFECTS", []).duplicate(true)
	self_radius = maxi(0, int(parameterDictionary.get("SELF_RADIUS", 0)))
	aoe_targets = str(parameterDictionary.get("AOE_TARGETS", "self"))
	heal_amount = maxi(0, int(parameterDictionary.get("HEAL_AMOUNT", 0)))




	pass

func _to_string():
	return name


## A battle may change a spell instance without changing its catalog definition.
## This is the complete runtime surface copied by battle snapshots.
func serializeRuntime() -> Dictionary:
	return {
		"uniqueID": uniqueID, "name": name,
		"minRange": min_range, "range": range,
		"maxHeightDelta": max_height_delta,
		"damage": damage, "element": element,
		"damageLines": damage_lines.duplicate(true),
		"targetType": targetType, "radius": radius,
		"areaShape": area_shape, "heals": heals,
		"canTargetEmpty": can_target_empty,
		"inflictsStatus": inflicts_status,
		"removesStatus": removes_status,
		"bypassLoS": bypass_los,
		"buffsAtk": buffs_atk, "buffDuration": buff_duration,
		"revertsDamage": reverts_damage, "cooldown": cooldown,
		"sequenceLevel": sequence_level,
		"resonanceElement": resonance_element,
		"effects": effects.duplicate(true),
		"selfRadius": self_radius, "aoeTargets": aoe_targets,
		"healAmount": heal_amount, "ownerID": ownerID,
		"castByTeam": castByTeam,
		"position": {"x": position.x, "y": position.y},
	}


func restoreRuntime(data: Dictionary) -> void:
	uniqueID = int(data.get("uniqueID", 0))
	name = str(data.get("name", ""))
	min_range = int(data.get("minRange", 0))
	range = int(data.get("range", 1))
	max_height_delta = int(data.get("maxHeightDelta", 1))
	damage = int(data.get("damage", 0))
	element = str(data.get("element", "none"))
	damage_lines = data.get("damageLines", []).duplicate(true)
	targetType = str(data.get("targetType", "single"))
	radius = int(data.get("radius", 0))
	area_shape = str(data.get("areaShape", "circle"))
	heals = bool(data.get("heals", false))
	can_target_empty = bool(data.get("canTargetEmpty", false))
	inflicts_status = str(data.get("inflictsStatus", ""))
	removes_status = str(data.get("removesStatus", ""))
	bypass_los = bool(data.get("bypassLoS", false))
	buffs_atk = int(data.get("buffsAtk", 0))
	buff_duration = int(data.get("buffDuration", 0))
	reverts_damage = bool(data.get("revertsDamage", false))
	cooldown = int(data.get("cooldown", 0))
	sequence_level = int(data.get("sequenceLevel", 0))
	resonance_element = str(data.get("resonanceElement", "none"))
	effects = data.get("effects", []).duplicate(true)
	self_radius = int(data.get("selfRadius", 0))
	aoe_targets = str(data.get("aoeTargets", "self"))
	heal_amount = int(data.get("healAmount", 0))
	ownerID = int(data.get("ownerID", 0))
	castByTeam = int(data.get("castByTeam", 0))
	var savedPosition: Dictionary = data.get("position", {})
	position = Vector2(float(savedPosition.get("x", 0.0)), float(savedPosition.get("y", 0.0)))
