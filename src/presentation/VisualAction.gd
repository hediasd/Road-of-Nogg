## Typed, presentation-only snapshot consumed by VisualActionQueue.
##
## Events may advance the simulation long before playback reaches an action,
## so every field needed for display is copied here at enqueue time.
class_name VisualAction
extends RefCounted

enum Kind { FOCUS, MESSAGE, MOVE, BUMP, CAST_AREA, DEFEAT }
enum CursorMode { TARGET, TURN, MOVEMENT }

var kind: Kind
var coord: Vector2i = Vector2i(-1, -1)
var cursor_mode: CursorMode = CursorMode.TARGET
var monster_id: int = -1
var target_id: int = -1
var killer_id: int = -1
var path: Array = []
var element: String = ""
var vfx_profile: String = ""
var vfx_radius: int = 0
var vfx_area_shape: String = "circle"
var vfx_seed: int = 0
var vfx_ground_span: float = 0.0
var origin: Vector3 = Vector3.ZERO
var has_origin: bool = false
var left_monster_id: int = -1
var has_left_monster: bool = false
var right_monster_id: int = -1
var has_right_monster: bool = false
var prompt_text: String = ""
var log_text: String = ""
## A damage/heal number to show above `target_id`'s tile during playback. Unset
## (has_damage_number false) on a miss or an empty-tile cast — there is no
## target to show a number above.
var has_damage_number: bool = false
var damage_number: int = 0
var is_heal_number: bool = false


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
	copy.vfx_profile = vfx_profile
	copy.vfx_radius = vfx_radius
	copy.vfx_area_shape = vfx_area_shape
	copy.vfx_seed = vfx_seed
	copy.vfx_ground_span = vfx_ground_span
	copy.origin = origin
	copy.has_origin = has_origin
	copy.left_monster_id = left_monster_id
	copy.has_left_monster = has_left_monster
	copy.right_monster_id = right_monster_id
	copy.has_right_monster = has_right_monster
	copy.prompt_text = prompt_text
	copy.log_text = log_text
	copy.has_damage_number = has_damage_number
	copy.damage_number = damage_number
	copy.is_heal_number = is_heal_number
	return copy


func kind_name() -> String:
	return Kind.keys()[kind].to_lower()
