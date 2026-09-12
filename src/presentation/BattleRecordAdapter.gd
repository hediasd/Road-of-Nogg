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
const RECORD_VERSION := 1

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
func _on_turn_started(monsterID: int, roundNumber: int, turnNumber: int) -> void:
	if _sim == null:
		return
	_historyMark = _sim.state.history.size()
	_open = {
		"index": _decisions.size(),
		"round": roundNumber,
		"turn": turnNumber,
		"party_id": int(_sim.state.activePartyID),
		"actor_id": monsterID,
		"observation": _observation(monsterID),
		"legal": _legalActions(monsterID),
		"before": _positions(),
	}


## Closes it. The command itself is read from the simulator's own history rather than stitched
## back together from the events in between: `finishTurn()` writes exactly one `command` event per
## turn and the replay system already trusts it, so reading it here means the record and a replay
## of the same battle agree by construction instead of by coincidence.
func _on_turn_ended(monsterID: int) -> void:
	if _open.is_empty() or int(_open.get("actor_id", -1)) != monsterID:
		return
	var chosen := {}
	var result := {}
	var rejected: Array = []
	for index in range(_historyMark, _sim.state.history.size()):
		var event: Dictionary = _sim.state.history[index]
		var type := str(event.get("type", ""))
		if type == "command" and int(event.get("actor_id", -1)) == monsterID:
			var data: Dictionary = event.get("data", {})
			chosen = SerializerScript.jsonSafe(data.get("command", {}))
			result = SerializerScript.jsonSafe(data.get("result", {}))
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
	_decisions.append(decision)
	_open = {}


## A petrified member never reaches `finishTurn`, so its turn would otherwise close with an empty
## command and no reason. Held until `_on_turn_ended` so the reason lands on that member's own
## decision rather than on whoever acts next.
func _on_monster_skipped_turn(monsterID: int, reason: String) -> void:
	_skips.append({"actor_id": monsterID, "reason": reason})


func _on_battle_ended(winningTeam: int) -> void:
	if _sim == null:
		return
	_outcome = {
		"winner_team": winningTeam,
		"rounds": int(_sim.state.roundCount),
		"decisions": _decisions.size(),
		"survivors": _survivors(),
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
		"parties": _parties(scenario),
		"brains": _brains(),
		"decisions": _decisions,
		"outcome": _outcome if not _outcome.is_empty() else {
			"winner_team": int(state.battleOutcome),
			"rounds": int(state.roundCount),
			"decisions": _decisions.size(),
			"survivors": _survivors(),
		},
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
			"is_actor": int(monsterID) == actorID,
			"effects": _effects(int(monsterID)),
		})
	return {"actor_id": actorID, "monsters": monsters}


func _effects(monsterID: int) -> Array:
	var result: Array = []
	for effect in _sim.state.getActiveEffects(monsterID):
		if not effect is Dictionary:
			continue
		result.append({
			"name": str((effect as Dictionary).get("name", "")),
			"remaining": int((effect as Dictionary).get("remainingTurns", 0)),
			"damage_per_turn": int((effect as Dictionary).get("damagePerTurn", 0)),
		})
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
