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
