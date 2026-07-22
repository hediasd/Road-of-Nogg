class_name Spell

var uniqueID: int
var name: String = "Dump"

var radius: int = 1
var range: int = 1
var damage: int = 0
var element: String = "none"
var targetType: String = "single"  # "single" or "area"

var heals: bool = false              # If true, restores HP instead of dealing damage
var inflicts_status: String = ""     # e.g. "burn", "poison". Empty = no status.
var removes_status: String = ""      # e.g. "petrify". Empty = no status removal.
var bypass_los: bool = false         # If true, LoS check is skipped for this spell

var ownerID: int
var castByTeam: int
var position: Vector2

func _init(parameterDictionary) -> void:

	#uniqueID = _uniqueID

	name = parameterDictionary["NAME"] if (parameterDictionary.has("NAME")) else 1

	radius = parameterDictionary["RADIUS"] if (parameterDictionary.has("RADIUS")) else 1
	range = parameterDictionary["RANGE"] if (parameterDictionary.has("RANGE")) else 1
	damage = parameterDictionary["DAMAGE"] if (parameterDictionary.has("DAMAGE")) else 0
	element = parameterDictionary["ELEMENT"] if (parameterDictionary.has("ELEMENT")) else "none"
	targetType = parameterDictionary["TARGET_TYPE"] if (parameterDictionary.has("TARGET_TYPE")) else "single"
	heals = parameterDictionary["HEALS"] if (parameterDictionary.has("HEALS")) else false
	inflicts_status = parameterDictionary["INFLICTS_STATUS"] if (parameterDictionary.has("INFLICTS_STATUS")) else ""
	removes_status = parameterDictionary["REMOVES_STATUS"] if (parameterDictionary.has("REMOVES_STATUS")) else ""
	bypass_los = parameterDictionary["BYPASS_LOS"] if (parameterDictionary.has("BYPASS_LOS")) else false

	pass

func _to_string():
	return name
