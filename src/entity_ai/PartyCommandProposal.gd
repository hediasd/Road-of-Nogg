## Read-only result of one complete party-member deliberation.

class_name PartyCommandProposal
extends RefCounted

const StateRevisionScript = preload("res://src/entity_ai/StateRevision.gd")

var actor_id: int = -1
var command: BattleCommand
var state_revision: String = ""
var score: int = -2147483648
var candidate_count: int = 0
var work_slice_count: int = 0


func _init(
		_actorID: int,
		_command: BattleCommand,
		_stateRevision: String,
		_score: int,
		_candidateCount: int,
		_workSliceCount: int) -> void:
	actor_id = _actorID
	command = _command.duplicate_command()
	state_revision = _stateRevision
	score = _score
	candidate_count = _candidateCount
	work_slice_count = _workSliceCount


func isCurrent(state: BattleState) -> bool:
	return state_revision == StateRevisionScript.capture(state)
