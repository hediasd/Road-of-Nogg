## Where a company stands on one road: who is in it, how much Belief each monster holds, who is
## fielded and who commands, and how far along the road it has got.
##
## OWNERSHIP. This is the road's canonical state, the way `BattleState` is the battle's. The road
## scene reads it and asks it to change; it never edits the fields itself. Every operation that
## can be refused returns `{ok, error}` so a refusal reaches the player as a reason.
##
## THE ROAD IS LINEAR. Stops `0 .. clearedCount - 1` are cleared and may be fought again; stop
## `clearedCount` is the next one; anything past it is locked. A loss or a draw leaves the company
## where it is.
##
## SERIALIZATION. `toDictionary()` / `fromDictionary()` are the save format. The save names the
## road and its revision, and loading refuses a save made for a different road or revision rather
## than guessing how to map one company onto another (AGENTS.md: fail loudly on desync).

extends RefCounted

const RoadRulesScript = preload("res://road/RoadRules.gd")
const MonsterReferencesScript = preload("res://content/MonsterReferences.gd")

const SAVE_FORMAT_VERSION := 1

var roadName := ""
var roadRevision := 1
## One entry per company slot: `{monster: String, belief: int}`. Slots never move, so a battle's
## member ids can map back to them.
var company: Array[Dictionary] = []
## Company slots that go into the next battle, in deployment order.
var fielded: Array[int] = []
## The fielded slot that commands. Its fall withdraws the party and loses the battle.
var commander := -1
var fieldSize := 4
var clearedCount := 0
## Where the company token stands: -1 at the start, otherwise the stop last fought at.
var position := -1
## stop index -> how many battles were started there. Part of each battle's seed.
var attempts: Dictionary = {}
## What the last applied battle paid, for the road screen to show. Not needed to resume.
var lastReport: Dictionary = {}


## A fresh company at the start of `road` (a normalized road from `RoadReferences`).
static func fromRoad(road: Dictionary) -> RefCounted:
	var state = load("res://road/RoadState.gd").new()
	state.roadName = str(road["name"])
	state.roadRevision = int(road["revision"])
	state.fieldSize = int(road["field_size"])
	for monsterName: String in road["company"]:
		state.company.append({"monster": monsterName, "belief": 0})
	state.fielded = (road["fielded"] as Array[int]).duplicate()
	state.commander = int(road["commander"])
	return state


func levelOf(slot: int) -> int:
	return RoadRulesScript.levelForBelief(int(company[slot]["belief"]))


func monsterOf(slot: int) -> String:
	return str(company[slot]["monster"])


func beliefOf(slot: int) -> int:
	return int(company[slot]["belief"])


func isFielded(slot: int) -> bool:
	return fielded.has(slot)


func isStopOpen(stopIndex: int, stopCount: int) -> bool:
	return stopIndex >= 0 and stopIndex < stopCount and stopIndex <= clearedCount


func isComplete(stopCount: int) -> bool:
	return clearedCount >= stopCount


## Adds a slot to the field, or takes it off. Taking off the commander hands command to the first
## slot still fielded; the field can never be emptied.
func toggleFielded(slot: int) -> Dictionary:
	if slot < 0 or slot >= company.size():
		return _refuse("no company slot %d" % slot)
	if fielded.has(slot):
		if fielded.size() == 1:
			return _refuse("at least one monster must be fielded")
		fielded.erase(slot)
		if commander == slot:
			commander = fielded[0]
		return _ok()
	if fielded.size() >= fieldSize:
		return _refuse("only %d monsters can be fielded" % fieldSize)
	fielded.append(slot)
	return _ok()


func setCommander(slot: int) -> Dictionary:
	if not fielded.has(slot):
		return _refuse("only a fielded monster can command")
	commander = slot
	return _ok()


func canAscend(slot: int) -> bool:
	return slot >= 0 and slot < company.size() \
		and RoadRulesScript.canAscend(monsterOf(slot), beliefOf(slot))


## Turns the monster in `slot` into its ascended form. Belief, and so level, is kept.
func ascend(slot: int) -> Dictionary:
	if not canAscend(slot):
		return _refuse("this monster cannot ascend yet")
	var before := monsterOf(slot)
	var after := RoadRulesScript.ascendedFormOf(before)
	company[slot]["monster"] = after
	return {"ok": true, "error": "", "from": before, "to": after}


## Counts a battle started at `stopIndex` and returns its attempt number (1 for the first).
func beginAttempt(stopIndex: int) -> int:
	attempts[stopIndex] = int(attempts.get(stopIndex, 0)) + 1
	position = stopIndex
	return int(attempts[stopIndex])


## Pays a finished battle. `summary` comes from `RoadBattle.summarize`:
## `{outcome: "won"|"lost"|"draw", units: {slot: {standing, felled, commanders_felled}}}`.
## Returns, and keeps in `lastReport`, what each fielded slot earned and whether it levelled.
func applyBattle(stopIndex: int, summary: Dictionary) -> Dictionary:
	var won := str(summary.get("outcome", "")) == "won"
	var units: Dictionary = summary.get("units", {})
	var paid: Dictionary = {}
	for slotValue in units:
		var slot := int(slotValue)
		if slot < 0 or slot >= company.size():
			push_error("RoadState: a battle summary named company slot %d, which does not exist" % slot)
			continue
		var levelBefore := levelOf(slot)
		var earned := RoadRulesScript.beliefEarned(units[slotValue], won)
		company[slot]["belief"] = beliefOf(slot) + earned
		paid[slot] = {
			"earned": earned,
			"level_before": levelBefore,
			"level_after": levelOf(slot),
			"can_ascend": canAscend(slot),
		}
	if won and stopIndex == clearedCount:
		clearedCount += 1
	lastReport = {"stop": stopIndex, "outcome": str(summary.get("outcome", "")), "units": paid}
	return lastReport


func toDictionary() -> Dictionary:
	var attemptList: Array = []
	var stopKeys := attempts.keys()
	stopKeys.sort()
	for stopIndex in stopKeys:
		attemptList.append([int(stopIndex), int(attempts[stopIndex])])
	var companyList: Array = []
	for entry in company:
		companyList.append({"MONSTER": str(entry["monster"]), "BELIEF": int(entry["belief"])})
	return {
		"FORMAT_VERSION": SAVE_FORMAT_VERSION,
		"ROAD": roadName,
		"ROAD_REVISION": roadRevision,
		"COMPANY": companyList,
		"FIELDED": fielded.duplicate(),
		"COMMANDER": commander,
		"CLEARED": clearedCount,
		"POSITION": position,
		"ATTEMPTS": attemptList,
	}


## Rebuilds a state saved for `road`. `{ok, error, state}`; refuses a save for another road, an
## older revision of this one, or one whose numbers do not fit it.
static func fromDictionary(raw: Dictionary, road: Dictionary) -> Dictionary:
	if int(raw.get("FORMAT_VERSION", -1)) != SAVE_FORMAT_VERSION:
		return {"ok": false, "error": "unsupported save format", "state": null}
	if str(raw.get("ROAD", "")) != str(road["name"]):
		return {"ok": false, "error": "the save is for road '%s'" % str(raw.get("ROAD", "")), "state": null}
	if int(raw.get("ROAD_REVISION", -1)) != int(road["revision"]):
		return {"ok": false, "error": "the save is for an older revision of this road", "state": null}
	var state = load("res://road/RoadState.gd").new()
	state.roadName = str(road["name"])
	state.roadRevision = int(road["revision"])
	state.fieldSize = int(road["field_size"])
	var companyValue = raw.get("COMPANY")
	if not companyValue is Array or (companyValue as Array).size() != (road["company"] as Array).size():
		return {"ok": false, "error": "the saved company does not match the road's", "state": null}
	for entry in companyValue:
		var monsterName := str((entry as Dictionary).get("MONSTER", "")) if entry is Dictionary else ""
		if not MonsterReferencesScript.hasReference(monsterName):
			return {"ok": false, "error": "the save names unknown monster '%s'" % monsterName, "state": null}
		state.company.append({"monster": monsterName, "belief": maxi(0, int((entry as Dictionary).get("BELIEF", 0)))})
	for slot in raw.get("FIELDED", []):
		if int(slot) < 0 or int(slot) >= state.company.size() or state.fielded.has(int(slot)):
			return {"ok": false, "error": "the save fields an invalid slot", "state": null}
		state.fielded.append(int(slot))
	if state.fielded.is_empty() or state.fielded.size() > state.fieldSize:
		return {"ok": false, "error": "the save fields the wrong number of monsters", "state": null}
	state.commander = int(raw.get("COMMANDER", -1))
	if not state.fielded.has(state.commander):
		return {"ok": false, "error": "the saved commander is not fielded", "state": null}
	var stopCount := (road["stops"] as Array).size()
	state.clearedCount = clampi(int(raw.get("CLEARED", 0)), 0, stopCount)
	state.position = clampi(int(raw.get("POSITION", -1)), -1, stopCount - 1)
	for pair in raw.get("ATTEMPTS", []):
		if pair is Array and (pair as Array).size() == 2:
			state.attempts[int(pair[0])] = maxi(0, int(pair[1]))
	return {"ok": true, "error": "", "state": state}


static func _ok() -> Dictionary:
	return {"ok": true, "error": ""}


static func _refuse(message: String) -> Dictionary:
	return {"ok": false, "error": message}
