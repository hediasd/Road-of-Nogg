## Aggressive role: prizes damage and closing distance, ignores threat.

class_name BerserkBrain
extends EntityBrain


func _evaluationWeights() -> Dictionary:
	return {"damage": 135, "utility": 35, "threat": 0, "distance": 4, "wait_penalty": 12}
