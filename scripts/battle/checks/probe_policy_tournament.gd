extends SceneTree

## The experiment runner's contracts: that the same manifest names the same
## matches however many workers run it, that a resume neither loses a match nor
## counts one twice, that a killed process leaves recoverable work, and that a
## crash is never quietly filed as a loss.

const ManifestScript = preload("res://scripts/battle/tournament/TournamentManifest.gd")
const MatchPlanScript = preload("res://scripts/battle/tournament/MatchPlan.gd")
const ShardScript = preload("res://scripts/battle/tournament/ResultShard.gd")
const BuildIdentityScript = preload("res://scripts/battle/tournament/BuildIdentity.gd")
const OutputPathsScript = preload("res://src/presentation/BattleOutputPaths.gd")

const MANIFEST_PATH := "res://scripts/battle/fixtures/ai/tournament_smoke.json"

var failures: Array[String] = []
var workDirectory: String = ""


func _init() -> void:
	workDirectory = OutputPathsScript.pathFor("tournaments", "probe")
	_clean(workDirectory)
	_checkManifestValidation()
	_checkMatchPlanIsStable()
	_checkShardingCoversEveryMatchOnce()
	_checkPartialLineRecovery()
	_checkResumeDoesNotDoubleCount()
	_checkFailuresStayVisible()
	_checkMergeOrderAndDuplicates()
	_checkDeterministicBytesExcludeTiming()
	_checkBuildIdentity()
	if not failures.is_empty():
		for failure: String in failures:
			printerr("AI_POLICY_TOURNAMENT_FAILURE: %s" % failure)
		quit(1)
		return
	print("AI_POLICY_TOURNAMENT_OK")
	quit(0)


func _require(condition: bool, message: String) -> void:
	if not condition:
		failures.append(message)


func _clean(directory: String) -> void:
	var handle := DirAccess.open(directory)
	if handle == null:
		DirAccess.make_dir_recursive_absolute(directory)
		return
	for fileName in handle.get_files():
		handle.remove(fileName)


func _manifest() -> TournamentManifest:
	return ManifestScript.fromFile(MANIFEST_PATH)


func _checkManifestValidation() -> void:
	var manifest := _manifest()
	_require(manifest.isValid(), "the smoke manifest was rejected: %s" % str(manifest.errors))
	## A misspelled policy must fail loudly rather than fall back to a default
	## and report its numbers under a name that never ran.
	var unknown := ManifestScript.fromDictionary({
		"manifest_id": "x", "scenarios": ["a"], "seeds": [1],
		"policy_a": "no_such_policy_v9", "policy_b": "legacy_side_v1",
	})
	_require(not unknown.isValid(), "an unknown policy id was accepted")
	var named := false
	for error: String in unknown.errors:
		if error.contains("no_such_policy_v9"):
			named = true
	_require(named, "the rejection did not name the unknown policy")
	var overlapping := ManifestScript.fromDictionary({
		"manifest_id": "x", "scenarios": ["a"], "seeds": [1],
		"policy_a": "legacy_side_v1", "policy_b": "tactical_side_v1",
		"tuning_scenarios": ["a"], "holdout_scenarios": ["a"],
	})
	_require(not overlapping.isValid(),
		"a scenario was allowed to be both tuning and held out")


func _checkMatchPlanIsStable() -> void:
	var first := MatchPlanScript.matchesFor(_manifest())
	var second := MatchPlanScript.matchesFor(_manifest())
	_require(not first.is_empty(), "the manifest produced no matches")
	_require(JSON.stringify(first, "", true) == JSON.stringify(second, "", true),
		"the same manifest named its matches differently twice")
	var identifiers: Dictionary = {}
	for matchRow in first:
		var identifier := str(matchRow["match_id"])
		_require(not identifiers.has(identifier),
			"two matches shared the id %s" % identifier)
		identifiers[identifier] = true
	## Both side assignments are generated as a pair, so a scenario is never
	## measured with one policy on the favourable side alone.
	var swaps: Dictionary = {}
	for matchRow in first:
		var key := "%s:%d" % [str(matchRow["scenario"]), int(matchRow["seed"])]
		swaps[key] = int(swaps.get(key, 0)) + 1
	for key in swaps:
		_require(int(swaps[key]) == 2,
			"%s was not played with both side assignments" % key)


func _checkShardingCoversEveryMatchOnce() -> void:
	## However many workers run it, every match is played exactly once. This is
	## the property that makes a worker-count change safe.
	var matches := MatchPlanScript.matchesFor(_manifest())
	for shardCount in [1, 2, 3, 7]:
		var seen: Dictionary = {}
		for shardIndex in range(shardCount):
			for matchRow in MatchPlanScript.shardOf(matches, shardIndex, shardCount):
				var identifier := str(matchRow["match_id"])
				_require(not seen.has(identifier),
					"match %s was assigned to two workers at %d shards" %
					[identifier, shardCount])
				seen[identifier] = true
		_require(seen.size() == matches.size(),
			"%d shards covered %d of %d matches" %
			[shardCount, seen.size(), matches.size()])


func _checkPartialLineRecovery() -> void:
	## A process killed mid-write leaves half a row. That line is dropped; the
	## rows before it are not, because they are finished work.
	var path := "%s/partial.jsonl" % workDirectory
	var file := FileAccess.open(path, FileAccess.WRITE)
	file.store_line(JSON.stringify({"match_id": "a", "end_reason": "elimination"}, "", true))
	file.store_line(JSON.stringify({"match_id": "b", "end_reason": "draw"}, "", true))
	file.store_string("{\"match_id\": \"c\", \"end_rea")
	file.close()
	var shard := ShardScript.read(path)
	_require(shard["rows"].size() == 2,
		"recovery kept %d rows instead of the two that were complete" % shard["rows"].size())
	_require(int(shard["recovered_partial_lines"]) == 1,
		"the truncated final line was not reported")
	## The line that matters: appending to a file whose last line has no newline
	## welds the new row onto the broken one and destroys both. Compacting first
	## is what makes a resume safe, and this is the case that proves it.
	_require(ShardScript.compact(path, shard["rows"]), "a shard could not be compacted")
	ShardScript.append(path, {"match_id": "c", "end_reason": ShardScript.END_DRAW})
	var resumed := ShardScript.read(path)
	_require(resumed["rows"].size() == 3,
		"a row appended after recovery did not read back: %d rows" % resumed["rows"].size())
	_require(int(resumed["recovered_partial_lines"]) == 0,
		"the compacted shard still reported a partial line")
	var identifiers: Array = []
	for row in resumed["rows"]:
		identifiers.append(str(row["match_id"]))
	_require(identifiers == ["a", "b", "c"],
		"recovery then append produced %s" % str(identifiers))


func _checkResumeDoesNotDoubleCount() -> void:
	## A match id names the work; an attempt id names one try at it. A resume
	## skips matches that succeeded and retries those that did not, so the
	## matches hardest to finish are neither lost nor counted twice.
	var rows: Array = [
		{"match_id": "m1", "end_reason": ShardScript.END_ELIMINATION},
		{"match_id": "m2", "end_reason": ShardScript.END_CRASH},
		{"match_id": "m3", "end_reason": ShardScript.END_ROUND_CAP},
	]
	var completed := ShardScript.completedMatchIDs(rows)
	_require(completed.has("m1") and completed.has("m3"),
		"a finished match was not recognised as complete")
	_require(not completed.has("m2"),
		"a crashed match was treated as complete and would never be retried")
	_require(MatchPlanScript.attemptID("m2", 0) != MatchPlanScript.attemptID("m2", 1),
		"two attempts at one match shared an id")


func _checkFailuresStayVisible() -> void:
	## A crash that was later retried successfully is still a crash that
	## happened. Dropping it would hide exactly the matches that were hardest to
	## finish, and those are never a random sample.
	var pathA := "%s/fail_a.jsonl" % workDirectory
	var pathB := "%s/fail_b.jsonl" % workDirectory
	ShardScript.append(pathA, {"match_id": "m1", "end_reason": ShardScript.END_CRASH})
	ShardScript.append(pathB, {"match_id": "m1", "end_reason": ShardScript.END_ELIMINATION})
	var merged := ShardScript.merge([pathA, pathB], ["m1"])
	_require(merged["rows"].size() == 1, "the retry did not produce one result row")
	_require(merged["failures"].size() == 1,
		"the crash disappeared once the retry succeeded")
	_require(merged["duplicate_match_ids"].is_empty(),
		"a crash and its retry were counted as two results")


func _checkMergeOrderAndDuplicates() -> void:
	## Rows come out in canonical match order whatever order the shards were
	## written in, and two *successful* attempts at one match are a defect the
	## merge names rather than an average it takes.
	var pathA := "%s/order_a.jsonl" % workDirectory
	var pathB := "%s/order_b.jsonl" % workDirectory
	ShardScript.append(pathA, {"match_id": "m3", "end_reason": ShardScript.END_DRAW})
	ShardScript.append(pathA, {"match_id": "m1", "end_reason": ShardScript.END_ELIMINATION})
	ShardScript.append(pathB, {"match_id": "m2", "end_reason": ShardScript.END_ROUND_CAP})
	var merged := ShardScript.merge([pathA, pathB], ["m1", "m2", "m3"])
	var order: Array = []
	for row in merged["rows"]:
		order.append(str(row["match_id"]))
	_require(order == ["m1", "m2", "m3"],
		"the merge did not order rows canonically: %s" % str(order))
	_require(merged["missing_match_ids"].is_empty(), "a merged match went missing")

	ShardScript.append(pathB, {"match_id": "m1", "end_reason": ShardScript.END_ELIMINATION})
	var doubled := ShardScript.merge([pathA, pathB], ["m1", "m2", "m3"])
	_require(doubled["duplicate_match_ids"].has("m1"),
		"a match recorded twice was not reported as a duplicate")


func _checkDeterministicBytesExcludeTiming() -> void:
	## How long a match took and which machine ran it must not make two runs of
	## the same experiment look different.
	var fast: Array = [{"match_id": "m1", "end_reason": "draw", "attempt_id": "m1#a0",
		"telemetry": {"elapsed_usec": 10, "host_os": "Windows"}}]
	var slow: Array = [{"match_id": "m1", "end_reason": "draw", "attempt_id": "m1#a4",
		"telemetry": {"elapsed_usec": 99999, "host_os": "Linux"}}]
	_require(ShardScript.deterministicBytes(fast) == ShardScript.deterministicBytes(slow),
		"timing or host data leaked into the deterministic result bytes")
	var different: Array = [{"match_id": "m1", "end_reason": "elimination"}]
	_require(ShardScript.deterministicBytes(fast) != ShardScript.deterministicBytes(different),
		"a different result compared equal")


func _checkBuildIdentity() -> void:
	## Rows carry a hash of what actually ran, so an experiment launched from a
	## tree somebody is editing cannot silently mix two programs.
	var build := BuildIdentityScript.capture()
	_require(str(build.get("simulation", "")).begins_with("sha256:"),
		"the build identity carried no simulation hash")
	_require(BuildIdentityScript.agrees(build, BuildIdentityScript.capture()),
		"the build identity was unstable within one process")
	_require(not BuildIdentityScript.agrees(build,
		{"engine": build["engine"], "simulation": "sha256:other", "content": build["content"]}),
		"two different simulations were treated as the same build")
