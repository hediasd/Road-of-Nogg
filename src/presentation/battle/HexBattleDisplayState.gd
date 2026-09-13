## What the hex battle has actually SHOWN, as opposed to what the simulation already knows.
##
## Simulation runs ahead of playback. Event callbacks capture their values at event time, but a
## row only becomes current here when its queued action reaches playback. Readers (the HUD and
## status badges of later items) must read this, never `BattleState`, or a hit's HP drop appears
## before the hit does. Recovery is the one path that deliberately snaps to authoritative state.
##
## Written only by the adapter and its feedback helper. Every getter returns a copy.
class_name HexBattleDisplayState
extends RefCounted

const REASON_DEFEATED := "defeated"
const REASON_WITHDRAWN := "withdrawn"

var _hitpoints: Dictionary = {}
var _positions: Dictionary = {}
## monsterID -> Array of effect rows, in the same shape `BattleState.getActiveEffects` returns so
## a badge row can consume them unchanged.
var _effects: Dictionary = {}
var _removed: Dictionary = {}


func registerMonster(monsterID: int, position: Vector2i, hitpoints: int) -> void:
	_positions[monsterID] = position
	_hitpoints[monsterID] = hitpoints
	_effects[monsterID] = []
	_removed.erase(monsterID)


func setPosition(monsterID: int, position: Vector2i) -> void:
	if monsterID < 0:
		return
	_positions[monsterID] = position


func setHitpoints(monsterID: int, hitpoints: int) -> void:
	if monsterID < 0 or hitpoints < 0:
		return
	_hitpoints[monsterID] = hitpoints


## `row` is the effect as the simulation held it at event time. A re-application replaces the
## existing row of the same name rather than stacking a second badge.
func applyEffect(monsterID: int, row: Dictionary) -> void:
	var effectName := str(row.get("name", ""))
	var rows: Array = []
	var replaced := false
	for existing in _effects.get(monsterID, []):
		if str(existing.get("name", "")) == effectName:
			rows.append(row.duplicate(true))
			replaced = true
		else:
			rows.append((existing as Dictionary).duplicate(true))
	if not replaced:
		rows.append(row.duplicate(true))
	_effects[monsterID] = rows


func tickEffect(monsterID: int, effectName: String, remainingTurns: int) -> void:
	for existing in _effects.get(monsterID, []):
		if str(existing.get("name", "")) == effectName:
			existing["remainingTurns"] = remainingTurns
			return
	applyEffect(monsterID, {"name": effectName, "remainingTurns": remainingTurns})


func removeEffect(monsterID: int, effectName: String) -> void:
	var kept: Array = []
	for existing in _effects.get(monsterID, []):
		if str(existing.get("name", "")) != effectName:
			kept.append((existing as Dictionary).duplicate(true))
	_effects[monsterID] = kept


## First reason wins. A unit is removed once; a late second removal for the same unit must not
## turn a death into a withdrawal or the other way round.
func markRemoved(monsterID: int, reason: String) -> void:
	if monsterID < 0 or _removed.has(monsterID):
		return
	_removed[monsterID] = reason
	_positions.erase(monsterID)
	_effects.erase(monsterID)


func hitpointsOf(monsterID: int) -> int:
	return int(_hitpoints.get(monsterID, -1))


func positionOf(monsterID: int) -> Vector2i:
	return _positions.get(monsterID, Vector2i(-1, -1))


func effectsOf(monsterID: int) -> Array:
	return (_effects.get(monsterID, []) as Array).duplicate(true)


func removalReason(monsterID: int) -> String:
	return str(_removed.get(monsterID, ""))


func isShown(monsterID: int) -> bool:
	return _positions.has(monsterID) and not _removed.has(monsterID)


func recover(authoritative: BattleState) -> void:
	_hitpoints.clear()
	_positions.clear()
	_effects.clear()
	_removed.clear()
	if authoritative == null:
		return
	for value in authoritative.monsters.keys():
		var monsterID := int(value)
		var monster = authoritative.getMonster(monsterID)
		_hitpoints[monsterID] = int(monster.hitpoints) if monster != null else 0
		if authoritative.monsterPositions.has(monsterID):
			_positions[monsterID] = authoritative.getMonsterPosition(monsterID)
			_effects[monsterID] = authoritative.getActiveEffects(monsterID).duplicate(true)
		elif authoritative.isMonsterWithdrawn(monsterID):
			_removed[monsterID] = REASON_WITHDRAWN
		else:
			_removed[monsterID] = REASON_DEFEATED
