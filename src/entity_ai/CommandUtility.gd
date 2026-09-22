## What one candidate is worth, in components a human can read back.
##
## Every number here is an integer in one currency -- hit points -- so terms can
## be compared without a weight table deciding what "utility" means. Terminal
## outcomes sit above that currency on their own tiers, because winning is not
## worth some number of hit points, it is worth the game.
##
## The two danger labels are used for the two different jobs they exist for:
##
## - **The bound decides survival.** A destination where everything the enemy
##   side could throw would take the unit off the board is refused outright,
##   whatever it scores. Overstating danger costs a tile; understating it costs
##   a unit.
## - **The feasible continuation prices the trade.** What the side can really
##   carry out is what the unit is actually paying, and only the *added*
##   exposure is charged: danger the unit already stands in is not a reason to
##   act, and retreating earns nothing, so a unit cannot buy points by running.
##
## Position is a first-class term, not a tiebreak. Closing to melee is worth
## nothing this turn and everything next turn, and a one-decision horizon cannot
## see that; `EngagementBand` prices it so a bruiser will pay real exposure to
## reach the distance it fights at, while an archer will not.

class_name CommandUtility
extends RefCounted

const BandScript = preload("res://src/entity_ai/EngagementBand.gd")
const DangerScript = preload("res://src/entity_ai/DangerQuery.gd")
const HexGridScript = preload("res://src/board/HexGrid.gd")

## Terminal tiers. Far apart so no accumulation of ordinary value can climb one.
const WIN_BATTLE := 1_000_000
const DEFEAT_COMMANDER := 100_000
const DEFEAT_UNIT := 10_000


## The cheap half: everything that does not need to know what the enemy could
## do back. Scoring in two passes is what keeps the policy affordable -- asking
## the danger contract about every destination a side could reach costs more
## than the rest of the decision put together, so only a shortlist earns it.
static func preScore(context: DecisionContext, candidate: ActionCandidate,
		configuration: Dictionary) -> Dictionary:
	var state := context.state()
	var actor: Monster = state.getMonster(candidate.actor_id)
	var trace := {
		"tie_key": candidate.tie_key,
		"action_class": candidate.action_class,
		"destination": {"x": candidate.destination.x, "y": candidate.destination.y},
		"components": {},
		"rejected": "",
		"score": 0,
		"priced": false,
	}
	if actor == null or not actor.is_alive():
		trace["rejected"] = "actor_gone"
		return trace
	var outcome := _offensiveOutcome(context, candidate, actor)
	var origin: Vector2i = context.reachability(candidate.actor_id)["origin"]
	var bands := BandScript.bandsFor(state, candidate.actor_id)
	var positionBefore := BandScript.bestFitValue(bands,
		context.nearestEnemyDistance(candidate.actor_id, origin))
	var positionAfter := BandScript.bestFitValue(bands,
		context.nearestEnemyDistance(candidate.actor_id, candidate.destination))
	var terminal := 0
	if bool(outcome["wins_battle"]):
		terminal += WIN_BATTLE
	terminal += int(outcome["commanders"]) * DEFEAT_COMMANDER
	terminal += int(outcome["defeats"]) * DEFEAT_UNIT
	trace["components"] = {
		"terminal": terminal,
		"damage": int(outcome["damage"]),
		"support": int(outcome["support"]),
		"position": (positionAfter - positionBefore)
			* int(configuration.get("position_weight", 1)),
		"commander_preference": int(configuration.get("commander_preference", 1))
			if bool(outcome["touches_commander"]) else 0,
		## Swinging at an empty tile, or casting where the spell catches
		## nobody, is waiting with extra steps -- and it is worse than waiting,
		## because it is a command a player's own controls cannot express. It
		## must never win at a destination where Wait is also available, so its
		## penalty is strictly the larger one. Waiting itself is still penalised,
		## so anything that achieves something beats standing there.
		"idle_penalty": _idlePenalty(candidate, bool(outcome["useful"]), configuration),
	}
	trace["decisive"] = bool(outcome["wins_battle"]) or int(outcome["commanders"]) > 0
	trace["score"] = _total(trace["components"])
	return trace


## The expensive half, for shortlisted candidates only: what the destination
## costs. Returns the same trace with the survival gate applied and the risk
## term added, or a rejection.
static func priceRisk(context: DecisionContext, candidate: ActionCandidate,
		configuration: Dictionary, dangerCache: Dictionary,
		trace: Dictionary) -> Dictionary:
	var state := context.state()
	var actor: Monster = state.getMonster(candidate.actor_id)
	if actor == null or not actor.is_alive():
		trace["rejected"] = "actor_gone"
		return trace
	var origin: Vector2i = context.reachability(candidate.actor_id)["origin"]
	var here := _danger(context, actor.team, origin, dangerCache, configuration)
	var there := _danger(context, actor.team, candidate.destination, dangerCache,
		configuration)
	## The veto is on the **feasible** continuation, not the bound. The bound
	## assumes every enemy on the board turns on this one unit; that is a real
	## worst case, but vetoing on it makes a unit refuse every engagement as soon
	## as it has taken a wound, and both sides then stand and look at each other
	## until the round cap. Measured on the technical scenario: vetoing on the
	## bound gave 30 rounds and no result, vetoing on the feasible reply gives a
	## decided battle.
	var lethal := int(there["feasible"]) + int(there["status"]) >= actor.hitpoints
	if lethal and not bool(trace.get("decisive", false)):
		trace["rejected"] = "destination_is_lethal"
		trace["components"]["feasible"] = int(there["feasible"])
		return trace
	## The worst case is still priced, just not obeyed: the excess of the bound
	## over the realistic reply is what this destination risks going wrong by.
	var addedRisk := maxi(0, int(there["feasible"]) - int(here["feasible"]))
	var worstHere := maxi(0, int(here["bound"]) - int(here["feasible"]))
	var worstThere := maxi(0, int(there["bound"]) - int(there["feasible"]))
	var addedExposure := maxi(0, worstThere - worstHere)
	trace["components"]["risk"] = -addedRisk * int(configuration.get("risk_weight", 1))
	trace["components"]["exposure"] = -addedExposure * int(
		configuration.get("exposure_weight", 1))
	trace["score"] = _total(trace["components"])
	trace["approximations"] = there["approximations"]
	trace["priced"] = true
	return trace


static func _idlePenalty(candidate: ActionCandidate, useful: bool,
		configuration: Dictionary) -> int:
	var penalty := int(configuration.get("idle_penalty", 1))
	if useful:
		return 0
	if candidate.action_class == "wait":
		return -penalty
	return -(penalty + 1)


static func _total(components: Dictionary) -> int:
	var total := 0
	for key in components:
		if key == "bound" or key == "feasible":
			continue
		total += int(components[key])
	return total


## Scores one candidate in one call. Used where cost does not matter, such as a
## probe checking that the two-pass path agrees with the whole answer.
static func score(context: DecisionContext, candidate: ActionCandidate,
		configuration: Dictionary, dangerCache: Dictionary) -> Dictionary:
	var trace := preScore(context, candidate, configuration)
	if not str(trace.get("rejected", "")).is_empty():
		return trace
	return priceRisk(context, candidate, configuration, dangerCache, trace)


## What resolving this candidate would do, asked of the canonical resolvers
## rather than guessed. Damage is an estimate under current rules, not a
## forecast: a forecast per candidate costs a fork per candidate.
static func _offensiveOutcome(context: DecisionContext, candidate: ActionCandidate,
		actor: Monster) -> Dictionary:
	var state := context.state()
	var resolver := context.resolver()
	var damage := 0
	var support := 0
	var defeats := 0
	var commanders := 0
	var touchesCommander := false
	var hostilesRemaining := 0
	for monsterIDValue in state.getAliveMonsterIDs():
		var monster: Monster = state.getMonster(int(monsterIDValue))
		if monster != null and monster.team != actor.team:
			hostilesRemaining += 1

	if candidate.action_class == "attack":
		var targetID := candidate.command.target_id
		var target: Monster = state.getMonster(targetID) if targetID >= 0 else null
		if target != null and target.team != actor.team:
			damage = resolver.calculateBasicDamage(actor, target, true,
				candidate.destination)
			if _isCommander(state, targetID):
				touchesCommander = true
			if damage >= target.hitpoints:
				defeats += 1
				if _isCommander(state, targetID):
					commanders += 1
	elif candidate.action_class.begins_with("spell"):
		var spell: Spell = actor.spellSets[candidate.spell_set_index][candidate.spell_index]
		for affectedID in candidate.affected_targets:
			var target: Monster = state.getMonster(affectedID)
			if target == null:
				continue
			if spell.heals:
				if target.team != actor.team:
					continue
				var restored := mini(target.max_hitpoints - target.hitpoints,
					resolver.calculateHeal(actor, spell))
				support += DangerScript.healWorth(context, affectedID,
					state.getMonsterPosition(affectedID), restored)
				continue
			if target.team == actor.team:
				## Catching your own side is a cost, priced the same way.
				damage -= _spellDamage(resolver, actor, target, spell, candidate.destination)
				continue
			var dealt := _spellDamage(resolver, actor, target, spell, candidate.destination)
			damage += dealt
			if _isCommander(state, affectedID):
				touchesCommander = true
			if dealt >= target.hitpoints:
				defeats += 1
				if _isCommander(state, affectedID):
					commanders += 1

	return {
		"damage": damage,
		"support": support,
		"defeats": defeats,
		"commanders": commanders,
		"touches_commander": touchesCommander,
		"useful": damage > 0 or support > 0 or defeats > 0,
		"wins_battle": defeats > 0 and defeats >= hostilesRemaining,
	}


static func _spellDamage(resolver: CombatResolver, actor: Monster, target: Monster,
		spell: Spell, from: Vector2i) -> int:
	var total := 0
	for line in spell.damage_lines:
		var base := int(line.get("damage", 0))
		if base <= 0:
			continue
		total += resolver.calculateSpellDamage(actor, target, base,
			str(line.get("element", "none")), true, from)
	return total


static func _isCommander(state: BattleState, monsterID: int) -> bool:
	for partyID in state.parties:
		if int(state.parties[partyID].commanderID) == monsterID:
			return true
	return false


static func _danger(context: DecisionContext, team: int, tile: Vector2i,
		cache: Dictionary, configuration: Dictionary = {}) -> Dictionary:
	var key := [team, tile]
	if cache.has(key):
		return cache[key]
	var budget := int(configuration.get("danger_budget", DangerScript.DEFAULT_QUERY_BUDGET))
	var bound := DangerScript.conservativeBound(context, team, tile, budget)
	var feasible := DangerScript.feasibleContinuation(context, team, tile, budget)
	var entry := {
		"bound": bound.value,
		"feasible": feasible.value,
		"status": 0,
		"approximations": bound.approximations.duplicate(),
	}
	cache[key] = entry
	return entry
