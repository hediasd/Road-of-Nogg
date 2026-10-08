## The road's progression rules: what a battle pays in Belief, what Belief makes a monster's
## level, and when Belief lets it ascend.
##
## Every number here is a mechanical default chosen when the road was first built and stated to
## the user as overrulable (docs/GAME_DESIGN.md, "The road"). They are constants rather than
## catalog data on purpose: they are rules, read by code, and the probe pins each one.
##
## WHY BELIEF. The lore makes belief the thing that lets a humble creature ascend: "player
## attachment is literally the magical catalyst". So Belief measures how much the player has
## leaned on a monster -- fielded it, kept it standing, given it the blows that felled enemies and
## commanders. A monster left out of a battle earns nothing from it.
##
## Headless and static: no state of its own, so the probe and the road scene ask the same rules.

extends RefCounted

const MonsterReferencesScript = preload("res://content/MonsterReferences.gd")

const BELIEF_FIELDED := 1
const BELIEF_STANDING := 1
const BELIEF_PER_FELLED := 1
## On top of BELIEF_PER_FELLED, for an enemy that was a party's commander.
const BELIEF_PER_COMMANDER_FELLED := 2
const BELIEF_WIN := 1

## Reaching level L costs LEVEL_STEP * (L - 1) * L / 2 Belief in total: 3, 9, 18, 30, ...
const LEVEL_STEP := 3
const LEVEL_CAP := 10

## Belief needed for the first and second ascension. Indexed by the ascension tier the monster
## already has (`MonsterReferences.ascensionTier`), so the save needs no ascension counter.
## These are the totals for levels 4 and 7.
const ASCENSION_BELIEF := [18, 63]


## What one battle paid a fielded monster. `facts` is one entry of a battle summary:
## `{standing: bool, felled: int, commanders_felled: int}`.
static func beliefEarned(facts: Dictionary, won: bool) -> int:
	var earned := BELIEF_FIELDED
	if bool(facts.get("standing", false)):
		earned += BELIEF_STANDING
	earned += int(facts.get("felled", 0)) * BELIEF_PER_FELLED
	earned += int(facts.get("commanders_felled", 0)) * BELIEF_PER_COMMANDER_FELLED
	if won:
		earned += BELIEF_WIN
	return earned


static func beliefForLevel(level: int) -> int:
	var clamped := clampi(level, 1, LEVEL_CAP)
	return LEVEL_STEP * (clamped - 1) * clamped / 2


static func levelForBelief(belief: int) -> int:
	var level := 1
	while level < LEVEL_CAP and belief >= beliefForLevel(level + 1):
		level += 1
	return level


## The Belief still needed for the next level, or 0 at the cap.
static func beliefToNextLevel(belief: int) -> int:
	var level := levelForBelief(belief)
	if level >= LEVEL_CAP:
		return 0
	return beliefForLevel(level + 1) - belief


## The species this monster ascends into, or "" when none does. When several catalog entries name
## the same predecessor, the alphabetically first is the one offered, so the answer is stable.
static func ascendedFormOf(monsterName: String) -> String:
	for candidate in MonsterReferencesScript.getNames():
		var reference: Dictionary = MonsterReferencesScript.getReference(candidate)
		if str(reference.get("ASCENDS_FROM", "")) == monsterName:
			return candidate
	return ""


## The Belief this monster needs before its next ascension, or -1 when it cannot ascend again
## (no ascended form, or past the last threshold).
static func ascensionThreshold(monsterName: String) -> int:
	if ascendedFormOf(monsterName).is_empty():
		return -1
	var tier := MonsterReferencesScript.ascensionTier(monsterName)
	if tier < 0 or tier >= ASCENSION_BELIEF.size():
		return -1
	return int(ASCENSION_BELIEF[tier])


static func canAscend(monsterName: String, belief: int) -> bool:
	var threshold := ascensionThreshold(monsterName)
	return threshold >= 0 and belief >= threshold
