## What the enemy side could do to one tile, and how sure that number is.
##
## Three different questions get three different answers, and confusing them is
## how a CPU either walks into a crossfire or refuses to leave its corner:
##
## - `REPLY` -- the most one named enemy could deal there. Exact under current
##   rules, for that enemy alone.
## - `BOUND` -- every enemy's best reply added up. **An upper bound, never a
##   prediction.** Enemies can be counted here who could not all actually do it:
##   two of them may need the same tile to stand on. Use it to decide what is
##   unsafe, because overstating danger is the safe direction.
## - `FEASIBLE` -- a continuation the side can really execute: one action each,
##   no two enemies on the same tile, and anyone who casts stays where it is
##   because magic is pre-move. **A lower bound**, because it is one assignment
##   and not necessarily the best one.
##
## So `feasible <= truth <= bound`. A caller that wants one number must say which
## risk it is willing to take, rather than being handed an average of the two
## that means neither.
##
## `approximations` names what the number does not know. It is part of the
## answer, not a comment: a caller that reads the value and ignores this is
## treating a bound as a fact.

class_name DangerAssessment
extends RefCounted

const REPLY := "reply"
const BOUND := "bound"
const FEASIBLE := "feasible"

var mode: String = BOUND
var tile: Vector2i = Vector2i(-1, -1)
var value: int = 0
## `{enemy_id: {"value": int, "from": Vector2i, "kind": "melee"|"spell"}}`
var contributors: Dictionary = {}
## Named blind spots, not prose. See DangerQuery.APPROXIMATIONS.
var approximations: Array[String] = []
## Work actually spent, so a budget can be enforced and reported rather than
## hoped for.
var queries: int = 0
var truncated: bool = false


static func create(mode: String, tile: Vector2i) -> DangerAssessment:
	var assessment := DangerAssessment.new()
	assessment.mode = mode
	assessment.tile = tile
	return assessment


func note(approximation: String) -> void:
	if not approximations.has(approximation):
		approximations.append(approximation)


func to_dictionary() -> Dictionary:
	var contributorData: Dictionary = {}
	for enemyID in contributors:
		var entry: Dictionary = contributors[enemyID]
		contributorData[str(enemyID)] = {
			"value": int(entry["value"]),
			"from": {"x": int(entry["from"].x), "y": int(entry["from"].y)},
			"kind": str(entry["kind"]),
		}
	return {
		"mode": mode,
		"tile": {"x": tile.x, "y": tile.y},
		"value": value,
		"contributors": contributorData,
		"approximations": approximations.duplicate(),
		"queries": queries,
		"truncated": truncated,
	}
