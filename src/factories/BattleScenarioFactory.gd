## Strict JSON boundary joining a tactical map to deterministic battle parties.

class_name BattleScenarioFactory
extends RefCounted

const BattlePartyScript = preload("res://src/entities/BattleParty.gd")
const BattleScenarioScript = preload("res://src/entities/BattleScenario.gd")
const BattleMapFactoryScript = preload("res://src/factories/BattleMapFactory.gd")
const JsonCatalogLoaderScript = preload("res://src/factories/JsonCatalogLoader.gd")
const MonsterReferencesScript = preload("res://src/factories/MonsterReferences.gd")

const FORMAT_VERSION := 1


static func loadScenario(scenarioID: String) -> Dictionary:
	if not scenarioID.is_valid_identifier() or scenarioID.to_lower() != scenarioID:
		return _failure("invalid_scenario_id", scenarioID)
	return loadFromPath("res://data/battle/scenarios/%s.json" % scenarioID)


static func loadFromPath(path: String) -> Dictionary:
	var loaded := JsonCatalogLoaderScript.loadNamedCatalog(path)
	if not loaded["success"]:
		return _failure("scenario_resource_error", str(loaded["error"]))
	if loaded["list"].size() != 1:
		return _failure("scenario_file_entry_count", path)
	return fromDictionary(loaded["list"][0])


static func fromDictionary(rawValue) -> Dictionary:
	if not rawValue is Dictionary:
		return _failure("scenario_not_dictionary")
	var raw: Dictionary = rawValue.duplicate(true)
	var versionResult := _nonnegativeInteger(raw.get("FORMAT_VERSION"))
	if not versionResult["success"] or int(versionResult["value"]) != FORMAT_VERSION:
		return _failure("unsupported_scenario_version")
	var scenarioID := str(raw.get("NAME", ""))
	if scenarioID.is_empty():
		return _failure("missing_scenario_id")
	var revisionResult := _positiveInteger(raw.get("REVISION", 1))
	var seedResult := _nonnegativeInteger(raw.get("SEED", 42))
	if not revisionResult["success"] or not seedResult["success"]:
		return _failure("invalid_scenario_numbers")

	var mapValue = raw.get("MAP")
	if not mapValue is Dictionary:
		return _failure("invalid_scenario_map")
	var mapData: Dictionary = mapValue
	var mapPath := str(mapData.get("PATH", ""))
	if mapPath.is_empty():
		return _failure("missing_map_resource")
	var mapResult := BattleMapFactoryScript.loadFromPath(mapPath)
	if not mapResult["success"]:
		return _failure("map_load_failed", str(mapResult["error"]))
	var definition = mapResult["definition"]
	if str(mapData.get("ID", "")) != definition.mapID:
		return _failure("map_id_mismatch")
	var mapRevisionResult := _positiveInteger(mapData.get("REVISION"))
	if not mapRevisionResult["success"] or int(mapRevisionResult["value"]) != definition.revision:
		return _failure("map_revision_mismatch")
	if str(mapData.get("SOURCE_FINGERPRINT", "")) != definition.sourceFingerprint:
		return _failure("map_fingerprint_mismatch")

	var partiesValue = raw.get("PARTIES")
	if not partiesValue is Array or partiesValue.is_empty():
		return _failure("missing_parties")
	var parties: Array[BattleParty] = []
	var partyIDs: Dictionary = {}
	var memberIDs: Dictionary = {}
	var occupied: Dictionary = {}
	var teams: Dictionary = {}
	for partyValue in partiesValue:
		if not partyValue is Dictionary:
			return _failure("invalid_party")
		var partyData: Dictionary = partyValue
		var partyIDResult := _positiveInteger(partyData.get("PARTY_ID"))
		var teamIDResult := _positiveInteger(partyData.get("TEAM_ID"))
		var commanderIDResult := _positiveInteger(partyData.get("COMMANDER_ID"))
		if not partyIDResult["success"] or not teamIDResult["success"] or not commanderIDResult["success"]:
			return _failure("invalid_party_identity")
		var partyID := int(partyIDResult["value"])
		var teamID := int(teamIDResult["value"])
		var commanderID := int(commanderIDResult["value"])
		if partyIDs.has(partyID):
			return _failure("duplicate_party_id", str(partyID))
		partyIDs[partyID] = true
		teams[teamID] = true
		var controller := str(partyData.get("CONTROLLER", ""))
		if controller not in [BattlePartyScript.CONTROLLER_PLAYER, BattlePartyScript.CONTROLLER_CPU]:
			return _failure("unknown_controller", controller)

		var membersValue = partyData.get("MEMBERS")
		if not membersValue is Array or membersValue.is_empty():
			return _failure("empty_party", str(partyID))
		var party = BattlePartyScript.new()
		party.partyID = partyID
		party.teamID = teamID
		party.commanderID = commanderID
		party.controller = controller
		party.sourceData = partyData.duplicate(true)
		for memberValue in membersValue:
			if not memberValue is Dictionary:
				return _failure("invalid_member", str(partyID))
			var member: Dictionary = memberValue
			var memberIDResult := _positiveInteger(member.get("MEMBER_ID"))
			var levelResult := _positiveInteger(member.get("LEVEL", 1))
			if not memberIDResult["success"] or not levelResult["success"]:
				return _failure("invalid_member_identity", str(partyID))
			var memberID := int(memberIDResult["value"])
			if memberIDs.has(memberID):
				return _failure("duplicate_member_id", str(memberID))
			memberIDs[memberID] = partyID
			var monsterName := str(member.get("MONSTER", ""))
			if not MonsterReferencesScript.hasReference(monsterName):
				return _failure("unknown_monster", monsterName)
			var cellResult := _vectorPair(member.get("CELL"))
			if not cellResult["success"]:
				return _failure("invalid_deployment", str(memberID))
			var cell: Vector2i = cellResult["value"]
			if not definition.containsCell(cell):
				return _failure("deployment_outside_valid_mask", str(cell))
			if not definition.isStoppable(cell):
				return _failure("deployment_not_standable", str(cell))
			if occupied.has(cell):
				return _failure("overlapping_deployment", str(cell))
			occupied[cell] = memberID
			party.memberIDs.append(memberID)
			party.monsterNames[memberID] = monsterName
			party.memberLevels[memberID] = int(levelResult["value"])
			party.startingCells[memberID] = cell
		if not party.containsMember(commanderID):
			return _failure("commander_not_in_party", str(commanderID))
		parties.append(party)
	if teams.size() < 2:
		return _failure("insufficient_teams")

	parties.sort_custom(func(a: BattleParty, b: BattleParty) -> bool:
		return a.partyID < b.partyID)
	var scenario = BattleScenarioScript.new()
	scenario.formatVersion = FORMAT_VERSION
	scenario.scenarioID = scenarioID
	scenario.revision = int(revisionResult["value"])
	scenario.seed = int(seedResult["value"])
	scenario.mapPath = mapPath
	scenario.mapID = definition.mapID
	scenario.mapRevision = definition.revision
	scenario.sourceFingerprint = definition.sourceFingerprint
	scenario.battleMap = definition
	scenario.sourceData = raw
	scenario.configureParties(parties)
	return {"success": true, "scenario": scenario, "error": ""}


static func _vectorPair(value) -> Dictionary:
	if not value is Array or value.size() != 2:
		return _failure("invalid_coordinate")
	var xResult := _nonnegativeInteger(value[0])
	var yResult := _nonnegativeInteger(value[1])
	if not xResult["success"] or not yResult["success"]:
		return _failure("invalid_coordinate")
	return {"success": true, "value": Vector2i(int(xResult["value"]), int(yResult["value"])), "error": ""}


static func _positiveInteger(value) -> Dictionary:
	var result := _nonnegativeInteger(value)
	if not result["success"] or int(result["value"]) <= 0:
		return _failure("invalid_positive_integer")
	return result


static func _nonnegativeInteger(value) -> Dictionary:
	if not (value is int or value is float):
		return _failure("invalid_integer")
	var number := float(value)
	if not is_finite(number) or number < 0.0 or number != floor(number):
		return _failure("invalid_integer")
	return {"success": true, "value": int(number), "error": ""}


static func _failure(code: String, detail: String = "") -> Dictionary:
	return {"success": false, "scenario": null, "error": code, "detail": detail}
