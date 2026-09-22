## Narrows a complete legal action set to the subset a policy will search.
##
## Everything this drops is a decision made in the open. Two rules keep it from
## quietly deciding the game:
##
## - **Collapse only true duplicates.** Candidates may be merged on
##   `equivalence_key` alone, which is equal exactly when resolving either one
##   produces the same supported effects. Anything else -- "this looks useless",
##   "this is far away" -- is ranking, and ranking belongs to a policy that can
##   be measured against another one.
## - **Never let a cap hide a whole class.** A destination or count limit is
##   applied per action class with a reserved allowance, so a new mechanic the
##   ranking does not understand still reaches the forecast. A filter that can
##   starve a class is how a new spell becomes invisible to the CPU and stays
##   that way until somebody plays two hundred battles and notices.
##
## The allowance is deterministic: it takes the first candidates of the class in
## tie-key order, not a sample, so the same position always searches the same
## subset.

class_name CandidateFilter
extends RefCounted

const CandidateScript = preload("res://src/entity_ai/ActionCandidate.gd")

## Kept per class when a cap would otherwise remove all of it.
const DEFAULT_CLASS_ALLOWANCE := 2


## Merges candidates whose resolution is indistinguishable. The survivor is the
## lowest tie key of its group, so the choice does not depend on input order.
static func collapseEquivalent(candidates: Array) -> Array[ActionCandidate]:
	var ordered: Array = candidates.duplicate()
	ordered.sort_custom(CandidateScript.tieKeyLess)
	var seen: Dictionary = {}
	var kept: Array[ActionCandidate] = []
	for candidateValue in ordered:
		var candidate: ActionCandidate = candidateValue
		if seen.has(candidate.equivalence_key):
			continue
		seen[candidate.equivalence_key] = true
		kept.append(candidate)
	return kept


## Applies a total cap while guaranteeing every present class its allowance.
## `rank` orders candidates best-first; when it is not supplied, tie-key order
## stands in, which is arbitrary but stable.
static func capWithAllowance(candidates: Array, limit: int,
		rank: Callable = Callable(),
		allowance: int = DEFAULT_CLASS_ALLOWANCE) -> Array[ActionCandidate]:
	var ordered: Array = candidates.duplicate()
	ordered.sort_custom(rank if rank.is_valid() else CandidateScript.tieKeyLess)
	if limit <= 0 or ordered.size() <= limit:
		var all: Array[ActionCandidate] = []
		for candidateValue in ordered:
			all.append(candidateValue)
		return all

	var reserved: Dictionary = {}
	var kept: Array[ActionCandidate] = []
	var keptKeys: Dictionary = {}
	for candidateValue in ordered:
		var candidate: ActionCandidate = candidateValue
		var taken := int(reserved.get(candidate.action_class, 0))
		if taken >= allowance:
			continue
		reserved[candidate.action_class] = taken + 1
		kept.append(candidate)
		keptKeys[candidate.tie_key] = true
	for candidateValue in ordered:
		if kept.size() >= limit:
			break
		var candidate: ActionCandidate = candidateValue
		if keptKeys.has(candidate.tie_key):
			continue
		kept.append(candidate)
		keptKeys[candidate.tie_key] = true
	kept.sort_custom(rank if rank.is_valid() else CandidateScript.tieKeyLess)
	return kept


## Removes attacks that cannot touch anybody.
##
## A basic attack has exactly one rule: it damages the occupant of the target
## tile. Aimed at an empty tile it therefore does nothing at all, which makes it
## the same move as the Wait the enumerator emits at that same destination --
## the same walk, the same spent turn, the same board afterwards. Keeping both
## lets a policy pick the spelling a player's own controls cannot express: there
## is no way to click "swing at nothing", so a CPU that chose it would be
## playing a move the person across the board could not.
##
## This is an equivalence, **not** a judgement that the action looks useless.
## Spells whose centre catches nobody are deliberately left alone: an effect
## that reads the ground rather than the units standing on it is a mechanic this
## game could gain, and a filter that had quietly dropped the whole class would
## hide it. **If a basic attack ever gains an effect that lands without a
## target, this filter is wrong and must go.**
static func dropIdleAttacks(candidates: Array) -> Array[ActionCandidate]:
	var waitDestinations: Dictionary = {}
	for candidateValue in candidates:
		var candidate: ActionCandidate = candidateValue
		if candidate.action_class == CandidateScript.CLASS_WAIT:
			waitDestinations[candidate.destination] = true
	var kept: Array[ActionCandidate] = []
	for candidateValue in candidates:
		var candidate: ActionCandidate = candidateValue
		if candidate.action_class != CandidateScript.CLASS_ATTACK:
			kept.append(candidate)
			continue
		if candidate.command.target_id >= 0 or not waitDestinations.has(candidate.destination):
			kept.append(candidate)
			continue
		continue
	return kept


## The legacy destination budget, kept executable rather than described: the
## nearest destinations to an enemy, the origin always first. It is a policy
## choice about where to look, so it lives with the filters and is named, not
## buried in an enumerator as if it were a rule.
static func nearestDestinations(context: DecisionContext, actorID: int,
		limit: int) -> Array[Vector2i]:
	var reach := context.reachability(actorID)
	var origin: Vector2i = reach["origin"]
	var destinations: Array = (reach["destinations"] as Array).duplicate()
	if limit <= 0 or destinations.size() <= limit:
		var all: Array[Vector2i] = []
		for destination: Vector2i in destinations:
			all.append(destination)
		return all
	destinations.sort_custom(func(a: Vector2i, b: Vector2i) -> bool:
		if a == origin and b == origin:
			return false
		if a == origin:
			return true
		if b == origin:
			return false
		var distanceA := context.nearestEnemyDistance(actorID, a)
		var distanceB := context.nearestEnemyDistance(actorID, b)
		if distanceA != distanceB:
			return distanceA < distanceB
		return DecisionContext.rowMajorLess(a, b)
	)
	var limited: Array[Vector2i] = []
	for destination: Vector2i in destinations.slice(0, limit):
		limited.append(destination)
	return limited
