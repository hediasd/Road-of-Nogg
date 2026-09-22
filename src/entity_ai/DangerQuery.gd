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
## Geometry is shared rather than re-derived. Which tiles a unit could strike, and
## from where, is the same answer whoever is asking, so it is computed once per
## unit on the decision context and looked up here; only the damage depends on
## who is standing on the tile. Nothing is pruned by a distance guess: the reach
## comes from the authoritative resolvers, so an ability whose range this code
## could not have reasoned about is included rather than dropped, and the
## assessment says when one was seen.

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
##
## The geometry comes from the context's shared strike reach, computed once per
## unit rather than re-derived for every tile asked about -- a side policy asks
## about dozens of tiles with the same few enemies, and re-deriving was the most
## expensive thing in a decision. Only the damage is computed here, because only
## the damage depends on who is standing on the tile.
static func _replyOptions(context: DecisionContext, enemyID: int,
		tile: Vector2i, assessment: DangerAssessment, budget: int) -> Array:
	var options: Array = []
	var state := context.state()
	var enemy: Monster = state.getMonster(enemyID)
	if enemy == null or not enemy.is_alive():
		return options
	if assessment.queries >= budget:
		assessment.truncated = true
		return options
	var resolver := context.resolver()
	var victim: Monster = state.getMonsterAt(tile)
	var reach := context.strikeReach(enemyID)

	for wayValue in (reach["spells"] as Dictionary).get(tile, []):
		var way: Dictionary = wayValue
		assessment.queries += 1
		var from: Vector2i = way["from"]
		var spell: Spell = enemy.spellSets[int(way["set"])][int(way["index"])]
		var damage := _spellDamageAt(resolver, enemy, victim, spell, from)
		if damage > 0:
			options.append({"enemy_id": enemyID, "value": damage,
				"from": from, "kind": "spell"})

	var meleeFrom = (reach["melee"] as Dictionary).get(tile)
	if meleeFrom != null and Vector2i(meleeFrom) != tile:
		assessment.queries += 1
		var damage := enemy.atk if victim == null else 			resolver.calculateBasicDamage(enemy, victim, true, Vector2i(meleeFrom))
		if damage > 0:
			options.append({"enemy_id": enemyID, "value": damage,
				"from": Vector2i(meleeFrom), "kind": "melee"})
	return options


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
