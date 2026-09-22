## Everything an actor may legally do this turn, asked of the simulator.
##
## Complete enumeration and the bounded subset a policy actually searches are
## two different things, and this is the complete one. Nothing here decides that
## a move is bad, pointless or too numerous; `CandidateFilter` does that, in the
## open, where it can be measured. Legality itself is never re-implemented --
## every question goes to `MovementResolver` and `CombatResolver`, so a rules
## change reaches the AI without anyone remembering to copy it across.
##
## Magic is pre-move only, so a spell is enumerated at the origin alone. That is
## a rule, not a budget: `BattleSimulator._sideLegalCommand()` rewrites a
## move-then-cast command into a move and a Wait, so the cast the policy thought
## it chose would never happen.

class_name LegalActionEnumerator
extends RefCounted

const CandidateScript = preload("res://src/entity_ai/ActionCandidate.gd")


## Every legal candidate for one actor, in a deterministic order.
static func forActor(context: DecisionContext, actorID: int) -> Array[ActionCandidate]:
	var candidates: Array[ActionCandidate] = []
	var state := context.state()
	var actor: Monster = state.getMonster(actorID)
	if actor == null or not actor.is_alive():
		return candidates
	var reach := context.reachability(actorID)
	var origin: Vector2i = reach["origin"]
	var resolver := context.resolver()

	for destination: Vector2i in reach["destinations"]:
		var path := context.pathTo(actorID, destination)
		## A destination the recorded predecessors do not reach contributes
		## nothing: there is no command that arrives there.
		if destination != origin and path.is_empty():
			continue

		candidates.append(CandidateScript.create(actorID, CandidateScript.CLASS_WAIT,
			destination, path, Vector2i(-1, -1), 0, 0, [], -1))

		var attackPositions: Array = resolver.getBasicAttackTargetPositionsFrom(
			actorID, destination)
		attackPositions.sort_custom(DecisionContext.rowMajorLess)
		for targetPos: Vector2i in attackPositions:
			var occupantID: int = resolver.getProjectedOccupantID(
				actorID, destination, targetPos)
			candidates.append(CandidateScript.create(actorID,
				CandidateScript.CLASS_ATTACK, destination, path, targetPos,
				0, 0, [], -1 if occupantID == 0 else occupantID))

		if destination != origin:
			continue
		for spellSetIndex in range(actor.spellSets.size()):
			for spellIndex in range(actor.spellSets[spellSetIndex].size()):
				candidates.append_array(_spellCandidates(
					context, actorID, destination, path, spellSetIndex, spellIndex))

	candidates.sort_custom(CandidateScript.tieKeyLess)
	return candidates


static func _spellCandidates(context: DecisionContext, actorID: int,
		destination: Vector2i, path: Array[Vector2i], spellSetIndex: int,
		spellIndex: int) -> Array[ActionCandidate]:
	var candidates: Array[ActionCandidate] = []
	var resolver := context.resolver()
	var centers: Array = resolver.getSpellTargetPositionsFrom(
		actorID, spellSetIndex, spellIndex, destination)
	centers.sort_custom(DecisionContext.rowMajorLess)
	for centerPos: Vector2i in centers:
		var affected: Array = resolver.getSpellAffectedTargetsFrom(
			actorID, spellSetIndex, spellIndex, destination, centerPos)
		## A castable centre that catches nobody is still a legal action, and a
		## distinct one: an effect that reads the ground rather than the units
		## standing on it would live here, and a policy that never sees the
		## class can never learn to use it.
		var actionClass := CandidateScript.CLASS_SPELL_UNIT if not affected.is_empty() \
			else CandidateScript.CLASS_SPELL_EMPTY
		var occupantID: int = resolver.getProjectedOccupantID(
			actorID, destination, centerPos) if context.state().withinBounds(centerPos) else 0
		candidates.append(CandidateScript.create(actorID, actionClass, destination,
			path, centerPos, spellSetIndex, spellIndex, affected,
			-1 if occupantID == 0 else occupantID))
	return candidates


## How much of the legal action space a set of candidates actually covers, by
## class. A sampler that reports a count and not this can look thorough while
## never once casting a spell.
static func classCoverage(candidates: Array) -> Dictionary:
	var counts: Dictionary = {}
	for actionClass: String in CandidateScript.ALL_CLASSES:
		counts[actionClass] = 0
	for candidateValue in candidates:
		var candidate: ActionCandidate = candidateValue
		counts[candidate.action_class] = int(counts.get(candidate.action_class, 0)) + 1
	return counts
