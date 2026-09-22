## The named policies a battle may be played with, and their configuration.
##
## A decision is only reproducible if you know what chose it. An experiment that
## records "the CPU won 58%" without naming the policy and its configuration has
## recorded nothing, and two runs of "the CPU" a month apart are not comparable.
## Every policy therefore has an id, a configuration, and a fingerprint over
## both, and an id this catalog does not know is refused rather than silently
## defaulted -- a typo in a manifest must fail loudly, not quietly run something
## else and label the numbers with the name that was asked for.

class_name PolicyCatalog
extends RefCounted

## The shipped role-weighted side policy: the behaviour that plays today.
const LEGACY_SIDE := "legacy_side_v1"
## Uniform choice among legal actions. A fuzzer, never an opponent.
const RANDOM_LEGAL := "random_legal_v1"

const _POLICIES: Dictionary = {
	LEGACY_SIDE: {
		"kind": "scored",
		"summary": "Role-weighted scoring over a capped destination set, first ready actor by role priority.",
		"configuration": {
			"max_side_destinations": 10,
			"weights": {
				"damage": 100, "utility": 100, "threat": 2,
				"distance": 1, "wait_penalty": 5,
			},
		},
	},
	RANDOM_LEGAL: {
		"kind": "uniform",
		"summary": "Uniform draw over enumerated legal candidates, with waiting in the pool.",
		"configuration": {"includes_wait": true},
	},
}


static func ids() -> Array[String]:
	var known: Array[String] = []
	for id in _POLICIES:
		known.append(str(id))
	known.sort()
	return known


static func has(policyID: String) -> bool:
	return _POLICIES.has(policyID)


## Refuses an unknown id. Callers that want to test for one use `has()`.
static func describe(policyID: String) -> Dictionary:
	assert(_POLICIES.has(policyID),
		"Unknown policy id '%s'. Known ids: %s" % [policyID, str(ids())])
	if not _POLICIES.has(policyID):
		return {}
	return _POLICIES[policyID].duplicate(true)


static func configurationFor(policyID: String) -> Dictionary:
	var description := describe(policyID)
	return description.get("configuration", {})


## Identity of a policy together with the configuration it actually ran with,
## so a recorded result can be matched to the thing that produced it.
static func fingerprint(policyID: String, overrides: Dictionary = {}) -> String:
	if not _POLICIES.has(policyID):
		return "unknown:%s" % policyID
	var configuration: Dictionary = configurationFor(policyID)
	for key in overrides:
		configuration[key] = overrides[key]
	return "%s:%s" % [policyID, JSON.stringify(configuration, "", true)]
