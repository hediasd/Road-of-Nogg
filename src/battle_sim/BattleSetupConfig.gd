class_name BattleSetupConfig
extends RefCounted

const MapReferencesScript = preload("res://src/factories/MapReferences.gd")
const MonsterReferencesScript = preload("res://src/factories/MonsterReferences.gd")

const MODE_CPU_VS_CPU := "cpu_vs_cpu"
const MODE_PLAYER_VS_CPU := "player_vs_cpu"
const TEAM_SIZE := 4

var battleMode: String = MODE_CPU_VS_CPU
var mapName: String = "Meadow"
var seed: int = 42
var team1: Array[String] = []
var team2: Array[String] = []


func controllerForTeam(team: int) -> String:
	if battleMode == MODE_PLAYER_VS_CPU and team == 1:
		return "player"
	return "cpu"


func serialize() -> Dictionary:
	return {
		"battleMode": battleMode,
		"mapName": mapName,
		"seed": seed,
		"team1": team1.duplicate(),
		"team2": team2.duplicate(),
		"controllers": {
			"1": controllerForTeam(1),
			"2": controllerForTeam(2)
		}
	}


func validate() -> Dictionary:
	var errors: Array[String] = []
	if battleMode not in [MODE_CPU_VS_CPU, MODE_PLAYER_VS_CPU]:
		errors.append("Unknown battle mode.")
	if not MapReferencesScript.hasReference(mapName):
		errors.append("Unknown map: %s." % mapName)
	if team1.size() != TEAM_SIZE or team2.size() != TEAM_SIZE:
		errors.append("Each team must contain exactly %d monsters." % TEAM_SIZE)

	for monsterName in team1 + team2:
		if not MonsterReferencesScript.hasReference(monsterName):
			errors.append("Unknown monster: %s." % monsterName)

	if MapReferencesScript.hasReference(mapName):
		for team in [1, 2]:
			var slots = MapReferencesScript.getDeploymentSlots(mapName, team)
			if slots.size() < TEAM_SIZE:
				errors.append("%s does not have enough Team %d deployment slots." % [mapName, team])
				continue
			var reference = MapReferencesScript.getReference(mapName)
			var size: Vector2i = reference["SIZE"]
			var layout: Array = reference["LAYOUT"]
			for slot in slots.slice(0, TEAM_SIZE):
				if slot.x < 0 or slot.y < 0 or slot.x >= size.x or slot.y >= size.y:
					errors.append("%s has an out-of-bounds Team %d deployment slot." % [mapName, team])
				elif layout[slot.y][slot.x] != ".":
					errors.append("%s has a blocked Team %d deployment slot at %s." % [mapName, team, slot])

	return {
		"success": errors.is_empty(),
		"errors": errors
	}


static func fromDictionary(data: Dictionary):
	var config = load("res://src/battle_sim/BattleSetupConfig.gd").new()
	config.battleMode = data.get("battleMode", MODE_CPU_VS_CPU)
	config.mapName = data.get("mapName", "Meadow")
	config.seed = int(data.get("seed", 42))
	config.team1.assign(data.get("team1", []))
	config.team2.assign(data.get("team2", []))
	return config
