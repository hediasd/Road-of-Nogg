class_name BattleSetupPresets
extends RefCounted

const MonsterReferencesScript = preload("res://src/factories/MonsterReferences.gd")

const PRESET_DEFAULT := "Default"
const PRESET_RANDOM_BALANCED := "Random Balanced"
const PRESET_CUSTOM := "Custom"

const DEFAULT_TEAM_1: Array[String] = [
	"Envoy of Lightning", "Gigasaurus", "Healer Mage", "Mage Dragon"
]
const DEFAULT_TEAM_2: Array[String] = [
	"Smoke Cloud", "Megidos", "Oracle of Ages", "Snowzilla"
]
const BALANCED_BRAINS: Array[String] = [
	"BerserkBrain", "TacticalBrain", "MageBrain", "SupportBrain"
]


static func getPresetNames() -> Array[String]:
	return [PRESET_DEFAULT, PRESET_RANDOM_BALANCED, PRESET_CUSTOM]


static func getRoster(presetName: String, team: int, seedValue: int) -> Array[String]:
	if presetName == PRESET_RANDOM_BALANCED:
		return _randomBalancedRoster(seedValue, team)
	if presetName == PRESET_DEFAULT:
		return (DEFAULT_TEAM_1 if team == 1 else DEFAULT_TEAM_2).duplicate()
	return []


static func _randomBalancedRoster(seedValue: int, team: int) -> Array[String]:
	var rng = RandomNumberGenerator.new()
	rng.seed = seedValue + team * 104729
	var roster: Array[String] = []

	for brainName in BALANCED_BRAINS:
		var candidates: Array[String] = []
		for reference in MonsterReferencesScript.list:
			if reference.get("BRAIN", "TacticalBrain") == brainName:
				candidates.append(reference["NAME"])
		if candidates.is_empty():
			candidates = MonsterReferencesScript.getNames()
		roster.append(candidates[rng.randi_range(0, candidates.size() - 1)])

	return roster
