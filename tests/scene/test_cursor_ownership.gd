## Ported from run_cursor_check.gd. Exercises discrete cursor ownership
## transitions and the visual adapter's queued-movement/event-driven cursor
## sync, including two entities occupying adjacent tiles after immediate moves.
extends "res://tests/TestCase.gd"

const BattleCursorControllerScript = preload("res://src/presentation/BattleCursorController.gd")
const BattleSimulatorScript = preload("res://src/battle_sim/BattleSimulator.gd")
const GodotVisualAdapterScript = preload("res://src/presentation/GodotVisualAdapter.gd")


func describe() -> String:
	return "cursor ownership transitions and visual-adapter sync behave correctly"


func run() -> void:
	var cursor = MeshInstance3D.new()
	root.add_child(cursor)
	var controller = BattleCursorControllerScript.new(cursor)

	controller.focusTurn(Vector2i(1, 1))
	controller.focusMovementDestination(Vector2i(3, 1))
	if controller.mode != BattleCursorControllerScript.Mode.MOVEMENT_TARGET:
		fail("movement destination did not own the cursor")
		return
	if controller.grid_position != Vector2i(3, 1):
		fail("cursor did not snap to the movement destination")
		return
	if cursor.position != Vector3(3, BattleCursorControllerScript.CURSOR_LIFT, 1):
		fail("cursor interpolated instead of snapping to the destination")
		return

	controller.focusTarget(Vector2i(7, 4))
	if controller.mode != BattleCursorControllerScript.Mode.TARGETING:
		fail("action target did not own the cursor")
		return
	if controller.grid_position != Vector2i(7, 4):
		fail("cursor did not snap to the action target")
		return

	controller.focusPlayerSelection(Vector2i(5, 2))
	if controller.mode != BattleCursorControllerScript.Mode.PLAYER_SELECTION:
		fail("player selection did not retain cursor ownership")
		return
	if controller.grid_position != Vector2i(5, 2):
		fail("player selection moved unexpectedly")
		return

	var visualRoot = Node3D.new()
	root.add_child(visualRoot)
	var simulator = BattleSimulatorScript.new(42)
	simulator.loadMap("Meadow")
	var adapter = GodotVisualAdapterScript.new(simulator.state, visualRoot)
	simulator.setVisualAdapter(adapter)
	var actor = simulator.spawnMonster("Mage Dragon", 1, Vector2i(0, 0))
	var follower = simulator.spawnMonster("Healer Mage", 1, Vector2i(0, 1))
	var target = simulator.spawnMonster("Smoke Cloud", 2, Vector2i(3, 0))
	simulator.startBattle()

	simulator.state.currentMonsterID = actor.uniqueID
	simulator.events.turn_started.emit(actor.uniqueID, 1, 1)
	simulator.events.movement_targeted.emit(actor.uniqueID, Vector2i(2, 0))
	if adapter._cursor_controller.grid_position != Vector2i(2, 0):
		fail("visual adapter did not show the movement destination")
		return

	simulator.events.action_targeted.emit(actor.uniqueID, target.uniqueID, "spell")
	if adapter._cursor_controller.grid_position != Vector2i(3, 0):
		fail("action target did not replace the movement destination")
		return

	# A second move may reuse a tile as soon as the first entity vacates it in
	# authoritative state. Presentation keeps both moves in order and never
	# rewrites the first visual from the newer backend position.
	simulator.state.moveMonsterTo(actor.uniqueID, Vector2i(1, 0))
	simulator.events.monster_moved.emit(actor.uniqueID, [Vector2i(1, 0)])
	simulator.state.moveMonsterTo(follower.uniqueID, Vector2i(0, 0))
	simulator.events.monster_moved.emit(follower.uniqueID, [Vector2i(0, 0)])
	simulator.state.assertValidOccupancy()
	if adapter._monster_visuals[actor.uniqueID].position != Vector3(0, 0.25, 0):
		fail("queued movement resynchronized from newer backend state")
		return
	if adapter._monster_visuals[actor.uniqueID].position == adapter._monster_visuals[follower.uniqueID].position:
		fail("two entity visuals occupied the same tile after immediate moves")
		return

	visualRoot.free()
	cursor.free()
	await nextFrame()
