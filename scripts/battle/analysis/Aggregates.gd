## Everything a report needs that is not the headline number.
##
## The headline is one paired comparison and it is easy to over-read. These are
## the columns that let somebody see *why* it came out that way, and they are
## kept deliberately separate from it:
##
## - **Round-cap finishes are not wins.** A battle that hit the cap tells you
##   about pacing and about the cap, and pooling it into a strength tally
##   measures game balance while calling it policy quality.
## - **Infrastructure failures have their own denominator.** They are counted
##   against everything scheduled, so a run that crashed a third of its matches
##   cannot look like a clean result over the two thirds that survived.
## - **Cost is reported beside quality, at the budget it was bought with.** A
##   policy that wins by thinking ten times longer has not been shown to be
##   better; it has been shown to be slower, and the reader should be able to
##   see both numbers without going looking.

class_name Aggregates
extends RefCounted

const INFRASTRUCTURE: Array[String] = ["crash", "timeout"]


static func endReasons(rows: Array) -> Dictionary:
	var reasons: Dictionary = {}
	for rowValue in rows:
		var reason := str((rowValue as Dictionary).get("end_reason", "unknown"))
		reasons[reason] = int(reasons.get(reason, 0)) + 1
	return reasons


## Against every scheduled match, not only the ones that produced a result.
static func infrastructure(rows: Array, scheduledMatches: int) -> Dictionary:
	var failed := 0
	for rowValue in rows:
		if INFRASTRUCTURE.has(str((rowValue as Dictionary).get("end_reason", ""))):
			failed += 1
	var missing := maxi(0, scheduledMatches - rows.size())
	return {
		"failed_rows": failed,
		"missing_rows": missing,
		"scheduled_matches": scheduledMatches,
		"failure_rate": 0.0 if scheduledMatches <= 0
			else float(failed + missing) / float(scheduledMatches),
		"note": "Rate is over every scheduled match, so surviving matches cannot flatter a run.",
	}


## Which policy won, per side, per scenario. A policy that only wins from side
## one has not beaten the other policy; it has been handed the better seat.
static func bySide(rows: Array) -> Dictionary:
	var sides: Dictionary = {}
	for rowValue in rows:
		var row: Dictionary = rowValue
		var winner := str(row.get("winning_policy", ""))
		if winner.is_empty():
			continue
		var seat := "side_one" if int(row.get("winner_team", 0)) == 1 else "side_two"
		if not sides.has(seat):
			sides[seat] = {}
		sides[seat][winner] = int((sides[seat] as Dictionary).get(winner, 0)) + 1
	return sides


static func byScenario(rows: Array) -> Dictionary:
	var scenarios: Dictionary = {}
	for rowValue in rows:
		var row: Dictionary = rowValue
		var scenario := str(row.get("scenario", ""))
		if not scenarios.has(scenario):
			scenarios[scenario] = {"matches": 0, "end_reasons": {}, "winners": {}}
		var entry: Dictionary = scenarios[scenario]
		entry["matches"] = int(entry["matches"]) + 1
		var reason := str(row.get("end_reason", "unknown"))
		entry["end_reasons"][reason] = int((entry["end_reasons"] as Dictionary).get(reason, 0)) + 1
		var winner := str(row.get("winning_policy", ""))
		if not winner.is_empty():
			entry["winners"][winner] = int((entry["winners"] as Dictionary).get(winner, 0)) + 1
	return scenarios


## Who beat whom, as a matrix, so a league of more than two policies reads
## without anybody recomputing it.
static func opponentMatrix(rows: Array) -> Dictionary:
	var matrix: Dictionary = {}
	for rowValue in rows:
		var row: Dictionary = rowValue
		var one := str(row.get("side_one_policy", ""))
		var two := str(row.get("side_two_policy", ""))
		var winner := str(row.get("winning_policy", ""))
		if one.is_empty() or two.is_empty():
			continue
		var key := "%s_vs_%s" % [one, two] if one <= two else "%s_vs_%s" % [two, one]
		if not matrix.has(key):
			matrix[key] = {"matches": 0, "wins": {}, "undecided": 0}
		var entry: Dictionary = matrix[key]
		entry["matches"] = int(entry["matches"]) + 1
		if winner.is_empty():
			entry["undecided"] = int(entry["undecided"]) + 1
			continue
		entry["wins"][winner] = int((entry["wins"] as Dictionary).get(winner, 0)) + 1
	return matrix


## What the results cost. Work counts are deterministic and comparable across
## machines; the microseconds beside them are neither, and say so.
static func cost(rows: Array) -> Dictionary:
	var deliberations := 0
	var slices := 0
	var candidates := 0
	var elapsed := 0
	var p50: Array[int] = []
	var p95: Array[int] = []
	for rowValue in rows:
		var row: Dictionary = rowValue
		var work: Dictionary = row.get("work", {})
		deliberations += int(work.get("deliberations", 0))
		slices += int(work.get("slices", 0))
		candidates += int(work.get("candidates_enumerated", 0))
		var telemetry: Dictionary = row.get("telemetry", {})
		elapsed += int(telemetry.get("elapsed_usec", 0))
		p50.append(int(telemetry.get("decision_usec_p50", 0)))
		p95.append(int(telemetry.get("decision_usec_p95", 0)))
	p50.sort()
	p95.sort()
	return {
		"deliberations": deliberations,
		"slices": slices,
		"candidates_enumerated": candidates,
		"slices_per_deliberation": 0.0 if deliberations == 0
			else float(slices) / float(deliberations),
		"median_match_decision_usec_p50": 0 if p50.is_empty() else p50[p50.size() / 2],
		"median_match_decision_usec_p95": 0 if p95.is_empty() else p95[p95.size() / 2],
		"total_elapsed_usec": elapsed,
		"note": (
			"Slices and candidate counts are deterministic and comparable. "
			+ "Microseconds are observations of whichever host ran the shard."
		),
	}


## Matches worth opening, each with enough identity to replay it. A report that
## says a policy lost without saying which battles is not actionable.
static func representativeLosses(rows: Array, policyID: String,
		limit: int = 3) -> Array[Dictionary]:
	var losses: Array[Dictionary] = []
	for rowValue in rows:
		var row: Dictionary = rowValue
		var winner := str(row.get("winning_policy", ""))
		if winner.is_empty() or winner == policyID:
			continue
		if str(row.get("side_one_policy", "")) != policyID \
				and str(row.get("side_two_policy", "")) != policyID:
			continue
		losses.append({
			"match_id": str(row.get("match_id", "")),
			"scenario": str(row.get("scenario", "")),
			"seed": int(row.get("seed", 0)),
			"swapped": int(row.get("swapped", 0)),
			"rounds": int(row.get("rounds", 0)),
			"end_reason": str(row.get("end_reason", "")),
			"won_by": winner,
			"reproduce": (
				"run_battle.gd -- %s %d  (policies: side one %s, side two %s)"
			) % [str(row.get("scenario", "")), int(row.get("seed", 0)),
				str(row.get("side_one_policy", "")), str(row.get("side_two_policy", ""))],
		})
	losses.sort_custom(func(a: Dictionary, b: Dictionary) -> bool:
		return str(a["match_id"]) < str(b["match_id"]))
	return losses.slice(0, limit)
