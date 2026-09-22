extends SceneTree

## Runs one shard of a declared experiment, or merges the shards into a result
## set. One process, one shard, one file it owns alone -- which is what lets the
## supervisor run several at once and kill one that hangs without losing the
## work the others have already written.
##
##     Godot --headless --path . --script scripts/battle/run_policy_tournament.gd -- \
##         --manifest=<path> --output=<dir> [--shard=<i> --shards=<n>] [--merge] [--resume]
##
## `--merge` reads every shard, keeps the last successful attempt per match,
## keeps every failed attempt beside it, and writes one results file in
## canonical match order. `--resume` skips matches that already have a
## successful attempt on disk, which is why a match id is not an attempt id:
## counting attempts would double-count exactly the matches that had to be
## retried, and those are never a random sample.
##
## The build the rows were produced by is hashed here rather than declared,
## because only the process that ran it knows what it actually ran.

const ManifestScript = preload("res://scripts/battle/tournament/TournamentManifest.gd")
const MatchPlanScript = preload("res://scripts/battle/tournament/MatchPlan.gd")
const ShardScript = preload("res://scripts/battle/tournament/ResultShard.gd")
const BuildIdentityScript = preload("res://scripts/battle/tournament/BuildIdentity.gd")
const ConfigScript = preload("res://src/battle_sim/BattleSetupConfig.gd")
const SetupScript = preload("res://src/battle_sim/BattleSetupFactory.gd")
const SimulatorScript = preload("res://src/battle_sim/BattleSimulator.gd")
const ScenarioFactoryScript = preload("res://src/factories/BattleScenarioFactory.gd")


func _init() -> void:
	var flags := _parseFlags(OS.get_cmdline_user_args())
	if not str(flags.get("error", "")).is_empty():
		_fail(str(flags["error"]))
		return
	var manifest: TournamentManifest = ManifestScript.fromFile(str(flags["manifest"]))
	if not manifest.isValid():
		_fail("manifest rejected: %s" % str(manifest.errors))
		return
	var matches := MatchPlanScript.matchesFor(manifest)
	var outputDirectory := str(flags["output"])
	if bool(flags["merge"]):
		_merge(manifest, matches, outputDirectory)
		return
	_runShard(manifest, matches, outputDirectory, int(flags["shard"]),
		int(flags["shards"]), bool(flags["resume"]))


func _runShard(manifest: TournamentManifest, matches: Array, outputDirectory: String,
		shardIndex: int, shardCount: int, resume: bool) -> void:
	var path := ShardScript.shardPath(outputDirectory, shardIndex)
	var existing := ShardScript.read(path)
	## A killed process leaves its last line unterminated, and appending to that
	## would weld the next row onto it. Rewrite the shard from what survived
	## before adding anything to it.
	if int(existing["recovered_partial_lines"]) > 0:
		if not ShardScript.compact(path, existing["rows"]):
			_fail("could not compact a recovered shard at %s" % path)
			return
	var completed: Dictionary = ShardScript.completedMatchIDs(existing["rows"]) if resume else {}
	var build := BuildIdentityScript.capture()
	var assigned := MatchPlanScript.shardOf(matches, shardIndex, shardCount)
	var played := 0
	var skipped := 0
	for matchValue in assigned:
		var matchRow: Dictionary = matchValue
		if completed.has(str(matchRow["match_id"])):
			skipped += 1
			continue
		var attempt := _attemptNumber(existing["rows"], str(matchRow["match_id"]))
		var row := _playMatch(manifest, matchRow, build, attempt)
		if not ShardScript.append(path, row):
			_fail("could not write shard %s" % path)
			return
		played += 1
	print("POLICY_TOURNAMENT_SHARD_OK shard=%d played=%d skipped=%d recovered=%d path=%s" %
		[shardIndex, played, skipped, int(existing["recovered_partial_lines"]), path])
	quit(0)


## One battle, both policies assigned before it starts. Assigning them together
## rather than one at a time is what keeps a half-configured match from being
## recorded as though it had been played under the manifest's pairing.
func _playMatch(manifest: TournamentManifest, matchRow: Dictionary,
		build: Dictionary, attempt: int) -> Dictionary:
	var started := Time.get_ticks_usec()
	var row := {
		"match_id": str(matchRow["match_id"]),
		"attempt_id": MatchPlanScript.attemptID(str(matchRow["match_id"]), attempt),
		"manifest_id": manifest.manifest_id,
		"scenario": str(matchRow["scenario"]),
		"seed": int(matchRow["seed"]),
		"swapped": int(matchRow["swapped"]),
		"side_one_policy": str(matchRow["side_one_policy"]),
		"side_two_policy": str(matchRow["side_two_policy"]),
		"identity": manifest.identity(),
		"build": build,
	}
	var loaded := ScenarioFactoryScript.loadFromPath(str(matchRow["scenario"]))
	if not bool(loaded.get("success", false)):
		row["end_reason"] = ShardScript.END_CRASH
		row["error"] = "scenario could not be loaded: %s" % str(loaded.get("error", ""))
		row["telemetry"] = _telemetry(started)
		return row

	var config = ConfigScript.new()
	config.scenarioPath = str(matchRow["scenario"])
	config.seed = int(matchRow["seed"])
	var setup: Dictionary = SetupScript.createHexState(config)
	if not bool(setup.get("success", false)):
		row["end_reason"] = ShardScript.END_CRASH
		row["error"] = "setup failed: %s" % str(setup.get("error", ""))
		row["telemetry"] = _telemetry(started)
		return row

	var simulator: BattleSimulator = SimulatorScript.new(config.seed)
	simulator.configureHexState(setup["state"], setup["scenario"], config.serialize())
	simulator.setInvariantChecks(true)
	simulator.startBattle()

	var decisions := 0
	var illegal := ""
	while simulator.state.battleOutcome == -1 \
			and simulator.state.roundCount < manifest.max_rounds:
		if simulator.state.activeSideID == -1:
			if not bool(simulator.startNextSideTurn("tournament").get("success", false)):
				break
		## Both sides are configured before each decision, so which policy holds
		## which side is never ambiguous and never half-applied.
		simulator.sidePolicyID = str(matchRow["side_one_policy"]) \
			if simulator.state.activeSideID == 1 else str(matchRow["side_two_policy"])
		var proposal = simulator.beginSideDeliberation().run(64)
		if proposal == null:
			simulator.endSideTurn("no_proposal")
			continue
		decisions += 1
		if not bool(simulator.selectUnit(proposal.actor_id, "tournament").get("success", false)):
			illegal = "actor %d was refused" % int(proposal.actor_id)
			break
		var executed = simulator.executeCommand(proposal.actor_id, proposal.command, "tournament")
		if not executed.success:
			illegal = "command refused: %s" % str(executed.reason)
			break

	var survivors: Dictionary = {}
	for monsterIDValue in simulator.state.getAliveMonsterIDs():
		var monster: Monster = simulator.state.getMonster(int(monsterIDValue))
		survivors[str(monster.team)] = int(survivors.get(str(monster.team), 0)) + 1

	if not illegal.is_empty():
		row["end_reason"] = ShardScript.END_ILLEGAL_COMMAND
		row["error"] = illegal
	elif not simulator.invariantViolations().is_empty():
		row["end_reason"] = ShardScript.END_INVARIANT
		row["error"] = "invariant violations: %s" % str(simulator.invariantViolations())
	elif simulator.state.battleOutcome > 0:
		row["end_reason"] = ShardScript.END_ELIMINATION
	elif simulator.state.battleOutcome == 0:
		row["end_reason"] = ShardScript.END_DRAW
	else:
		row["end_reason"] = ShardScript.END_ROUND_CAP
	row["winner_team"] = simulator.state.battleOutcome
	row["rounds"] = simulator.state.roundCount
	row["decisions"] = decisions
	row["survivors"] = survivors
	row["invariant_violations"] = simulator.invariantViolations()
	## Which policy won, rather than which side, so a swapped assignment can be
	## pooled with its pair without anyone having to remember the mapping.
	row["winning_policy"] = _winningPolicy(matchRow, simulator.state.battleOutcome)
	row["telemetry"] = _telemetry(started)
	return row


static func _winningPolicy(matchRow: Dictionary, outcome: int) -> String:
	if outcome == 1:
		return str(matchRow["side_one_policy"])
	if outcome == 2:
		return str(matchRow["side_two_policy"])
	return ""


func _merge(manifest: TournamentManifest, matches: Array, outputDirectory: String) -> void:
	var shardPaths: Array = []
	var directory := DirAccess.open(outputDirectory)
	if directory != null:
		for fileName in directory.get_files():
			if fileName.begins_with("shard_") and fileName.ends_with(".jsonl"):
				shardPaths.append("%s/%s" % [outputDirectory.rstrip("/"), fileName])
	shardPaths.sort()
	var orderedIDs: Array = []
	for matchValue in matches:
		orderedIDs.append(str((matchValue as Dictionary)["match_id"]))
	var merged := ShardScript.merge(shardPaths, orderedIDs)
	var path := ShardScript.mergedPath(outputDirectory)
	if not DirAccess.dir_exists_absolute(path.get_base_dir()):
		DirAccess.make_dir_recursive_absolute(path.get_base_dir())
	var file := FileAccess.open(path, FileAccess.WRITE)
	if file == null:
		_fail("could not write %s" % path)
		return
	for row in merged["rows"]:
		file.store_line(JSON.stringify(row, "", true))
	file.close()
	var summaryPath := "%s/summary.json" % outputDirectory.rstrip("/")
	var summaryFile := FileAccess.open(summaryPath, FileAccess.WRITE)
	if summaryFile != null:
		summaryFile.store_string(JSON.stringify({
			"manifest": manifest.identity(),
			"expected_matches": orderedIDs.size(),
			"merged_rows": merged["rows"].size(),
			"missing_match_ids": merged["missing_match_ids"],
			"duplicate_match_ids": merged["duplicate_match_ids"],
			"failures": merged["failures"],
			"corrupt_rows": merged["corrupt_rows"],
			"recovered_partial_lines": merged["recovered_partial_lines"],
			"shards": shardPaths,
		}, "\t", true))
		summaryFile.close()
	if not merged["duplicate_match_ids"].is_empty():
		_fail("a match was recorded twice: %s" % str(merged["duplicate_match_ids"]))
		return
	print("POLICY_TOURNAMENT_MERGE_OK rows=%d expected=%d missing=%d failures=%d path=%s" %
		[merged["rows"].size(), orderedIDs.size(), merged["missing_match_ids"].size(),
		merged["failures"].size(), path])
	quit(0)


static func _attemptNumber(rows: Array, matchIdentifier: String) -> int:
	var attempts := 0
	for rowValue in rows:
		if str((rowValue as Dictionary).get("match_id", "")) == matchIdentifier:
			attempts += 1
	return attempts


static func _telemetry(startedUsec: int) -> Dictionary:
	return {
		"elapsed_usec": Time.get_ticks_usec() - startedUsec,
		"host_os": OS.get_name(),
	}


static func _parseFlags(arguments: PackedStringArray) -> Dictionary:
	var flags := {"manifest": "", "output": "", "shard": 0, "shards": 1,
		"merge": false, "resume": false, "error": ""}
	for argumentValue in arguments:
		var argument := str(argumentValue)
		if argument.begins_with("--manifest="):
			flags["manifest"] = argument.substr("--manifest=".length())
		elif argument.begins_with("--output="):
			flags["output"] = argument.substr("--output=".length())
		elif argument.begins_with("--shard="):
			flags["shard"] = int(argument.substr("--shard=".length()))
		elif argument.begins_with("--shards="):
			flags["shards"] = maxi(1, int(argument.substr("--shards=".length())))
		elif argument == "--merge":
			flags["merge"] = true
		elif argument == "--resume":
			flags["resume"] = true
		else:
			flags["error"] = "unknown flag %s" % argument
			return flags
	if str(flags["manifest"]).is_empty() or str(flags["output"]).is_empty():
		flags["error"] = "--manifest and --output are required"
	return flags


func _fail(reason: String) -> void:
	printerr("POLICY_TOURNAMENT_FAILED: %s" % reason)
	quit(1)
