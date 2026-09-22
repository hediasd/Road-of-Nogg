## The side policy that ships today, named and kept executable.
##
## This is not new behaviour and must never become any. It is the existing
## `PartyCommandDeliberation` stream given an identity, so that when the reworked
## policy arrives there is something concrete to play it against instead of a
## description of what the old CPU used to do. Its decisions are frozen in
## `scripts/battle/fixtures/ai/legacy_decisions.json`, and the candidates probe
## replays them: a change here that moves a single decision fails, whether it was
## meant or not.
##
## It drives the existing classes rather than copying them. A second
## implementation of the same policy would drift from the first within a cycle,
## and then neither would be the baseline.
##
## The three things worth naming, because the rework replaces exactly these:
##
## - **Actor priority** is by brain role, with a large bonus for a support unit
##   that has an injured ally and a smaller one scaled by the actor's own missing
##   health. The side deliberates the highest-priority ready actor and stops.
## - **The destination cap** keeps the ten destinations nearest an enemy, origin
##   first. Destinations past the cap are never scored at all.
## - **Selection** takes the best score with a tie-key tiebreak, then overrides
##   it with the nearest-approach candidate when nothing the actor can do from
##   anywhere it can reach touches an enemy.

class_name LegacySidePolicy
extends RefCounted

const PolicyCatalogScript = preload("res://src/entity_ai/PolicyCatalog.gd")
const PartyDeliberationScript = preload("res://src/entity_ai/PartyCommandDeliberation.gd")

const POLICY_ID := PolicyCatalogScript.LEGACY_SIDE


static func policyFingerprint() -> String:
	return PolicyCatalogScript.fingerprint(POLICY_ID)


## One side decision, run to completion. Returns the proposal's actor, command
## and score plus the identity that produced them, or an empty actor when the
## side has nothing to do.
static func decide(simulator, sliceCount: int = 64) -> Dictionary:
	var deliberation = PartyDeliberationScript.new(simulator)
	var proposal = deliberation.run(sliceCount)
	if proposal == null:
		return {
			"policy": POLICY_ID,
			"policy_fingerprint": policyFingerprint(),
			"actor_id": -1,
			"command": null,
			"score": 0,
			"candidate_count": deliberation.candidateCount(),
			"eligible": deliberation.eligibleUnitIDs(),
			"stale": deliberation.isStale(),
		}
	return {
		"policy": POLICY_ID,
		"policy_fingerprint": policyFingerprint(),
		"actor_id": proposal.actor_id,
		"command": proposal.command,
		"score": proposal.score,
		"candidate_count": proposal.candidate_count,
		"eligible": deliberation.eligibleUnitIDs(),
		"stale": false,
	}


## The same decision reduced to comparable data. Work-slice counts are excluded
## deliberately: they are a cost of how the decision was spent, not part of it,
## and freezing them would fail the moment slicing changes without any decision
## changing.
static func decisionRecord(simulator, sliceCount: int = 64) -> Dictionary:
	var decision := decide(simulator, sliceCount)
	var command = decision["command"]
	return {
		"policy": decision["policy"],
		"actor_id": int(decision["actor_id"]),
		"score": int(decision["score"]),
		"candidate_count": int(decision["candidate_count"]),
		"eligible": decision["eligible"],
		"command": command.to_dictionary() if command != null else null,
	}
