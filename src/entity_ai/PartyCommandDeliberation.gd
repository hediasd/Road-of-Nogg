## Resumable, deterministic choice of a ready side unit and command.
##
## This object only reads the canonical simulator. The owner submits the final
## actor through selectUnit() and the command through executeCommand().
## A changed canonical state revision makes the whole proposal stale; callers
## discard it and construct a fresh deliberation from the simulator.

class_name PartyCommandDeliberation
extends RefCounted

const ProposalScript = preload("res://src/entity_ai/PartyCommandProposal.gd")
const StateRevisionScript = preload("res://src/entity_ai/StateRevision.gd")

var _simulator
var _stateRevision: String
var _eligibleUnitIDs: Array[int] = []
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
	for monsterID in simulator.eligibleSideUnitIDs():
		_eligibleUnitIDs.append(int(monsterID))
	_eligibleUnitIDs.sort_custom(func(a: int, b: int) -> bool:
		var priorityA := _unitPriority(a)
		var priorityB := _unitPriority(b)
		return a < b if priorityA == priorityB else priorityA > priorityB
	)
	if _eligibleUnitIDs.is_empty():
		_finished = true
		return
	# A side playing at random picks WHICH unit acts at random too, and the ordinary best-score
	# walk then runs over that one unit. Scoring random picks against each other would not choose
	# a random unit: a wait scores 0 and a random real move often scores below it, so the side
	# would wait with almost every unit, every round. A 100-battle corpus of nothing but waits is
	# what found this.
	var uniformChoiceRNG = null
	if _simulator.has_method("uniformChoiceRNGForActiveSide"):
		uniformChoiceRNG = _simulator.uniformChoiceRNGForActiveSide()
	if uniformChoiceRNG != null:
		var pickedID := _eligibleUnitIDs[uniformChoiceRNG.randi_range(
			0, _eligibleUnitIDs.size() - 1)]
		_eligibleUnitIDs = [pickedID] as Array[int]


func isFinished() -> bool:
	return _finished


func isStale() -> bool:
	return _stale or StateRevisionScript.capture(_simulator.state) != _stateRevision


func eligibleMemberIDs() -> Array[int]:
	return _eligibleUnitIDs.duplicate()


func eligibleUnitIDs() -> Array[int]:
	return _eligibleUnitIDs.duplicate()


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
		if _memberCursor >= _eligibleUnitIDs.size():
			_finish()
			return
		var memberID := _eligibleUnitIDs[_memberCursor]
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
	var actorID := _eligibleUnitIDs[_memberCursor]
	_candidateCount += _memberDeliberation.candidateCount()
	if not _memberDeliberation.isStale():
		var score := _memberDeliberation.resultScore()
		if score > _bestScore or (score == _bestScore and actorID < _bestActorID):
			_bestActorID = actorID
			_bestScore = score
			_bestCommand = _memberDeliberation.result().duplicate_command()
	_memberDeliberation = null
	_memberCursor += 1
	_finish()


func _finish() -> void:
	_finished = true
	if _bestActorID == -1 or _bestCommand == null:
		return
	_bestCommand = _simulator._sideLegalCommand(_bestCommand)
	_proposal = ProposalScript.new(
		_bestActorID,
		_bestCommand,
		_stateRevision,
		_bestScore,
		_candidateCount,
		_workSliceCount
	)


func _unitPriority(monsterID: int) -> int:
	var monster: Monster = _simulator.state.getMonster(monsterID)
	if monster == null:
		return -2147483648
	var brain = _simulator.brains.get(monsterID)
	var role := str(brain.get_script().resource_path.get_file().get_basename()) \
		if brain != null else ""
	var priority: int = {
		"SupportBrain": 120,
		"MageBrain": 220,
		"TacticalBrain": 180,
		"BerserkBrain": 160,
	}.get(role, 100)
	if role == "SupportBrain" and _sideHasInjuredAlly(monster.team):
		priority += 180
	if monster.max_hitpoints > 0:
		priority += int(round(50.0 * float(monster.max_hitpoints - monster.hitpoints) \
			/ float(monster.max_hitpoints)))
	return priority


func _sideHasInjuredAlly(sideID: int) -> bool:
	for allyIDValue in _simulator.state.teamRosters.get(sideID, []):
		var ally: Monster = _simulator.state.getMonster(int(allyIDValue))
		if ally != null and ally.is_alive() and ally.hitpoints < ally.max_hitpoints:
			return true
	return false
