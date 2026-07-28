## IBattleVisualAdapter — Interface for the visual bridge.
## Subclass this to connect battle events to any visual system.
## The console adapter is the simplest implementation (for testing).
## Later, a Godot3D adapter will render sprites, animations, etc.

class_name IBattleVisualAdapter

var _connectedEvents: BattleEvents


func connectToEvents(battleEvents: BattleEvents) -> void:
	if _connectedEvents == battleEvents:
		return
	disconnectFromEvents()
	_connectedEvents = battleEvents
	battleEvents.battle_started.connect(_on_battle_started)
	battleEvents.battle_ended.connect(_on_battle_ended)
	battleEvents.round_started.connect(_on_round_started)
	battleEvents.round_ended.connect(_on_round_ended)
	battleEvents.turn_started.connect(_on_turn_started)
	battleEvents.monster_skipped_turn.connect(_on_monster_skipped_turn)
	battleEvents.turn_ended.connect(_on_turn_ended)
	battleEvents.monster_spawned.connect(_on_monster_spawned)
	battleEvents.movement_targeted.connect(_on_movement_targeted)
	battleEvents.monster_moved.connect(_on_monster_moved)
	battleEvents.action_targeted.connect(_on_action_targeted)
	battleEvents.monster_attacked.connect(_on_monster_attacked)
	battleEvents.monster_cast_spell.connect(_on_monster_cast_spell)
	battleEvents.monster_healed.connect(_on_monster_healed)
	battleEvents.resonance_changed.connect(_on_resonance_changed)
	battleEvents.monster_defeated.connect(_on_monster_defeated)
	battleEvents.effect_applied.connect(_on_effect_applied)
	battleEvents.effect_ticked.connect(_on_effect_ticked)
	battleEvents.effect_removed.connect(_on_effect_removed)
	battleEvents.status_damage_dealt.connect(_on_status_damage_dealt)
	battleEvents.passive_triggered.connect(_on_passive_triggered)
	battleEvents.passive_aoe_damage.connect(_on_passive_aoe_damage)


func disconnectFromEvents() -> void:
	if _connectedEvents == null:
		return
	_disconnect(_connectedEvents.battle_started, _on_battle_started)
	_disconnect(_connectedEvents.battle_ended, _on_battle_ended)
	_disconnect(_connectedEvents.round_started, _on_round_started)
	_disconnect(_connectedEvents.round_ended, _on_round_ended)
	_disconnect(_connectedEvents.turn_started, _on_turn_started)
	_disconnect(_connectedEvents.monster_skipped_turn, _on_monster_skipped_turn)
	_disconnect(_connectedEvents.turn_ended, _on_turn_ended)
	_disconnect(_connectedEvents.monster_spawned, _on_monster_spawned)
	_disconnect(_connectedEvents.movement_targeted, _on_movement_targeted)
	_disconnect(_connectedEvents.monster_moved, _on_monster_moved)
	_disconnect(_connectedEvents.action_targeted, _on_action_targeted)
	_disconnect(_connectedEvents.monster_attacked, _on_monster_attacked)
	_disconnect(_connectedEvents.monster_cast_spell, _on_monster_cast_spell)
	_disconnect(_connectedEvents.monster_healed, _on_monster_healed)
	_disconnect(_connectedEvents.resonance_changed, _on_resonance_changed)
	_disconnect(_connectedEvents.monster_defeated, _on_monster_defeated)
	_disconnect(_connectedEvents.effect_applied, _on_effect_applied)
	_disconnect(_connectedEvents.effect_ticked, _on_effect_ticked)
	_disconnect(_connectedEvents.effect_removed, _on_effect_removed)
	_disconnect(_connectedEvents.status_damage_dealt, _on_status_damage_dealt)
	_disconnect(_connectedEvents.passive_triggered, _on_passive_triggered)
	_disconnect(_connectedEvents.passive_aoe_damage, _on_passive_aoe_damage)
	_connectedEvents = null


func _disconnect(eventSignal: Signal, callback: Callable) -> void:
	if eventSignal.is_connected(callback):
		eventSignal.disconnect(callback)


# --- Override these in subclasses ---

func _on_battle_started(_boardSize: Vector2i, _monsterList: Array) -> void: pass
func _on_battle_ended(_winningTeam: int) -> void: pass
func _on_round_started(_roundNumber: int, _turnOrderIDs: Array) -> void: pass
func _on_round_ended(_roundNumber: int) -> void: pass
func _on_turn_started(_monsterID: int, _roundNumber: int, _turnNumber: int) -> void: pass
func _on_monster_skipped_turn(_monsterID: int, _reason: String) -> void: pass
func _on_turn_ended(_monsterID: int) -> void: pass
func _on_monster_spawned(_monsterID: int, _name: String, _team: int, _pos: Vector2i, _stats: Dictionary) -> void: pass
func _on_movement_targeted(_monsterID: int, _destination: Vector2i) -> void: pass
func _on_monster_moved(_monsterID: int, _path: Array) -> void: pass
func _on_action_targeted(_monsterID: int, _targetID: int, _action: String) -> void: pass
func _on_monster_attacked(_attackerID: int, _targetID: int, _damage: int, _targetNewHP: int) -> void: pass
func _on_monster_cast_spell(casterID: int, targetID: int, spellName: String, damageLines: Array, targetNewHP: int) -> void: pass
func _on_monster_healed(_healerID: int, _targetID: int, _spellName: String, _healAmount: int, _targetNewHP: int) -> void: pass
func _on_resonance_changed(_monsterID: int, _element: String, _oldCharge: int, _newCharge: int, _reason: String) -> void: pass
func _on_monster_defeated(_monsterID: int, _killerID: int) -> void: pass
func _on_effect_applied(_monsterID: int, _effectName: String, _duration: int, _sourceMonsterID: int, _sourceSpellName: String) -> void: pass
func _on_effect_ticked(_monsterID: int, _effectName: String, _remainingTurns: int) -> void: pass
func _on_effect_removed(_monsterID: int, _effectName: String) -> void: pass
func _on_status_damage_dealt(_monsterID: int, _effectName: String, _damage: int, _newHP: int) -> void: pass
func _on_passive_triggered(_monsterID: int, _passiveName: String, _trigger: String) -> void: pass
func _on_passive_aoe_damage(_sourceID: int, _passiveName: String, _targetID: int, _element: String, _damage: int, _targetNewHP: int) -> void: pass
