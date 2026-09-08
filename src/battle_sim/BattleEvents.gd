## BattleEvents — Signal bus for decoupling logic from visuals
## All battle events flow through here. Visual adapters subscribe to these signals.

class_name BattleEvents

signal battle_started(boardSize: Vector2i, monsterList: Array)
signal battle_ended(winningTeam: int)

signal round_started(roundNumber: int, turnOrderIDs: Array)
signal round_ended(roundNumber: int)
signal turn_started(monsterID: int, roundNumber: int, turnNumber: int)
signal monster_skipped_turn(monsterID: int, reason: String)
signal turn_ended(monsterID: int)

signal monster_spawned(monsterID: int, monsterName: String, team: int, pos: Vector2i, stats: Dictionary)
signal movement_targeted(monsterID: int, destination: Vector2i)
signal monster_moved(monsterID: int, path: Array)
signal action_targeted(monsterID: int, targetPos: Vector2i, targetID: int, action: String)
signal monster_attacked(attackerID: int, targetPos: Vector2i, targetID: int, damage: int, targetNewHP: int)
## `resolvedRadius` and `areaShape` are the footprint the resolver actually used
## for this cast. They deliberately travel with the event instead of being
## re-read from immutable catalog data: transient buffs may change a live
## Spell's radius without changing its reference definition.
signal spell_cast_started(
	casterID: int,
	centerPos: Vector2i,
	spellName: String,
	element: String,
	targetsHit: int,
	resolvedRadius: int,
	areaShape: String)
signal monster_cast_spell(casterID: int, centerPos: Vector2i, targetID: int, spellName: String, damageLines: Array, targetNewHP: int)
signal monster_healed(healerID: int, centerPos: Vector2i, targetID: int, spellName: String, healAmount: int, targetNewHP: int)
signal resonance_changed(monsterID: int, element: String, oldCharge: int, newCharge: int, reason: String)
signal monster_defeated(monsterID: int, killerID: int)

signal effect_applied(monsterID: int, effectName: String, duration: int, sourceMonsterID: int, sourceSpellName: String)
signal effect_ticked(monsterID: int, effectName: String, remainingTurns: int)
signal effect_removed(monsterID: int, effectName: String)
signal status_damage_dealt(monsterID: int, effectName: String, damage: int, newHP: int)

signal passive_triggered(monsterID: int, passiveName: String, trigger: String)
signal passive_aoe_damage(sourceID: int, passiveName: String, targetID: int, element: String, damage: int, targetNewHP: int)
