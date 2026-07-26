## Pure deterministic level-stat derivation shared by construction and UI.

class_name MonsterStatCalculator
extends RefCounted


static func derive(baseValue: int, growthHundredths: int, level: int) -> int:
	assert(baseValue >= 0, "Base stat cannot be negative.")
	assert(growthHundredths >= 0, "Stat growth cannot be negative.")
	assert(level >= 1, "Monster level must be at least 1.")
	return baseValue + int(floor(float(growthHundredths * (level - 1)) / 100.0))


static func deriveFromReference(reference: Dictionary, level: int) -> Dictionary:
	var baseHP = int(reference.get("BASE_HP", reference.get("HP", 1)))
	var baseATK = int(reference.get("BASE_ATK", reference.get("ATK", 1)))
	var baseDEF = int(reference.get("BASE_DEF", reference.get("DEF", 1)))
	return {
		"hp": derive(baseHP, int(reference.get("HP_GROWTH", 0)), level),
		"atk": derive(baseATK, int(reference.get("ATK_GROWTH", 0)), level),
		"def": derive(baseDEF, int(reference.get("DEF_GROWTH", 0)), level)
	}
