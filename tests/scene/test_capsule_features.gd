## Ported from run_capsule_features_check.gd. Exercises map height schema,
## stat-growth rounding, jump-limited pathfinding, state schema versioning and
## migration, elevation-aware direct damage/LoS, elevated-tile rendering,
## queued visual playback (movement/attack/defeat), and CPU decision latency.
##
## KNOWN ISSUE (see BACKLOG_LONGTERM.md "Tooling"): this check's mesh/material
## construction leaks three RendererDummy RIDs on shutdown on this Windows
## host, which run_godot_check.ps1's benign-error allowlist does not cover, and
## its own success marker has been observed missing from every captured
## output stream even when every assertion below passes. Confirmed pre-existing
## via `git stash` bisection on a clean HEAD (2026-07-27) — unrelated to this
## migration. Trust this file's PASS/FAIL line from run_tests.gd's own
## accounting over run_godot_check.ps1's wrapper-level exit code until that
## investigation lands.
extends "res://tests/TestCase.gd"

const MapReferencesScript = preload("res://src/factories/MapReferences.gd")
const MapFactoryScript = preload("res://src/factories/MapFactory.gd")
const MonsterFactoryScript = preload("res://src/factories/MonsterFactory.gd")
const MonsterStatCalculatorScript = preload("res://src/battle_sim/MonsterStatCalculator.gd")
const StateSerializerScript = preload("res://src/battle_sim/BattleStateSerializer.gd")
const GodotVisualAdapterScript = preload("res://src/presentation/GodotVisualAdapter.gd")
const BattleSetupConfigScript = preload("res://src/battle_sim/BattleSetupConfig.gd")
const BattleSetupFactoryScript = preload("res://src/battle_sim/BattleSetupFactory.gd")
const BattleSetupPresetsScript = preload("res://src/factories/BattleSetupPresets.gd")

var _decisionMicros: int = 0
var _percentile95: int = 0


func describe() -> String:
	return "capsule rendering/elevation/replay/CPU-latency contract holds (decision_us=%d p95_us=%d)" % [_decisionMicros, _percentile95]


func run() -> void:
	for mapName in MapReferencesScript.getNames():
		var reference = MapReferencesScript.getReference(mapName)
		var validation = MapFactoryScript.validateReference(reference)
		if not validation["success"] or int(reference.get("REVISION", 0)) < 3:
			fail("map height schema failed for %s" % mapName)
			return
		var distinctHeights: Dictionary = {}
		for row in reference["HEIGHTS"]:
			for height in row:
				distinctHeights[int(height)] = true
		if distinctHeights.size() < 3 or not distinctHeights.has(0) or not distinctHeights.has(2):
			fail("production elevation profile is missing low/mid/high ground for %s" % mapName)
			return

	if MonsterStatCalculatorScript.derive(10, 25, 5) != 11:
		fail("stat growth hundredths rounding is incorrect")
		return
	if MonsterStatCalculatorScript.derive(10, 33, 4) != 10:
		fail("stat growth floor boundary is incorrect")
		return

	var state = BattleState.new(77)
	state.setup_board(Vector2i(4, 2))
	state.mapName = "HeightFixture"
	state.mapRevision = 3
	state.heightBoard.set_at(0, Vector2i(0, 0))
	state.heightBoard.set_at(1, Vector2i(1, 0))
	state.heightBoard.set_at(3, Vector2i(2, 0))
	state.heightBoard.set_at(0, Vector2i(3, 0))
	var mover = MonsterFactoryScript.createMonster("Defaultgon", 100)
	mover.jump = 1
	state.addMonster(mover, Vector2i(0, 0), 1)
	var events = BattleEvents.new()
	var movement = MovementResolver.new(state, events)
	var reachable = movement.getReachablePositions(mover.uniqueID)
	if not reachable.has(Vector2i(1, 0)) or reachable.has(Vector2i(2, 0)):
		fail("jump-limited reachability is incorrect")
		return
	var invalidPath = movement.validateMovePath(
		mover.uniqueID, [Vector2i(1, 0), Vector2i(2, 0)]
	)
	if invalidPath["success"] or invalidPath["reason"] != "height_exceeds_jump":
		fail("multi-step height validation accepted an excessive jump")
		return

	var serialized = StateSerializerScript.serialize(state)
	if serialized["version"] != 5 or serialized["mapRevision"] != 3:
		fail("state schema version or map revision was not serialized")
		return
	var restored = StateSerializerScript.deserialize(
		JSON.parse_string(JSON.stringify(serialized))
	)
	if restored.getHeight(Vector2i(2, 0)) != 3 or restored.getMonster(100).jump != 1:
		fail("height/jump JSON round trip failed")
		return
	var versionTwo = serialized.duplicate(true)
	versionTwo["version"] = 2
	versionTwo.erase("heightBoard")
	versionTwo["monsters"]["100"].erase("level")
	versionTwo["monsters"]["100"].erase("jump")
	var migrated = StateSerializerScript.deserialize(versionTwo)
	if migrated.getHeight(Vector2i(2, 0)) != 0:
		fail("version-2 flat-height migration failed")
		return
	if migrated.getMonster(100).level != 1 or migrated.getMonster(100).jump != 1:
		fail("version-2 monster defaults failed")
		return

	var combatState = BattleState.new(5)
	combatState.setup_board(Vector2i(4, 2))
	var attacker = MonsterFactoryScript.createMonster("Gigasaurus", 200)
	var target = MonsterFactoryScript.createMonster("Defaultgon", 201)
	attacker.atk = 20
	target.def = 0
	combatState.addMonster(attacker, Vector2i(0, 0), 1)
	combatState.addMonster(target, Vector2i(1, 0), 2)
	combatState.heightBoard.set_at(1, Vector2i(0, 0))
	combatState.heightBoard.set_at(0, Vector2i(1, 0))
	var combat = CombatResolver.new(combatState, BattleEvents.new())
	if combat.calculateBasicDamage(attacker, target, true) != 22:
		fail("high-ground direct damage is incorrect")
		return
	combatState.heightBoard.set_at(0, Vector2i(0, 0))
	combatState.heightBoard.set_at(1, Vector2i(1, 0))
	if combat.calculateBasicDamage(attacker, target, true) != 18:
		fail("low-ground direct damage is incorrect")
		return
	combatState.heightBoard.set_at(3, Vector2i(1, 0))
	if combat.getBasicAttackTargets(attacker.uniqueID).has(target.uniqueID):
		fail("melee accepted an excessive height delta")
		return

	combatState.moveMonsterTo(target.uniqueID, Vector2i(3, 0))
	combatState.heightBoard.set_at(0, Vector2i(0, 0))
	combatState.heightBoard.set_at(2, Vector2i(1, 0))
	combatState.heightBoard.set_at(0, Vector2i(3, 0))
	if combat._hasLoS(attacker.uniqueID, Vector2i(0, 0), Vector2i(3, 0), target.uniqueID):
		fail("intervening ridge did not block line of sight")
		return

	var visualState = BattleState.new(9)
	visualState.setup_board(Vector2i(3, 2))
	visualState.heightBoard.set_at(2, Vector2i(1, 0))
	var visualMonster = MonsterFactoryScript.createMonster("Defaultgon", 300)
	var visualTarget = MonsterFactoryScript.createMonster("Gigasaurus", 301)
	visualState.addMonster(visualMonster, Vector2i(0, 0), 1)
	visualState.addMonster(visualTarget, Vector2i(2, 0), 2)
	var visualRoot = Node3D.new()
	root.add_child(visualRoot)
	var adapter = GodotVisualAdapterScript.new(visualState, visualRoot, visualRoot)
	adapter._on_battle_started(visualState.boardSize, [300, 301])
	adapter._on_monster_spawned(300, visualMonster.name, 1, Vector2i(0, 0), {})
	adapter._on_monster_spawned(301, visualTarget.name, 2, Vector2i(2, 0), {})
	var elevatedColumn = adapter.getTileColumn(Vector2i(1, 0))
	var elevatedSurface = adapter.getTileSurface(Vector2i(1, 0))
	if elevatedColumn == null or elevatedColumn.get_child_count() != 3:
		fail("height-2 tile did not render as a three-block column")
		return
	for layer in range(3):
		var block = elevatedColumn.get_child(layer) as MeshInstance3D
		if block == null or not is_equal_approx(block.position.y, float(layer) * 0.5):
			fail("elevated tile column has a gap or misplaced layer")
			return
		var blockMesh = block.mesh as BoxMesh
		if blockMesh == null or not blockMesh.size.is_equal_approx(Vector3(1.0, 0.5, 1.0)):
			fail("terrain cell dimensions are not exactly 1 x 0.5 x 1")
			return
	var surfaceMesh = elevatedSurface.mesh as BoxMesh
	if surfaceMesh == null or not is_equal_approx(
			elevatedSurface.position.y + surfaceMesh.size.y * 0.5,
			1.25
	):
		fail("elevated tile top surface is misaligned")
		return
	adapter.show_player_cursor(Vector2i(1, 0))
	if not is_equal_approx(adapter._cursor.position.y, 1.265):
		fail("elevated cursor is misaligned")
		return
	adapter.show_movement_options([Vector2i(1, 0)])
	if not is_equal_approx(adapter.overlay_node.get_child(0).position.y, 1.265):
		fail("elevated tactical overlay is misaligned")
		return
	var lightGrass = adapter.tileColorFor(Color(0.2, 0.8, 0.2), Vector2i(0, 0), 0)
	var darkGrass = adapter.tileColorFor(Color(0.2, 0.8, 0.2), Vector2i(1, 0), 0)
	if lightGrass.is_equal_approx(darkGrass) or lightGrass.v <= darkGrass.v:
		fail("terrain checker does not alternate light and dark tones")
		return
	var base = adapter._monster_visuals[300].get_child(0) as MeshInstance3D
	var baseMaterial = base.material_override as ShaderMaterial
	var teamColor: Color = baseMaterial.get_shader_parameter("color_a")
	if teamColor.b <= teamColor.r:
		fail("Team 1 capsule base is not blue")
		return

	visualState.moveMonsterTo(300, Vector2i(1, 0))
	adapter._on_monster_moved(300, [Vector2i(1, 0)])
	adapter._on_monster_attacked(300, 301, 1, visualTarget.hitpoints - 1)
	adapter._on_battle_ended(1)
	# Simulate authoritative state advancing again while the view still owns the
	# earlier movement and attack snapshots.
	visualState.moveMonsterTo(300, Vector2i(0, 0))
	if adapter.activeAnimationKind() != "move" or adapter.queuedAnimationCount() != 2:
		fail("movement, attack, and victory were not serialized in the visual queue")
		return
	var movementStart: Vector3 = adapter._monster_visuals[300].position
	if not movementStart.is_equal_approx(Vector3(0.0, 0.25, 0.0)):
		fail("queued attack snapped the still-moving model to backend state")
		return
	# Focused SceneTree scripts may not continuously tick bound tweens while
	# headless, so step the tween explicitly to inspect the in-flight transform.
	adapter.anim_tween.custom_step(0.12)
	var movementInFlight: Vector3 = adapter._monster_visuals[300].position
	if (
		movementInFlight.x <= movementStart.x or
		movementInFlight.x >= 1.0 or
		movementInFlight.y <= movementStart.y
	):
		fail("uphill movement snapped instead of following its jump arc: start=%s in_flight=%s" % [movementStart, movementInFlight])
		return
	adapter.anim_tween.custom_step(0.3)
	await nextFrame()
	if adapter.activeAnimationKind() != "bump":
		fail("attack animation did not wait for movement completion")
		return
	adapter.anim_tween.custom_step(0.3)
	await nextFrame()
	if adapter.isAnimationBusy() or adapter.queuedAnimationCount() != 0:
		fail("visual animation queue did not drain")
		return
	var queuedFinal: Vector3 = adapter._monster_visuals[300].position
	if not is_equal_approx(queuedFinal.x, 1.0) or not is_equal_approx(queuedFinal.y, 1.25):
		fail("queued movement read later authoritative position instead of its snapshot")
		return

	adapter._on_monster_moved(300, [Vector2i(0, 0)])
	adapter.anim_tween.pause()
	await waitSeconds(1.2)
	if adapter.isAnimationBusy() or not is_equal_approx(adapter._monster_visuals[300].position.x, 0.0):
		fail("visual animation watchdog did not recover a stalled tween")
		return

	visualTarget.hitpoints = 0
	adapter._on_monster_defeated(301, 300)
	await nextFrame()
	var selection = adapter._monster_visuals[301].get_node("SelectionBody") as StaticBody3D
	if selection.collision_layer != 0:
		fail("defeat did not disable selection when its queued action began")
		return
	if adapter._monster_visuals[301].get_node_or_null("CapsuleShatter") == null:
		fail("defeat did not create the capsule shatter effect")
		return
	adapter.anim_tween.custom_step(0.45)
	await nextFrame()
	if adapter.isAnimationBusy() or adapter._monster_visuals.has(301):
		fail("defeat animation did not finish and release its visual")
		return
	adapter.dispose()
	visualRoot.queue_free()
	await nextFrame()

	var ai = BattleSimulator.new(13)
	ai.state.setup_board(Vector2i(5, 3))
	var cpu = ai.spawnMonster("Gigasaurus", 1, Vector2i(1, 1))
	var lethalTarget = ai.spawnMonster("Defaultgon", 2, Vector2i(2, 1))
	ai.spawnMonster("Defaultgon", 2, Vector2i(4, 1))
	lethalTarget.hitpoints = 1
	ai.state.currentMonsterID = cpu.uniqueID
	var decisionStart = Time.get_ticks_usec()
	var decision = ai.brains[cpu.uniqueID].decideTurn(cpu.uniqueID)
	_decisionMicros = Time.get_ticks_usec() - decisionStart
	if decision["action"] != "attack" or decision["target_id"] != lethalTarget.uniqueID:
		fail("CPU did not prioritize a safe lethal action")
		return

	var benchmarkConfig = BattleSetupConfigScript.new()
	benchmarkConfig.team1 = BattleSetupPresetsScript.DEFAULT_TEAM_1.duplicate()
	benchmarkConfig.team2 = BattleSetupPresetsScript.DEFAULT_TEAM_2.duplicate()
	var benchmark = BattleSetupFactoryScript.createSimulator(benchmarkConfig)
	var timings: Array[int] = []
	for monsterID in benchmark.state.getAliveMonsterIDs():
		var started = Time.get_ticks_usec()
		benchmark.brains[monsterID].decideTurn(monsterID)
		timings.append(Time.get_ticks_usec() - started)
	timings.sort()
	_percentile95 = timings[mini(timings.size() - 1, ceili(timings.size() * 0.95) - 1)]
	if _percentile95 >= 50000:
		fail("eight-unit CPU decision p95 exceeded 50 ms")
		return
