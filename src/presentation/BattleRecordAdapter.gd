## Records a battle as machine-readable data, for training rather than for reading.
##
## WHY A SECOND ADAPTER RATHER THAN A SECOND FORMAT IN THE FIRST ONE. `ConsoleVisualAdapter`
## writes prose with emoji for a person following one run; this writes structured decisions for a
## program consuming thousands. Those are different jobs with opposite pressures -- one wants
## narrative and elision, the other wants completeness and stability -- and a single writer serving
## both ends up serving neither. Both attach to the same `BattleEvents`, so a run can produce both
## at once without either knowing the other exists.
##
## WHAT A RECORD IS FOR. A homebrew model has to be able to answer, from the file alone: what did
## the actor see, what could it have done instead, what did it do, and what did that lead to. Those
## four questions are the schema. Anything that cannot be reconstructed from the file is a gap in
## the corpus, and the gap is only discovered much later, by which point there is a corpus in the
## wrong shape -- so the bias here is toward recording more per decision, not less.
##
## THE LEGAL ACTION SPACE COMES FROM `ReachQuery`, WHICH IS NOT A CHOICE MADE HERE. That is the
## same query the player's own movement overlay and the CPU's own reach both read; recording its
## answer means the corpus says exactly what the game itself offered, and it cannot drift from what
## the simulator would actually have accepted. Deriving a second opinion here -- a private loop over
## neighbours, say -- would be a slow-motion bug: it would agree for months and then disagree about
## a terrain rule nobody thought to mirror.
##
## NOT THE CPU'S CANDIDATE SCORES. `PartyCommandDeliberation` enumerates and scores candidates
## internally, and capturing that list would mean reaching into `src/entity_ai/` and recording the
## current heuristic's opinion as if it were ground truth. What a learner needs is the legal move
## set and the outcome, not this brain's preferences -- and a corpus that encoded them would teach a
## model to imitate `TacticalBrain` rather than to win. The brain's own identity is recorded per
## battle, so a later pass can still segment by it.
##
## DETERMINISM IS A PROPERTY OF THIS FILE, NOT A HOPE. Nothing here reads a clock, a random number,
## an object id or a file-system order. Keys are sorted by `JSON.stringify`'s own `sort_keys`, and
## coordinates go through `BattleStateSerializer.jsonSafe` so they encode exactly the way the replay
## system already encodes them. Two runs at one seed produce byte-identical bytes, and
## `probe_battle_runner.gd` asserts it rather than trusting this paragraph.

class_name BattleRecordAdapter
extends IBattleVisualAdapter

const SerializerScript = preload("res://src/battle_sim/BattleStateSerializer.gd")
const ReachQueryScript = preload("res://src/battle_sim/ReachQuery.gd")

## Bumped when the shape below changes in a way a reader must notice. A consumer that finds a
## version it does not know should stop rather than guess which fields moved.
##
## 2 (FHB-6): the record carries the board and a per-monster catalogue, the outcome says why the
## battle ended, and the observation flags withdrawn members and their resonance. See the notes on
## `_board`, `_roster` and `_endReason` for the reading that found each gap.
##
## 3 (FHB-10): the scoring under the record changed, not only its shape. A round-limit battle now
## plays its last round to the end, a tied tally is a draw (`winner_team` 0) instead of a win for
## the first-listed team, and the outcome says `draw` outright. The brains changed in the same
## item (see `BattleCommandEvaluator.healWorth`), so v2 decisions came from a different policy too.
## A consumer must not pool the two versions.
const RECORD_VERSION := 4

## `outcome.end_reason` values. A round-limit win is decided by counting survivors, which is a
## different kind of result from a side being wiped out, and a scorer must be able to tell them
## apart without replaying the battle.
const END_ELIMINATION := "elimination"
const END_ROUND_LIMIT := "round_limit_survivor_count"

var _sim
var _decisions: Array = []
var _open: Dictionary = {}
var _historyMark: int = 0
var _outcome: Dictionary = {}
var _skips: Array = []


func _init(simulator) -> void:
	_sim = simulator


# --- event hooks -------------------------------------------------------------


## Opens a decision. Everything the actor could see and do is captured HERE, before any of it
## resolves -- after the fact the board has already moved and the question "what did it decide
## against" no longer has an answer.
func _on_unit_selected(sideID: int, monsterID: int) -> void:
	if _sim == null:
		return
	_historyMark = _sim.state.history.size()
	_open = {
		"index": _decisions.size(),
		"round": int(_sim.state.roundCount),
		"turn": int(_sim.state.turnCount),
		"side_id": sideID,
		# Who else in the party could have been activated instead, and the round's party order.
		# FHB-6: without these, member selection -- a real decision the player makes -- was
		# invisible, and the headless loop's "first eligible member" rule looked like a policy.
		"eligible_units": SerializerScript.jsonSafe(
			_sim.state.eligibleUnitIDs(sideID)
		),
		"side_order": SerializerScript.jsonSafe(_sim.state.sideOrder),
		"actor_id": monsterID,
		"observation": _observation(monsterID),
		"legal": _legalActions(monsterID),
		"before": _positions(),
	}


## Closes it. The command itself is read from the simulator's own history rather than stitched
## back together from the events in between: `finishTurn()` writes exactly one `command` event per
## turn and the replay system already trusts it, so reading it here means the record and a replay
## of the same battle agree by construction instead of by coincidence.
func _on_unit_spent(_sideID: int, monsterID: int) -> void:
	if _open.is_empty() or int(_open.get("actor_id", -1)) != monsterID:
		return
	var chosen := {}
	var result := {}
	var rejected: Array = []
	for index in range(_historyMark, _sim.state.history.size()):
		var event: Dictionary = _sim.state.history[index]
		var type := str(event.get("type", ""))
		if type == "unit_action" and int(event.get("actor_id", -1)) == monsterID:
			var data: Dictionary = event.get("data", {})
			result = SerializerScript.jsonSafe(data.get("result", {}))
			chosen = (result.get("command", {}) as Dictionary).duplicate(true)
			# `BattleCommandResult.to_dictionary()` nests the command it resolved, which is
			# byte-for-byte what `chosen` already holds. Dropped rather than stored twice: it
			# was four percent of the file, and two copies of one fact is a chance for a reader
			# to find them disagreeing.
			result.erase("command")
		elif type == "command_rejected" and int(event.get("actor_id", -1)) == monsterID:
			rejected.append(str((event.get("data", {}) as Dictionary).get("reason", "")))

	var decision := _open.duplicate(true)
	var before: Dictionary = decision["before"]
	decision.erase("before")
	decision["chosen"] = chosen
	decision["result"] = result
	decision["rejected"] = rejected
	decision["skipped"] = _takeSkipReason(monsterID)
	decision["changed"] = _changesSince(before)
	decision["withdrawals"] = []
	_decisions.append(decision)
	_open = {}


## A commander's death withdraws its party, but the simulator does that AFTER `turn_ended`, so the
## decision that killed the commander would otherwise close without saying its surviving members
## left the board. Found by FHB-6. Attached to the decision that caused it.
func _on_party_withdrawn(partyID: int, memberIDs: Array) -> void:
	if _decisions.is_empty():
		return
	var ids: Array = []
	for memberID in memberIDs:
		ids.append(int(memberID))
	ids.sort()
	(_decisions.back()["withdrawals"] as Array).append({"party_id": partyID, "member_ids": ids})


## A petrified member never reaches `finishTurn`, so its turn would otherwise close with an empty
## command and no reason. Held until `_on_turn_ended` so the reason lands on that member's own
## decision rather than on whoever acts next.
func _on_monster_skipped_turn(monsterID: int, reason: String) -> void:
	_skips.append({"actor_id": monsterID, "reason": reason})


func _on_battle_ended(winningTeam: int) -> void:
	if _sim == null:
		return
	_outcome = _outcomeBlock(winningTeam)


## Why the battle ended. `checkWinCondition()` answers -1 exactly when more than one side still
## stands, which at `battle_ended` can only mean the headless loop ran out of rounds and fell back to
## counting survivors. Found by FHB-6: seed 14 of the first hexmap championship ended at round 30
## with a winner, and nothing in its record said that winner was a tally rather than a result.
func _endReason() -> String:
	return END_ROUND_LIMIT if int(_sim.checkWinCondition()) == -1 else END_ELIMINATION


func _outcomeBlock(winningTeam: int) -> Dictionary:
	var survivors := _survivors()
	var byTeam: Dictionary = {}
	for monsterID in survivors:
		var team := str(int(_sim.state.getMonster(monsterID).team))
		byTeam[team] = int(byTeam.get(team, 0)) + 1
	return {
		"winner_team": winningTeam,
		# Said outright so a reader need not know that team ids start at 1 and 0 means nobody won.
		"draw": winningTeam == BattleSimulator.DRAW_TEAM,
		"end_reason": _endReason(),
		"rounds": int(_sim.state.roundCount),
		"decisions": _decisions.size(),
		"survivors": survivors,
		"survivors_by_team": byTeam,
	}


# --- record assembly ---------------------------------------------------------


## The finished record. `scenario` supplies the deployment the battle was built from, which the
## live state no longer carries once anything has moved.
##
## IDENTITY IS READ FROM THE SAME PLACES `createReplaySnapshot()` READS IT, deliberately: a record
## and a replay of one battle must name the same scenario, map, revision, fingerprint and seed, and
## the way to guarantee that is to take both from one source rather than to write the block twice.
func buildRecord(scenario) -> Dictionary:
	var state = _sim.state
	return {
		"record_version": RECORD_VERSION,
		"engine": Engine.get_version_info().get("string", ""),
		"ruleset_id": str(state.rulesetID),
		"grid_kind": str(state.gridKind),
		"coordinate_convention": str(state.coordinateConvention),
		"scenario": {
			"id": str(state.scenarioID),
			"revision": int(state.scenarioRevision),
			"path": str(state.scenarioPath),
		},
		"map": {
			"id": str(state.mapName),
			"revision": int(state.mapRevision),
			"source_fingerprint": str(state.battleMap.sourceFingerprint) if state.battleMap != null else "",
		},
		"content_fingerprint": str(state.contentFingerprint),
		"seed": int(state.battleSeed),
		"board": _board(),
		"parties": _parties(scenario),
		"roster": _roster(),
		"brains": _brains(),
		"decisions": _decisions,
		"outcome": _outcome if not _outcome.is_empty() else _outcomeBlock(int(state.battleOutcome)),
	}


## One record, one line. See `run_battle.gd`'s own note on why the corpus is JSONL and why a
## single battle is simply a one-line file rather than its own shape.
func recordLine(scenario) -> String:
	return JSON.stringify(buildRecord(scenario), "", true)


# --- observation -------------------------------------------------------------


## What the actor could see. Every living monster, not only the visible ones: line of sight is a
## rule a learner should be able to derive from positions and terrain, and baking this brain's
## visibility answer into the observation would hide that rule from it.
func _observation(actorID: int) -> Dictionary:
	var monsters: Array = []
	var ids: Array = _sim.state.monsters.keys()
	ids.sort()
	for monsterID in ids:
		var monster = _sim.state.monsters[monsterID]
		if monster == null:
			continue
		monsters.append({
			"id": int(monsterID),
			"name": str(monster.name),
			"team": int(monster.team),
			"party_id": int(_sim.state.monsterPartyIDs.get(monsterID, -1)),
			"pos": SerializerScript.jsonSafe(_sim.state.getMonsterPosition(int(monsterID))),
			"hp": int(monster.hitpoints),
			"max_hp": int(monster.max_hitpoints),
			"atk": int(monster.atk),
			"def": int(monster.def),
			"move": int(monster.move),
			"alive": bool(monster.is_alive()),
			# A member whose commander fell is withdrawn: still alive, off the board at (-1, -1),
			# and no longer counted for anything. Without this flag it reads as a living unit
			# standing on an impossible cell.
			"withdrawn": bool(_sim.state.isMonsterWithdrawn(int(monsterID))),
			"is_actor": int(monsterID) == actorID,
			"resonance": SerializerScript.jsonSafe(monster.resonance_bars),
			"effects": _effects(int(monsterID)),
		})
	return {"actor_id": actorID, "monsters": monsters}


## Every field the effect carries, not a chosen three. Effects are open dictionaries -- a buff
## holds `atk_bonus`, a mark holds `damage_multiplier` -- and the damage rules read those keys
## directly, so a reader given only name and duration cannot tell why a hit landed harder.
func _effects(monsterID: int) -> Array:
	var result: Array = []
	for effect in _sim.state.getActiveEffects(monsterID):
		if not effect is Dictionary:
			continue
		result.append(SerializerScript.jsonSafe(effect))
	return result


## Where the actor could go and what it could strike from there, straight from `ReachQuery` -- see
## the class note on why this is not recomputed here. Costs travel with their own cell rather than
## in a parallel dictionary keyed by a stringified vector, which would be both uglier and harder
## for a consumer to parse.
func _legalActions(monsterID: int) -> Dictionary:
	var reach: Dictionary = ReachQueryScript.forMonster(_sim, monsterID)
	var costs: Dictionary = reach.get("movement_costs", {})
	var reachable: Array = []
	for cell in reach.get("reachable", []):
		reachable.append({
			"cell": SerializerScript.jsonSafe(cell),
			"cost": int(costs.get(cell, 0)),
		})
	var attackable: Array = []
	for cell in reach.get("attackable", []):
		attackable.append(SerializerScript.jsonSafe(cell))
	return {
		"reachable": reachable,
		"attackable": attackable,
		"spells": _spellMenu(monsterID),
	}


## The actor's own spell menu, indexed exactly the way a command addresses it -- `spell_set_index`
## then `spell_index`. Found by reading one real record back as if training on it: the chosen
## command carries those two integers and nothing else in the decision said what they could have
## been, so a policy could see WHICH spell was cast but never learn which ones it was choosing
## among, or that a cooldown had taken one off the menu. `ReachQuery` cannot answer this -- it is
## about reach, not about the menu -- so it is read from the monster itself.
func _spellMenu(monsterID: int) -> Array:
	var monster = _sim.state.getMonster(monsterID)
	if monster == null:
		return []
	var sets: Array = []
	for setIndex in monster.spellSets.size():
		var spells: Array = []
		for spellIndex in monster.spellSets[setIndex].size():
			var spell = monster.spellSets[setIndex][spellIndex]
			if spell == null:
				continue
			var remaining := int(monster.spell_cooldowns.get(spell.name, 0))
			spells.append({
				"spell_index": spellIndex,
				"name": str(spell.name),
				"element": str(spell.element),
				"target_type": str(spell.targetType),
				"radius": int(spell.radius),
				"cooldown_remaining": remaining,
				"ready": remaining <= 0,
			})
		sets.append({"spell_set_index": setIndex, "spells": spells})
	return sets


# --- change tracking ---------------------------------------------------------


func _positions() -> Dictionary:
	var snapshot: Dictionary = {}
	for monsterID in _sim.state.monsters:
		var monster = _sim.state.monsters[monsterID]
		if monster == null:
			continue
		snapshot[int(monsterID)] = {
			"hp": int(monster.hitpoints),
			"pos": _sim.state.getMonsterPosition(int(monsterID)),
			"alive": bool(monster.is_alive()),
		}
	return snapshot


## Only what actually moved. A full after-state per decision would double the file to restate the
## nine tenths of the board that did not change, and the observation of the NEXT decision already
## carries the resulting board in full.
func _changesSince(before: Dictionary) -> Array:
	var changes: Array = []
	var ids: Array = before.keys()
	ids.sort()
	for monsterID in ids:
		var monster = _sim.state.monsters.get(monsterID)
		if monster == null:
			continue
		var was: Dictionary = before[monsterID]
		var nowPos: Vector2i = _sim.state.getMonsterPosition(int(monsterID))
		var nowHP := int(monster.hitpoints)
		var nowAlive := bool(monster.is_alive())
		if nowHP == int(was["hp"]) and nowPos == was["pos"] and nowAlive == bool(was["alive"]):
			continue
		changes.append({
			"id": int(monsterID),
			"hp_before": int(was["hp"]),
			"hp_after": nowHP,
			"pos_before": SerializerScript.jsonSafe(was["pos"]),
			"pos_after": SerializerScript.jsonSafe(nowPos),
			"alive_before": bool(was["alive"]),
			"alive_after": nowAlive,
		})
	return changes


func _takeSkipReason(monsterID: int) -> String:
	for index in range(_skips.size() - 1, -1, -1):
		var entry: Dictionary = _skips[index]
		if int(entry.get("actor_id", -1)) == monsterID:
			_skips.remove_at(index)
			return str(entry.get("reason", ""))
	return ""


func _survivors() -> Array:
	var result: Array = []
	var ids: Array = _sim.state.getAliveMonsterIDs()
	ids.sort()
	for monsterID in ids:
		result.append(int(monsterID))
	return result


## The deployment the battle was built from. Taken from the scenario rather than from the live
## state because the state's positions are wherever the battle ended, not where it began.
func _parties(scenario) -> Array:
	var result: Array = []
	if scenario == null:
		return result
	for party in scenario.parties:
		var members: Array = []
		for memberID in party.memberIDs:
			members.append({
				"member_id": int(memberID),
				"monster": str(party.monsterNames.get(memberID, "")),
				"level": int(party.memberLevels.get(memberID, 1)),
				"cell": SerializerScript.jsonSafe(party.startingCells.get(memberID, Vector2i.ZERO)),
			})
		result.append({
			"party_id": int(party.partyID),
			"team_id": int(party.teamID),
			"controller": str(party.controller),
			"commander_id": int(party.commanderID),
			"members": members,
		})
	return result


## The battlefield, once per record. Found by FHB-6 reading a hexmap record as the model: the
## record named the map by fingerprint and nothing else, so which cells were water, and why a
## reachable set stopped where it did, could only be answered by opening a second file. Every valid
## cell is listed with its terrain and height, plus the terrain table those names resolve through,
## so movement, line of sight and elevation damage are all derivable from this line alone. About
## 8 KB against a record of roughly 250 KB.
func _board() -> Dictionary:
	var state = _sim.state
	var definition = state.battleMap
	var cells: Array = []
	var terrainTable: Dictionary = {}
	if definition != null:
		var valid: Array = definition.validCells()
		valid.sort_custom(func(a: Vector2i, b: Vector2i) -> bool:
			return a.y < b.y or (a.y == b.y and a.x < b.x))
		for cell: Vector2i in valid:
			cells.append({
				"cell": SerializerScript.jsonSafe(cell),
				"terrain": definition.terrainAt(cell),
				"height": definition.heightAt(cell),
			})
		terrainTable = SerializerScript.jsonSafe(definition.terrainDefinitions)
	return {
		"size": SerializerScript.jsonSafe(state.boardSize),
		"cells": cells,
		"terrain_definitions": terrainTable,
	}


## What each monster IS, once per record: the stats and spell parameters that do not change turn by
## turn. Found by FHB-6: the per-decision spell menu gave a name, an element and a radius, so a
## reader could see a spell was ready but not how far it reached, what it did or how long its
## cooldown was; and the observation omitted level, speed, luck and race, which decide party order,
## critical chance and elemental damage. Kept out of the decisions so a static fact is written once
## rather than eighty times.
func _roster() -> Dictionary:
	var result: Dictionary = {}
	var ids: Array = _sim.state.monsters.keys()
	ids.sort()
	for monsterID in ids:
		var monster = _sim.state.monsters[monsterID]
		if monster == null:
			continue
		var passives: Array = []
		for passive in monster.passives:
			# Parameters, not only names: in seed 14 a dying Snowzilla's `Snowfall` took 15 HP off
			# four monsters inside one decision, and nothing else in the record could say why.
			if passive != null:
				passives.append({
					"name": str(passive.name),
					"trigger": str(passive.trigger),
					"effect_type": str(passive.effect_type),
					"value": passive.value,
					"element": str(passive.element),
					"radius": int(passive.radius),
				})
		var sets: Array = []
		for setIndex in monster.spellSets.size():
			var spells: Array = []
			for spellIndex in monster.spellSets[setIndex].size():
				var spell = monster.spellSets[setIndex][spellIndex]
				if spell == null:
					continue
				spells.append(_spellParameters(spell, spellIndex))
			sets.append({"spell_set_index": setIndex, "spells": spells})
		result[str(int(monsterID))] = {
			"name": str(monster.name),
			"team": int(monster.team),
			"level": int(monster.level),
			"speed": int(monster.speed),
			"luck": int(monster.luck),
			"critical_chance": monster.get_critical_chance(),
			"jump": int(monster.jump),
			"race": str(monster.race),
			"family": str(monster.family),
			"elements": SerializerScript.jsonSafe(monster.elements),
			"passives": passives,
			"spell_sets": sets,
		}
	return result


func _spellParameters(spell, spellIndex: int) -> Dictionary:
	return {
		"spell_index": spellIndex,
		"name": str(spell.name),
		"element": str(spell.element),
		"target_type": str(spell.targetType),
		"area_shape": str(spell.area_shape),
		"radius": int(spell.radius),
		"self_radius": int(spell.self_radius),
		"min_range": int(spell.min_range),
		"range": int(spell.range),
		"max_height_delta": int(spell.max_height_delta),
		"damage": int(spell.damage),
		"damage_lines": SerializerScript.jsonSafe(spell.damage_lines),
		"heals": bool(spell.heals),
		"heal_amount": int(spell.heal_amount),
		"inflicts_status": str(spell.inflicts_status),
		"removes_status": str(spell.removes_status),
		"buffs_atk": int(spell.buffs_atk),
		"buff_duration": int(spell.buff_duration),
		"reverts_damage": bool(spell.reverts_damage),
		"bypass_los": bool(spell.bypass_los),
		"can_target_empty": bool(spell.can_target_empty),
		"cooldown": int(spell.cooldown),
		"resonance_element": str(spell.resonance_element),
		"sequence_level": int(spell.sequence_level),
		"aoe_targets": str(spell.aoe_targets),
		"effects": SerializerScript.jsonSafe(spell.effects),
	}


## Which brain drove each member. Not the candidates it considered -- see the class note -- but
## enough that a later pass can segment a corpus by the policy that generated it.
func _brains() -> Dictionary:
	var result: Dictionary = {}
	for monsterID in _sim.brains:
		var brain = _sim.brains[monsterID]
		if brain == null:
			continue
		result[str(monsterID)] = brain.get_script().resource_path.get_file().get_basename()
	return result
