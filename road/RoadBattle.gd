## Turns a road stop into a battle and a finished battle back into what the road pays for it.
##
## COMPOSING. A stop's battle is an ordinary hex scenario, built as the same Dictionary a
## scenario file holds and checked by `BattleScenarioFactory.fromDictionary`, so a road battle is
## refused for exactly the reasons any battle is. The company is one party on team 1, the stop's
## enemy parties are team 2. Member ids are derived from company slots (`PLAYER_MEMBER_BASE +
## slot`), so the battle can be read back onto the company without a lookup table surviving the
## battle. The map's id, revision and fingerprint are read from the battle map itself, so a road
## never goes stale when a map is re-exported.
##
## TALLYING. `Tally` listens to `BattleEvents.monster_defeated` while a battle runs and records
## who felled whom; `summarize` combines that with the final `BattleState`. Only events reach the
## tally, never presentation. There is no player-facing rewind; a rewound timeline would leave
## defeats in the tally that the restored state no longer has.
##
## SEEDS. `road seed + 1000 * stop + attempt`: a retry is a different battle, and the same
## attempt is the same battle.

extends RefCounted

const BattleScenarioFactoryScript = preload("res://content/BattleScenarioFactory.gd")
const BattleMapFactoryScript = preload("res://content/BattleMapFactory.gd")
const RoadRulesScript = preload("res://road/RoadRules.gd")

const PLAYER_TEAM := 1
const ENEMY_TEAM := 2
const PLAYER_PARTY_ID := 10
const ENEMY_PARTY_BASE := 20
const PLAYER_MEMBER_BASE := 100
const ENEMY_MEMBER_BASE := 200
const SEED_STOP_STRIDE := 1000

const CONTROLLER_PLAYER := "player"
const CONTROLLER_CPU := "cpu"


static func seedFor(road: Dictionary, stopIndex: int, attempt: int) -> int:
	return int(road["seed"]) + SEED_STOP_STRIDE * stopIndex + attempt


static func memberIDFor(slot: int) -> int:
	return PLAYER_MEMBER_BASE + slot


static func slotForMember(memberID: int) -> int:
	return memberID - PLAYER_MEMBER_BASE


## `{ok, error, scenario: Dictionary, seed: int}`. `controller` is "player" for real play and
## "cpu" for a battle the CPU plays on the company's behalf (probes, autoplay).
static func compose(state, road: Dictionary, stopIndex: int, attempt: int,
		controller: String = CONTROLLER_PLAYER) -> Dictionary:
	var stops: Array = road["stops"]
	if stopIndex < 0 or stopIndex >= stops.size():
		return _refuse("no stop %d on this road" % stopIndex)
	var stop: Dictionary = stops[stopIndex]
	var mapResult := BattleMapFactoryScript.loadFromPath(str(stop["map_path"]))
	if not mapResult["success"]:
		return _refuse("stop %s's map did not load: %s" % [stop["id"], str(mapResult["error"])])
	var definition = mapResult["definition"]
	var playerCells: Array = stop["player_cells"]
	if state.fielded.size() > playerCells.size():
		return _refuse("stop %s has room for %d, not %d" % [stop["id"], playerCells.size(), state.fielded.size()])

	var members: Array = []
	for index in range(state.fielded.size()):
		var slot: int = state.fielded[index]
		var cell: Vector2i = playerCells[index]
		members.append({
			"MEMBER_ID": memberIDFor(slot),
			"MONSTER": state.monsterOf(slot),
			"LEVEL": state.levelOf(slot),
			"CELL": [cell.x, cell.y],
		})
	var parties: Array = [{
		"PARTY_ID": PLAYER_PARTY_ID,
		"TEAM_ID": PLAYER_TEAM,
		"CONTROLLER": controller,
		"COMMANDER_ID": memberIDFor(state.commander),
		"MEMBERS": members,
	}]
	var enemies: Array = stop["enemies"]
	for partyIndex in range(enemies.size()):
		var enemy: Dictionary = enemies[partyIndex]
		var enemyMembers: Array = []
		var enemyList: Array = enemy["members"]
		for memberIndex in range(enemyList.size()):
			var member: Dictionary = enemyList[memberIndex]
			var cell: Vector2i = member["cell"]
			enemyMembers.append({
				"MEMBER_ID": _enemyMemberID(partyIndex, memberIndex),
				"MONSTER": str(member["monster"]),
				"LEVEL": int(member["level"]),
				"CELL": [cell.x, cell.y],
			})
		parties.append({
			"PARTY_ID": ENEMY_PARTY_BASE + partyIndex,
			"TEAM_ID": ENEMY_TEAM,
			"CONTROLLER": CONTROLLER_CPU,
			"COMMANDER_ID": _enemyMemberID(partyIndex, int(enemy["commander"])),
			"MEMBERS": enemyMembers,
		})

	var seed := seedFor(road, stopIndex, attempt)
	var scenario := {
		"FORMAT_VERSION": BattleScenarioFactoryScript.FORMAT_VERSION,
		"NAME": "%s_%s" % [str(road["name"]), str(stop["id"])],
		"REVISION": 1,
		"MAP": {
			"PATH": str(stop["map_path"]),
			"ID": definition.mapID,
			"REVISION": definition.revision,
			"SOURCE_FINGERPRINT": definition.sourceFingerprint,
		},
		"SEED": seed,
		"PARTIES": parties,
	}
	var checked := BattleScenarioFactoryScript.fromDictionary(scenario)
	if not checked["success"]:
		return _refuse("the stop's battle is not valid: %s %s" % [str(checked["error"]), str(checked.get("detail", ""))])
	return {"ok": true, "error": "", "scenario": scenario, "seed": seed}


## Writes a composed scenario where `BattleScenarioFactory.loadFromPath` can read it: a one-entry
## catalog, like the files under `data/scenarios`.
static func writeScenario(scenario: Dictionary, path: String) -> Dictionary:
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(path.get_base_dir()))
	var file := FileAccess.open(path, FileAccess.WRITE)
	if file == null:
		return _refuse("could not write %s (error %d)" % [path, FileAccess.get_open_error()])
	file.store_string(JSON.stringify([scenario], "\t"))
	file.close()
	return {"ok": true, "error": "", "path": path}


## `{outcome: "won"|"lost"|"draw"|"unfinished", units: {slot: {standing, felled, commanders_felled}}}`
## for every company slot that fought. `defeats` is a `Tally`'s record.
static func summarize(battleState, defeats: Array) -> Dictionary:
	var outcome := "unfinished"
	var result := int(battleState.battleOutcome)
	if result == PLAYER_TEAM:
		outcome = "won"
	elif result == 0:
		outcome = "draw"
	elif result != -1:
		outcome = "lost"

	var units: Dictionary = {}
	var playerParty = battleState.parties.get(PLAYER_PARTY_ID)
	if playerParty == null:
		return {"outcome": outcome, "units": units}
	for memberID in playerParty.memberIDs:
		var monster = battleState.getMonster(memberID)
		var standing: bool = monster != null and monster.is_alive() \
			and not battleState.isMonsterWithdrawn(memberID)
		units[slotForMember(memberID)] = {"standing": standing, "felled": 0, "commanders_felled": 0}
	for defeat: Dictionary in defeats:
		var killerID := int(defeat["killer"])
		if not playerParty.memberIDs.has(killerID):
			continue
		var facts: Dictionary = units[slotForMember(killerID)]
		facts["felled"] = int(facts["felled"]) + 1
		if bool(defeat["commander"]):
			facts["commanders_felled"] = int(facts["commanders_felled"]) + 1
	return {"outcome": outcome, "units": units}


static func _enemyMemberID(partyIndex: int, memberIndex: int) -> int:
	return ENEMY_MEMBER_BASE + 10 * partyIndex + memberIndex


static func _refuse(message: String) -> Dictionary:
	return {"ok": false, "error": message, "scenario": {}, "seed": -1}


## Records each defeat as it is announced: who fell, who felled it, and whether it commanded.
## Attach it before the battle starts; it reads the state only to ask who commands.
class Tally:
	extends RefCounted

	var defeats: Array[Dictionary] = []
	var _state

	func attach(events, battleState) -> void:
		_state = battleState
		events.monster_defeated.connect(_onDefeated)

	func _onDefeated(monsterID: int, killerID: int) -> void:
		var partyID := int(_state.monsterPartyIDs.get(monsterID, -1))
		var party = _state.parties.get(partyID)
		defeats.append({
			"monster": monsterID,
			"killer": killerID,
			"commander": party != null and int(party.commanderID) == monsterID,
		})
