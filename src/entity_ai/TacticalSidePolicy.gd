## Chooses which ready unit acts and what it does, one bounded slice at a time.
##
## Composed rather than written as one loop: `DecisionContext` supplies the
## board, `LegalActionEnumerator` says what is legal, `CandidateFilter` narrows
## it, `CommandUtility` prices it and `DangerQuery` says what it costs. This
## object only sequences that work and picks the winner, which is why its own
## body is short and every interesting decision is somewhere it can be tested.
##
## **Horizon: one decision step.** It chooses the next command the simulator
## will actually resolve, and it values a position by what the acting unit could
## do from there afterwards. It does not schedule an enemy turn: the enemy's
## reply enters only through `DangerQuery`, explicitly labelled as a
## single-enemy-round approximation, never as a move that was searched.
##
## Things this horizon cannot see, written down rather than discovered later: a
## combination that only pays off once two allies have both acted, an effect
## whose value arrives after its duration elapses, terrain that matters in two
## turns, and anything an opponent does other than reply. `EngagementBand` is
## the one deliberate exception -- it prices standing somewhere useful, which is
## a next-turn benefit a one-step horizon would otherwise value at zero.
##
## Determinism: candidates accumulate in a fixed order and are ranked once at
## the end on a total key, so where the slices happen to fall cannot change the
## answer. Nothing here draws from the battle's RNG, and no state survives
## between decisions -- the policy is stateless, and a fresh instance is built
## after every resolution so later units see the board the earlier ones changed.

class_name TacticalSidePolicy
extends RefCounted

const ProposalScript = preload("res://src/entity_ai/PartyCommandProposal.gd")
const ContextScript = preload("res://src/entity_ai/DecisionContext.gd")
const EnumeratorScript = preload("res://src/entity_ai/LegalActionEnumerator.gd")
const FilterScript = preload("res://src/entity_ai/CandidateFilter.gd")
const UtilityScript = preload("res://src/entity_ai/CommandUtility.gd")
const CatalogScript = preload("res://src/entity_ai/PolicyCatalog.gd")
const StateRevisionScript = preload("res://src/entity_ai/StateRevision.gd")

enum Phase { SETUP, ENUMERATE, PRESCORE, PRICE, FINISHED }

var _simulator
var _context: DecisionContext
var _configuration: Dictionary
var _policyID: String
var _phase: Phase = Phase.SETUP
var _eligible: Array[int] = []
var _actorCursor: int = 0
var _pending: Array[ActionCandidate] = []
var _scoreCursor: int = 0
var _dangerCache: Dictionary = {}
var _preScored: Array[Dictionary] = []
var _shortlist: Array[Dictionary] = []
var _priceCursor: int = 0
var _scored: Array[Dictionary] = []
## Why candidates were dropped. A trace that shows only what was considered
## cannot answer the question people actually ask, which is why the obvious move
## was not taken.
var _rejected: Array[Dictionary] = []
var _droppedByFilters: int = 0
var _candidateCount: int = 0
var _workSlices: int = 0
var _stale: bool = false
var _proposal
var _bestTrace: Dictionary = {}


func _init(simulator, policyID: String = CatalogScript.TACTICAL_SIDE) -> void:
	_simulator = simulator
	_policyID = policyID
	_configuration = CatalogScript.configurationFor(policyID)
	_context = ContextScript.forSimulator(simulator)
	for monsterID in simulator.eligibleSideUnitIDs():
		_eligible.append(int(monsterID))
	_eligible.sort()
	if _eligible.is_empty():
		_finish()


func isFinished() -> bool:
	return _phase == Phase.FINISHED


## Cheap: the context's revision pair, not a serialization of every actor. Once
## finished, the recorded answer stands -- see _finish().
func isStale() -> bool:
	if _phase == Phase.FINISHED:
		return _stale
	return _stale or not _context.isCurrent()


func eligibleUnitIDs() -> Array[int]:
	return _eligible.duplicate()


func eligibleMemberIDs() -> Array[int]:
	return eligibleUnitIDs()


func candidateCount() -> int:
	return _candidateCount


func workSliceCount() -> int:
	return _workSlices


## The winning candidate's component breakdown, and the runners-up. Read by
## probes and by anyone asking why the CPU did that.
func trace() -> Dictionary:
	var alternatives: Array = []
	for index in range(mini(_scored.size(), int(_configuration.get("trace_alternatives", 5)))):
		alternatives.append(_readableTrace(_scored[index]))
	return {
		"policy": _policyID,
		"policy_fingerprint": CatalogScript.fingerprint(_policyID),
		"horizon": str(_configuration.get("horizon", "one_decision_step")),
		"chosen": _bestTrace,
		"alternatives": alternatives,
		"candidates_enumerated": _candidateCount,
		"candidates_scored": _scored.size(),
		## Pruning, in the three places it happens: duplicates and idle attacks
		## removed before scoring, candidates that never earned a danger
		## question, and destinations refused as lethal.
		"pruned": {
			"dropped_by_filters": _droppedByFilters,
			"not_shortlisted": maxi(0, _preScored.size() - _shortlist.size()),
			"rejected_when_priced": _rejected.size(),
			"rejections": _rejected,
		},
		"work_slices": _workSlices,
	}


func stepSlices(sliceCount: int) -> bool:
	if _phase == Phase.FINISHED:
		return true
	if not _context.isCurrent():
		_stale = true
		_finish()
		return true
	for _slice in range(maxi(1, sliceCount)):
		_advanceOne()
		if _phase == Phase.FINISHED:
			return true
	return false


func run(sliceCount: int = 64):
	while not stepSlices(sliceCount):
		pass
	return result()


func result():
	if isStale():
		_stale = true
		return null
	return _proposal


func _advanceOne() -> void:
	_workSlices += 1
	match _phase:
		Phase.SETUP:
			_phase = Phase.ENUMERATE
		Phase.ENUMERATE:
			_stepEnumerate()
		Phase.PRESCORE:
			_stepPreScore()
		Phase.PRICE:
			_stepPrice()
		_:
			pass


## One actor per slice: everything it may legally do, narrowed to the bounded
## set this policy will price.
func _stepEnumerate() -> void:
	if _actorCursor >= _eligible.size():
		_phase = Phase.PRESCORE
		return
	var actorID := _eligible[_actorCursor]
	_actorCursor += 1
	var candidates := EnumeratorScript.forActor(_context, actorID)
	_candidateCount += candidates.size()
	## Only duplicates are removed here. Nothing is capped before anything has
	## been scored: a cap applied to an unranked set keeps candidates in tie-key
	## order, which is board position, so whole regions of the board simply
	## stopped being considered and units walked towards the top-left of the map
	## instead of towards the fight. Narrowing happens after the cheap pass, on
	## the shortlist, where it can rank.
	var narrowed := FilterScript.dropIdleAttacks(
		FilterScript.collapseEquivalent(candidates))
	_droppedByFilters += candidates.size() - narrowed.size()
	_pending.append_array(narrowed)


## The cheap pass, in batches: everything except what the enemy could do back.
##
## A slice is a unit of work, not a unit of candidate. Pricing one candidate
## cheaply costs a fraction of a millisecond while enumerating one actor costs
## several, so spending a whole slice on each was the reason a decision took
## dozens of frames to finish on the presentation thread. Each phase takes as
## many items as fit comfortably inside one slice instead.
func _stepPreScore() -> void:
	var batch := int(_configuration.get("prescore_per_slice", 32))
	for _item in range(maxi(1, batch)):
		if _scoreCursor >= _pending.size():
			_buildShortlist()
			_phase = Phase.PRICE
			return
		var candidate := _pending[_scoreCursor]
		_scoreCursor += 1
		var trace := UtilityScript.preScore(_context, candidate, _configuration)
		if str(trace.get("rejected", "")).is_empty():
			trace["actor_id"] = candidate.actor_id
			trace["command"] = candidate.command
			trace["candidate"] = candidate
			_preScored.append(trace)


## The shortlist that earns a danger question: the best few per actor, so one
## actor with many good-looking moves cannot spend the whole budget and leave
## another actor unpriced. Ranked on the same total key the final sort uses.
func _buildShortlist() -> void:
	_preScored.sort_custom(_traceLess)
	var perActor: Dictionary = {}
	var allowance := int(_configuration.get("shortlist_per_actor", 6))
	for trace in _preScored:
		var actorID := int(trace["actor_id"])
		var taken := int(perActor.get(actorID, 0))
		if taken >= allowance:
			continue
		perActor[actorID] = taken + 1
		_shortlist.append(trace)


## One shortlisted candidate per slice. The first danger question about a tile
## is the expensive one; it is budgeted and cached by tile, so no single slice
## can run away and a repeated destination is free.
func _stepPrice() -> void:
	var batch := int(_configuration.get("price_per_slice", 4))
	for _item in range(maxi(1, batch)):
		if _priceCursor >= _shortlist.size():
			_finish()
			return
		var trace: Dictionary = _shortlist[_priceCursor]
		_priceCursor += 1
		var priced := UtilityScript.priceRisk(_context, trace["candidate"],
			_configuration, _dangerCache, trace)
		if str(priced.get("rejected", "")).is_empty():
			_scored.append(priced)
		else:
			_rejected.append(_readableTrace(priced))


func _finish() -> void:
	## Staleness is decided before the context closes, because closing is itself
	## a reason the context stops answering -- reading it afterwards would make
	## every completed decision look stale and throw away every proposal.
	_stale = _stale or not _context.isCurrent()
	_phase = Phase.FINISHED
	if _context != null:
		_context.close()
	if _stale or _scored.is_empty():
		return
	## One total order: score, then the lower actor id, then the tie key. No two
	## distinct candidates can compare equal, so the sort is the same everywhere.
	_scored.sort_custom(_traceLess)
	var best: Dictionary = _scored[0]
	_bestTrace = _readableTrace(best)
	var command: BattleCommand = _simulator._sideLegalCommand(best["command"])
	_proposal = ProposalScript.new(int(best["actor_id"]), command,
		StateRevisionScript.capture(_simulator.state), int(best["score"]),
		_candidateCount, _workSlices)


## One total order, used for the shortlist and for the final pick alike, so a
## candidate cannot be shortlisted by one rule and chosen by another. No two
## distinct candidates compare equal, so the sort is the same everywhere.
static func _traceLess(a: Dictionary, b: Dictionary) -> bool:
	if int(a["score"]) != int(b["score"]):
		return int(a["score"]) > int(b["score"])
	if int(a["actor_id"]) != int(b["actor_id"]):
		return int(a["actor_id"]) < int(b["actor_id"])
	return str(a["tie_key"]) < str(b["tie_key"])


## A trace without the live objects in it, so it can be printed, compared or
## written to disk.
static func _readableTrace(trace: Dictionary) -> Dictionary:
	var readable: Dictionary = {}
	for key in trace:
		if key == "candidate":
			continue
		if key == "command":
			readable["command"] = (trace[key] as BattleCommand).to_dictionary()
			continue
		readable[key] = trace[key]
	return readable
