## Balanced role: values offense while respecting threatened destinations.

class_name TacticalBrain
extends EntityBrain


func _evaluationWeights() -> Dictionary:
	return {"damage": 100, "utility": 100, "threat": 3, "distance": 1, "wait_penalty": 6}
