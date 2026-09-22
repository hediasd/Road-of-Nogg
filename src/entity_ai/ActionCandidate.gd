## One legal thing an actor could do, named well enough to compare with another.
##
## A candidate is not a score. It carries who acts, the canonical command the
## simulator would receive, where the actor ends up and how it walked there, and
## two keys that mean different things:
##
## - `tie_key` is a **total order** over candidates of one actor. It exists so a
##   selection among equals is the same on every machine and every run.
## - `equivalence_key` is what makes two candidates **the same move**, and is the
##   only thing a filter may collapse on. Two candidates are equivalent when
##   every supported effect of resolving them is equal: same action class, same
##   destination, same ability, same set of affected units. The route walked to
##   the destination is deliberately absent, because nothing in the current rules
##   observes which tiles were crossed.
##
## **Extending this is a rules obligation, not an optimization.** The moment a
## rule reads the route -- a tile that triggers when entered, a trail left
## behind, an opportunity attack -- routes stop being interchangeable and the
## path must enter `equivalence_key`, or the filter will silently discard the
## only route that fires the trigger. The same applies to an effect that depends
## on an empty cell's contents rather than on which units it catches.

class_name ActionCandidate
extends RefCounted

## Every legal action class the enumerator can produce. Coverage is measured
## against this list, so an action a policy can never see is visible as a gap
## rather than as an absence nobody counted.
const CLASS_WAIT := "wait"
const CLASS_ATTACK := "attack"
const CLASS_SPELL_UNIT := "spell_unit"
const CLASS_SPELL_EMPTY := "spell_empty"
const ALL_CLASSES: Array[String] = [
	CLASS_WAIT, CLASS_ATTACK, CLASS_SPELL_UNIT, CLASS_SPELL_EMPTY,
]

var actor_id: int = -1
var command: BattleCommand
var action_class: String = CLASS_WAIT
var destination: Vector2i = Vector2i(-1, -1)
var move_path: Array[Vector2i] = []
var target_pos: Vector2i = Vector2i(-1, -1)
var spell_set_index: int = 0
var spell_index: int = 0
var affected_targets: Array[int] = []
var tie_key: String = ""
var equivalence_key: String = ""


static func create(actorID: int, actionClass: String, destination: Vector2i,
		movePath: Array, targetPos: Vector2i, spellSetIndex: int,
		spellIndex: int, affectedTargets: Array, targetID: int) -> ActionCandidate:
	var candidate := ActionCandidate.new()
	candidate.actor_id = actorID
	candidate.action_class = actionClass
	candidate.destination = destination
	candidate.target_pos = targetPos
	candidate.spell_set_index = spellSetIndex
	candidate.spell_index = spellIndex
	for step in movePath:
		candidate.move_path.append(step)
	var sortedTargets: Array = affectedTargets.duplicate()
	sortedTargets.sort()
	for affectedID in sortedTargets:
		candidate.affected_targets.append(int(affectedID))
	var commandAction := "spell" if actionClass.begins_with("spell") else actionClass
	candidate.command = BattleCommand.new(candidate.move_path, commandAction,
		targetID, spellSetIndex, spellIndex, "move_first", targetPos)
	candidate.tie_key = "%02d:%02d:%s:%02d:%02d:%02d:%02d" % [
		destination.y, destination.x, commandAction, spellSetIndex, spellIndex,
		targetPos.y + 1, targetPos.x + 1,
	]
	candidate.equivalence_key = "%s|%d,%d|%d.%d|%s" % [
		actionClass, destination.x, destination.y, spellSetIndex, spellIndex,
		candidate._affectedSignature(),
	]
	return candidate


## Which units resolving this would touch. An action that touches nobody is not
## the same as one that touches somebody, so the empty case is named.
func _affectedSignature() -> String:
	if action_class == CLASS_ATTACK:
		return "unit:%d" % command.target_id if command.target_id >= 0 else "empty"
	if affected_targets.is_empty():
		return "empty:%d,%d" % [target_pos.x, target_pos.y] \
			if action_class == CLASS_SPELL_EMPTY else "none"
	var parts := PackedStringArray()
	for affectedID in affected_targets:
		parts.append(str(affectedID))
	return ",".join(parts)


func to_dictionary() -> Dictionary:
	return {
		"actor_id": actor_id,
		"action_class": action_class,
		"destination": {"x": destination.x, "y": destination.y},
		"move_path": _pathData(),
		"target_pos": {"x": target_pos.x, "y": target_pos.y},
		"spell_set_index": spell_set_index,
		"spell_index": spell_index,
		"affected_targets": affected_targets.duplicate(),
		"tie_key": tie_key,
		"equivalence_key": equivalence_key,
		"command": command.to_dictionary(),
	}


func _pathData() -> Array:
	var data: Array = []
	for step: Vector2i in move_path:
		data.append({"x": step.x, "y": step.y})
	return data


static func tieKeyLess(a: ActionCandidate, b: ActionCandidate) -> bool:
	return a.tie_key < b.tie_key
