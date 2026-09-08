## Support role: prizes useful spell effects and strongly avoids threat.

class_name SupportBrain
extends EntityBrain


func _evaluationWeights() -> Dictionary:
	return {"damage": 45, "utility": 180, "threat": 8, "distance": 0, "wait_penalty": 4}
