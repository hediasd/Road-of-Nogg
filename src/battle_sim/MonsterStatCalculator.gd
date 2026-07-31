## Pure deterministic level-stat derivation shared by construction and UI.

class_name MonsterStatCalculator
extends RefCounted


static func derive(baseValue: int, growthHundredths: int, level: int) -> int:
	assert(baseValue >= 0, "Base stat cannot be negative.")
	assert(growthHundredths >= 0, "Stat growth cannot be negative.")
	assert(level >= 1, "Monster level must be at least 1.")
	return baseValue + int(floor(float(growthHundredths * (level - 1)) / 100.0))


static func deriveFromReference(reference: Dictionary, level: int) -> Dictionary:
	var statsValue = reference.get("STATS", {})
	assert(statsValue is Dictionary, "Monster reference STATS must be a dictionary.")
	var stats: Dictionary = statsValue
	return {
		"hp": derive(int(stats.get("HP", 1)), int(stats.get("HP_GROWTH", 0)), level),
		"atk": derive(int(stats.get("ATK", 1)), int(stats.get("ATK_GROWTH", 0)), level),
		"def": derive(int(stats.get("DEF", 1)), int(stats.get("DEF_GROWTH", 0)), level)
	}
