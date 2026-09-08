## Base role policy for controller-neutral entity AI.

class_name EntityBrain

const BattleCommandEvaluatorScript = preload("res://src/entity_ai/BattleCommandEvaluator.gd")

var state: BattleState
var movementResolver: MovementResolver
var combatResolver: CombatResolver
var commandEvaluator


func _init(
		_state: BattleState,
		_movementResolver: MovementResolver,
		_combatResolver: CombatResolver) -> void:
	state = _state
	movementResolver = _movementResolver
	combatResolver = _combatResolver
	commandEvaluator = BattleCommandEvaluatorScript.new(
		state, movementResolver, combatResolver)


func decideTurn(monsterID: int) -> BattleCommand:
	return beginDeliberation(monsterID).run()


## The same decision, resumable. Weights stay behind this seam so a subclass
## applies its role to both individual and party deliberation.
func beginDeliberation(monsterID: int) -> CommandDeliberation:
	return commandEvaluator.beginDeliberation(monsterID, _evaluationWeights())


func _evaluationWeights() -> Dictionary:
	return {
		"damage": 100,
		"utility": 100,
		"threat": 2,
		"distance": 1,
		"wait_penalty": 5,
	}
