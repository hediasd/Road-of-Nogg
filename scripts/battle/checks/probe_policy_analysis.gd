extends SceneTree

## The analysis, checked against numbers worked out by hand.
##
## Every case here is small enough to verify on paper, which is the point: an
## analysis that can only be checked by running it is an analysis nobody checks.

const PairedScript = preload("res://scripts/battle/analysis/PairedOutcomes.gd")
const AggregatesScript = preload("res://scripts/battle/analysis/Aggregates.gd")
const AnalyzerScript = preload("res://scripts/battle/analyze_policy_tournament.gd")
const ManifestScript = preload("res://scripts/battle/tournament/TournamentManifest.gd")

const CASES_PATH := "res://scripts/battle/fixtures/ai/analysis_cases.json"
const EVALUATION_PATH := "res://scripts/battle/fixtures/ai/evaluation_manifest.json"

const POLICY_A := "tactical_side_v1"
const POLICY_B := "legacy_side_v1"

var failures: Array[String] = []
var cases: Dictionary = {}


func _init() -> void:
	cases = JSON.parse_string(FileAccess.get_file_as_string(CASES_PATH))
	_checkHandComputedCases()
	_checkPairingIsTheSampleUnit()
	_checkIncompletePairsAreNotScored()
	_checkDuplicatesAreNotSamples()
	_checkRoundCapIsNotStrength()
	_checkFailureDenominator()
	_checkNarrowIntervalsOnly()
	_checkEvaluationManifest()
	_checkReportStatesItsLimits()
	if not failures.is_empty():
		for failure: String in failures:
			printerr("AI_POLICY_ANALYSIS_FAILURE: %s" % failure)
		quit(1)
		return
	print("AI_POLICY_ANALYSIS_OK")
	quit(0)


func _require(condition: bool, message: String) -> void:
	if not condition:
		failures.append(message)


func _row(scenario: String, seed: int, swapped: int, winner: String,
		reason: String = "elimination") -> Dictionary:
	var one := POLICY_A if swapped == 0 else POLICY_B
	var two := POLICY_B if swapped == 0 else POLICY_A
	return {
		"match_id": "%s-%d-%d" % [scenario, seed, swapped],
		"scenario": scenario, "seed": seed, "swapped": swapped,
		"side_one_policy": one, "side_two_policy": two,
		"winning_policy": winner, "end_reason": reason,
		"winner_team": 1 if winner == one else (2 if winner == two else 0),
		"rounds": 7, "decisions": 40,
		"work": {"deliberations": 40, "slices": 400, "candidates_enumerated": 4000},
		"telemetry": {"elapsed_usec": 1000, "decision_usec_p50": 25,
			"decision_usec_p95": 60, "host_os": "Windows"},
	}


func _checkHandComputedCases() -> void:
	## Each fixture case states its expected outcome in words as well as a value,
	## so a disagreement says which reading was wrong.
	for caseValue in cases["clusters"]:
		var entry: Dictionary = caseValue
		var rows: Array = []
		for rowValue in entry["matches"]:
			var spec: Dictionary = rowValue
			rows.append(_row("s", 1, int(spec["swapped"]), str(spec["winner"]),
				str(spec.get("end_reason", "elimination"))))
		var clusterMap := PairedScript.clusters(rows, POLICY_A, POLICY_B)
		_require(clusterMap.size() == 1,
			"%s produced %d clusters" % [str(entry["why"]), clusterMap.size()])
		for key in clusterMap:
			_require(str(clusterMap[key]["outcome"]) == str(entry["outcome"]),
				"%s: expected %s, got %s" %
				[str(entry["why"]), str(entry["outcome"]),
				str(clusterMap[key]["outcome"])])


func _checkPairingIsTheSampleUnit() -> void:
	## Eight matches over four positions are four sample units, not eight. This
	## is the whole reason the analysis groups before it counts.
	var rows: Array = []
	for seed in [1, 2, 3, 4]:
		rows.append(_row("s", seed, 0, POLICY_A))
		rows.append(_row("s", seed, 1, POLICY_A))
	var tally := PairedScript.tally(PairedScript.clusters(rows, POLICY_A, POLICY_B))
	_require(int(tally["scheduled_clusters"]) == 4,
		"eight matches over four positions counted as %d units" %
		int(tally["scheduled_clusters"]))
	_require(int(tally["counts"][PairedScript.OUTCOME_A]) == 4,
		"a policy winning both sides of every position did not take them all")
	_require(not str(tally["estimand"]).is_empty(),
		"the tally did not state what it estimates")


func _checkIncompletePairsAreNotScored() -> void:
	## A crash on one side leaves the comparison unfinished. Scoring it from the
	## half that ran keeps exactly the results that correlate with whatever made
	## the other half fail.
	var rows: Array = [
		_row("s", 1, 0, POLICY_A),
		_row("s", 1, 1, "", "crash"),
	]
	var clusterMap := PairedScript.clusters(rows, POLICY_A, POLICY_B)
	for key in clusterMap:
		_require(str(clusterMap[key]["outcome"]) == PairedScript.OUTCOME_INCOMPLETE,
			"a position with a crashed half was scored anyway")
	var tally := PairedScript.tally(clusterMap)
	_require(int(tally["scheduled_clusters"]) == 1 and int(tally["decided_clusters"]) == 0,
		"an incomplete position was dropped from the denominator instead of counted")


func _checkDuplicatesAreNotSamples() -> void:
	## Two rows for one match id are a reproduction check. They say the runner is
	## deterministic; they add nothing to the evidence about which policy is better.
	var once: Array = [_row("s", 1, 0, POLICY_A), _row("s", 1, 1, POLICY_A)]
	var twice: Array = once.duplicate()
	twice.append(_row("s", 1, 0, POLICY_A))
	var first := PairedScript.tally(PairedScript.clusters(once, POLICY_A, POLICY_B))
	var second := PairedScript.tally(PairedScript.clusters(twice, POLICY_A, POLICY_B))
	_require(JSON.stringify(first, "", true) == JSON.stringify(second, "", true),
		"a repeated match changed the tally, so reproduction was counted as evidence")


func _checkRoundCapIsNotStrength() -> void:
	## A battle that hit the cap measures pacing and the cap. It must not be
	## pooled into a tally that will be read as policy quality.
	var rows: Array = [
		_row("s", 1, 0, "", "round_cap"),
		_row("s", 1, 1, "", "round_cap"),
	]
	var clusterMap := PairedScript.clusters(rows, POLICY_A, POLICY_B)
	for key in clusterMap:
		_require(str(clusterMap[key]["outcome"]) == PairedScript.OUTCOME_DRAWN,
			"two capped battles were scored as a win for somebody")
	var manifest := ManifestScript.fromFile(EVALUATION_PATH)
	var analysis := AnalyzerScript.analyze(manifest, rows, 2)
	var mentioned := false
	for note in analysis["unsupported_conclusions"]:
		if str(note).contains("round cap"):
			mentioned = true
	_require(mentioned, "the report did not warn that capped battles are not strength")


func _checkFailureDenominator() -> void:
	## Failures count against everything scheduled, so a run that lost half its
	## matches cannot look clean over the half that survived.
	var rows: Array = [_row("s", 1, 0, POLICY_A), _row("s", 1, 1, "", "timeout")]
	var infrastructure := AggregatesScript.infrastructure(rows, 4)
	_require(int(infrastructure["failed_rows"]) == 1
		and int(infrastructure["missing_rows"]) == 2,
		"failures and absences were not both counted")
	_require(absf(float(infrastructure["failure_rate"]) - 0.75) < 0.001,
		"three of four scheduled matches missing or failed gave a rate of %f" %
		float(infrastructure["failure_rate"]))


func _checkNarrowIntervalsOnly() -> void:
	## Below the declared minimum, no interval is printed at all. A range from
	## almost zero to almost one is not a finding, and its midpoint would be read
	## as one.
	var small := PairedScript.signTest({"counts": {
		PairedScript.OUTCOME_A: 3, PairedScript.OUTCOME_B: 1,
		PairedScript.OUTCOME_SPLIT: 0, PairedScript.OUTCOME_DRAWN: 0,
		PairedScript.OUTCOME_INCOMPLETE: 0}}, 8)
	_require(str(small["conclusion"]) == "insufficient_evidence",
		"four positions were enough to draw a conclusion")
	_require(not small.has("interval_low"),
		"an interval was printed below the declared minimum")
	var large := PairedScript.signTest({"counts": {
		PairedScript.OUTCOME_A: 18, PairedScript.OUTCOME_B: 2,
		PairedScript.OUTCOME_SPLIT: 0, PairedScript.OUTCOME_DRAWN: 0,
		PairedScript.OUTCOME_INCOMPLETE: 0}}, 8)
	_require(str(large["conclusion"]) == "policy_a_ahead",
		"eighteen of twenty positions did not separate the policies")
	_require(float(large["interval_low"]) > 0.5
		and float(large["interval_high"]) <= 1.0,
		"the interval was outside its possible range")
	var even := PairedScript.signTest({"counts": {
		PairedScript.OUTCOME_A: 10, PairedScript.OUTCOME_B: 10,
		PairedScript.OUTCOME_SPLIT: 0, PairedScript.OUTCOME_DRAWN: 0,
		PairedScript.OUTCOME_INCOMPLETE: 0}}, 8)
	_require(str(even["conclusion"]) == "not_separated",
		"an even split claimed a winner")


func _checkEvaluationManifest() -> void:
	## Budgets and criteria are declared before results exist, and a scenario
	## cannot be both tuning and held out.
	var manifest := ManifestScript.fromFile(EVALUATION_PATH)
	_require(manifest.isValid(), "the evaluation manifest was rejected: %s" % str(manifest.errors))
	_require(not manifest.acceptance.is_empty(),
		"the evaluation manifest declared no acceptance criteria")
	_require(manifest.acceptance.has("minimum_decisive_positions"),
		"the manifest did not declare how much evidence it requires")
	for scenario in manifest.holdout_scenarios:
		_require(not manifest.tuning_scenarios.has(scenario),
			"scenario %s is both tuning and held out" % scenario)


func _checkReportStatesItsLimits() -> void:
	var manifest := ManifestScript.fromFile(EVALUATION_PATH)
	var rows: Array = [_row("s", 1, 0, POLICY_A), _row("s", 1, 1, POLICY_B)]
	var analysis := AnalyzerScript.analyze(manifest, rows, 2)
	_require(not analysis["unsupported_conclusions"].is_empty(),
		"the analysis listed nothing it cannot conclude")
	var seedNote := false
	for note in analysis["unsupported_conclusions"]:
		if str(note).contains("shared seed"):
			seedNote = true
	_require(seedNote,
		"the report did not say that a shared seed is not an identical random stream")
	_require(analysis.has("held_out") and analysis.has("cost")
		and analysis.has("opponent_matrix") and analysis.has("by_side"),
		"the analysis omitted a required section")
	var report := AnalyzerScript._report(analysis)
	_require(report.contains("What this cannot say"),
		"the readable report had no limitations section")
	_require(report.contains("Effective sample units"),
		"the readable report did not state its sample unit")
