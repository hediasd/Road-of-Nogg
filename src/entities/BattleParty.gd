## Immutable setup description for one commander-led battle party.

class_name BattleParty
extends RefCounted

const CONTROLLER_PLAYER := "player"
const CONTROLLER_CPU := "cpu"

var partyID: int = -1
var teamID: int = -1
var commanderID: int = -1
var controller: String = CONTROLLER_CPU
var memberIDs: Array[int] = []
var monsterNames: Dictionary = {}
var memberLevels: Dictionary = {}
var startingCells: Dictionary = {}
var sourceData: Dictionary = {}


func containsMember(monsterID: int) -> bool:
	return memberIDs.has(monsterID)


func monsterNameFor(monsterID: int) -> String:
	return str(monsterNames.get(monsterID, ""))


func memberLevel(monsterID: int) -> int:
	return int(memberLevels.get(monsterID, 1))


func startingCellFor(monsterID: int) -> Vector2i:
	return startingCells.get(monsterID, Vector2i(-1, -1))


func toDictionary() -> Dictionary:
	return sourceData.duplicate(true)
