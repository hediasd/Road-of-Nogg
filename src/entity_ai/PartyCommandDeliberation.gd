## Resumable, deterministic choice of an eligible party member and command.
##
## This object only reads the canonical simulator. The owner submits the final
## actor through selectPartyMember() and the command through executeCommand().
## A changed canonical state revision makes the whole proposal stale; callers
## discard it and construct a fresh deliberation from the simulator.

class_name PartyCommandDeliberation
extends RefCounted

const ProposalScript = preload("res://src/entity_ai/PartyCommandProposal.gd")
const StateRevisionScript = preload("res://src/entity_ai/StateRevision.gd")

var _simulator
var _stateRevision: String
var _eligibleMemberIDs: Array[int] = []
var _memberCursor: int = 0
var _memberDeliberation: CommandDeliberation
var _bestActorID: int = -1
var _bestCommand: BattleCommand
var _bestScore: int = -2147483648
var _candidateCount: int = 0
var _workSliceCount: int = 0
var _finished: bool = false
var _stale: bool = false
var _proposal


func _init(simulator) -> void:
	_simulator = simulator
	_stateRevision = StateRevisionScript.capture(simulator.state)
	for memberID in simulator.eligiblePartyMemberIDs():
		_eligibleMemberIDs.append(int(memberID))
	_eligibleMemberIDs.sort()
	if _eligibleMemberIDs.is_empty():
		_finished = true


func isFinished() -> bool:
	return _finished


func isStale() -> bool:
	return _stale or StateRevisionScript.capture(_simulator.state) != _stateRevision


func eligibleMemberIDs() -> Array[int]:
	return _eligibleMemberIDs.duplicate()


## Advances a deterministic count of CommandDeliberation cursor slices.
func stepSlices(sliceCount: int) -> bool:
	if _finished:
		return true
	if StateRevisionScript.capture(_simulator.state) != _stateRevision:
		_stale = true
		_finished = true
		return true
	for _slice in range(maxi(1, sliceCount)):
		_advanceOne()
		if _finished:
			break
	return _finished


func run(sliceCount: int = 64):
	while not stepSlices(sliceCount):
		pass
	return result()


func result():
	if isStale():
		_stale = true
		_proposal = null
	return _proposal


func candidateCount() -> int:
	return _candidateCount


func workSliceCount() -> int:
	return _workSliceCount


func _advanceOne() -> void:
	if _memberDeliberation == null:
		if _memberCursor >= _eligibleMemberIDs.size():
			_finish()
			return
		var memberID := _eligibleMemberIDs[_memberCursor]
		var brain = _simulator.brains.get(memberID)
		if brain == null:
			_memberCursor += 1
			return
		_memberDeliberation = brain.beginDeliberation(memberID)

	_workSliceCount += 1
	## This public party step already checked the revision. No external mutation
	## can interleave with the synchronous inner slice.
	if not _memberDeliberation.stepSlices(1, false):
		return
	var actorID := _eligibleMemberIDs[_memberCursor]
	_candidateCount += _memberDeliberation.candidateCount()
	if not _memberDeliberation.isStale():
		var score := _memberDeliberation.resultScore()
		if score > _bestScore or (score == _bestScore and actorID < _bestActorID):
			_bestActorID = actorID
			_bestScore = score
			_bestCommand = _memberDeliberation.result().duplicate_command()
	_memberDeliberation = null
	_memberCursor += 1
	if _memberCursor >= _eligibleMemberIDs.size():
		_finish()


func _finish() -> void:
	_finished = true
	if _bestActorID == -1 or _bestCommand == null:
		return
	_proposal = ProposalScript.new(
		_bestActorID,
		_bestCommand,
		_stateRevision,
		_bestScore,
		_candidateCount,
		_workSliceCount
	)
