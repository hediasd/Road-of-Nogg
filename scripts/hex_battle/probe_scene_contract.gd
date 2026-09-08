extends SceneTree

const ControllerScript = preload("res://src/systems/hex_battle/HexBattleController.gd")
const AdapterScript = preload("res://src/presentation/battle/HexBattleVisualAdapter.gd")
const CursorScript = preload("res://src/presentation/battle/HexBattleCursor.gd")
const PlaybackScript = preload("res://src/presentation/battle/HexBattlePlayback.gd")
const CameraScript = preload("res://src/presentation/battle/HexBattleCamera.gd")
const MemberTurnScript = preload("res://src/systems/hex_battle/HexBattleMemberTurn.gd")
const BattleMapDefinitionScript = preload("res://src/entities/BattleMapDefinition.gd")
const HexGridScript = preload("res://src/board/HexGrid.gd")
const HexBattleLayoutScript = preload("res://src/presentation/battle/HexBattleLayout.gd")

const CONTROLLER_PATH := "res://src/systems/hex_battle/HexBattleController.gd"
const ADAPTER_PATH := "res://src/presentation/battle/HexBattleVisualAdapter.gd"

const BATTLE_SCENE := "res://scenes/battle/HexBattle.tscn"
const DEBUG_SCENE := "res://scenes/debug/HexBattleDebugScene.tscn"

## Ports the simulation reaches the screen through. A hex adapter missing one of these would
## compile and then silently drop that whole class of event.
const REQUIRED_ADAPTER_METHODS := [
	"connectToEvents", "disconnectFromEvents", "isAnimationBusy", "queuedAnimationCount",
	"show_player_cursor", "release_player_cursor", "show_movement_options",
	"show_target_options", "clear_tactical_overlays", "worldPositionOf",
]

## Files this item owns, audited for the two things it was told not to do.
const OWNED_FILES := [
	"res://src/systems/hex_battle/HexBattleController.gd",
	"res://src/systems/hex_battle/HexBattleMemberTurn.gd",
	"res://src/presentation/battle/HexBattleVisualAdapter.gd",
	"res://src/presentation/battle/HexBattleCursor.gd",
	"res://src/presentation/battle/HexBattleCamera.gd",
	"res://src/presentation/battle/HexBattleHud.gd",
	"res://src/presentation/battle/HexBattleSetupUI.gd",
	"res://src/presentation/battle/HexBattlePlayback.gd",
]

var failures: Array[String] = []


func _init() -> void:
	process_frame.connect(_run, CONNECT_ONE_SHOT)


func _run() -> void:
	_checkScenesLoad()
	_checkAdapterPorts()
	_checkInheritedDrainSignalIsNotRedeclared()
	_checkSixDirectionsAreReachable()
	_checkSchedulingHasOneOwner()
	_checkNoSquareControllerDependency()
	_checkNoDirectStateWrites()

	if not failures.is_empty():
		for failure: String in failures:
			printerr("HXB_SCENE_FAILURE: %s" % failure)
		quit(1)
		return
	print("HXB_SCENE_OK")
	quit(0)


func _require(condition: bool, message: String) -> void:
	if not condition:
		failures.append(message)


func _map(cols := 11, rows := 11) -> BattleMapDefinition:
	var map: BattleMapDefinition = BattleMapDefinitionScript.new()
	map.boardSize = Vector2i(cols, rows)
	map.cellWidth = 2.0
	map.cellHeight = 2.0
	map.heightStep = 0.5
	map.terrainDefinitions = {"clear": {"traversable": true, "stoppable": true, "movement_cost": 1}}
	var cells: Array[Vector2i] = []
	var data := {}
	for y in range(rows):
		for x in range(cols):
			var cell := Vector2i(x, y)
			cells.append(cell)
			data[cell] = {"terrain": "clear", "height": 0}
	map.configureCells(cells, data)
	return map


## Narrow-loaded, not instantiated: instancing the controller would run a battle, and the probe's
## own instruction is not to substitute direct handler calls for real input.
func _checkScenesLoad() -> void:
	for path in [BATTLE_SCENE, DEBUG_SCENE]:
		_require(ResourceLoader.exists(path), "scene %s does not exist" % path)
		if not ResourceLoader.exists(path):
			continue
		var packed := ResourceLoader.load(path) as PackedScene
		_require(packed != null, "scene %s did not load as a PackedScene" % path)
		if packed == null:
			continue
		var state := packed.get_state()
		_require(state.get_node_count() > 0, "scene %s has no nodes" % path)
		# Both scenes must wrap the SAME composition -- the debug scene is a wrapper, not a fork.
		var found := false
		for i in range(state.get_node_property_count(0)):
			if str(state.get_node_property_name(0, i)) == "script":
				var script: Script = state.get_node_property_value(0, i)
				found = script != null and script.resource_path == CONTROLLER_PATH
		_require(found, "scene %s does not carry HexBattleController" % path)

	# UIDs must be distinct, or one scene silently resolves to the other.
	var battleUID := ResourceLoader.get_resource_uid(BATTLE_SCENE)
	var debugUID := ResourceLoader.get_resource_uid(DEBUG_SCENE)
	_require(battleUID != debugUID, "the two hex scenes share a resource UID")
	_require(battleUID != ResourceUID.INVALID_ID, "the battle scene has no resource UID")


func _checkAdapterPorts() -> void:
	var adapterParent := Node3D.new()
	var adapter := AdapterScript.new(adapterParent, _map())
	for methodName: String in REQUIRED_ADAPTER_METHODS:
		_require(adapter.has_method(methodName),
			"the hex adapter is missing the '%s' port" % methodName)
	_require(adapter is IPlayerTurnVisualAdapter,
		"the hex adapter does not extend IPlayerTurnVisualAdapter")
	_require(adapter is IBattleVisualAdapter,
		"the hex adapter does not satisfy the IBattleVisualAdapter boundary")
	# Every position resolves through the layout, so the adapter and a freshly built layout must
	# agree cell for cell.
	var layout: HexBattleLayout = HexBattleLayoutScript.new(_map())
	for cell in [Vector2i(0, 0), Vector2i(1, 0), Vector2i(3, 4)]:
		_require(adapter.worldPositionOf(cell).is_equal_approx(layout.cellCenter(cell)),
			"the adapter placed %s somewhere the layout does not" % cell)
	adapter.dispose()
	adapterParent.free()


## `animation_queue_drained` is declared on IPlayerTurnVisualAdapter. Redeclaring it in the hex
## adapter would shadow the base's, and a controller connected to one while the queue emitted the
## other is a battle that never advances -- so this asserts the hex file does not declare it.
func _checkInheritedDrainSignalIsNotRedeclared() -> void:
	var file := FileAccess.open(ADAPTER_PATH, FileAccess.READ)
	_require(file != null, "could not read the hex adapter")
	if file == null:
		return
	var text := file.get_as_text()
	file.close()
	_require(not text.contains("signal animation_queue_drained"),
		"the hex adapter redeclares the inherited animation_queue_drained signal")
	var signalParent := Node3D.new()
	var probeAdapter := AdapterScript.new(signalParent, _map())
	var hasSignal := false
	for entry in probeAdapter.get_signal_list():
		if str(entry.get("name", "")) == "animation_queue_drained":
			hasSignal = true
	_require(hasSignal, "animation_queue_drained is not reachable on the hex adapter")
	probeAdapter.dispose()
	signalParent.free()


## The item forbids claiming that four arrows give six directions. This demonstrates the mapping
## instead: with the six neighbours projected, six distinct input vectors must reach six distinct
## neighbours, and every neighbour must be reachable by some vector.
func _checkSixDirectionsAreReachable() -> void:
	var map := _map()
	var layout: HexBattleLayout = HexBattleLayoutScript.new(map)
	var cursor: HexBattleCursor = CursorScript.new()
	var origin := Vector2i(5, 5)
	_require(cursor.moveTo(origin, map), "the cursor refused a valid cell")

	# A plan projection: world X/Z straight to screen X/Y. Stands in for a camera without needing
	# one, and is the same shape the camera's own projectToScreen returns.
	var project := func(cell: Vector2i) -> Vector2:
		var centre: Vector3 = layout.cellCenter(cell)
		return Vector2(centre.x, centre.z)

	var neighbours := cursor.reachableNeighbours(map)
	_require(neighbours.size() == 6, "an interior cell has %d reachable neighbours, expected 6" % neighbours.size())

	var reached := {}
	for neighbour: Vector2i in neighbours:
		# Aim exactly at each neighbour in the projected frame; the resolver must return it.
		var direction: Vector2 = project.call(neighbour) - project.call(origin)
		var picked := cursor.neighbourFor(direction, project, map)
		_require(picked == neighbour,
			"aiming at %s selected %s instead" % [neighbour, picked])
		reached[picked] = true
	_require(reached.size() == 6,
		"only %d of the six neighbours were reachable by direction" % reached.size())

	# Below the deadzone nothing moves, and facing away from every candidate is not a move.
	_require(cursor.neighbourFor(Vector2(0.01, 0.0), project, map) == origin,
		"a sub-deadzone input moved the cursor")

	# An off-board neighbour is not offered as a direction rather than being clamped onto.
	var edgeCursor: HexBattleCursor = CursorScript.new()
	edgeCursor.moveTo(Vector2i(0, 0), map)
	for neighbour: Vector2i in edgeCursor.reachableNeighbours(map):
		_require(map.containsCell(neighbour),
			"the cursor offered off-board neighbour %s" % neighbour)


## One owner, and only the holder may release it.
func _checkSchedulingHasOneOwner() -> void:
	var gate: HexBattlePlayback = PlaybackScript.new(null)
	_require(gate.isIdle(), "a fresh gate is not idle")
	_require(gate.canAdvance(), "an idle gate refuses to advance")

	_require(gate.claim(HexBattlePlayback.OWNER_PLAYER, 7), "the gate refused a first claim")
	_require(not gate.canAdvance(), "the gate allowed advancing while claimed")
	_require(not gate.claim(HexBattlePlayback.OWNER_CPU, 9),
		"the gate allowed a second owner over an open claim")
	_require(not gate.release(HexBattlePlayback.OWNER_CPU, 9),
		"a non-holder released the gate")
	_require(not gate.release(HexBattlePlayback.OWNER_PLAYER, 8),
		"a stale member id released the gate")
	_require(gate.release(HexBattlePlayback.OWNER_PLAYER, 7), "the holder could not release")
	_require(gate.isIdle() and gate.canAdvance(), "the gate did not reopen after release")

	gate.finish()
	_require(gate.isFinished(), "the gate did not record the battle as finished")
	_require(not gate.canAdvance(), "a finished gate still allows advancing")
	_require(not gate.claim(HexBattlePlayback.OWNER_PLAYER, 1),
		"a finished gate accepted a new claim")


## The hex composition must not depend on the square controller family, which HXB-14 retires.
func _checkNoSquareControllerDependency() -> void:
	var forbidden := [
		"src/systems/BattlePresentationController.gd",
		"src/systems/PlayerTurnController.gd",
		"src/presentation/GodotVisualAdapter.gd",
		"src/presentation/BattleCursorController.gd",
		"src/presentation/BattleCameraDirector.gd",
		"src/presentation/TurnOrderRail.gd",
	]
	for path: String in OWNED_FILES:
		var file := FileAccess.open(path, FileAccess.READ)
		_require(file != null, "could not read owned file %s" % path)
		if file == null:
			continue
		var text := file.get_as_text()
		file.close()
		for dependency: String in forbidden:
			for form in ["preload(\"res://%s" % dependency, "load(\"res://%s" % dependency]:
				_require(not text.contains(form),
					"%s loads %s, which HXB-14 retires" % [path.get_file(), dependency.get_file()])
		_require(not text.contains("extends BattlePresentationController"),
			"%s inherits the square controller" % path.get_file())


## Simulation stays authoritative: nothing this item owns writes to BattleState. Reads are
## expected and fine; ASSIGNMENTS into state are what would make a second simulator.
##
## Matched with a regex rather than a substring, because `state.activePartyID =` is also a prefix
## of `state.activePartyID ==` -- the first version of this check failed the controller for
## nine comparisons and no writes at all. The pattern requires a single `=` not followed by
## another, which is what separates an assignment from every comparison operator.
func _checkNoDirectStateWrites() -> void:
	var assignment := RegEx.new()
	assignment.compile("state\\.[A-Za-z_]+(\\[[^\\]]*\\])?\\s*=\\s*[^=]")
	for path: String in OWNED_FILES:
		var file := FileAccess.open(path, FileAccess.READ)
		if file == null:
			continue
		var lines := file.get_as_text().split("\n")
		file.close()
		for index in range(lines.size()):
			var line := str(lines[index]).strip_edges()
			# A comment describing the rule is not a breach of it.
			if line.begins_with("#"):
				continue
			var found := assignment.search(line)
			_require(found == null,
				"%s:%d assigns into battle state: %s" % [path.get_file(), index + 1, line])
