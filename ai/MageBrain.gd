## Ranged role: prizes damage while applying a stronger threat penalty.

class_name MageBrain
extends EntityBrain


func _evaluationWeights() -> Dictionary:
	return {"damage": 125, "utility": 70, "threat": 4, "distance": 1, "wait_penalty": 8}
