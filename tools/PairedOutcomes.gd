## Turns match rows into the unit a conclusion may actually be drawn about.
##
## The thing that makes tournament numbers lie is counting matches as
## independent. They are not. The same scenario at the same seed played with the
## sides swapped is **one comparison**, run twice to remove the advantage of
## going first -- and a manifest of two scenarios at two seeds produces eight
## rows but only four things that could independently have gone either way.
## Reporting "8 matches, 75% win rate" from that overstates the evidence by
## exactly the factor somebody would need to be misled by.
##
## So rows are grouped into **clusters** keyed by scenario and seed. A cluster
## is scored as a paired comparison: a policy that wins both sides of it won the
## position, one that wins one and loses the other drew it, and the effective
## sample size is the number of clusters, not the number of matches.
##
## A cluster that is **incomplete** -- a crashed or killed match on one side --
## is not quietly scored from the half that finished. Winning as the stronger
## side while the other assignment never ran is not a result, and it is exactly
## the half that would survive if crashes correlated with hard positions.
##
## Repeated identical matches are reproduction checks, not extra samples. Two
## rows with the same match id say the runner is deterministic; they say nothing
## additional about which policy is better, and are counted once.

class_name PairedOutcomes
extends RefCounted

const OUTCOME_A := "policy_a"
const OUTCOME_B := "policy_b"
const OUTCOME_SPLIT := "split"
const OUTCOME_DRAWN := "drawn"
const OUTCOME_INCOMPLETE := "incomplete"


## `{cluster_key: {scenario, seed, matches, outcome, reasons, incomplete_reason}}`
static func clusters(rows: Array, policyA: String, policyB: String) -> Dictionary:
	var grouped: Dictionary = {}
	var seenMatchIDs: Dictionary = {}
	for rowValue in rows:
		var row: Dictionary = rowValue
		var matchIdentifier := str(row.get("match_id", ""))
		if matchIdentifier.is_empty() or seenMatchIDs.has(matchIdentifier):
			continue
		seenMatchIDs[matchIdentifier] = true
		var key := "%s@%d" % [str(row.get("scenario", "")), int(row.get("seed", 0))]
		if not grouped.has(key):
			grouped[key] = {
				"scenario": str(row.get("scenario", "")),
				"seed": int(row.get("seed", 0)),
				"matches": [],
			}
		(grouped[key]["matches"] as Array).append(row)
	for key in grouped:
		var cluster: Dictionary = grouped[key]
		cluster["outcome"] = _scoreCluster(cluster["matches"], policyA, policyB)
		cluster["end_reasons"] = _endReasons(cluster["matches"])
	return grouped


static func _scoreCluster(matches: Array, policyA: String, policyB: String) -> String:
	var wins := {policyA: 0, policyB: 0}
	var decided := 0
	for matchValue in matches:
		var row: Dictionary = matchValue
		var reason := str(row.get("end_reason", ""))
		## A match that never finished leaves the comparison unfinished. Scoring
		## the cluster from its surviving half would keep exactly the results
		## that correlate with whatever made the other one fail.
		if reason == "crash" or reason == "timeout":
			return OUTCOME_INCOMPLETE
		decided += 1
		var winner := str(row.get("winning_policy", ""))
		if wins.has(winner):
			wins[winner] = int(wins[winner]) + 1
	if decided < 2:
		return OUTCOME_INCOMPLETE
	if int(wins[policyA]) > int(wins[policyB]):
		return OUTCOME_A
	if int(wins[policyB]) > int(wins[policyA]):
		return OUTCOME_B
	if int(wins[policyA]) == 0 and int(wins[policyB]) == 0:
		return OUTCOME_DRAWN
	return OUTCOME_SPLIT


static func _endReasons(matches: Array) -> Dictionary:
	var reasons: Dictionary = {}
	for matchValue in matches:
		var reason := str((matchValue as Dictionary).get("end_reason", "unknown"))
		reasons[reason] = int(reasons.get(reason, 0)) + 1
	return reasons


## The tally a conclusion rests on, with the denominator stated. Incomplete
## clusters stay in `scheduled` and out of `decided`, so a reader can see how
## much of the experiment actually produced evidence.
static func tally(clusterMap: Dictionary) -> Dictionary:
	var counts := {
		OUTCOME_A: 0, OUTCOME_B: 0, OUTCOME_SPLIT: 0,
		OUTCOME_DRAWN: 0, OUTCOME_INCOMPLETE: 0,
	}
	for key in clusterMap:
		var outcome := str(clusterMap[key]["outcome"])
		counts[outcome] = int(counts.get(outcome, 0)) + 1
	var scheduled := clusterMap.size()
	var decided := scheduled - int(counts[OUTCOME_INCOMPLETE])
	return {
		"counts": counts,
		"scheduled_clusters": scheduled,
		"decided_clusters": decided,
		"effective_sample_units": decided,
		"estimand": (
			"Probability that policy_a wins a scenario-and-seed position outright, "
			+ "playing both side assignments. The unit is the position, not the match."
		),
	}


## A sign test over clusters, which is the most that can be claimed from a
## paired design this small: positions the two policies split or drew carry no
## information about which is better, so only decisive positions count.
##
## The interval is a Wilson interval on decisive positions. Below the declared
## minimum it is not reported as an interval at all -- a range from almost zero
## to almost one is not a finding, and printing one invites somebody to read the
## midpoint as an estimate.
static func signTest(clusterTally: Dictionary, minimumUnits: int = 8) -> Dictionary:
	var counts: Dictionary = clusterTally["counts"]
	var winsA := int(counts[OUTCOME_A])
	var winsB := int(counts[OUTCOME_B])
	var decisive := winsA + winsB
	var result := {
		"decisive_positions": decisive,
		"policy_a_positions": winsA,
		"policy_b_positions": winsB,
		"minimum_units": minimumUnits,
	}
	if decisive < minimumUnits:
		result["conclusion"] = "insufficient_evidence"
		result["note"] = (
			"%d decisive positions is below the declared minimum of %d. No interval is "
			+ "reported, because one this wide would be read as an estimate."
		) % [decisive, minimumUnits]
		return result
	var proportion := float(winsA) / float(decisive)
	var interval := _wilson(winsA, decisive)
	result["policy_a_share"] = proportion
	result["interval_low"] = interval.x
	result["interval_high"] = interval.y
	result["conclusion"] = "policy_a_ahead" if interval.x > 0.5 \
		else ("policy_b_ahead" if interval.y < 0.5 else "not_separated")
	return result


## Wilson score interval at roughly 95 percent. Chosen over the textbook normal
## approximation because that one produces impossible bounds at the small counts
## this project will actually be running.
static func _wilson(successes: int, trials: int) -> Vector2:
	if trials <= 0:
		return Vector2(0.0, 1.0)
	var z := 1.96
	var proportion := float(successes) / float(trials)
	var denominator := 1.0 + z * z / float(trials)
	var centre := proportion + z * z / (2.0 * float(trials))
	var spread := z * sqrt(proportion * (1.0 - proportion) / float(trials)
		+ z * z / (4.0 * float(trials) * float(trials)))
	return Vector2(maxf(0.0, (centre - spread) / denominator),
		minf(1.0, (centre + spread) / denominator))
