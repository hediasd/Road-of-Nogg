extends SceneTree

## FHB-5: the headless runner's two load-bearing promises.
##
## DETERMINISM IS THE ONE THAT MATTERS. A corpus whose records drift between runs at the same seed
## cannot be used to attribute anything -- a model trained on it would be learning partly from
## noise nobody can reproduce. Dictionary iteration order, float formatting and any clock reading
## all break it quietly, so this asserts byte equality of two real runs rather than trusting that
## none of those crept in.
##
## Runs both battles in-process through `run_battle.run()` rather than spawning the runner twice:
## the same-process case is the STRICTER test, because a fresh process would hide state that
## leaked between battles behind a clean interpreter.

const RunBattleScript = preload("res://scripts/battle/run_battle.gd")
const RecordAdapterScript = preload("res://src/presentation/BattleRecordAdapter.gd")

const CPU_SCENARIO := "res://data/battle/scenarios/proving_ground_cpu_cpu.json"
const PLAYER_SCENARIO := "res://data/battle/scenarios/proving_ground_player_cpu.json"
const SEED := 20260912

var failures: Array[String] = []


func _init() -> void:
	_checkDeterminism()
	_checkPlayerPartyRefused()
	_checkRecordShape()

	if not failures.is_empty():
		for failure in failures:
			printerr("HEX_BATTLE_RUNNER_FAILURE: %s" % failure)
		quit(1)
		return
	print("HEX_BATTLE_RUNNER_OK")
	quit(0)


func _checkDeterminism() -> void:
	var first := RunBattleScript.run(CPU_SCENARIO, SEED, "", "")
	var second := RunBattleScript.run(CPU_SCENARIO, SEED, "", "")
	_require(bool(first.get("ok", false)), "first run failed: %s" % str(first.get("error", "")))
	_require(bool(second.get("ok", false)), "second run failed: %s" % str(second.get("error", "")))
	if not bool(first.get("ok", false)) or not bool(second.get("ok", false)):
		return

	var a := str(first["line"])
	var b := str(second["line"])
	_require(a == b, "two runs at seed %d produced different records (%d vs %d bytes)" % [
		SEED, a.length(), b.length(),
	])
	# A record that is identical because it is EMPTY would pass the check above and mean nothing.
	_require(int(first.get("decisions", 0)) > 0, "the battle recorded no decisions at all")
	_require(int(first.get("winner_team", -1)) != -1, "the battle reached no winner")


## A console has nobody to choose a member or a command, so a player party must be refused rather
## than played by a fallback and recorded as though a policy chose it.
func _checkPlayerPartyRefused() -> void:
	var result := RunBattleScript.run(PLAYER_SCENARIO, SEED, "", "")
	_require(not bool(result.get("ok", false)), "a player-controlled scenario was simulated anyway")
	var error := str(result.get("error", ""))
	_require(error.contains("player"), "the refusal does not say what is wrong: %s" % error)


## Every field a consumer is promised. Checked on a real record rather than a synthetic one,
## because the point is that a battle actually produces them.
func _checkRecordShape() -> void:
	var result := RunBattleScript.run(CPU_SCENARIO, SEED, "", "")
	if not bool(result.get("ok", false)):
		_require(false, "shape run failed: %s" % str(result.get("error", "")))
		return
	var parsed = JSON.parse_string(str(result["line"]))
	_require(parsed is Dictionary, "the record line is not a JSON object")
	if not parsed is Dictionary:
		return
	var record: Dictionary = parsed

	for key: String in [
		"record_version", "engine", "ruleset_id", "grid_kind", "coordinate_convention",
		"scenario", "map", "content_fingerprint", "seed", "parties", "brains", "decisions",
		"outcome",
	]:
		_require(record.has(key), "the record has no '%s'" % key)

	_require(int(record.get("record_version", -1)) == RecordAdapterScript.RECORD_VERSION,
		"the record does not declare the adapter's own version")
	_require(int(record.get("seed", -1)) == SEED, "the record does not carry the seed it ran at")
	_require(not str((record.get("map", {}) as Dictionary).get("source_fingerprint", "")).is_empty(),
		"the record carries no map source fingerprint, so it cannot be tied to a map revision")

	var outcome: Dictionary = record.get("outcome", {})
	for key: String in ["winner_team", "rounds", "decisions", "survivors"]:
		_require(outcome.has(key), "the outcome has no '%s'" % key)

	var decisions: Array = record.get("decisions", [])
	_require(not decisions.is_empty(), "the record carries no decisions")
	if decisions.is_empty():
		return
	var decision: Dictionary = decisions[0]
	for key: String in [
		"index", "round", "turn", "party_id", "actor_id", "observation", "legal", "chosen",
		"result", "changed", "rejected", "skipped",
	]:
		_require(decision.has(key), "a decision has no '%s'" % key)

	# The four questions a record exists to answer: what did it see, what could it have done,
	# what did it do, what changed. Each needs actual content, not merely a present key.
	var observation: Dictionary = decision.get("observation", {})
	_require(not (observation.get("monsters", []) as Array).is_empty(),
		"the observation names no monsters")
	var legal: Dictionary = decision.get("legal", {})
	for key: String in ["reachable", "attackable", "spells"]:
		_require(legal.has(key), "the legal action space has no '%s'" % key)
	_require(not (legal.get("reachable", []) as Array).is_empty(),
		"the actor could reach nowhere, not even the cell it stands on")
	_require(not (decision.get("chosen", {}) as Dictionary).is_empty(),
		"the decision records no chosen command")

	# The command addresses a spell by two indices; the menu has to exist for those to mean
	# anything to a reader. See the adapter's own note on why this was added.
	var spellSets: Array = legal.get("spells", [])
	if not spellSets.is_empty():
		var firstSet: Dictionary = spellSets[0]
		_require(firstSet.has("spell_set_index") and firstSet.has("spells"),
			"a spell set is not addressable the way a command addresses it")

	# The result must not restate the command; see the adapter's note on the dropped duplicate.
	_require(not (decision.get("result", {}) as Dictionary).has("command"),
		"the result still carries a duplicate copy of the chosen command")


func _require(condition: bool, message: String) -> void:
	if not condition:
		failures.append(message)
