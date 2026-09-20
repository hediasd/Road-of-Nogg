## Aggregates matched policy samples without floating-point order effects.
class_name OutcomeEstimator
extends RefCounted

const ForecastScript = preload("res://src/battle_sim/BattleForecast.gd")

static func summarize(forecasts: Array) -> Dictionary:
	var accepted := 0
	var resolved := 0
	var hpByActor: Dictionary = {}
	var terminalCounts: Dictionary = {}
	var sampleIDs: Array[int] = []
	for forecast in forecasts:
		assert(forecast.rng_mode == ForecastScript.POLICY_SAMPLE,
			"Only policy-safe forecasts may be used for policy summaries.")
		assert(not sampleIDs.has(forecast.sample_id),
			"Policy sample IDs must be unique within a summary.")
		sampleIDs.append(forecast.sample_id)
		accepted += int(forecast.accepted)
		resolved += int(forecast.resolved)
		for change in forecast.changes:
			var path := str(change.get("path", ""))
			if path.ends_with("/hitpoints"):
				var parts := path.split("/")
				if parts.size() >= 3:
					var actorID := parts[parts.size() - 2]
					hpByActor[actorID] = int(hpByActor.get(actorID, 0)) + \
						int(change["after"]) - int(change["before"])
			elif path == "/battleOutcome":
				var outcome := str(change["after"])
				terminalCounts[outcome] = int(terminalCounts.get(outcome, 0)) + 1
	sampleIDs.sort()
	return {"sample_count": forecasts.size(), "sample_ids": sampleIDs,
		"accepted_count": accepted, "resolved_count": resolved,
		"hp_delta_sums": hpByActor, "terminal_counts": terminalCounts}
