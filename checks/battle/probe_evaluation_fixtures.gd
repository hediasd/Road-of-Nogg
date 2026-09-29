extends SceneTree

## Keep the exploratory mirrors honest about what they control: the roster
## changes, while each map, spawn cell, stable ID, and commander slot stays put.

const ScenarioFactoryScript = preload("res://content/BattleScenarioFactory.gd")
const ManifestScript = preload("res://tools/TournamentManifest.gd")
const MatchPlanScript = preload("res://tools/MatchPlan.gd")

const MANIFEST_PATH := "res://checks/fixtures/evaluation_mirrors_v2.json"
const CASES := [
	["technical_hxb_contract_cpu_cpu", "technical"],
	["proving_ground_cpu_cpu", "proving"],
	["hexmap_cpu_cpu", "hexmap"],
]

var failures: Array[String] = []


func _init() -> void:
	var fixturePaths: Array[String] = []
	for caseValue in CASES:
		var sourcePath := "res://data/scenarios/%s.json" % str(caseValue[0])
		for roster in ["a", "b"]:
			var fixturePath := "res://data/scenarios/eval_mirror_%s_%s.json" % [
				str(caseValue[1]), roster]
			fixturePaths.append(fixturePath)
			_checkFixture(sourcePath, fixturePath, 1 if roster == "a" else 2)
	_checkManifest(fixturePaths)
	if not failures.is_empty():
		for failure: String in failures:
			printerr("EVALUATION_FIXTURES_FAILURE: %s" % failure)
		quit(1)
		return
	print("EVALUATION_FIXTURES_OK")
	quit(0)


func _require(condition: bool, message: String) -> void:
	if not condition:
		failures.append(message)


func _document(path: String) -> Dictionary:
	if not FileAccess.file_exists(path):
		failures.append("missing scenario %s" % path)
		return {}
	var parsed = JSON.parse_string(FileAccess.get_file_as_string(path))
	if not parsed is Array or parsed.size() != 1 or not parsed[0] is Dictionary:
		failures.append("scenario is not a one-entry catalog: %s" % path)
		return {}
	return parsed[0]


func _members(document: Dictionary, teamID: int) -> Array:
	var result: Array = []
	for party in document["PARTIES"]:
		if int(party["TEAM_ID"]) == teamID:
			result.append_array(party["MEMBERS"])
	return result


func _checkFixture(sourcePath: String, fixturePath: String, donorTeam: int) -> void:
	var source := _document(sourcePath)
	var fixture := _document(fixturePath)
	if source.is_empty() or fixture.is_empty():
		return
	var loaded := ScenarioFactoryScript.loadFromPath(fixturePath)
	_require(bool(loaded.get("success", false)),
		"%s failed load or legal deployment: %s" % [fixturePath, str(loaded.get("error", ""))])
	_require(str(fixture.get("NAME", "")) == fixturePath.get_file().get_basename(),
		"%s has a mismatched scenario ID" % fixturePath)
	for field in ["FORMAT_VERSION", "REVISION", "MAP", "SEED"]:
		_require(fixture.get(field) == source.get(field),
			"%s changed source %s" % [fixturePath, field])
	var sourceParties: Array = source["PARTIES"]
	var fixtureParties: Array = fixture["PARTIES"]
	_require(sourceParties.size() == 4 and fixtureParties.size() == 4,
		"%s did not preserve four parties" % fixturePath)
	if sourceParties.size() != 4 or fixtureParties.size() != 4:
		return
	var donorMembers := _members(source, donorTeam)
	_require(donorMembers.size() == 4, "%s donor kit did not have four members" % sourcePath)
	if donorMembers.size() != 4:
		return
	for index in range(4):
		var oldParty: Dictionary = sourceParties[index]
		var newParty: Dictionary = fixtureParties[index]
		for field in ["PARTY_ID", "TEAM_ID", "CONTROLLER", "COMMANDER_ID"]:
			_require(newParty.get(field) == oldParty.get(field),
				"%s changed party %d %s" % [fixturePath, index, field])
		var oldMembers: Array = oldParty["MEMBERS"]
		var newMembers: Array = newParty["MEMBERS"]
		_require(oldMembers.size() == newMembers.size(),
			"%s changed party %d size" % [fixturePath, index])
		if oldMembers.size() != newMembers.size():
			continue
		for memberIndex in range(oldMembers.size()):
			var original: Dictionary = oldMembers[memberIndex]
			var mirrored: Dictionary = newMembers[memberIndex]
			for field in ["MEMBER_ID", "CELL"]:
				_require(mirrored.get(field) == original.get(field),
					"%s changed member %s %s" % [fixturePath,
						str(original.get("MEMBER_ID", "?")), field])
	for teamID in [1, 2]:
		var teamMembers := _members(fixture, teamID)
		_require(teamMembers.size() == 4, "%s team %d lacks four members" % [fixturePath, teamID])
		if teamMembers.size() != 4:
			continue
		for memberIndex in range(4):
			for field in ["MONSTER", "LEVEL"]:
				_require(teamMembers[memberIndex].get(field) == donorMembers[memberIndex].get(field),
					"%s team %d slot %d has wrong %s" % [
						fixturePath, teamID, memberIndex, field])


func _checkManifest(fixturePaths: Array[String]) -> void:
	var manifest := ManifestScript.fromFile(MANIFEST_PATH)
	_require(manifest.isValid(), "manifest invalid: %s" % str(manifest.errors))
	if not manifest.isValid():
		return
	_require(manifest.scenarios == fixturePaths, "manifest does not list exactly the six fixtures")
	_require(manifest.tuning_scenarios == fixturePaths and manifest.holdout_scenarios.is_empty(),
		"inspected fixtures were represented as a holdout")
	_require(manifest.seeds.size() == 6,
		"manifest does not declare six seeds")
	var distinctSeeds: Dictionary = {}
	for seed: int in manifest.seeds:
		distinctSeeds[seed] = true
	_require(distinctSeeds.size() == 6, "manifest repeats a seed")
	_require(manifest.side_assignment == ManifestScript.SIDE_BOTH,
		"manifest does not swap both policies across sides")
	_require(manifest.policy_a == "tactical_side_v1" and manifest.policy_b == "legacy_side_v1",
		"manifest changed policy comparison")
	_require(manifest.max_rounds == 30 and manifest.max_workers == 3,
		"manifest changed declared run budget")
	_require(manifest.acceptance.has("minimum_decisive_positions")
		and manifest.acceptance.has("max_infrastructure_failure_rate")
		and manifest.acceptance.has("max_round_cap_share")
		and manifest.acceptance.has("non_regression"),
		"manifest lacks declared acceptance criteria")
	var matches := MatchPlanScript.matchesFor(manifest)
	_require(matches.size() == 72, "manifest does not produce 36 paired positions")
	var pairCounts: Dictionary = {}
	for matchRow in matches:
		var key := "%s:%d" % [str(matchRow["scenario"]), int(matchRow["seed"])]
		pairCounts[key] = int(pairCounts.get(key, 0)) + 1
	_require(pairCounts.size() == 36, "manifest has wrong scenario-seed positions")
	for key in pairCounts:
		_require(int(pairCounts[key]) == 2, "%s lacks its side swap" % key)
