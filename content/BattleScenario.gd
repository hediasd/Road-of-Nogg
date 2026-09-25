## Typed setup resource tying a tactical map to commander-led parties.

class_name BattleScenario
extends RefCounted

var formatVersion: int = 1
var scenarioID: String = ""
var revision: int = 1
var mapPath: String = ""
var mapID: String = ""
var mapRevision: int = 1
var sourceFingerprint: String = ""
var seed: int = 42
var battleMap: BattleMapDefinition
var parties: Array[BattleParty] = []
var sourceData: Dictionary = {}

var _partyByID: Dictionary = {}
var _partyIDByMember: Dictionary = {}


func configureParties(values: Array[BattleParty]) -> void:
	parties = values.duplicate()
	_partyByID.clear()
	_partyIDByMember.clear()
	for party: BattleParty in parties:
		_partyByID[party.partyID] = party
		for memberID: int in party.memberIDs:
			_partyIDByMember[memberID] = party.partyID


func partyForID(partyID: int) -> BattleParty:
	return _partyByID.get(partyID)


func partyForMember(memberID: int) -> BattleParty:
	return partyForID(int(_partyIDByMember.get(memberID, -1)))


func toDictionary() -> Dictionary:
	return sourceData.duplicate(true)
