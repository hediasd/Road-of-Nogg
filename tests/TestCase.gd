## TestCase — Base class for every test under tests/. Subclasses override
## describe() and run(), and report problems through the assert*/fail helpers
## instead of throwing, so one file surfaces every failure it finds in a
## single run rather than stopping at the first one.
extends RefCounted

var _failures: Array[String] = []
var _tree: SceneTree


func describe() -> String:
	return "unnamed test"


func run() -> void:
	fail("run() was not overridden")


func fail(message: String) -> void:
	_failures.append(message)


func assertTrue(condition: bool, message: String = "expected true") -> void:
	if not condition:
		fail(message)


func assertFalse(condition: bool, message: String = "expected false") -> void:
	if condition:
		fail(message)


func assertEqual(actual, expected, message: String = "") -> void:
	if actual != expected:
		var label = message if not message.is_empty() else "values differ"
		fail("%s (got %s, expected %s)" % [label, actual, expected])


func assertHas(collection, value, message: String = "") -> void:
	if not collection.has(value):
		var label = message if not message.is_empty() else "membership check failed"
		fail("%s (%s does not contain %s)" % [label, collection, value])


func assertDoesNotHave(collection, value, message: String = "") -> void:
	if collection.has(value):
		var label = message if not message.is_empty() else "membership check failed"
		fail("%s (%s unexpectedly contains %s)" % [label, collection, value])


# --- Scene-tier helpers. Only meaningful when the runner supplies a live tree. ---

func getRoot() -> Node:
	return _tree.get_root()


func nextFrame() -> void:
	await _tree.process_frame


func waitSeconds(seconds: float) -> void:
	await _tree.create_timer(seconds).timeout


## Pass-throughs matching SceneTree's own members, so a script ported from
## `extends SceneTree` needs no changes beyond its outer shell: `root`,
## `await process_frame`, `await physics_frame`, and `create_timer(...)` all
## behave exactly as they did as a standalone SceneTree script.
var root: Node:
	get: return _tree.get_root() if _tree != null else null

var process_frame: Signal:
	get: return _tree.process_frame

var physics_frame: Signal:
	get: return _tree.physics_frame


func create_timer(seconds: float) -> SceneTreeTimer:
	return _tree.create_timer(seconds)


# --- Fixtures shared by unit and integration tests ---

func makeMonster(elements: Array, overrides: Dictionary = {}, uniqueID: int = 900) -> Monster:
	## A synthetic monster independent of the reference catalog, so a test
	## survives content edits. Callers needing a specific race, spell set, or
	## stat pass it through overrides using the same MONSTER_REFERENCE keys
	## MonsterFactory understands (e.g. {"RACE": "Nymph", "ATK": 10}). Pass a
	## distinct uniqueID when placing more than one synthetic monster in the
	## same BattleState.
	var parameters := {
		"NAME": "Fixture", "ELEMENTS": elements, "RACE": "none",
		"HP": 20, "ATK": 5, "DEF": 5, "SPD": 5, "MOVE": 3
	}
	for key in overrides:
		parameters[key] = overrides[key]
	return Monster.new(parameters, uniqueID)


func makeSimulator(seedValue: int = 0, boardSize: Vector2i = Vector2i(8, 8)) -> BattleSimulator:
	var simulator := BattleSimulator.new(seedValue)
	simulator.state.setup_board(boardSize)
	return simulator
