## The one place anything asks how dangerous a tile is.
##
## Commander safety, whether a heal is worth casting, and how a destination
## ranks are the same question asked three ways, and they used to be answered by
## three different pieces of arithmetic. They go through here now, so a change to
## what "dangerous" means reaches all of them at once.
##
## Two rules about what this may claim:
##
## - **A bound is not a prediction.** Adding up every enemy's best reply counts
##   enemies who could not all actually do it. That number is honest only while
##   it is labelled `BOUND`, and `DangerAssessment` labels it.
## - **Pre-move magic is respected.** An enemy that walks cannot then cast, so a
##   spell is only ever credited from where the enemy already stands. The
##   influence map this replaces credited casts from every tile an enemy could
##   walk to, which inflated danger around any caster that could move.
##
## Work is bounded and counted. Every query reports what it spent, and a caller
## that hands over a budget gets a truncated answer rather than a stall -- with
## `truncated` set, because an answer that ran out of budget is a different
## thing from one that finished.
##
## Cheap geometric rejection comes first: an enemy whose movement plus reach
## cannot span the distance to the tile is dropped before anything asks the
## resolvers about legality, line of sight or height. That bound is deliberately
## generous, and any capability it cannot reason about -- an unfamiliar
## traversal, an effect with no declared range -- falls back to *not* rejecting,
## because a bound that prunes something it does not understand is unsound.

class_name DangerQuery
extends RefCounted

const AssessmentScript = preload("res://src/entity_ai/DangerAssessment.gd")
const HexGridScript = preload("res://src/board/HexGrid.gd")

## Named blind spots. A caller that wants to know what a number does not cover
## reads these off the assessment rather than out of this comment.
const APPROX_NO_REACTIONS := "ignores_reaction_passives"
const APPROX_NO_STATUS_TICKS := "ignores_status_damage_over_time"
const APPROX_SINGLE_ROUND := "single_enemy_round_only"
const APPROX_GREEDY_ASSIGNMENT := "feasible_assignment_is_greedy_not_optimal"
const APPROX_UNBOUNDED_ABILITY := "an_ability_without_a_declared_range_was_not_pruned"

## Enough work for a side of a handful of units on a normal board. A caller with
## a tighter frame spends less and is told that it did.
const DEFAULT_QUERY_BUDGET := 20000


## The most one named enemy could deal at `tile`. Exact for that enemy.
static func reply(context: DecisionContext, enemyID: int, tile: Vector2i,
		budget: int = DEFAULT_QUERY_BUDGET) -> DangerAssessment:
	var assessment: DangerAssessment = AssessmentScript.create(
		AssessmentScript.REPLY, tile)
	assessment.note(APPROX_NO_REACTIONS)
	assessment.note(APPROX_NO_STATUS_TICKS)
	assessment.note(APPROX_SINGLE_ROUND)
	var best := _bestReply(context, enemyID, tile, assessment, budget)
	if not best.is_empty():
		assessment.value = int(best["value"])
		assessment.contributors[enemyID] = best
	return assessment


## Every hostile unit's best reply, added. An upper bound on what the side could
## do to a unit standing on `tile`, and the number to use when deciding whether
## somewhere is unsafe.
static func conservativeBound(context: DecisionContext, team: int,
		tile: Vector2i, budget: int = DEFAULT_QUERY_BUDGET) -> DangerAssessment:
	var assessment: DangerAssessment = AssessmentScript.create(
		AssessmentScript.BOUND, tile)
	assessment.note(APPROX_NO_REACTIONS)
	assessment.note(APPROX_NO_STATUS_TICKS)
	assessment.note(APPROX_SINGLE_ROUND)
	for enemyID in _hostileIDs(context, team):
		if assessment.queries >= budget:
			assessment.truncated = true
			break
		var best := _bestReply(context, enemyID, tile, assessment, budget)
		if best.is_empty():
			continue
		assessment.contributors[enemyID] = best
		assessment.value += int(best["value"])
	return assessment


## One continuation the side could actually carry out against `tile`: every
## enemy acts at most once, no two end on the same cell, and a caster stays put
## because magic is pre-move. A lower bound on the side's best answer.
static func feasibleContinuation(context: DecisionContext, team: int,
		tile: Vector2i, budget: int = DEFAULT_QUERY_BUDGET) -> DangerAssessment:
	var assessment: DangerAssessment = AssessmentScript.create(
		AssessmentScript.FEASIBLE, tile)
	assessment.note(APPROX_NO_REACTIONS)
	assessment.note(APPROX_NO_STATUS_TICKS)
	assessment.note(APPROX_SINGLE_ROUND)
	assessment.note(APPROX_GREEDY_ASSIGNMENT)

	## Collect each enemy's options, then take them in descending value. Greedy
	## over a conflict set is not the best assignment, and saying so is the point
	## of the label: this is what the side can certainly do, not the worst it
	## could do.
	var offers: Array = []
	for enemyID in _hostileIDs(context, team):
		if assessment.queries >= budget:
			assessment.truncated = true
			break
		for option in _replyOptions(context, enemyID, tile, assessment, budget):
			offers.append(option)
	offers.sort_custom(func(a: Dictionary, b: Dictionary) -> bool:
		if int(a["value"]) != int(b["value"]):
			return int(a["value"]) > int(b["value"])
		if int(a["enemy_id"]) != int(b["enemy_id"]):
			return int(a["enemy_id"]) < int(b["enemy_id"])
		return DecisionContext.rowMajorLess(a["from"], b["from"])
	)

	var usedCells: Dictionary = {tile: true}
	for offerValue in offers:
		var offer: Dictionary = offerValue
		var enemyID := int(offer["enemy_id"])
		if assessment.contributors.has(enemyID):
			continue
		var from: Vector2i = offer["from"]
		if usedCells.has(from):
			continue
		usedCells[from] = true
		assessment.contributors[enemyID] = {
			"value": int(offer["value"]), "from": from, "kind": str(offer["kind"]),
		}
		assessment.value += int(offer["value"])
	return assessment


## Whether a unit standing on `tile` could be taken off the board this enemy
## round. Commander safety asks exactly this, and it asks it of the bound,
## because being wrong in the other direction loses a commander.
static func couldBeDefeatedAt(context: DecisionContext, monsterID: int,
		tile: Vector2i, budget: int = DEFAULT_QUERY_BUDGET) -> Dictionary:
	var monster: Monster = context.state().getMonster(monsterID)
	if monster == null:
		return {"at_risk": false, "danger": 0, "hitpoints": 0}
	var assessment := conservativeBound(context, monster.team, tile, budget)
	var incoming := assessment.value + _statusDamagePerTurn(context, monsterID)
	return {
		"at_risk": incoming >= monster.hitpoints,
		"danger": incoming,
		"hitpoints": monster.hitpoints,
		"assessment": assessment,
	}


## What a heal on `targetID` is actually worth: the hit points it restores, but
## only when the target could fall before acting again without them. A heal that
## changes nobody's survival is worth nothing, however much it restores.
static func healWorth(context: DecisionContext, targetID: int, tile: Vector2i,
		restored: int, budget: int = DEFAULT_QUERY_BUDGET) -> int:
	if restored <= 0:
		return 0
	var risk := couldBeDefeatedAt(context, targetID, tile, budget)
	return restored if bool(risk.get("at_risk", false)) else 0


static func _hostileIDs(context: DecisionContext, team: int) -> Array[int]:
	var state := context.state()
	var hostile: Array[int] = []
	for monsterIDValue in state.getAliveMonsterIDs():
		var monsterID := int(monsterIDValue)
		var monster: Monster = state.getMonster(monsterID)
		if monster == null or monster.team == team:
			continue
		hostile.append(monsterID)
	hostile.sort()
	return hostile


static func _bestReply(context: DecisionContext, enemyID: int, tile: Vector2i,
		assessment: DangerAssessment, budget: int) -> Dictionary:
	var best: Dictionary = {}
	for optionValue in _replyOptions(context, enemyID, tile, assessment, budget):
		var option: Dictionary = optionValue
		if best.is_empty() or int(option["value"]) > int(best["value"]):
			best = {"value": int(option["value"]), "from": option["from"],
				"kind": option["kind"]}
	return best


## Every way this enemy could hit `tile`, with where it would have to stand.
## Cheap geometry rejects the impossible before the resolvers are asked anything.
static func _replyOptions(context: DecisionContext, enemyID: int,
		tile: Vector2i, assessment: DangerAssessment, budget: int) -> Array:
	var options: Array = []
	var state := context.state()
	var enemy: Monster = state.getMonster(enemyID)
	if enemy == null or not enemy.is_alive():
		return options
	var resolver := context.resolver()
	var origin: Vector2i = state.getMonsterPosition(enemyID)
	var victim: Monster = state.getMonsterAt(tile)

	## Magic is pre-move, so a cast only ever happens from where the enemy is.
	for setIndex in range(enemy.spellSets.size()):
		for spellIndex in range(enemy.spellSets[setIndex].size()):
			var spell: Spell = enemy.spellSets[setIndex][spellIndex]
			if spell.heals or not enemy.can_cast(spell):
				continue
			if not _couldReach(enemy, spell, origin, tile, assessment):
				continue
			if assessment.queries >= budget:
				assessment.truncated = true
				return options
			for centerPos: Vector2i in resolver.getSpellTargetPositionsFrom(
					enemyID, setIndex, spellIndex, origin, true):
				assessment.queries += 1
				var affected: Array = resolver.getSpellAffectedPositionsFrom(
					enemyID, setIndex, spellIndex, origin, centerPos, true)
				if not affected.has(tile):
					continue
				var damage := _spellDamageAt(resolver, enemy, victim, spell, origin)
				if damage <= 0:
					continue
				options.append({"enemy_id": enemyID, "value": damage,
					"from": origin, "kind": "spell"})
				break

	## Melee happens after moving, so any reachable cell adjacent to the tile
	## counts -- except the tile itself, which its occupant is standing on.
	var reach := context.reachability(enemyID)
	for destination: Vector2i in reach["destinations"]:
		if destination == tile:
			continue
		if HexGridScript.distance(destination, tile) != 1:
			continue
		if assessment.queries >= budget:
			assessment.truncated = true
			return options
		assessment.queries += 1
		if not resolver.canBasicAttackPositionFrom(enemyID, destination, tile):
			continue
		var damage := enemy.atk if victim == null else \
			resolver.calculateBasicDamage(enemy, victim, true, destination)
		if damage <= 0:
			continue
		options.append({"enemy_id": enemyID, "value": damage,
			"from": destination, "kind": "melee"})
	return options


## Generous geometric rejection. Returns false only when no arrangement of legal
## movement and this ability's declared reach could span the gap. An ability
## that declares no reach is never rejected, and says so on the assessment.
static func _couldReach(enemy: Monster, spell: Spell, origin: Vector2i,
		tile: Vector2i, assessment: DangerAssessment) -> bool:
	if spell.range <= 0 and spell.radius <= 0 and spell.targetType != "self":
		assessment.note(APPROX_UNBOUNDED_ABILITY)
		return true
	var span := spell.range + spell.radius
	return HexGridScript.distance(origin, tile) <= span


static func _spellDamageAt(resolver: CombatResolver, enemy: Monster,
		victim: Monster, spell: Spell, from: Vector2i) -> int:
	if victim == null:
		return enemy.atk + spell.damage
	var total := 0
	for line in spell.damage_lines:
		var base := int(line.get("damage", 0))
		if base <= 0:
			continue
		total += resolver.calculateSpellDamage(enemy, victim, base,
			str(line.get("element", "none")), true, from)
	return total


static func _statusDamagePerTurn(context: DecisionContext, monsterID: int) -> int:
	var total := 0
	for effect in context.state().getActiveEffects(monsterID):
		total += maxi(0, int(effect.get("damagePerTurn", 0)))
	return total
