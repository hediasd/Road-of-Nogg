## One CPU decision in progress, resumable between frames.
##
## `BattleCommandEvaluator.chooseCommand()` used to run start to finish inside a
## single call, which meant a single frame — see docs/ARCHITECTURE.md, "Frame
## budget: deliberation must not block presentation". This object holds the same
## work as an explicit cursor so a caller can spend a bounded slice of it per
## frame and resume later.
##
## **It produces exactly the decision `chooseCommand()` produces.** Candidates
## are accumulated in the same order and sorted once at the end with the same
## total tie key, so where the slices happen to fall cannot change the outcome.
## `chooseCommand()` is now `run()` on this object, so the two cannot drift.
##
## Two rules for anything that touches this class:
##
## - **It reads simulation state and writes only its own accumulators.**
##   Deliberation is a pure query; that is what makes deferring it safe for
##   determinism, and `debug/verify_frame_pacing.gd` guards it.
## - **State must not change while a deliberation is in flight.** A decision
##   spanning frames is computed against the board as it stood when the turn
##   started; a mutation landing mid-scan would leave the back half of the
##   candidate list disagreeing with the front half. The owner of the
##   deliberation is responsible for that window.

class_name CommandDeliberation
extends RefCounted

const ThreatMapScript = preload("res://src/algorithms/ThreatMap.gd")
const StateRevisionScript = preload("res://src/entity_ai/StateRevision.gd")

enum Phase { SETUP, THREAT, CANDIDATES, FINISHED }

var _evaluator: BattleCommandEvaluator
var _state: BattleState
var _monsterID: int
var _weights: Dictionary

var _phase: Phase = Phase.SETUP
var _actor: Monster
var _origin: Vector2i
var _destinations: Array = []
var _predecessors: Dictionary = {}
var _enemyPositions: Array[Vector2i] = []

var _threat: Dictionary = {}
var _threatEnemies: Array = []
var _threatCursor: int = 0

## Every (spellSetIndex, spellIndex) pair the actor owns, in the order
## chooseCommand() iterated them. One pair is one slice of work.
var _spellSlots: Array = []
var _destinationCursor: int = 0
## 0 is the wait-and-attack slice for the current destination; 1..n index
## _spellSlots. Reset to 0 when the destination advances.
var _subTask: int = 0
var _currentPath: Array = []

var _candidates: Array[Dictionary] = []
var _result: BattleCommand = null
var _resultScore: int = -2147483648
var _resultTieKey: String = ""
var _stateRevision: String = ""
var _stale: bool = false
var _workSlices: int = 0


func _init(
		evaluator: BattleCommandEvaluator,
		state: BattleState,
		monsterID: int,
		weights: Dictionary) -> void:
	_evaluator = evaluator
	_state = state
	_monsterID = monsterID
	_weights = weights
	_stateRevision = StateRevisionScript.capture(_state)


func isFinished() -> bool:
	return _phase == Phase.FINISHED


func isStale() -> bool:
	return _stale or (
		not _stateRevision.is_empty()
		and StateRevisionScript.capture(_state) != _stateRevision
	)


## Runs to completion. This is what chooseCommand() and every headless caller
## use, so the synchronous path stays synchronous.
func run() -> BattleCommand:
	_checkRevision()
	while _phase != Phase.FINISHED:
		_advanceOne()
	_checkRevision()
	return result()


## Spends up to `budgetMsec` on this decision and returns true once finished.
## Always performs at least one slice, so progress is guaranteed even at a zero
## budget and a caller cannot spin without advancing.
##
## The budget is wall-clock rather than a slice count because slice cost varies
## by an order of magnitude between a wait-and-attack slice and a long-range
## area spell. Which slices land in which frame is therefore machine-dependent
## — and that is fine, because the result does not depend on the split.
func step(budgetMsec: float) -> bool:
	if _phase == Phase.FINISHED:
		return true
	_checkRevision()
	if _phase == Phase.FINISHED:
		return true
	var startUsec := Time.get_ticks_usec()
	while true:
		_advanceOne()
		if _phase == Phase.FINISHED:
			return true
		if (Time.get_ticks_usec() - startUsec) / 1000.0 >= budgetMsec:
			return false
	return false


## Deterministic work budgeting for party deliberation and probes. Unlike the
## wall-clock adapter, the same slice count always advances the same cursor.
func stepSlices(sliceCount: int, checkRevision: bool = true) -> bool:
	if _phase == Phase.FINISHED:
		return true
	if checkRevision:
		_checkRevision()
	if _phase == Phase.FINISHED:
		return true
	for _slice in range(maxi(1, sliceCount)):
		_advanceOne()
		if _phase == Phase.FINISHED:
			return true
	return false


func result() -> BattleCommand:
	if _result != null:
		return _result
	return BattleCommand.wait()


func resultScore() -> int:
	return _resultScore


func resultTieKey() -> String:
	return _resultTieKey


func candidateCount() -> int:
	return _candidates.size()


func workSliceCount() -> int:
	return _workSlices


func _advanceOne() -> void:
	if _phase == Phase.FINISHED:
		return
	_workSlices += 1
	match _phase:
		Phase.SETUP: _stepSetup()
		Phase.THREAT: _stepThreat()
		Phase.CANDIDATES: _stepCandidates()
		_: pass


func _checkRevision() -> void:
	if (
		_phase != Phase.FINISHED
		and not _stateRevision.is_empty()
		and StateRevisionScript.capture(_state) != _stateRevision
	):
		_stale = true
		_finish()


func _stepSetup() -> void:
	_actor = _state.getMonster(_monsterID)
	if _actor == null or not _actor.is_alive():
		_finish()
		return
	_origin = _state.getMonsterPosition(_monsterID)
	var reachability: Dictionary = _evaluator.movementResolver.getReachability(_monsterID)
	_destinations = reachability["positions"].duplicate()
	_predecessors = reachability["predecessors"].duplicate()
	if not _destinations.has(_origin):
		_destinations.append(_origin)
	_evaluator.sortPositions(_destinations)

	for candidateID in _state.getAliveMonsterIDs():
		if _state.getMonster(candidateID).team != _actor.team:
			_enemyPositions.append(_state.getMonsterPosition(candidateID))

	for spellSetIndex in range(_actor.spellSets.size()):
		for spellIndex in range(_actor.spellSets[spellSetIndex].size()):
			_spellSlots.append([spellSetIndex, spellIndex])

	_threat = ThreatMapScript.beginMap(_state)
	_threatEnemies = ThreatMapScript.threateningEnemies(_state, _actor.team)
	_threatCursor = 0
	_phase = Phase.THREAT


func _stepThreat() -> void:
	if _threatCursor >= _threatEnemies.size():
		_destinationCursor = 0
		_subTask = 0
		_phase = Phase.CANDIDATES
		return
	ThreatMapScript.accumulateEnemy(
		_state,
		_threat,
		int(_threatEnemies[_threatCursor]),
		_evaluator.movementResolver,
		_evaluator.combatResolver
	)
	_threatCursor += 1


func _stepCandidates() -> void:
	if _destinationCursor >= _destinations.size():
		_finish()
		return
	var destination: Vector2i = _destinations[_destinationCursor]

	if _subTask == 0:
		_currentPath = _pathTo(destination)
		# An unreachable destination contributes nothing at all, not even a
		# Wait — matching chooseCommand()'s `continue`.
		if destination != _origin and _currentPath.is_empty():
			_advanceDestination()
			return
		_emitWaitAndAttacks(destination)
	else:
		var slot: Array = _spellSlots[_subTask - 1]
		_emitSpell(destination, int(slot[0]), int(slot[1]))

	_subTask += 1
	if _subTask > _spellSlots.size():
		_advanceDestination()


func _advanceDestination() -> void:
	_destinationCursor += 1
	_subTask = 0
	_currentPath = []


func _pathTo(destination: Vector2i) -> Array:
	if destination == _origin:
		return []
	var reversed: Array = []
	var cursor := destination
	while cursor != _origin:
		if not _predecessors.has(cursor):
			return []
		reversed.append(cursor)
		cursor = _predecessors[cursor]
	reversed.reverse()
	return reversed


func _emitWaitAndAttacks(destination: Vector2i) -> void:
	_candidates.append(_evaluator.scoreCandidate(
		_actor, _currentPath, destination, "wait", Vector2i(-1, -1),
		0, 0, [], _threat, _weights, _enemyPositions
	))

	var attackPositions = _evaluator.combatResolver.getBasicAttackTargetPositionsFrom(
		_monsterID, destination
	)
	_evaluator.sortPositions(attackPositions)
	var seenAttackOutcomes: Dictionary = {}
	for targetPos in attackPositions:
		var targetID = _evaluator.combatResolver.getProjectedOccupantID(
			_monsterID, destination, targetPos
		)
		var outcomeKey = "unit:%d" % targetID if targetID != 0 else "empty"
		if seenAttackOutcomes.has(outcomeKey):
			continue
		seenAttackOutcomes[outcomeKey] = true
		_candidates.append(_evaluator.scoreCandidate(
			_actor, _currentPath, destination, "attack", targetPos,
			0, 0, [], _threat, _weights, _enemyPositions
		))


func _emitSpell(destination: Vector2i, spellSetIndex: int, spellIndex: int) -> void:
	var targetPositions = _evaluator.combatResolver.getSpellTargetPositionsFrom(
		_monsterID, spellSetIndex, spellIndex, destination
	)
	_evaluator.sortPositions(targetPositions)
	# Scoped to this one spell at this one destination, as chooseCommand() had
	# it: a center is deduplicated against other centers of the same spell, not
	# against a different spell's.
	var seenSpellOutcomes: Dictionary = {}
	for centerPos in targetPositions:
		var affected = _evaluator.combatResolver.getSpellAffectedTargetsFrom(
			_monsterID, spellSetIndex, spellIndex, destination, centerPos
		)
		var outcomeKey = _evaluator.affectedOutcomeKey(affected)
		if seenSpellOutcomes.has(outcomeKey):
			continue
		seenSpellOutcomes[outcomeKey] = true
		_candidates.append(_evaluator.scoreCandidate(
			_actor, _currentPath, destination, "spell", centerPos,
			spellSetIndex, spellIndex, affected, _threat, _weights, _enemyPositions
		))


func _finish() -> void:
	_phase = Phase.FINISHED
	if _stale or _candidates.is_empty():
		_result = BattleCommand.wait()
		return
	_candidates.sort_custom(func(a: Dictionary, b: Dictionary) -> bool:
		if a["score"] != b["score"]:
			return a["score"] > b["score"]
		return a["tie_key"] < b["tie_key"]
	)
	var chosen: Dictionary = _candidates[0]
	if not _enemyPositions.is_empty() and not _anyCandidateEngagesEnemy():
		chosen = _closestApproach()
	_result = chosen["command"]
	_resultScore = int(chosen["score"])
	_resultTieKey = str(chosen["tie_key"])


func _anyCandidateEngagesEnemy() -> bool:
	for candidate in _candidates:
		if bool(candidate["engages_enemy"]):
			return true
	return false


## Nothing this unit can do from anywhere it can walk touches an enemy, so the
## only thing worth doing is getting nearer to one.
##
## Left to the scores, it would not. Holding position versus stepping forward is
## decided by the threat term, and every brain but Berserk weighs threat above
## distance, so a unit out of reach scores its own cell highest and holds -- then
## scores the same cell highest next turn, forever. A caster with a self-buff
## stalls the same way for a different reason: buffing itself outscores waiting,
## so it stands there topping itself up while the battle never ends.
##
## This is deliberately blunt. Contact beats positioning, and a battle that
## reaches a result beats one that reads well and never finishes.
##
## Candidates are already sorted and the comparison is strict, so this takes the
## best-scoring candidate at the nearest reachable distance and is deterministic.
func _closestApproach() -> Dictionary:
	var best: Dictionary = _candidates[0]
	for candidate in _candidates:
		if int(candidate["enemy_distance"]) < int(best["enemy_distance"]):
			best = candidate
	return best
