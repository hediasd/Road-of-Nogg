## What an experiment declares before it runs, and what it refuses.
##
## A result is only worth reading if you know what produced it. The manifest
## pins the scenarios, the seeds, the two policies and how sides are assigned,
## and every one of those travels into each result row, so a row can be traced
## back to the thing that made it without consulting anyone's memory.
##
## **Unknown names fail loudly.** A misspelled policy id must not quietly fall
## back to a default and then have its numbers reported under the name that was
## asked for. That is how an experiment comes to prove something about a policy
## that never ran.
##
## Budgets and acceptance criteria are declared here too, before any result
## exists, because a threshold chosen after seeing the outcome is not a
## threshold. The analysis item reads them back; this item only carries them.

class_name TournamentManifest
extends RefCounted

const CatalogScript = preload("res://src/entity_ai/PolicyCatalog.gd")

const SIDE_AS_DECLARED := "as_declared"
const SIDE_BOTH := "both"
const SIDE_ASSIGNMENTS: Array[String] = [SIDE_AS_DECLARED, SIDE_BOTH]

var manifest_id: String = ""
var scenarios: Array[String] = []
var seeds: Array[int] = []
var policy_a: String = ""
var policy_b: String = ""
var side_assignment: String = SIDE_BOTH
var max_rounds: int = 30
var worker_timeout_seconds: int = 300
var max_workers: int = 2
## Declared before any result is read. Carried, not judged, by this item.
var acceptance: Dictionary = {}
var tuning_scenarios: Array[String] = []
var holdout_scenarios: Array[String] = []
var errors: Array[String] = []


static func fromFile(path: String) -> TournamentManifest:
	var manifest := TournamentManifest.new()
	if not FileAccess.file_exists(path):
		manifest.errors.append("manifest does not exist: %s" % path)
		return manifest
	var parsed = JSON.parse_string(FileAccess.get_file_as_string(path))
	if not parsed is Dictionary:
		manifest.errors.append("manifest is not an object: %s" % path)
		return manifest
	return fromDictionary(parsed)


static func fromDictionary(data: Dictionary) -> TournamentManifest:
	var manifest := TournamentManifest.new()
	manifest.manifest_id = str(data.get("manifest_id", ""))
	if manifest.manifest_id.is_empty():
		manifest.errors.append("manifest_id is required")
	for value in data.get("scenarios", []):
		manifest.scenarios.append(str(value))
	if manifest.scenarios.is_empty():
		manifest.errors.append("at least one scenario is required")
	for value in data.get("seeds", []):
		manifest.seeds.append(int(value))
	if manifest.seeds.is_empty():
		manifest.errors.append("at least one seed is required")
	manifest.policy_a = str(data.get("policy_a", ""))
	manifest.policy_b = str(data.get("policy_b", ""))
	for policyID in [manifest.policy_a, manifest.policy_b]:
		if not CatalogScript.has(policyID):
			manifest.errors.append(
				"unknown policy id '%s'; known ids are %s" % [policyID, str(CatalogScript.ids())])
	manifest.side_assignment = str(data.get("side_assignment", SIDE_BOTH))
	if not SIDE_ASSIGNMENTS.has(manifest.side_assignment):
		manifest.errors.append("side_assignment must be one of %s" % str(SIDE_ASSIGNMENTS))
	manifest.max_rounds = int(data.get("max_rounds", 30))
	manifest.worker_timeout_seconds = int(data.get("worker_timeout_seconds", 300))
	manifest.max_workers = maxi(1, int(data.get("max_workers", 2)))
	manifest.acceptance = data.get("acceptance", {})
	for value in data.get("tuning_scenarios", []):
		manifest.tuning_scenarios.append(str(value))
	for value in data.get("holdout_scenarios", []):
		manifest.holdout_scenarios.append(str(value))
	for scenario in manifest.holdout_scenarios:
		if manifest.tuning_scenarios.has(scenario):
			manifest.errors.append(
				"scenario %s is declared as both tuning and held out" % scenario)
	return manifest


func isValid() -> bool:
	return errors.is_empty()


## Everything a reader needs to know what produced a row, other than the build,
## which the runner adds because only it can hash the files it ran.
func identity() -> Dictionary:
	return {
		"manifest_id": manifest_id,
		"policy_a": policy_a,
		"policy_b": policy_b,
		"policy_a_fingerprint": CatalogScript.fingerprint(policy_a),
		"policy_b_fingerprint": CatalogScript.fingerprint(policy_b),
		"side_assignment": side_assignment,
		"max_rounds": max_rounds,
		"scenarios": scenarios.duplicate(),
		"seeds": seeds.duplicate(),
	}
