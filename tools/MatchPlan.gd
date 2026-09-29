## The complete list of matches a manifest asks for, in one fixed order.
##
## Two ideas are kept apart on purpose, because confusing them is how a resumed
## experiment reports a win rate that never happened:
##
## - A **match id** names the thing to be played: manifest, scenario, seed and
##   which policy holds which side. It is the same string on every machine and
##   every run, so a result row can be matched to the work it belongs to and a
##   resume can tell what is already done.
## - An **attempt id** names one try at playing it. A match that crashed and was
##   retried has two attempts and one match; counting attempts as matches
##   double-counts exactly the matches that were hardest to finish, which are
##   rarely a random sample.
##
## Side assignment is part of the match, not a variation applied afterwards.
## When a manifest asks for both assignments, the pair is generated together so
## a scenario is never measured with one policy on the favourable side only.

class_name MatchPlan
extends RefCounted


## Every match, in canonical order: scenario, then seed, then side assignment.
## Sorting is not needed downstream -- generation order already is the order.
static func matchesFor(manifest: TournamentManifest) -> Array[Dictionary]:
	var matches: Array[Dictionary] = []
	if not manifest.isValid():
		return matches
	var assignments: Array = [0] if manifest.side_assignment \
		== TournamentManifest.SIDE_AS_DECLARED else [0, 1]
	for scenario: String in manifest.scenarios:
		for seed: int in manifest.seeds:
			for swapped in assignments:
				var sideOnePolicy := manifest.policy_a if int(swapped) == 0 else manifest.policy_b
				var sideTwoPolicy := manifest.policy_b if int(swapped) == 0 else manifest.policy_a
				matches.append({
					"match_id": matchID(manifest.manifest_id, scenario, seed, int(swapped)),
					"manifest_id": manifest.manifest_id,
					"scenario": scenario,
					"seed": seed,
					"swapped": int(swapped),
					"side_one_policy": sideOnePolicy,
					"side_two_policy": sideTwoPolicy,
				})
	return matches


## Stable across machines: a readable prefix plus a hash of the exact fields, so
## two runs of the same manifest name the same match the same way and a human
## reading a shard can still tell what a row is.
static func matchID(manifestID: String, scenario: String, seed: int,
		swapped: int) -> String:
	var context := HashingContext.new()
	context.start(HashingContext.HASH_SHA256)
	context.update(JSON.stringify({
		"manifest": manifestID, "scenario": scenario,
		"seed": seed, "swapped": swapped,
	}, "", true).to_utf8_buffer())
	return "%s-%s-%d-%d-%s" % [manifestID, scenario.get_file().get_basename(),
		seed, swapped, context.finish().hex_encode().substr(0, 12)]


static func attemptID(matchIdentifier: String, attempt: int) -> String:
	return "%s#a%d" % [matchIdentifier, attempt]


## Which matches belong to one worker. Striding rather than slicing keeps the
## work even when later matches are slower than earlier ones, which they are --
## a battle that runs to the round cap costs several times one that ends early.
static func shardOf(matches: Array, shardIndex: int, shardCount: int) -> Array[Dictionary]:
	var shard: Array[Dictionary] = []
	for index in range(matches.size()):
		if index % maxi(1, shardCount) == shardIndex:
			shard.append(matches[index])
	return shard
