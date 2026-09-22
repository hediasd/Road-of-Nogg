extends SceneTree

## Reads a merged result set and writes three things beside it: machine-readable
## aggregates, a CSV of the rows a spreadsheet wants, and a report a person can
## read without recomputing anything.
##
##     Godot --headless --path . --script scripts/battle/analyze_policy_tournament.gd -- \
##         --manifest=<path> --results=<dir>
##
## The report's job is to be hard to over-read. It states the estimand and the
## effective sample unit next to every headline, refuses to print an interval
## that is too wide to mean anything, keeps round-cap finishes out of the
## strength tally, and counts infrastructure failures against everything that
## was scheduled rather than everything that survived.
##
## **Held-out scenarios are reported separately and last.** If reading them
## prompts tuning, that is a new experiment with a fresh holdout -- the old one
## has been spent, and reusing it turns a test into a training set.

const ManifestScript = preload("res://scripts/battle/tournament/TournamentManifest.gd")
const MatchPlanScript = preload("res://scripts/battle/tournament/MatchPlan.gd")
const ShardScript = preload("res://scripts/battle/tournament/ResultShard.gd")
const PairedScript = preload("res://scripts/battle/analysis/PairedOutcomes.gd")
const AggregatesScript = preload("res://scripts/battle/analysis/Aggregates.gd")


func _init() -> void:
	var flags := _parseFlags(OS.get_cmdline_user_args())
	if not str(flags["error"]).is_empty():
		_fail(str(flags["error"]))
		return
	var manifest: TournamentManifest = ManifestScript.fromFile(str(flags["manifest"]))
	if not manifest.isValid():
		_fail("manifest rejected: %s" % str(manifest.errors))
		return
	var resultsDirectory := str(flags["results"])
	var resultsPath := ShardScript.mergedPath(resultsDirectory)
	var loaded := ShardScript.read(resultsPath)
	var rows: Array = loaded["rows"]
	if rows.is_empty():
		_fail("no result rows at %s" % resultsPath)
		return
	var scheduled := MatchPlanScript.matchesFor(manifest).size()
	var analysis := analyze(manifest, rows, scheduled)
	_write(resultsDirectory, analysis, rows)
	print("POLICY_ANALYSIS_OK clusters=%d decided=%d conclusion=%s path=%s" % [
		int(analysis["tally"]["scheduled_clusters"]),
		int(analysis["tally"]["decided_clusters"]),
		str(analysis["sign_test"]["conclusion"]), resultsDirectory])
	quit(0)


## Pure: the same rows always produce the same analysis, so a probe can check it
## against numbers worked out by hand.
static func analyze(manifest: TournamentManifest, rows: Array,
		scheduledMatches: int) -> Dictionary:
	var tuning: Array = []
	var holdout: Array = []
	for rowValue in rows:
		var row: Dictionary = rowValue
		if manifest.holdout_scenarios.has(str(row.get("scenario", ""))):
			holdout.append(row)
		else:
			tuning.append(row)
	var clusterMap := PairedScript.clusters(rows, manifest.policy_a, manifest.policy_b)
	var tally := PairedScript.tally(clusterMap)
	var minimumUnits := int(manifest.acceptance.get("minimum_decisive_positions", 8))
	return {
		"manifest": manifest.identity(),
		"acceptance": manifest.acceptance,
		"tally": tally,
		"sign_test": PairedScript.signTest(tally, minimumUnits),
		"end_reasons": AggregatesScript.endReasons(rows),
		"infrastructure": AggregatesScript.infrastructure(rows, scheduledMatches),
		"by_side": AggregatesScript.bySide(rows),
		"by_scenario": AggregatesScript.byScenario(rows),
		"opponent_matrix": AggregatesScript.opponentMatrix(rows),
		"cost": AggregatesScript.cost(rows),
		"representative_losses": {
			manifest.policy_a: AggregatesScript.representativeLosses(rows, manifest.policy_a),
			manifest.policy_b: AggregatesScript.representativeLosses(rows, manifest.policy_b),
		},
		"held_out": {
			"scenarios": manifest.holdout_scenarios.duplicate(),
			"rows": holdout.size(),
			"tuning_rows": tuning.size(),
			"note": (
				"Held-out results are reported separately. Tuning after reading them "
				+ "spends the holdout: the next claim needs a new experiment and a new one."
			),
		},
		"unsupported_conclusions": _unsupported(tally, rows, scheduledMatches),
	}


## What this data cannot be used to say. Written into the report on purpose, so
## the limits travel with the numbers instead of living in somebody's memory.
static func _unsupported(tally: Dictionary, rows: Array,
		scheduledMatches: int) -> Array[String]:
	var notes: Array[String] = []
	if int(tally["decided_clusters"]) < 8:
		notes.append(
			"Too few decided positions (%d) to claim either policy is stronger."
			% int(tally["decided_clusters"]))
	var reasons := AggregatesScript.endReasons(rows)
	if int(reasons.get("round_cap", 0)) > 0:
		notes.append(
			("%d matches ended on the round cap. Those measure pacing and the cap, "
			+ "not which policy plays better, and are not in the strength tally.")
			% int(reasons["round_cap"]))
	var infrastructure := AggregatesScript.infrastructure(rows, scheduledMatches)
	if float(infrastructure["failure_rate"]) > 0.0:
		notes.append(
			("%.1f%% of scheduled matches did not produce a result. Conclusions are "
			+ "conditional on the ones that did, which may not be a random sample.")
			% (float(infrastructure["failure_rate"]) * 100.0))
	var scenarios := AggregatesScript.byScenario(rows)
	if scenarios.size() < 2:
		notes.append(
			"Every match came from one scenario, so nothing here generalises to other maps.")
	notes.append(
		"A shared seed does not make two policies face identical random events: "
		+ "they consume the stream differently as soon as their decisions diverge.")
	return notes


func _write(directory: String, analysis: Dictionary, rows: Array) -> void:
	if not DirAccess.dir_exists_absolute(directory):
		DirAccess.make_dir_recursive_absolute(directory)
	var jsonFile := FileAccess.open("%s/analysis.json" % directory, FileAccess.WRITE)
	if jsonFile != null:
		jsonFile.store_string(JSON.stringify(analysis, "\t", true))
		jsonFile.close()
	var csvFile := FileAccess.open("%s/matches.csv" % directory, FileAccess.WRITE)
	if csvFile != null:
		csvFile.store_line("match_id,scenario,seed,swapped,side_one_policy,"
			+ "side_two_policy,winning_policy,end_reason,rounds,decisions,slices")
		for rowValue in rows:
			var row: Dictionary = rowValue
			var work: Dictionary = row.get("work", {})
			csvFile.store_line("%s,%s,%d,%d,%s,%s,%s,%s,%d,%d,%d" % [
				str(row.get("match_id", "")), str(row.get("scenario", "")),
				int(row.get("seed", 0)), int(row.get("swapped", 0)),
				str(row.get("side_one_policy", "")), str(row.get("side_two_policy", "")),
				str(row.get("winning_policy", "")), str(row.get("end_reason", "")),
				int(row.get("rounds", 0)), int(row.get("decisions", 0)),
				int(work.get("slices", 0))])
		csvFile.close()
	var reportFile := FileAccess.open("%s/report.md" % directory, FileAccess.WRITE)
	if reportFile != null:
		reportFile.store_string(_report(analysis))
		reportFile.close()


static func _report(analysis: Dictionary) -> String:
	var manifest: Dictionary = analysis["manifest"]
	var tally: Dictionary = analysis["tally"]
	var test: Dictionary = analysis["sign_test"]
	var lines: Array[String] = []
	lines.append("# Policy experiment: %s" % str(manifest["manifest_id"]))
	lines.append("")
	lines.append("%s against %s." % [str(manifest["policy_a"]), str(manifest["policy_b"])])
	lines.append("")
	lines.append("## What is being estimated")
	lines.append("")
	lines.append(str(tally["estimand"]))
	lines.append("")
	lines.append("Scheduled positions: %d. Decided: %d. Effective sample units: %d." % [
		int(tally["scheduled_clusters"]), int(tally["decided_clusters"]),
		int(tally["effective_sample_units"])])
	lines.append("")
	lines.append("## Result")
	lines.append("")
	if str(test["conclusion"]) == "insufficient_evidence":
		lines.append("**No conclusion.** %s" % str(test["note"]))
	else:
		lines.append("%s took %d decisive positions, %s took %d. Share %.2f, interval %.2f to %.2f. Conclusion: %s." % [
			str(manifest["policy_a"]), int(test["policy_a_positions"]),
			str(manifest["policy_b"]), int(test["policy_b_positions"]),
			float(test["policy_a_share"]), float(test["interval_low"]),
			float(test["interval_high"]), str(test["conclusion"])])
	lines.append("")
	lines.append("## What this cannot say")
	lines.append("")
	for note in analysis["unsupported_conclusions"]:
		lines.append("- %s" % str(note))
	lines.append("")
	lines.append("## How matches ended")
	lines.append("")
	lines.append("```")
	lines.append(JSON.stringify(analysis["end_reasons"], "\t", true))
	lines.append("```")
	lines.append("")
	lines.append("## Infrastructure")
	lines.append("")
	lines.append("```")
	lines.append(JSON.stringify(analysis["infrastructure"], "\t", true))
	lines.append("```")
	lines.append("")
	lines.append("## Cost")
	lines.append("")
	lines.append("```")
	lines.append(JSON.stringify(analysis["cost"], "\t", true))
	lines.append("```")
	lines.append("")
	lines.append("## Matches worth opening")
	lines.append("")
	for policyID in analysis["representative_losses"]:
		var losses: Array = analysis["representative_losses"][policyID]
		if losses.is_empty():
			continue
		lines.append("### %s lost" % str(policyID))
		lines.append("")
		for lossValue in losses:
			var loss: Dictionary = lossValue
			lines.append("- `%s` on %s seed %d, %d rounds, %s. Reproduce: `%s`" % [
				str(loss["match_id"]), str(loss["scenario"]).get_file(),
				int(loss["seed"]), int(loss["rounds"]), str(loss["end_reason"]),
				str(loss["reproduce"])])
		lines.append("")
	lines.append("## Held out")
	lines.append("")
	lines.append("```")
	lines.append(JSON.stringify(analysis["held_out"], "\t", true))
	lines.append("```")
	return "\n".join(lines) + "\n"


static func _parseFlags(arguments: PackedStringArray) -> Dictionary:
	var flags := {"manifest": "", "results": "", "error": ""}
	for argumentValue in arguments:
		var argument := str(argumentValue)
		if argument.begins_with("--manifest="):
			flags["manifest"] = argument.substr("--manifest=".length())
		elif argument.begins_with("--results="):
			flags["results"] = argument.substr("--results=".length())
		else:
			flags["error"] = "unknown flag %s" % argument
			return flags
	if str(flags["manifest"]).is_empty() or str(flags["results"]).is_empty():
		flags["error"] = "--manifest and --results are required"
	return flags


func _fail(reason: String) -> void:
	printerr("POLICY_ANALYSIS_FAILED: %s" % reason)
	quit(1)
