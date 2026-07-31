## Typed, presentation-only snapshot consumed by VisualActionQueue.
##
## Events may advance the simulation long before playback reaches an action,
## so every field needed for display is copied here at enqueue time.
class_name VisualAction
extends RefCounted

enum Kind { FOCUS, MESSAGE, MOVE, BUMP, DEFEAT }
enum CursorMode { TARGET, TURN, MOVEMENT }

var kind: Kind
var coord: Vector2i = Vector2i(-1, -1)
var cursor_mode: CursorMode = CursorMode.TARGET
var monster_id: int = -1
var target_id: int = -1
var killer_id: int = -1
var path: Array = []
var element: String = ""
var origin: Vector3 = Vector3.ZERO
var has_origin: bool = false
var left_monster_id: int = -1
var has_left_monster: bool = false
var right_monster_id: int = -1
var has_right_monster: bool = false
var prompt_text: String = ""
var log_text: String = ""


func _init(action_kind: Kind) -> void:
	kind = action_kind


func clone() -> VisualAction:
	var copy := VisualAction.new(kind)
	copy.coord = coord
	copy.cursor_mode = cursor_mode
	copy.monster_id = monster_id
	copy.target_id = target_id
	copy.killer_id = killer_id
	copy.path = path.duplicate(true)
	copy.element = element
	copy.origin = origin
	copy.has_origin = has_origin
	copy.left_monster_id = left_monster_id
	copy.has_left_monster = has_left_monster
	copy.right_monster_id = right_monster_id
	copy.has_right_monster = has_right_monster
	copy.prompt_text = prompt_text
	copy.log_text = log_text
	return copy


func kind_name() -> String:
	return Kind.keys()[kind].to_lower()
