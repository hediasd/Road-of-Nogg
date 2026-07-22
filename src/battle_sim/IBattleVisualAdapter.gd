## IBattleVisualAdapter — Interface for the visual bridge.
## Subclass this to connect battle events to any visual system.
## The console adapter is the simplest implementation (for testing).
## Later, a Godot3D adapter will render sprites, animations, etc.

class_name IBattleVisualAdapter


func connectToEvents(battleEvents: BattleEvents) -> void:
	battleEvents.battle_started.connect(_on_battle_started)
	battleEvents.battle_ended.connect(_on_battle_ended)
	battleEvents.round_started.connect(_on_round_started)
	battleEvents.round_ended.connect(_on_round_ended)
	battleEvents.turn_started.connect(_on_turn_started)
	battleEvents.monster_skipped_turn.connect(_on_monster_skipped_turn)
	battleEvents.turn_ended.connect(_on_turn_ended)
	battleEvents.monster_spawned.connect(_on_monster_spawned)
	battleEvents.monster_moved.connect(_on_monster_moved)
	battleEvents.monster_attacked.connect(_on_monster_attacked)
	battleEvents.monster_cast_spell.connect(_on_monster_cast_spell)
	battleEvents.monster_healed.connect(_on_monster_healed)
	battleEvents.monster_damaged.connect(_on_monster_damaged)
	battleEvents.monster_defeated.connect(_on_monster_defeated)
	battleEvents.effect_applied.connect(_on_effect_applied)
	battleEvents.effect_ticked.connect(_on_effect_ticked)
	battleEvents.effect_removed.connect(_on_effect_removed)
	battleEvents.status_damage_dealt.connect(_on_status_damage_dealt)
	battleEvents.passive_triggered.connect(_on_passive_triggered)
	battleEvents.passive_aoe_damage.connect(_on_passive_aoe_damage)


# --- Override these in subclasses ---

func _on_battle_started(_boardSize: Vector2i, _monsterList: Array) -> void: pass
func _on_battle_ended(_winningTeam: int) -> void: pass
func _on_round_started(_roundNumber: int, _turnOrderIDs: Array) -> void: pass
func _on_round_ended(_roundNumber: int) -> void: pass
func _on_turn_started(_monsterID: int, _roundNumber: int, _turnNumber: int) -> void: pass
func _on_monster_skipped_turn(_monsterID: int, _reason: String) -> void: pass
func _on_turn_ended(_monsterID: int) -> void: pass
func _on_monster_spawned(_monsterID: int, _name: String, _team: int, _pos: Vector2i, _stats: Dictionary) -> void: pass
func _on_monster_moved(_monsterID: int, _path: Array) -> void: pass
func _on_monster_attacked(_attackerID: int, _targetID: int, _damage: int, _targetNewHP: int) -> void: pass
func _on_monster_cast_spell(casterID: int, targetID: int, spellName: String, damageLines: Array, targetNewHP: int) -> void: pass
func _on_monster_healed(_healerID: int, _targetID: int, _spellName: String, _healAmount: int, _targetNewHP: int) -> void: pass
func _on_monster_damaged(_monsterID: int, _newHP: int, _damageAmount: int) -> void: pass
func _on_monster_defeated(_monsterID: int, _killerID: int) -> void: pass
func _on_effect_applied(_monsterID: int, _effectName: String, _duration: int, _sourceMonsterID: int, _sourceSpellName: String) -> void: pass
func _on_effect_ticked(_monsterID: int, _effectName: String, _remainingTurns: int) -> void: pass
func _on_effect_removed(_monsterID: int, _effectName: String) -> void: pass
func _on_status_damage_dealt(_monsterID: int, _effectName: String, _damage: int, _newHP: int) -> void: pass
func _on_passive_triggered(_monsterID: int, _passiveName: String, _trigger: String) -> void: pass
func _on_passive_aoe_damage(_sourceID: int, _passiveName: String, _targetID: int, _element: String, _damage: int, _targetNewHP: int) -> void: pass
