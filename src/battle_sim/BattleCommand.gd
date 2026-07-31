class_name BattleCommand
extends RefCounted

## Typed command value used between controllers, replay, AI, and the simulator.
## Dictionary conversion is intentionally confined to serialization edges.

var move_path: Array = []
var action: String = "wait"
var target_id: int = -1
var target_pos: Vector2i = Vector2i(-1, -1)
var spell_set_index: int = 0
var spell_index: int = 0
var order: String = "move_first"


func _init(
		_move_path: Array = [],
		_action: String = "wait",
		_target_id: int = -1,
		_spell_set_index: int = 0,
		_spell_index: int = 0,
		_order: String = "move_first",
		_target_pos: Vector2i = Vector2i(-1, -1)) -> void:
	move_path = _move_path.duplicate(true)
	action = _action
	target_id = _target_id
	target_pos = _target_pos
	spell_set_index = _spell_set_index
	spell_index = _spell_index
	order = _order


static func wait() -> BattleCommand:
	return BattleCommand.new()


static func from_dictionary(data: Dictionary) -> BattleCommand:
	return BattleCommand.new(
		data.get("move_path", []),
		str(data.get("action", "wait")),
		int(data.get("target_id", -1)),
		int(data.get("spell_set_index", 0)),
		int(data.get("spell_index", 0)),
		str(data.get("order", "move_first")),
		_vector_from(data.get("target_pos", Vector2i(-1, -1)))
	)


func to_dictionary() -> Dictionary:
	return {
		"move_path": move_path.duplicate(true),
		"action": action,
		"target_id": target_id,
		"target_pos": {"x": target_pos.x, "y": target_pos.y},
		"spell_set_index": spell_set_index,
		"spell_index": spell_index,
		"order": order
	}


func duplicate_command() -> BattleCommand:
	return BattleCommand.new(
		move_path, action, target_id, spell_set_index, spell_index, order, target_pos
	)


static func _vector_from(value) -> Vector2i:
	if value is Vector2i:
		return value
	if value is Dictionary:
		return Vector2i(int(value.get("x", -1)), int(value.get("y", -1)))
	if value is Array and value.size() >= 2:
		return Vector2i(int(value[0]), int(value[1]))
	return Vector2i(-1, -1)
