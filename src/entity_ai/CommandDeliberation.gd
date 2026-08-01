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

enum Phase { SETUP, THREAT, CANDIDATES, FINISHED }

var _evaluator: BattleCommandEvaluator
var _state: BattleState
var _monsterID: int
var _weights: Dictionary

var _phase: Phase = Phase.SETUP
var _actor: Monster
var _origin: Vector2i
var _destinations: Array = []
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


func _init(
		evaluator: BattleCommandEvaluator,
		state: BattleState,
		monsterID: int,
		weights: Dictionary) -> void:
	_evaluator = evaluator
	_state = state
	_monsterID = monsterID
	_weights = weights


func isFinished() -> bool:
	return _phase == Phase.FINISHED


## Runs to completion. This is what chooseCommand() and every headless caller
## use, so the synchronous path stays synchronous.
func run() -> BattleCommand:
	while _phase != Phase.FINISHED:
		_advanceOne()
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
	var startUsec := Time.get_ticks_usec()
	while true:
		_advanceOne()
		if _phase == Phase.FINISHED:
			return true
		if (Time.get_ticks_usec() - startUsec) / 1000.0 >= budgetMsec:
			return false
	return false


func result() -> BattleCommand:
	if _result != null:
		return _result
	return BattleCommand.wait()


func _advanceOne() -> void:
	match _phase:
		Phase.SETUP: _stepSetup()
		Phase.THREAT: _stepThreat()
		Phase.CANDIDATES: _stepCandidates()
		_: pass


func _stepSetup() -> void:
	_actor = _state.getMonster(_monsterID)
	if _actor == null or not _actor.is_alive():
		_finish()
		return
	_origin = _state.getMonsterPosition(_monsterID)
	_destinations = _evaluator.movementResolver.getReachablePositions(_monsterID)
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
		_currentPath = (
			[] if destination == _origin else
			_evaluator.movementResolver.findPath(
				_origin,
				destination,
				_evaluator.movementResolver.getEffectiveMove(_monsterID)
			)
		)
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
	if _candidates.is_empty():
		_result = BattleCommand.wait()
		return
	_candidates.sort_custom(func(a: Dictionary, b: Dictionary) -> bool:
		if a["score"] != b["score"]:
			return a["score"] > b["score"]
		return a["tie_key"] < b["tie_key"]
	)
	_result = _candidates[0]["command"]
