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
signal monster_moved(monsterID: int, path: Array)
signal monster_attacked(attackerID: int, targetID: int, damage: int, targetNewHP: int)
signal monster_cast_spell(casterID: int, targetID: int, spellName: String, element: String, damage: int, targetNewHP: int)
signal monster_healed(healerID: int, targetID: int, spellName: String, healAmount: int, targetNewHP: int)
signal monster_damaged(monsterID: int, newHP: int, damageAmount: int)
signal monster_defeated(monsterID: int, killerID: int)

signal effect_applied(monsterID: int, effectName: String, duration: int, sourceMonsterID: int, sourceSpellName: String)
signal effect_ticked(monsterID: int, effectName: String, remainingTurns: int)
signal effect_removed(monsterID: int, effectName: String)
signal status_damage_dealt(monsterID: int, effectName: String, damage: int, newHP: int)
